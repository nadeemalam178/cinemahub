package com.cinemahub.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val installerChannelName = "com.cinemahub.app/installer"
    private val torrentChannelName = "com.cinemahub.app/torrent"
    private val torrentEventsName = "com.cinemahub.app/torrent_events"

    private var torrentEngineManager: TorrentEngineManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. OTA APK installer & device ABI channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSupportedAbis" -> {
                        result.success(Build.SUPPORTED_ABIS.toList())
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "File path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val context = applicationContext
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !context.packageManager.canRequestPackageInstalls()
                            ) {
                                val permIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:${context.packageName}")
                                ).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                context.startActivity(permIntent)
                                result.error(
                                    "PERMISSION_REQUIRED",
                                    "Allow CinemaHub to install unknown apps, then tap Install Now again.",
                                    null
                                )
                                return@setMethodCallHandler
                            }

                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                                return@setMethodCallHandler
                            }

                            val contentUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                            } else {
                                Uri.fromFile(file)
                            }

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(contentUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.localizedMessage, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 2. Native libtorrent4j streaming engine + local HTTP proxy
        val manager = TorrentEngineManager(applicationContext).also {
            torrentEngineManager = it
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, torrentChannelName)
            .setMethodCallHandler(manager)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, torrentEventsName)
            .setStreamHandler(manager)
    }

    override fun onDestroy() {
        torrentEngineManager?.release()
        torrentEngineManager = null
        super.onDestroy()
    }
}
