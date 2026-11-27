import 'package:flutter/material.dart';
import '../../core/streaming/diagnostics/streaming_logger.dart';
import '../../core/streaming/models/stream_source.dart';
import '../../core/streaming/player/player_router.dart';
import '../../core/theme/cinemahub_colors.dart';

class PlaybackDiagnosticsScreen extends StatefulWidget {
  const PlaybackDiagnosticsScreen({super.key});

  @override
  State<PlaybackDiagnosticsScreen> createState() => _PlaybackDiagnosticsScreenState();
}

class DiagnosticTestCase {
  DiagnosticTestCase({
    required this.name,
    required this.formatLabel,
    required this.source,
    required this.description,
  });

  final String name;
  final String formatLabel;
  final StreamSource source;
  final String description;

  String? lastRouterDecision;
  String? lastInitStatus;
  String? lastDimensions;
  String? lastFirstFrameMetric;
  String? lastBufferingStatus;
  String? lastError;
  bool tested = false;
}

class _PlaybackDiagnosticsScreenState extends State<PlaybackDiagnosticsScreen> {
  final PlayerRouter _router = const PlayerRouter();

  late final List<DiagnosticTestCase> _testCases = [
    // 1. Direct MP4
    DiagnosticTestCase(
      name: 'Direct MP4 Stream',
      formatLabel: 'MP4 / Progressive',
      description: 'VideoJS Oceans Sample (1080p MP4, AAC, Byte-range)',
      source: const StreamSource(
        id: 'diag-mp4',
        provider: 'Diagnostic Test Suite',
        name: 'VideoJS Oceans (1080p MP4)',
        url: 'https://vjs.zencdn.net/v/oceans.mp4',
        type: StreamType.directHttp,
        isPlayableInternally: true,
      ),
    ),

    // 2. HLS (.m3u8)
    DiagnosticTestCase(
      name: 'HLS Master Playlist',
      formatLabel: 'HLS (.m3u8)',
      description: 'Mux adaptive bitrate HLS stream (multi-rendition)',
      source: const StreamSource(
        id: 'diag-hls',
        provider: 'Diagnostic Test Suite',
        name: 'Mux HLS Test Feed',
        url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        type: StreamType.hls,
        isPlayableInternally: true,
      ),
    ),

    // 3. MPEG-DASH (.mpd)
    DiagnosticTestCase(
      name: 'MPEG-DASH Stream',
      formatLabel: 'DASH (.mpd)',
      description: 'Google Shaka Angel One DASH manifest with media3-exoplayer-dash',
      source: const StreamSource(
        id: 'diag-dash',
        provider: 'Diagnostic Test Suite',
        name: 'Shaka Angel One DASH Feed',
        url: 'https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd',
        type: StreamType.dash,
        isPlayableInternally: true,
      ),
    ),

    // 4. HTML5 Web Embed
    DiagnosticTestCase(
      name: 'HTML5 Web Embed Player',
      formatLabel: 'Web Embed / WebView',
      description: 'Archive.org Clean HTML5 Video Embed (Ad-free & Unblocked)',
      source: const StreamSource(
        id: 'diag-embed',
        provider: 'Diagnostic Test Suite',
        name: 'Archive.org Big Buck Bunny Embed',
        url: 'https://archive.org/embed/BigBuckBunny_124',
        type: StreamType.embed,
        isPlayableInternally: true,
        metadata: {'isWebEmbed': true},
      ),
    ),

    // 5. Invalid URL
    DiagnosticTestCase(
      name: 'Invalid / Broken Stream URL',
      formatLabel: 'Error Handling',
      description: 'Non-existent host URL to test clean fallback and error handling',
      source: const StreamSource(
        id: 'diag-invalid',
        provider: 'Diagnostic Test Suite',
        name: 'Unresolvable Stream Host',
        url: 'https://invalid.stream.hoster.broken/404.mp4',
        type: StreamType.directHttp,
        isPlayableInternally: true,
      ),
    ),

    // 6. BitTorrent Magnet URI (In-app native libtorrent4j engine)
    DiagnosticTestCase(
      name: 'BitTorrent Magnet URI',
      formatLabel: 'P2P Magnet (In-App)',
      description: 'P2P magnet URI routed to native libtorrent4j + local HTTP proxy into ExoPlayer',
      source: const StreamSource(
        id: 'diag-magnet',
        provider: 'Diagnostic Test Suite',
        name: 'Big Buck Bunny (Public Magnet)',
        url: 'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny',
        type: StreamType.magnet,
        isPlayableInternally: true,
      ),
    ),
  ];

  Future<void> _runTestCase(DiagnosticTestCase test) async {
    final decision = _router.route(test.source);

    setState(() {
      test.tested = true;
      test.lastRouterDecision = '${decision.player.name} (${decision.reason})';
      test.lastInitStatus = 'Dispatching to ${decision.player.name}...';
      test.lastError = null;
    });

    StreamingLogger.instance.log(
      stage: 'DiagnosticsRun',
      message: 'Running diagnostic test: ${test.name}',
      provider: test.source.provider,
      streamUrl: test.source.url,
    );

    try {
      await _router.navigateToPlayer(
        context: context,
        source: test.source,
        title: test.name,
        onFirstFrame: () {
          if (mounted) {
            setState(() {
              test.lastFirstFrameMetric = 'Approximation: Playback active with rendered surface texture';
              test.lastInitStatus = 'Rendered Active';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          test.lastInitStatus = 'Completed / Player Closed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          test.lastError = e.toString();
          test.lastInitStatus = 'Error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CinemahubColors.darkBackground : CinemahubColors.lightBackground,
      appBar: AppBar(
        title: const Text('Playback Engine Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: 'View Diagnostics Log',
            onPressed: _showLogViewer,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Developer Verification Suite — Phase 2.2.\n'
                    'Runs authorized public test media across ExoPlayer, WebView, and libtorrent4j.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final test in _testCases) _buildTestCaseCard(test, isDark),
        ],
      ),
    );
  }

  Widget _buildTestCaseCard(DiagnosticTestCase test, bool isDark) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? CinemahubColors.darkSurface : CinemahubColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: test.tested
              ? (test.lastError != null ? Colors.redAccent : Colors.greenAccent)
              : (isDark ? Colors.white12 : Colors.black12),
          width: test.tested ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        test.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        test.formatLabel,
                        style: const TextStyle(
                          color: CinemahubColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _runTestCase(test),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(test.tested ? 'Re-run' : 'Test'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              test.description,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 12,
              ),
            ),
            if (test.tested) ...[
              const Divider(height: 20),
              _buildDetailRow('Routing Decision', test.lastRouterDecision ?? 'Pending', isDark),
              _buildDetailRow('Player State', test.lastInitStatus ?? 'Idle', isDark),
              if (test.lastFirstFrameMetric != null)
                _buildDetailRow('First Frame Event', test.lastFirstFrameMetric!, isDark),
              if (test.lastError != null)
                _buildDetailRow('Reported Error', test.lastError!, isDark, isError: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: isError
                    ? Colors.redAccent
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogViewer() {
    final logs = StreamingLogger.instance.exportFormattedLogs();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141422),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Streaming Diagnostics Log',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    logs.isEmpty ? 'No events recorded yet.' : logs,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
