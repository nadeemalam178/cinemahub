import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/catalogue/catalogue_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Home feed showing trending and popular content from TMDB.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final CatalogueService _catalogue;
  bool _loading = true;
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _popular = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _catalogue = context.read<CatalogueService>();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final trending = await _catalogue.getTrending();
      final popularMovies = await _catalogue.getPopularMovies();
      final popularSeries = await _catalogue.getPopularSeries();
      // Combine popular movies and series for the "Popular" section
      final popular = [...popularMovies, ...popularSeries];
      setState(() {
        _trending = trending;
        _popular = popular;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    return Scaffold(
      backgroundColor: CinemahubColors.background(Brightness.light),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: CinemahubColors.background(Brightness.light),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _HeroBanner(),
            ),
            actions: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: CinemahubSpacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContinueWatching(),
                  const SizedBox(height: CinemahubSpacing.lg),
                  SectionHeader(
                    title: 'Trending',
                    trailing: _trending.length > 10 ? 'See All' : null,
                    onSeeAll: () {},
                  ),
                  const SizedBox(height: CinemahubSpacing.md),
                  _buildContentGrid(_trending),
                  const SizedBox(height: CinemahubSpacing.lg),
                  SectionHeader(
                    title: 'Popular',
                    trailing: _popular.length > 10 ? 'See All' : null,
                    onSeeAll: () {},
                  ),
                  const SizedBox(height: CinemahubSpacing.md),
                  _buildContentGrid(_popular),
                  const SizedBox(height: CinemahubSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatching() {
    // Placeholder for continue watching - wired to SyncService in Milestone 4
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Continue Watching'),
        const SizedBox(height: CinemahubSpacing.md),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: CinemahubSpacing.md),
            itemBuilder: (_, i) => _ContentThumb(),
          ),
        ),
      ],
    );
  }

  Widget _buildContentGrid(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const SizedBox(
        height: 210,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: CinemahubSpacing.md),
        itemBuilder: (_, i) {
          final item = items[i];
          return MovieCard(item: item);
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Scaffold(
      backgroundColor: CinemahubColors.background(Brightness.light),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorState() {
    return ErrorState(
      message: _error ?? 'Failed to load data',
      onRetry: _loadData,
    );
  }
}

/// A movie/TV show card for horizontal lists.
class MovieCard extends StatelessWidget {
  const MovieCard({super.key, required this.item});

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
        // Navigate to detail screen - wired in Milestone 3
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
      child: SizedBox(
        width: 140,
        height: 210,
        child: CinemaCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: _imageUrl,
                    width: 140,
                    height: 210,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 140,
                      height: 210,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light).withValues(alpha: 0.3),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 140,
                      height: 210,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light),
                      ),
                      child: const Icon(Icons.play_circle_rounded, size: 48, color: Colors.grey),
                    ),
                  ),
                )
              else
                Container(
                  width: 140,
                  height: 210,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light),
                  ),
                  child: const Icon(Icons.play_circle_rounded, size: 48, color: Colors.grey),
                ),
              Padding(
                padding: const EdgeInsets.all(CinemahubSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
    );
  }
}

/// A small content thumbnail for continue watching.
class _ContentThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 200,
      height: 120,
      child: CinemaCard(
        child: Row(
          children: [
            Container(
              width: 80,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light),
              ),
            ),
            const SizedBox(width: CinemahubSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Show Title',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'S01E05 · Episode Title',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF3A0D2E), Color(0xFF1A0B18)]
                  : const [Color(0xFFF3D3DC), Color(0xFFFCE4EC)],
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  isDark
                      ? CinemahubColors.darkScrim
                      : CinemahubColors.lightScrim,
                ],
                stops: const [0.4, 1.0],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: CinemahubSpacing.lg,
            right: CinemahubSpacing.lg,
            bottom: CinemahubSpacing.xl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CinemahubSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: CinemahubRadius.allPill,
                  color: CinemahubColors.primary,
                ),
                child: const Text(
                  'FEATURED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: CinemahubSpacing.sm),
              Text(
                'CinemaHub Originals',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: isDark ? Colors.white : CinemahubColors.onLight,
                ),
              ),
              const SizedBox(height: CinemahubSpacing.sm),
              Text(
                'A premium private streaming experience, '
                'built for the people you trust.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.8)
                      : CinemahubColors.onLightMuted,
                ),
              ),
              const SizedBox(height: CinemahubSpacing.md),
              Row(
                children: [
                  CinemaButton(
                    label: 'Play',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () {},
                    expanded: false,
                  ),
                  const SizedBox(width: CinemahubSpacing.md),
                  CinemaButton(
                    label: 'More Info',
                    icon: Icons.info_outline_rounded,
                    onPressed: () {},
                    expanded: false,
                    outlined: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}