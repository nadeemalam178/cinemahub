import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/sync_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// My List / Watch History (wired in Milestone 5).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final SyncService _syncService;
  bool _loading = true;
  List<Map<String, dynamic>> _watchHistory = [];

  @override
  void initState() {
    super.initState();
    _syncService = context.read<SyncService>();
    _loadWatchHistory();
  }

  Future<void> _loadWatchHistory() async {
    setState(() => _loading = true);
    try {
      final history = await _syncService.getWatchHistory();
      if (mounted) {
        setState(() {
          _watchHistory = history;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My List')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_watchHistory.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_outline_rounded,
        title: 'Your list is empty',
        message:
            'Add movies and series to your watchlist to see them here. '
            'They sync across all your devices.',
        onAction: () {
          // Open search to add items
          Navigator.pushNamed(context, '/search');
        },
        actionLabel: 'Find Content',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(CinemahubSpacing.lg),
      itemCount: _watchHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: CinemahubSpacing.md),
      itemBuilder: (context, index) {
        final item = _watchHistory[index];
        return _WatchListItem(item: item);
      },
    );
  }
}

class _WatchListItem extends StatelessWidget {
  const _WatchListItem({required this.item});

  final Map<String, dynamic> item;

  String get _title =>
      item['title'] ?? item['name'] ?? 'Unknown Title';

  String? get _posterPath => item['poster_path'] as String?;

  String get _imageUrl =>
      _posterPath != null
          ? 'https://image.tmdb.org/t/p/w200$_posterPath'
          : '';

  double? get _rating => (item['vote_average'] as num?)?.toDouble();

  String get _releaseYear {
    final date = item['first_air_date'] ?? item['release_date'];
    if (date != null && date.toString().isNotEmpty) {
      return date.toString().substring(0, 4);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        final id = item['id'];
        final type = item.containsKey('first_air_date') ? 'series' : 'movie';
        Navigator.pushNamed(
          context,
          '/details',
          arguments: {
            'id': 'tmdb:$id',
            'type': type,
            'title': _title,
            'posterUrl': _imageUrl.isEmpty ? null : _imageUrl,
          },
        );
      },
      child: CinemaCard(
        child: Row(
          children: [
            if (_imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _imageUrl,
                  width: 80,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80,
                    height: 120,
                    decoration: BoxDecoration(
                      color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light),
                    ),
                    child: const Icon(Icons.play_circle_rounded, size: 32, color: Colors.grey),
                  ),
                ),
              )
            else
              Container(
                width: 80,
                height: 120,
                decoration: BoxDecoration(
                  color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_rounded, size: 32, color: Colors.grey),
              ),
            const SizedBox(width: CinemahubSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _releaseYear,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  if (_rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          _rating!.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}