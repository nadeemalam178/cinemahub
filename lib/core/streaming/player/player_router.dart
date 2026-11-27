import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diagnostics/streaming_logger.dart';
import '../models/stream_source.dart';
import 'native_video_player.dart';
import 'web_embed_player.dart';

enum TargetPlayer {
  nativePlayer,    // Chewie / ExoPlayer for MP4, HLS, DASH, and native libtorrent4j P2P streams
  webPlayer,       // In-App InAppWebView with ContentBlockers + Anti-Ad UserScript + Stream Sniffer
  torrentNotice,   // Optional fallback sheet if external app dispatch is requested
  externalBrowser, // System browser for general websites/directories
  unsupported,     // Diagnostic fallback
}

class PlayerRoutingDecision {
  const PlayerRoutingDecision({
    required this.player,
    required this.source,
    required this.reason,
  });

  final TargetPlayer player;
  final StreamSource source;
  final String reason;

  @override
  String toString() => 'PlayerRoutingDecision($player, reason: $reason)';
}

/// Routes incoming streams strictly to the appropriate playback engine.
class PlayerRouter {
  const PlayerRouter();

  /// Determine target player and validate stream preconditions
  PlayerRoutingDecision route(StreamSource source) {
    // 1. BitTorrent P2P Magnets -> Native libtorrent4j + ExoPlayer
    if (source.type == StreamType.magnet ||
        (source.url != null && source.url!.toLowerCase().startsWith('magnet:?')) ||
        (source.infoHash != null && source.infoHash!.isNotEmpty && (source.url ?? '').isEmpty)) {
      final decision = PlayerRoutingDecision(
        player: TargetPlayer.nativePlayer,
        source: source,
        reason: 'BitTorrent P2P magnet link routed to internal libtorrent4j engine.',
      );
      StreamingLogger.instance.log(
        stage: 'PlayerRouter',
        message: 'Routed to In-App Native Torrent Streamer',
        provider: source.provider,
        streamUrl: source.url,
      );
      return decision;
    }

    // 2. Web Embeds
    if (source.type == StreamType.embed || source.metadata['isWebEmbed'] == true) {
      if (source.url == null || source.url!.trim().isEmpty) {
        final decision = PlayerRoutingDecision(
          player: TargetPlayer.unsupported,
          source: source,
          reason: 'Embed stream URL is empty or malformed.',
        );
        StreamingLogger.instance.log(
          stage: 'PlayerRouter',
          message: 'Routing failed: Empty embed URL',
          provider: source.provider,
          severity: LogSeverity.error,
        );
        return decision;
      }

      final decision = PlayerRoutingDecision(
        player: TargetPlayer.webPlayer,
        source: source,
        reason: 'Embedded video stream routed to Ad-Blocked In-App Web Player.',
      );
      StreamingLogger.instance.log(
        stage: 'PlayerRouter',
        message: 'Routed to In-App Web Player',
        provider: source.provider,
        streamUrl: source.url,
      );
      return decision;
    }

    // 3. Direct Media: MP4, MKV, HLS (.m3u8), DASH (.mpd)
    if (source.type == StreamType.directHttp ||
        source.type == StreamType.hls ||
        source.type == StreamType.dash) {
      if (source.url == null || source.url!.trim().isEmpty) {
        final decision = PlayerRoutingDecision(
          player: TargetPlayer.unsupported,
          source: source,
          reason: 'Direct media URL is empty or malformed.',
        );
        StreamingLogger.instance.log(
          stage: 'PlayerRouter',
          message: 'Routing failed: Empty media URL',
          provider: source.provider,
          severity: LogSeverity.error,
        );
        return decision;
      }

      final decision = PlayerRoutingDecision(
        player: TargetPlayer.nativePlayer,
        source: source,
        reason: 'Direct media stream (${source.type.name}) routed to Native ExoPlayer with headers.',
      );
      StreamingLogger.instance.log(
        stage: 'PlayerRouter',
        message: 'Routed to Native Video Player (${source.type.name})',
        provider: source.provider,
        streamUrl: source.url,
      );
      return decision;
    }

    // 4. Ordinary Websites / Directory Links
    if (source.type == StreamType.website || source.metadata['isOrdinaryWebsite'] == true) {
      final decision = PlayerRoutingDecision(
        player: TargetPlayer.externalBrowser,
        source: source,
        reason: 'External directory / website portal link. Not an in-app playable embed.',
      );
      StreamingLogger.instance.log(
        stage: 'PlayerRouter',
        message: 'Routed to External Browser',
        provider: source.provider,
        streamUrl: source.url,
        details: decision.reason,
      );
      return decision;
    }

    // 5. Fallback: Unsupported stream type
    final decision = PlayerRoutingDecision(
      player: TargetPlayer.unsupported,
      source: source,
      reason: source.failureReason ?? 'Unrecognized or unplayable stream format.',
    );
    StreamingLogger.instance.log(
      stage: 'PlayerRouter',
      message: 'Routing rejected: Unsupported format',
      provider: source.provider,
      streamUrl: source.url,
      severity: LogSeverity.warning,
      details: decision.reason,
    );
    return decision;
  }

