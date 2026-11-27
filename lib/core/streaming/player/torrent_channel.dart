import 'dart:async';
import 'package:flutter/services.dart';

/// Live telemetry snapshot emitted by the native Android libtorrent4j engine.
class TorrentProgress {
  const TorrentProgress({
    required this.state,
    required this.progress,
    required this.bufferPercent,
    required this.downloadSpeedBps,
    required this.uploadSpeedBps,
    required this.peers,
    required this.seeds,
    required this.readyForPlayback,
    this.fileName = '',
    this.fileSize = 0,
    this.streamUrl = '',
    this.error,
  });

  final String state;
  final double progress;
  final double bufferPercent;
  final int downloadSpeedBps;
  final int uploadSpeedBps;
  final int peers;
  final int seeds;
  final bool readyForPlayback;
  final String fileName;
  final int fileSize;
  final String streamUrl;
  final String? error;

  factory TorrentProgress.fromMap(Map<dynamic, dynamic> map) {
    return TorrentProgress(
      state: map['state'] as String? ?? 'idle',
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      bufferPercent: (map['bufferPercent'] as num?)?.toDouble() ?? 0.0,
      downloadSpeedBps: (map['downloadSpeedBps'] as num?)?.toInt() ?? 0,
      uploadSpeedBps: (map['uploadSpeedBps'] as num?)?.toInt() ?? 0,
      peers: (map['peers'] as num?)?.toInt() ?? 0,
      seeds: (map['seeds'] as num?)?.toInt() ?? 0,
      readyForPlayback: map['readyForPlayback'] as bool? ?? false,
      fileName: map['fileName'] as String? ?? '',
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      streamUrl: map['streamUrl'] as String? ?? '',
      error: map['error'] as String?,
    );
  }

  String get formattedDownloadSpeed {
    if (downloadSpeedBps <= 0) return '0 KB/s';
    if (downloadSpeedBps >= 1024 * 1024) {
      return '${(downloadSpeedBps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(downloadSpeedBps / 1024).toStringAsFixed(0)} KB/s';
  }
}

class TorrentStartResult {
  const TorrentStartResult({
    required this.streamUrl,
    required this.fileName,
    required this.fileSize,
    required this.fileIndex,
  });

  final String streamUrl;
  final String fileName;
  final int fileSize;
  final int fileIndex;
}

/// Bridge to the native Android libtorrent4j engine + local HTTP range proxy.
class TorrentChannel {
  TorrentChannel._();

  static const MethodChannel _method = MethodChannel('com.cinemahub.app/torrent');
  static const EventChannel _events = EventChannel('com.cinemahub.app/torrent_events');

  static Stream<TorrentProgress>? _broadcastStream;

  /// Broadcast stream of real-time peer, speed, and buffer progress updates.
  static Stream<TorrentProgress> get progressStream {
    _broadcastStream ??= _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => TorrentProgress.fromMap(event as Map))
        .asBroadcastStream();
    return _broadcastStream!;
  }

  /// Starts streaming a magnet link in the native libtorrent4j session and returns
  /// the local `http://127.0.0.1:<port>/stream` URL once metadata resolves.
  static Future<TorrentStartResult> startStream(
    String magnetUri, {
    int? fileIndex,
  }) async {
    final res = await _method.invokeMapMethod<String, dynamic>(
      'startTorrent',
      <String, dynamic>{
        'magnetUri': magnetUri,
        if (fileIndex != null) 'fileIndex': fileIndex,
      },
    );

    if (res == null || (res['streamUrl'] as String? ?? '').isEmpty) {
      throw PlatformException(
        code: 'EMPTY_STREAM',
        message: 'Native torrent engine returned an empty stream URL.',
      );
    }

    return TorrentStartResult(
      streamUrl: res['streamUrl'] as String,
      fileName: res['fileName'] as String? ?? 'video',
      fileSize: (res['fileSize'] as num?)?.toInt() ?? 0,
      fileIndex: (res['fileIndex'] as num?)?.toInt() ?? 0,
    );
  }

  /// Stops the active torrent download & local HTTP proxy server.
  static Future<void> stopStream() async {
    try {
      await _method.invokeMethod<bool>('stopTorrent');
    } catch (_) {}
  }

  /// Fetches the latest snapshot status synchronously from the native engine.
  static Future<TorrentProgress?> getStatus() async {
    try {
      final res = await _method.invokeMapMethod<String, dynamic>('getStatus');
      if (res == null) return null;
      return TorrentProgress.fromMap(res);
    } catch (_) {
      return null;
    }
  }
}
