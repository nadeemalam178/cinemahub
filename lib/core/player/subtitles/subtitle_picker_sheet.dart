import 'package:flutter/material.dart';
import '../../theme/cinemahub_colors.dart';
import 'subtitle_model.dart';

/// Modal bottom sheet for choosing subtitle tracks, adjusting sync offset, and customizing text size.
class SubtitlePickerSheet extends StatefulWidget {
  const SubtitlePickerSheet({
    super.key,
    required this.tracks,
    required this.selectedTrack,
    required this.onTrackSelected,
    required this.syncDelay,
    required this.onSyncDelayChanged,
    required this.style,
    required this.onStyleChanged,
  });

  final List<CinemaSubtitleTrack> tracks;
  final CinemaSubtitleTrack? selectedTrack;
  final ValueChanged<CinemaSubtitleTrack?> onTrackSelected;
  final Duration syncDelay;
  final ValueChanged<Duration> onSyncDelayChanged;
  final CinemaSubtitleStyle style;
  final ValueChanged<CinemaSubtitleStyle> onStyleChanged;

  @override
  State<SubtitlePickerSheet> createState() => _SubtitlePickerSheetState();
}

class _SubtitlePickerSheetState extends State<SubtitlePickerSheet> {
  late double _delaySeconds;
  late double _fontSize;

  @override
  void initState() {
    super.initState();
    _delaySeconds = widget.syncDelay.inMilliseconds / 1000.0;
    _fontSize = widget.style.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF141422),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.subtitles_rounded, color: CinemahubColors.primary, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Subtitles & Captions',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sync Delay Offset Slider
          Row(
            children: [
              const Text(
                'Sync Delay:',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '${_delaySeconds >= 0 ? "+" : ""}${_delaySeconds.toStringAsFixed(1)}s',
                style: const TextStyle(color: CinemahubColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: _delaySeconds,
            min: -5.0,
            max: 5.0,
            divisions: 20,
            activeColor: CinemahubColors.primary,
            inactiveColor: Colors.white24,
            label: '${_delaySeconds >= 0 ? "+" : ""}${_delaySeconds.toStringAsFixed(1)}s',
            onChanged: (val) {
              setState(() => _delaySeconds = val);
              widget.onSyncDelayChanged(Duration(milliseconds: (val * 1000).round()));
            },
          ),

          const SizedBox(height: 10),

          // Subtitle Font Size Selection
          Row(
            children: [
              const Text(
                'Text Size:',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              _SizeChip(
                label: 'Small',
                size: 14.0,
                selected: _fontSize == 14.0,
                onTap: () {
                  setState(() => _fontSize = 14.0);
                  widget.onStyleChanged(widget.style.copyWith(fontSize: 14.0));
                },
              ),
              const SizedBox(width: 8),
              _SizeChip(
                label: 'Medium',
                size: 16.0,
                selected: _fontSize == 16.0,
                onTap: () {
                  setState(() => _fontSize = 16.0);
                  widget.onStyleChanged(widget.style.copyWith(fontSize: 16.0));
                },
              ),
              const SizedBox(width: 8),
              _SizeChip(
                label: 'Large',
                size: 20.0,
                selected: _fontSize == 20.0,
                onTap: () {
                  setState(() => _fontSize = 20.0);
                  widget.onStyleChanged(widget.style.copyWith(fontSize: 20.0));
                },
              ),
            ],
          ),

          const Divider(color: Colors.white12, height: 24),

          // Track List
          const Text(
            'Select Track:',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Off option
                  _TrackTile(
                    title: 'Off',
                    subtitle: 'Disable subtitles',
                    selected: widget.selectedTrack == null,
                    onTap: () {
                      widget.onTrackSelected(null);
                      Navigator.pop(context);
                    },
                  ),
                  ...widget.tracks.map(
                    (track) => _TrackTile(
                      title: track.label,
                      subtitle: 'Source: ${track.source}',
                      selected: widget.selectedTrack?.id == track.id,
                      onTap: () {
                        widget.onTrackSelected(track);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? CinemahubColors.primary : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? CinemahubColors.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? CinemahubColors.primary : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        dense: true,
        leading: Icon(
          selected ? Icons.check_circle_rounded : Icons.subtitles_outlined,
          color: selected ? CinemahubColors.primary : Colors.white54,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.9),
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ),
    );
  }
}
