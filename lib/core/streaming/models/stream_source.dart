import '../../providers/stremio_adapter.dart';
import '../diagnostics/streaming_logger.dart';

enum StreamType {
  directHttp, // Direct MP4 / MKV / progressive media (ExoPlayer)
  hls,        // HTTP Live Streaming (.m3u8) (ExoPlayer)
  dash,       // Dynamic Adaptive Streaming over HTTP (.mpd) (ExoPlayer)
  embed,      // Web embed / iframe player (In-App WebView)
  website,    // General external website / directory portal (external browser)
  magnet,     // BitTorrent P2P magnet link (In-app native torrent engine)
  unsupported,// Unhandled, DRM-protected, or invalid stream format
}

/// Normalized stream source returned by any provider.
class StreamSource {
  const StreamSource({
    required this.id,
    required this.provider,
    required this.name,
    this.url,
    this.infoHash,
    this.fileIndex,
    required this.type,
    this.mimeType,
    this.headers = const {},
    this.quality,
    this.language,
    this.codec,
    this.seeders,
    this.sizeBytes,
    required this.isPlayableInternally,
    this.failureReason,
    this.metadata = const {},
  });

  /// Reliable public UDP/HTTPS trackers appended when building magnets from bare infoHashes.
  static const List<String> defaultTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://tracker.bittor.pw:1337/announce',
    'udp://public.popcorn-tracker.org:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'https://tracker.tamersunion.org:443/announce',
  ];

  /// Unique identifier for this stream item
  final String id;

  /// Name of the providing engine (e.g. "Torrentio", "KnightCrawler", "MediaFusion")
  final String provider;

  /// User-facing stream title
  final String name;

  /// Direct URL (http/https) or magnet URI
  final String? url;

  /// Torrent infoHash for P2P streams
  final String? infoHash;

  /// Target file index inside multi-file torrent
  final int? fileIndex;

  /// Classified stream type
  final StreamType type;

  /// MIME type hint (e.g. "video/mp4", "application/x-mpegURL")
  final String? mimeType;

  /// Mandatory HTTP request headers (Referer, Origin, User-Agent)
  final Map<String, String> headers;

  /// Video resolution / quality (e.g. "4K UHD", "1080p FHD", "720p HD", "HDR", "Dolby Vision")
  final String? quality;

  /// Audio/subtitle language (e.g. "English", "Multi Audio")
  final String? language;

  /// Video/audio codec if known (e.g. "HEVC", "H.264", "AAC")
  final String? codec;

  /// Active P2P seeders
  final int? seeders;

  /// File size in bytes
  final int? sizeBytes;

  /// Whether CinemaHub can play this stream natively or inside its In-App Web Player
  final bool isPlayableInternally;

  /// Diagnostic reason if stream is not playable internally
  final String? failureReason;

  /// Extensible provider metadata
  final Map<String, dynamic> metadata;

  StreamSource copyWith({
    String? id,
    String? provider,
    String? name,
    String? url,
    String? infoHash,
    int? fileIndex,
    StreamType? type,
    String? mimeType,
    Map<String, String>? headers,
    String? quality,
    String? language,
    String? codec,
    int? seeders,
    int? sizeBytes,
    bool? isPlayableInternally,
    String? failureReason,
    Map<String, dynamic>? metadata,
  }) {
    return StreamSource(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      name: name ?? this.name,
      url: url ?? this.url,
      infoHash: infoHash ?? this.infoHash,
      fileIndex: fileIndex ?? this.fileIndex,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      headers: headers ?? this.headers,
      quality: quality ?? this.quality,
      language: language ?? this.language,
      codec: codec ?? this.codec,
      seeders: seeders ?? this.seeders,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      isPlayableInternally: isPlayableInternally ?? this.isPlayableInternally,
      failureReason: failureReason ?? this.failureReason,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Formatted file size string (e.g. "2.4 GB", "850 MB")
  String? get formattedSize {
    if (sizeBytes == null || sizeBytes! <= 0) return null;
    final bytes = sizeBytes!;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  /// Whether this stream is resolved via Real-Debrid / premium debrid service
  bool get isDebrid =>
      metadata['isDebrid'] == true ||
      provider.toLowerCase().contains('debrid') ||
      (url?.contains('real-debrid.com') ?? false);

  /// Appends default trackers to a magnet URI if none are present.
  static String ensureTrackers(String magnetUri) {
    final trimmed = magnetUri.trim();
    if (!trimmed.toLowerCase().startsWith('magnet:?')) return trimmed;
    if (trimmed.contains('&tr=') || trimmed.contains('?tr=')) return trimmed;
    final buf = StringBuffer(trimmed);
    for (final tr in defaultTrackers) {
      buf.write('&tr=${Uri.encodeComponent(tr)}');
    }
    return buf.toString();
  }

  /// Determines StreamType using URL, hints, MIME type, and known direct/embed domains.
  static StreamType detectStreamType(
    String? url, {
    Map<String, dynamic>? hints,
    String? mimeType,
    bool isVideo = false,
  }) {
    final trimmed = url?.trim() ?? '';
    final lower = trimmed.toLowerCase();

    // 1. BitTorrent P2P Magnet detection (explicit hash or magnet URI)
    if (lower.startsWith('magnet:?') ||
        lower.startsWith('urn:btih:') ||
        hints?['isTorrent'] == true) {
      return StreamType.magnet;
    }

    if (trimmed.isEmpty) return StreamType.unsupported;

    // 2. Explicit Debrid / Direct HTTP behavior hints
    if (hints?['isDebrid'] == true || hints?['isDirectHttp'] == true) {
      return StreamType.directHttp;
    }

    // 3. Explicit Web Embed behavior hints from provider
    if (hints?['isWebEmbed'] == true) {
      return StreamType.embed;
    }

    // 4. MIME type inspection
    final cleanMime = mimeType?.toLowerCase().trim() ?? '';
    if (cleanMime == 'application/x-mpegurl' ||
        cleanMime == 'application/vnd.apple.mpegurl' ||
        cleanMime == 'audio/x-mpegurl') {
      return StreamType.hls;
    }
    if (cleanMime == 'application/dash+xml') {
      return StreamType.dash;
    }
    if (cleanMime.startsWith('video/') ||
        cleanMime == 'application/x-matroska' ||
        cleanMime == 'application/mp4') {
      return StreamType.directHttp;
    }
    if (cleanMime == 'application/x-bittorrent') {
      return StreamType.magnet;
    }

    // 5. URI Path and extension boundary inspection
    final uri = Uri.tryParse(trimmed);
    final path = uri?.path.toLowerCase() ?? lower;

    if (path.endsWith('.m3u8') ||
        RegExp(r'\.m3u8(\?|$|#)', caseSensitive: false).hasMatch(lower)) {
      return StreamType.hls;
    }

    if (path.endsWith('.mpd') ||
        RegExp(r'\.mpd(\?|$|#)', caseSensitive: false).hasMatch(lower)) {
      return StreamType.dash;
    }

    if (path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm') ||
        path.endsWith('.mov') ||
        path.endsWith('.avi') ||
        path.endsWith('.ts') ||
        path.endsWith('.m4v') ||
        RegExp(r'\.(mp4|mkv|webm|mov|avi|ts|m4v)(\?|$|#)', caseSensitive: false)
            .hasMatch(lower)) {
      return StreamType.directHttp;
    }

    final filename = hints?['filename'] as String?;
    if (filename != null && filename.isNotEmpty) {
      final fLower = filename.toLowerCase();
      if (fLower.endsWith('.m3u8')) return StreamType.hls;
      if (fLower.endsWith('.mpd')) return StreamType.dash;
      if (fLower.endsWith('.mp4') ||
          fLower.endsWith('.mkv') ||
          fLower.endsWith('.webm') ||
          fLower.endsWith('.mov') ||
          fLower.endsWith('.avi') ||
          fLower.endsWith('.ts') ||
          fLower.endsWith('.m4v')) {
        return StreamType.directHttp;
      }
    }

    // 6. Known Debrid & Direct Streaming CDNs
    final host = uri?.host.toLowerCase() ?? '';
    if (host.contains('real-debrid.com') ||
        host.contains('alldebrid.com') ||
        host.contains('premiumize.me') ||
        host.contains('torbox.app') ||
        host.contains('debrid.it') ||
        (host.contains('torrentio.strem.fun') && lower.contains('/realdebrid='))) {
      return StreamType.directHttp;
    }

    if (isVideo) {
      return StreamType.directHttp;
    }

    if (hints?['isOrdinaryWebsite'] == true || hints?['isWebsite'] == true) {
      return StreamType.website;
    }

    if (host.contains('fmhy.net') ||
        host.contains('fmhy.pages.dev') ||
        host.contains('reddit.com') ||
        host.contains('imdb.com') ||
        host.contains('themoviedb.org') ||
        host.contains('wikipedia.org') ||
        host.contains('github.com')) {
      return StreamType.website;
    }

    if (host.contains('multiembed.mov') ||
        host.contains('2embed.') ||
        host.contains('vidsrc.') ||
        host.contains('autoembed.') ||
        host.contains('smashystream.') ||
        host.contains('moviesapi.club') ||
        host.contains('rive.stream') ||
        host.contains('frembed.') ||
        host.contains('vidlink.pro') ||
        host.contains('embed.su') ||
        host.contains('netflix.com') ||
        host.contains('primevideo.com') ||
        host.contains('youtube.com')) {
      return StreamType.embed;
    }

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return StreamType.embed;
    }

    return StreamType.unsupported;
  }

  /// Construct a StreamSource from a Stremio StreamResult with full metadata extraction
  factory StreamSource.fromStreamResult(StreamResult result, {String? providerName}) {
    final hints = Map<String, dynamic>.from(result.behaviorHints ?? const {});
    final rawUrl = result.url;
    final infoHash = result.hash ?? (hints['infoHash'] as String?);
    final isVideo = result.isVideo;
    final mimeType = result.type;

    String finalUrl = rawUrl;
    if (finalUrl.isEmpty && infoHash != null && infoHash.isNotEmpty) {
      finalUrl = 'magnet:?xt=urn:btih:$infoHash';
    }
    if (finalUrl.toLowerCase().startsWith('magnet:?')) {
      finalUrl = ensureTrackers(finalUrl);
    }

    final type = detectStreamType(
      finalUrl,
      hints: hints,
      mimeType: mimeType,
      isVideo: isVideo,
    );
    final isMagnet = type == StreamType.magnet;
    final isTorrent = hints['isTorrent'] == true || isMagnet;

    final provider = providerName ??
        (hints['provider'] as String?) ??
        (hints['addon'] as String?) ??
        'Stremio Addon';

    // Headers extraction
    final headers = <String, String>{};
    if (hints['headers'] is Map) {
      final rawHeaders = hints['headers'] as Map;
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    } else if (hints['proxyHeaders'] is Map &&
        (hints['proxyHeaders'] as Map)['request'] is Map) {
      final rawReq = (hints['proxyHeaders'] as Map)['request'] as Map;
      for (final entry in rawReq.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }

    if (headers.isEmpty && finalUrl.startsWith('http')) {
      final uri = Uri.tryParse(finalUrl);
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        headers['Referer'] = '${uri.scheme}://${uri.host}/';
        headers['Origin'] = '${uri.scheme}://${uri.host}';
        headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
      }
    }

    final rawDesc = result.description ?? result.name;
    final quality = hints['quality'] as String? ?? extractQuality(rawDesc);
    final seeders = hints['seeders'] as int? ?? extractSeeders(rawDesc);
    final language = hints['language'] as String? ?? extractLanguage(rawDesc);
    final sizeBytes = result.size ?? extractSizeBytes(rawDesc);
    final fileIdx = result.fileIndex ?? hints['fileIndex'] as int?;

    String? failure;
    bool playable = true;

    if (finalUrl.isEmpty) {
      playable = false;
      failure = 'Stream URL and infoHash are empty.';
    } else if (type == StreamType.website) {
      playable = false;
      failure = 'Ordinary website / directory link — not an in-app playable video embed.';
    }

    final source = StreamSource(
      id: '${provider}_${DateTime.now().microsecondsSinceEpoch}',
      provider: provider,
      name: result.name.isNotEmpty ? result.name : provider,
      url: finalUrl,
      infoHash: infoHash,
      fileIndex: fileIdx,
      type: type,
      mimeType: mimeType,
      headers: headers,
      quality: quality,
      language: language,
      seeders: seeders,
      sizeBytes: sizeBytes,
      isPlayableInternally: playable,
      failureReason: failure,
      metadata: hints,
    );

    StreamingLogger.instance.logClassification(
      provider,
      finalUrl,
      type.name,
      reason: 'MIME: $mimeType, isTorrent: $isTorrent, isDebrid: ${hints['isDebrid'] == true}',
    );

    return source;
  }

  static String? extractQuality(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final upper = text.toUpperCase();
    if (upper.contains('4K') || upper.contains('2160P') || upper.contains('UHD')) {
      return '4K UHD';
    }
    if (upper.contains('1080P') || upper.contains('FHD')) return '1080p FHD';
    if (upper.contains('720P') || upper.contains('HD')) return '720p HD';
    if (upper.contains('480P') || upper.contains('SD')) return '480p SD';
    if (upper.contains('DOLBY VISION') ||
        upper.contains(' DV ') ||
        upper.contains('DV-')) {
      return 'Dolby Vision';
    }
    if (upper.contains('HDR')) return 'HDR';
    if (upper.contains('CAM') || upper.contains('TELESYNC') || upper.contains(' TS ')) {
      return 'CAM/TS';
    }
    if (upper.contains('BDRIP') || upper.contains('BRRIP')) return 'BDRip';
    if (upper.contains('WEBRIP') || upper.contains('WEB-DL')) return 'WEB-DL';
    if (upper.contains('DVDRIP')) return 'DVDRip';
    return null;
  }

  static int? extractSeeders(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'[👤👥⚡]\s*(\d+)').firstMatch(text) ??
        RegExp(r'\b[sS]eeders?:\s*(\d+)\b').firstMatch(text);
    if (match != null) {
      final val = match.group(1);
      if (val != null) return int.tryParse(val);
    }
    return null;
  }

  static String? extractLanguage(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    if (text.contains('Multi') || text.contains('Dual')) return 'Multi Audio';
    if (text.contains('🇬🇧') ||
        RegExp(r'\b(ENG|English)\b', caseSensitive: false).hasMatch(text)) {
      return 'English';
    }
    if (text.contains('🇷🇺') ||
        RegExp(r'\b(RUS|Russian)\b', caseSensitive: false).hasMatch(text)) {
      return 'Russian';
    }
    if (text.contains('🇪🇸') ||
        RegExp(r'\b(SPA|Spanish|Castellano|Latino)\b', caseSensitive: false)
            .hasMatch(text)) {
      return 'Spanish';
    }
    if (text.contains('🇫🇷') ||
        RegExp(r'\b(FRE|French|VF|VOSTFR)\b', caseSensitive: false)
            .hasMatch(text)) {
      return 'French';
    }
    if (text.contains('🇩🇪') ||
        RegExp(r'\b(GER|German)\b', caseSensitive: false).hasMatch(text)) {
      return 'German';
    }
    if (text.contains('🇮🇹') ||
        RegExp(r'\b(ITA|Italian)\b', caseSensitive: false).hasMatch(text)) {
      return 'Italian';
    }
    if (text.contains('🇮🇳') ||
        RegExp(r'\b(HIN|Hindi|Tamil|Telugu)\b', caseSensitive: false)
            .hasMatch(text)) {
      return 'Hindi/Indian';
    }
    return null;
  }

  static int? extractSizeBytes(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match =
        RegExp(r'[💾]\s*([\d\.]+)\s*(GB|MB|KB)', caseSensitive: false)
                .firstMatch(text) ??
            RegExp(r'\b([\d\.]+)\s*(GB|MB|KB)\b', caseSensitive: false)
                .firstMatch(text);
    if (match != null) {
      final numVal = double.tryParse(match.group(1) ?? '');
      final unit = match.group(2)?.toUpperCase();
      if (numVal != null && unit != null) {
        if (unit == 'GB') return (numVal * 1024 * 1024 * 1024).round();
        if (unit == 'MB') return (numVal * 1024 * 1024).round();
        if (unit == 'KB') return (numVal * 1024).round();
      }
    }
    return null;
  }

  /// Convert back to a legacy StreamResult for components expecting legacy model
  StreamResult toStreamResult() {
    return StreamResult(
      name: name,
      url: url ?? '',
      type: mimeType ?? (type == StreamType.directHttp ? 'video/mp4' : 'text/html'),
      hash: infoHash,
      size: sizeBytes,
      fileIndex: fileIndex,
      behaviorHints: {
        ...metadata,
        'isWebEmbed': type == StreamType.embed,
        'isDirectHttp': type == StreamType.directHttp || type == StreamType.hls,
        'isTorrent': type == StreamType.magnet,
        'quality': quality,
        'language': language,
        'seeders': seeders,
        'provider': provider,
        'headers': headers,
      },
    );
  }
}