  /// Launch player route into Navigator, enriching stream metadata for subtitles & sync.
  Future<void> navigateToPlayer({
    required BuildContext context,
    required StreamSource source,
    required String title,
    VoidCallback? onFirstFrame,
    String? contentId,
    String? imdbId,
    String? contentType,
    int? season,
    int? episode,
    String? posterUrl,
    String? releaseDate,
    double? rating,
  }) async {
    final enrichedMetadata = Map<String, dynamic>.from(source.metadata);
    if (contentId != null && contentId.isNotEmpty) enrichedMetadata['contentId'] = contentId;
    if (imdbId != null && imdbId.isNotEmpty) enrichedMetadata['imdb_id'] = imdbId;
    if (contentType != null && contentType.isNotEmpty) enrichedMetadata['type'] = contentType;
    if (season != null) enrichedMetadata['season'] = season;
    if (episode != null) enrichedMetadata['episode'] = episode;
    if (posterUrl != null && posterUrl.isNotEmpty) enrichedMetadata['posterUrl'] = posterUrl;
    if (releaseDate != null && releaseDate.isNotEmpty) enrichedMetadata['releaseDate'] = releaseDate;
    if (rating != null) enrichedMetadata['rating'] = rating;

    final enrichedSource = source.copyWith(metadata: enrichedMetadata);
    final decision = route(enrichedSource);

    switch (decision.player) {
      case TargetPlayer.nativePlayer:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              body: NativeVideoPlayer(
                source: enrichedSource,
                title: title,
                onFirstFrameRendered: onFirstFrame,
              ),
            ),
          ),
        );
        break;

      case TargetPlayer.webPlayer:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WebEmbedPlayer(
              source: enrichedSource,
              title: title,
              onFirstFrameRendered: onFirstFrame,
            ),
          ),
        );
        break;

      case TargetPlayer.torrentNotice:
        await showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF141422),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => _TorrentNoticeSheet(source: enrichedSource),
        );
        break;

      case TargetPlayer.externalBrowser:
        if (enrichedSource.url != null && enrichedSource.url!.isNotEmpty) {
          final uri = Uri.tryParse(enrichedSource.url!);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        break;

      case TargetPlayer.unsupported:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback unavailable: ${decision.reason}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
        break;
    }
  }
}

class _TorrentNoticeSheet extends StatelessWidget {
  const _TorrentNoticeSheet({required this.source});
  final StreamSource source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hub_rounded, color: Colors.purpleAccent, size: 24),
              SizedBox(width: 10),
              Text(
                'P2P Torrent Stream',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'You can open this magnet link directly in VLC, Nova Video Player, or any torrent client.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open in External App (VLC / BitTorrent)'),
            onPressed: () async {
              Navigator.pop(context);
              final raw = source.url;
              if (raw != null && raw.isNotEmpty) {
                final uri = Uri.tryParse(raw);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No external player app found for magnet link.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Magnet URI'),
            onPressed: () async {
              Navigator.pop(context);
              final raw = source.url;
              if (raw != null && raw.isNotEmpty) {
                await Clipboard.setData(ClipboardData(text: raw));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Magnet link copied to clipboard.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
