import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/sync_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// My List (Watchlist) & Watch History screen.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final SyncService _syncService;
  bool _loading = true;
  List<Map<String, dynamic>> _watchlist = [];
  List<Map<String, dynamic>> _watchHistory = [];

  @override
  void initState() {
    super.initState();
    _syncService = context.read<SyncService>();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _syncService.getWatchlist(),
        _syncService.getWatchHistory(),
      ]);
      if (mounted) {
        setState(() {
          _watchlist = results[0];
          _watchHistory = results[1];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _removeWatchlistItem(String contentId) async {
    await _syncService.removeFromWatchlist(contentId);
    if (!mounted) return;
    setState(() {
      _watchlist.removeWhere((item) => (item['id'] ?? '').toString() == contentId);
    });
  }

  Future<void> _removeHistoryItem(String contentId) async {
    await _syncService.removeFromWatchHistory(contentId);
    if (!mounted) return;
    setState(() {
      _watchHistory.removeWhere(
        (item) => (item['id'] ?? item['contentId'] ?? '').toString() == contentId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Library'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.bookmark_rounded), text: 'Watchlist'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Watch History'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildList(
                    items: _watchlist,
                    isHistory: false,
                    emptyIcon: Icons.bookmark_outline_rounded,
                    emptyTitle: 'Your watchlist is empty',
                    emptyMessage:
                        'Bookmark movies and series from their detail pages to see them here.',
                  ),
                  _buildList(
                    items: _watchHistory,
                    isHistory: true,
                    emptyIcon: Icons.history_rounded,
                    emptyTitle: 'No watch history yet',
                    emptyMessage:
                        'Titles you watch will appear here with your playback progress.',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildList({
    required List<Map<String, dynamic>> items,
    required bool isHistory,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: EmptyState(
                icon: emptyIcon,
                title: emptyTitle,
                message: emptyMessage,
                onAction: () => Navigator.pushNamed(context, '/search'),
                actionLabel: 'Find Content',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(CinemahubSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: CinemahubSpacing.md),
        itemBuilder: (context, index) {
          final item = items[index];
          final contentId =
              (item['id'] ?? item['contentId'] ?? '').toString();
          return _LibraryItemCard(
            item: item,
            isHistory: isHistory,
            onRemove: contentId.isEmpty
                ? null
                : () => isHistory
                    ? _removeHistoryItem(contentId)
                    : _removeWatchlistItem(contentId),
          );
        },
      ),
    );
  }
}

class _LibraryItemCard extends StatelessWidget {
  const _LibraryItemCard({
    required this.item,
    required this.isHistory,
    this.onRemove,
  });

  final Map<String, dynamic> item;
  final bool isHistory;
  final VoidCallback? onRemove;

  String get _title =>
      (item['title'] as String?) ??
      (item['name'] as String?) ??
      _fallbackTitleFromId;

  String get _fallbackTitleFromId {
    final raw = (item['id'] ?? item['contentId'] ?? '').toString();
    return raw.isNotEmpty ? raw : 'Unknown Title';
  }

  String get _imageUrl {
    final normalized = item['posterUrl'] as String?;
    if (normalized != null && normalized.isNotEmpty) return normalized;
    final posterPath = item['poster_path'] as String?;
    if (posterPath != null && posterPath.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w200$posterPath';
    }
    return '';
  }

  double? get _rating =>
      (item['rating'] as num?)?.toDouble() ??
      (item['vote_average'] as num?)?.toDouble();

  String get _type {
    final rawType = item['type'] as String?;
    if (rawType == 'movie' || rawType == 'series') return rawType!;
    final rawId = (item['id'] ?? item['contentId'] ?? '').toString();
    if (rawId.contains(':series:') || item.containsKey('first_air_date')) {
      return 'series';
    }
    return 'movie';
  }

  String get _resolvedId {
    final raw = (item['id'] ?? item['contentId'] ?? '').toString();
    if (raw.startsWith('tmdb:') || raw.startsWith('stremio:')) {
      return raw;
    }
    return 'tmdb:$_type:$raw';
  }

  String get _releaseYear {
    final date =
        (item['releaseDate'] ?? item['first_air_date'] ?? item['release_date'])
            ?.toString();
    if (date != null && date.isNotEmpty) {
      return date.length >= 4 ? date.substring(0, 4) : date;
    }
    return '';
  }

  double? get _progressFraction {
    if (!isHistory) return null;
    final pos = (item['positionSeconds'] as num?)?.toDouble() ?? 0.0;
    final dur = (item['durationSeconds'] as num?)?.toDouble() ?? 0.0;
    if (dur <= 0) return null;
    return (pos / dur).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _progressFraction;

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/details',
          arguments: {
            'id': _resolvedId,
            'type': _type,
            'title': _title,
            'posterUrl': _imageUrl.isEmpty ? null : _imageUrl,
            'backdropUrl': item['backdropUrl'] as String?,
            'overview': item['overview'] as String?,
            'rating': _rating,
            'releaseDate':
                (item['releaseDate'] ?? item['first_air_date'] ?? item['release_date'])
                    ?.toString(),
            'genreIds': (item['genreIds'] as List?)?.cast<int>(),
          },
        );
      },
      child: CinemaCard(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _imageUrl,
                      width: 80,
                      height: 118,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _PosterPlaceholder(
                        isDark: isDark,
                      ),
                    )
                  : _PosterPlaceholder(isDark: isDark),
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
                  if (_releaseYear.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$_releaseYear • ${_type.toUpperCase()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                  if (_rating != null && _rating! > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          _rating!.toStringAsFixed(1),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.amber,
                                  ),
                        ),
                      ],
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor:
                          isDark ? Colors.white12 : Colors.black12,
                      color: CinemahubColors.primary,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(progress * 100).round()}% watched',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: isHistory ? 'Remove from history' : 'Remove from watchlist',
                onPressed: onRemove,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 118,
      decoration: BoxDecoration(
        color: CinemahubColors.surface(
          isDark ? Brightness.dark : Brightness.light,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.play_circle_rounded,
        size: 32,
        color: Colors.grey,
      ),
    );
  }
}
