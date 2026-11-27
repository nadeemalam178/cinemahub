package com.cinemahub.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentFlags
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native libtorrent4j P2P streaming engine + local 127.0.0.1 HTTP byte-range proxy.
 *
 * Streams magnet links sequentially directly into ExoPlayer without leaving the app,
 * prioritizes header & moov-atom pieces, supports seeking via range requests, and
 * streams live peer/speed/buffer telemetry back to Flutter over EventChannel.
 */
class TorrentEngineManager(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()
    private val sessionLock = Any()

    @Volatile
    private var sessionManager: SessionManager? = null

    @Volatile
    private var activeHandle: TorrentHandle? = null

    @Volatile
    private var activeInfo: TorrentInfo? = null

    @Volatile
    private var activeFileIndex: Int = 0

    @Volatile
    private var activeTargetFile: File? = null

    @Volatile
    private var activeFileSize: Long = 0L

    @Volatile
    private var activeFirstPiece: Int = 0

    @Volatile
    private var activeLastPiece: Int = 0

    @Volatile
    private var serverSocket: ServerSocket? = null

    @Volatile
    private var activeStreamUrl: String? = null

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private val isStreaming = AtomicBoolean(false)
    private val telemetryRunning = AtomicBoolean(false)

    private val videoExtensions = setOf(
        ".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".ts"
    )

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTorrent" -> {
                val magnetUri = call.argument<String>("magnetUri")?.trim()
                val fileIndex = call.argument<Int>("fileIndex")
                if (magnetUri.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "magnetUri is required", null)
                    return
                }
                startTorrent(magnetUri, fileIndex, result)
            }
            "stopTorrent" -> {
                executor.execute {
                    stopCurrentTorrent()
                    mainHandler.post { result.success(true) }
                }
            }
            "getStatus" -> {
                val payload = buildStatusPayload("status")
                result.success(payload)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureSessionStarted(): SessionManager {
        synchronized(sessionLock) {
            var sm = sessionManager
            if (sm == null) {
                sm = SessionManager()
                sm.start()
                sessionManager = sm
            }
            if (!sm.isDhtRunning) {
                try {
                    sm.startDht()
                } catch (_: Exception) {
                }
            }
            return sm
        }
    }

    private fun startTorrent(
        magnetUri: String,
        requestedFileIndex: Int?,
        result: MethodChannel.Result
    ) {
        executor.execute {
            try {
                stopCurrentTorrent()
                cleanCacheIfNeeded()

                val rootDir = File(context.cacheDir, "torrents").apply { mkdirs() }
                val saveDir = File(rootDir, "session_${System.currentTimeMillis()}").apply { mkdirs() }
                val tempDir = File(rootDir, "meta").apply { mkdirs() }

                val sm = ensureSessionStarted()
                isStreaming.set(true)

                emitTelemetry(
                    mapOf(
                        "state" to "resolving_metadata",
                        "progress" to 0.0,
                        "bufferPercent" to 0.0,
                        "downloadSpeedBps" to 0L,
                        "uploadSpeedBps" to 0L,
                        "peers" to 0,
                        "seeds" to 0,
                        "readyForPlayback" to false
                    )
                )

                val metaBytes = sm.fetchMagnet(magnetUri, 60, tempDir)
                if (!isStreaming.get()) {
                    mainHandler.post {
                        result.error("CANCELLED", "Torrent startup was cancelled", null)
                    }
                    return@execute
                }

                if (metaBytes == null || metaBytes.isEmpty()) {
                    isStreaming.set(false)
                    emitTelemetry(
                        mapOf(
                            "state" to "error",
                            "error" to "Timed out fetching torrent metadata from peers/DHT"
                        )
                    )
                    mainHandler.post {
                        result.error(
                            "METADATA_TIMEOUT",
                            "Could not resolve magnet metadata within 60s. No active peers found.",
                            null
                        )
                    }
                    return@execute
                }

                val ti = TorrentInfo.bdecode(metaBytes)
                val targetIdx = selectTargetFileIndex(ti, requestedFileIndex)
                val fs = ti.files()
                val fileSize = fs.fileSize(targetIdx)
                val relPath = fs.filePath(targetIdx)
                val targetFile = File(saveDir, relPath)
                targetFile.parentFile?.mkdirs()

                val priorities = Priority.array(Priority.IGNORE, ti.numFiles())
                priorities[targetIdx] = Priority.TOP_PRIORITY

                sm.download(
                    ti,
                    saveDir,
                    null,
                    priorities,
                    null,
                    TorrentFlags.SEQUENTIAL_DOWNLOAD
                )

                val handle = sm.find(Sha1Hash(ti.swig().info_hash()))
                if (handle == null || !handle.isValid) {
                    isStreaming.set(false)
                    mainHandler.post {
                        result.error("HANDLE_ERROR", "Failed to acquire TorrentHandle", null)
                    }
                    return@execute
                }

                handle.prioritizeFiles(priorities)

                val firstPiece: Int = ti.mapFile(targetIdx, 0L, 1).piece()
                val lastOffset = maxOf(0L, fileSize - 1L)
                val lastPiece: Int = if (fileSize > 0L) {
                    ti.mapFile(targetIdx, lastOffset, 1).piece()
                } else {
                    firstPiece
                }

                // Prioritize initial header pieces AND final piece (MP4 moov atom)
                val endHeaderPiece = minOf(firstPiece + 6, lastPiece)
                for (p in firstPiece..endHeaderPiece) {
                    handle.setPieceDeadline(p, (p - firstPiece) * 50)
                }
                if (lastPiece > firstPiece) {
                    handle.setPieceDeadline(lastPiece, 150)
                }

                activeInfo = ti
                activeHandle = handle
                activeFileIndex = targetIdx
                activeTargetFile = targetFile
                activeFileSize = fileSize
                activeFirstPiece = firstPiece
                activeLastPiece = lastPiece

                val port = startHttpProxyServer(ti, handle, targetIdx, targetFile, fileSize)
                val streamUrl = "http://127.0.0.1:$port/stream"
                activeStreamUrl = streamUrl

                startTelemetryLoop()

                val fileName = File(relPath).name
                mainHandler.post {
                    result.success(
                        mapOf(
                            "streamUrl" to streamUrl,
                            "fileName" to fileName,
                            "fileSize" to fileSize,
                            "fileIndex" to targetIdx
                        )
                    )
                }
            } catch (e: Exception) {
                isStreaming.set(false)
                emitTelemetry(
                    mapOf(
                        "state" to "error",
                        "error" to (e.localizedMessage ?: e.toString())
                    )
                )
                mainHandler.post {
                    result.error("TORRENT_ERROR", e.localizedMessage ?: e.toString(), null)
                }
            }
        }
    }

    private fun selectTargetFileIndex(ti: TorrentInfo, requestedFileIndex: Int?): Int {
        val fs = ti.files()
        val count = ti.numFiles()
        if (count <= 1) return 0

        if (requestedFileIndex != null && requestedFileIndex in 0 until count) {
            val reqName = fs.filePath(requestedFileIndex).lowercase(Locale.US)
            val isIgnored = reqName.endsWith(".txt") || reqName.endsWith(".nfo") || reqName.endsWith(".jpg")
            if (!isIgnored && fs.fileSize(requestedFileIndex) > 0) {
                return requestedFileIndex
            }
        }

        var bestVideoIdx = -1
        var bestVideoSize = -1L
        var largestIdx = 0
        var largestSize = -1L

        for (i in 0 until count) {
            val size = fs.fileSize(i)
            val path = fs.filePath(i).lowercase(Locale.US)
            if (size > largestSize) {
                largestSize = size
                largestIdx = i
            }
            if (videoExtensions.any { path.endsWith(it) } && size > bestVideoSize) {
                bestVideoSize = size
                bestVideoIdx = i
            }
        }

        return if (bestVideoIdx >= 0) bestVideoIdx else largestIdx
    }

    private fun startHttpProxyServer(
        ti: TorrentInfo,
        handle: TorrentHandle,
        fileIndex: Int,
        targetFile: File,
        fileSize: Long
    ): Int {
        val ss = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        serverSocket = ss
        val mime = guessMimeType(targetFile.name)

        val acceptThread = Thread({
            while (isStreaming.get() && !ss.isClosed) {
                try {
                    val client = ss.accept()
                    executor.execute {
                        handleHttpClient(client, ti, handle, fileIndex, targetFile, fileSize, mime)
                    }
                } catch (_: Exception) {
                    if (!isStreaming.get() || ss.isClosed) break
                }
            }
        }, "CinemaHub-TorrentHttpProxy")
        acceptThread.isDaemon = true
        acceptThread.start()

        return ss.localPort
    }

    private fun handleHttpClient(
        socket: Socket,
        ti: TorrentInfo,
        handle: TorrentHandle,
        fileIndex: Int,
        targetFile: File,
        fileSize: Long,
        mimeType: String
    ) {
        socket.use { sock ->
            sock.soTimeout = 30000
            val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
            val requestLine = reader.readLine() ?: return
            val parts = requestLine.split(" ")
            if (parts.size < 2) return
            val method = parts[0].uppercase(Locale.US)

            var rangeHeader: String? = null
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                if (line.lowercase(Locale.US).startsWith("range:")) {
                    rangeHeader = line.substringAfter(":").trim()
                }
            }

            if (method != "GET" && method != "HEAD") {
                val out = sock.getOutputStream()
                out.write("HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n".toByteArray())
                out.flush()
                return
            }

            var start = 0L
            var end = maxOf(0L, fileSize - 1L)
            var isPartial = false

            if (rangeHeader != null && rangeHeader.startsWith("bytes=")) {
                isPartial = true
                val spec = rangeHeader.removePrefix("bytes=").split(",").firstOrNull()?.trim() ?: ""
                val dashIdx = spec.indexOf('-')
                if (dashIdx >= 0) {
                    val sPart = spec.substring(0, dashIdx).trim()
                    val ePart = spec.substring(dashIdx + 1).trim()
                    if (sPart.isEmpty() && ePart.isNotEmpty()) {
                        val suffix = ePart.toLongOrNull() ?: 0L
                        start = maxOf(0L, fileSize - suffix)
                        end = maxOf(0L, fileSize - 1L)
                    } else {
                        start = sPart.toLongOrNull() ?: 0L
                        end = ePart.toLongOrNull() ?: maxOf(0L, fileSize - 1L)
                    }
                }
            }

            if (start >= fileSize && fileSize > 0) {
                val out = sock.getOutputStream()
                out.write(
                    "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */$fileSize\r\nConnection: close\r\n\r\n"
                        .toByteArray()
                )
                out.flush()
                return
            }

            if (end >= fileSize) end = maxOf(0L, fileSize - 1L)
            val contentLength = if (fileSize == 0L) 0L else (end - start + 1L)

            val out = BufferedOutputStream(sock.getOutputStream(), 64 * 1024)
            val statusLine = if (isPartial) "HTTP/1.1 206 Partial Content" else "HTTP/1.1 200 OK"
            val headerBuilder = StringBuilder()
                .append(statusLine).append("\r\n")
                .append("Content-Type: ").append(mimeType).append("\r\n")
                .append("Accept-Ranges: bytes\r\n")
                .append("Content-Length: ").append(contentLength).append("\r\n")
            if (isPartial) {
                headerBuilder.append("Content-Range: bytes ")
                    .append(start).append("-").append(end).append("/").append(fileSize)
                    .append("\r\n")
            }
            headerBuilder.append("Connection: close\r\n\r\n")
            out.write(headerBuilder.toString().toByteArray(Charsets.UTF_8))
            out.flush()

            if (method == "HEAD" || contentLength <= 0L) {
                return
            }

            val chunkBuffer = ByteArray(64 * 1024)
            var currentOffset = start
            val endExclusive = end + 1L
            var raf: RandomAccessFile? = null

            try {
                while (currentOffset < endExclusive && isStreaming.get() && !sock.isClosed) {
                    val toRead = minOf(chunkBuffer.size.toLong(), endExclusive - currentOffset).toInt()
                    val pr = ti.mapFile(fileIndex, currentOffset, toRead)
                    val piece = pr.piece()
                    // Clamp read length strictly within the verified piece boundary
                    val safeToRead = minOf(toRead, maxOf(1, pr.length()))

                    if (!waitForPiece(handle, piece)) {
                        return
                    }

                    // Ensure file is created and readable
                    var waitFileMs = 0
                    while (!targetFile.exists() && waitFileMs < 5000 && isStreaming.get()) {
                        Thread.sleep(50)
                        waitFileMs += 50
                    }
                    if (!targetFile.exists()) return

                    if (raf == null) {
                        raf = RandomAccessFile(targetFile, "r")
                    }

                    raf.seek(currentOffset)
                    val readCount = raf.read(chunkBuffer, 0, safeToRead)
                    if (readCount <= 0) {
                        Thread.sleep(50)
                        continue
                    }

                    out.write(chunkBuffer, 0, readCount)
                    currentOffset += readCount
                }
                out.flush()
            } catch (_: Exception) {
                // Client disconnected / ExoPlayer seeked
            } finally {
                try {
                    raf?.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun waitForPiece(handle: TorrentHandle, piece: Int): Boolean {
        if (!handle.isValid) return false
        if (handle.havePiece(piece)) {
            // Prefetch next 3 pieces gently
            for (ahead in 1..3) {
                val nextPiece = piece + ahead
                if (nextPiece <= activeLastPiece && !handle.havePiece(nextPiece)) {
                    handle.setPieceDeadline(nextPiece, ahead * 120)
                }
            }
            return true
        }

        handle.setPieceDeadline(piece, 0)
        for (ahead in 1..4) {
            val nextPiece = piece + ahead
            if (nextPiece <= activeLastPiece && !handle.havePiece(nextPiece)) {
                handle.setPieceDeadline(nextPiece, ahead * 80)
            }
        }

        val deadlineAt = System.currentTimeMillis() + 45_000L
        while (isStreaming.get() && handle.isValid && System.currentTimeMillis() < deadlineAt) {
            if (handle.havePiece(piece)) {
                return true
            }
            try {
                Thread.sleep(60)
            } catch (_: InterruptedException) {
                return false
            }
        }
        return handle.isValid && handle.havePiece(piece)
    }

    private fun startTelemetryLoop() {
        if (!telemetryRunning.compareAndSet(false, true)) return
        executor.execute {
            try {
                while (isStreaming.get() && telemetryRunning.get()) {
                    val payload = buildStatusPayload(null)
                    emitTelemetry(payload)
                    Thread.sleep(750)
                }
            } catch (_: Exception) {
            } finally {
                telemetryRunning.set(false)
            }
        }
    }

    private fun buildStatusPayload(overrideState: String?): Map<String, Any> {
        val handle = activeHandle
        if (handle == null || !handle.isValid) {
            return mapOf(
                "state" to (overrideState ?: if (isStreaming.get()) "resolving_metadata" else "idle"),
                "progress" to 0.0,
                "bufferPercent" to 0.0,
                "downloadSpeedBps" to 0L,
                "uploadSpeedBps" to 0L,
                "peers" to 0,
                "seeds" to 0,
                "readyForPlayback" to false,
                "streamUrl" to (activeStreamUrl ?: "")
            )
        }

        val st = handle.status()
        val progress = st.progress().toDouble().coerceIn(0.0, 1.0)
        val bufferPercent = (progress * 100.0).coerceIn(0.0, 100.0)
        val firstReady = handle.havePiece(activeFirstPiece)
        val secondReady = activeFirstPiece >= activeLastPiece || handle.havePiece(activeFirstPiece + 1)
        val readyForPlayback = firstReady && (secondReady || progress > 0.01)

        val stateName = overrideState ?: when {
            !readyForPlayback -> "buffering"
            progress >= 0.999 -> "seeding"
            else -> "streaming"
        }

        return mapOf(
            "state" to stateName,
            "progress" to progress,
            "bufferPercent" to bufferPercent,
            "downloadSpeedBps" to st.downloadRate().toLong(),
            "uploadSpeedBps" to st.uploadRate().toLong(),
            "peers" to st.numPeers(),
            "seeds" to st.numSeeds(),
            "fileName" to (activeTargetFile?.name ?: ""),
            "fileSize" to activeFileSize,
            "readyForPlayback" to readyForPlayback,
            "streamUrl" to (activeStreamUrl ?: "")
        )
    }

    private fun emitTelemetry(payload: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun stopCurrentTorrent() {
        isStreaming.set(false)
        telemetryRunning.set(false)

        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        activeStreamUrl = null

        val handle = activeHandle
        val sm = sessionManager
        if (handle != null && sm != null) {
            try {
                if (handle.isValid) {
                    sm.remove(handle)
                }
            } catch (_: Exception) {
            }
        }

        activeHandle = null
        activeInfo = null
        activeTargetFile = null
        activeFileSize = 0L

        emitTelemetry(
            mapOf(
                "state" to "stopped",
                "progress" to 0.0,
                "bufferPercent" to 0.0,
                "downloadSpeedBps" to 0L,
                "uploadSpeedBps" to 0L,
                "peers" to 0,
                "seeds" to 0,
                "readyForPlayback" to false
            )
        )
    }

    private fun cleanCacheIfNeeded() {
        try {
            val rootDir = File(context.cacheDir, "torrents")
            if (!rootDir.exists()) return
            rootDir.listFiles()?.forEach { child ->
                if (child.isDirectory && child.name.startsWith("session_")) {
                    child.deleteRecursively()
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun guessMimeType(name: String): String {
        val lower = name.lowercase(Locale.US)
        return when {
            lower.endsWith(".mkv") -> "video/x-matroska"
            lower.endsWith(".webm") -> "video/webm"
            lower.endsWith(".mov") -> "video/quicktime"
            lower.endsWith(".avi") -> "video/x-msvideo"
            lower.endsWith(".ts") -> "video/mp2t"
            else -> "video/mp4"
        }
    }

    fun release() {
        stopCurrentTorrent()
        synchronized(sessionLock) {
            try {
                sessionManager?.stop()
            } catch (_: Exception) {
            }
            sessionManager = null
        }
        executor.shutdownNow()
    }
}
