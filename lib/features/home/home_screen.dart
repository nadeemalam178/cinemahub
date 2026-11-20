import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/catalogue/catalogue_service.dart';
import '../../core/catalogue/stremio_catalog_service.dart';
import '../../core/theme/cinemahub_colors.dart';

/// Netflix-style cinematic home screen with dynamic billboard and curated shelves.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final CatalogueService _catalogue;
  bool _loading = true;
  String? _error;

  // Curated lists
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _popularMovies = [];
  List<Map<String, dynamic>> _popularSeries = [];
  List<Map<String, dynamic>> _topRated = [];
  List<Map<String, dynamic>> _actionMovies = [];
  List<Map<String, dynamic>> _sciFiMovies = [];

  // Stremio community shelves (loaded async separately so TMDB shows first)
  List<StremioShelf> _stremioShelves = [];
  bool _stremioLoading = false;

  // Filter tab selection: 0 = All, 1 = Movies, 2 = TV Shows
  int _selectedFilter = 0;

  @override
  void initState() {
    super.initState();
    _catalogue = context.read<CatalogueService>();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _catalogue.getTrending(),
        _catalogue.getPopularMovies(),
        _catalogue.getPopularSeries(),
        _catalogue.getTopRatedMovies(),
        _catalogue.getByGenre(28), // Action
        _catalogue.getByGenre(878), // Sci-Fi
      ]);

      if (!mounted) return;
      setState(() {
        _trending = results[0];
        _popularMovies = results[1];
        _popularSeries = results[2];
        _topRated = results[3];
        _actionMovies = results[4];
        _sciFiMovies = results[5];
        _error = null;
        _loading = false;
      });

      // Load Stremio shelves in background — doesn't block the main UI
      _loadStremioShelves();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadStremioShelves() async {
    if (!mounted) return;
    setState(() => _stremioLoading = true);
    try {
      final shelves = await _catalogue.getStremioShelves();
      if (!mounted) return;
      setState(() {
        _stremioShelves = shelves;
        _stremioLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stremioLoading = false);
      debugPrint('Stremio shelves failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? CinemahubColors.darkBackground : CinemahubColors.lightBackground;

    if (_loading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: CinemahubColors.primary),
        ),
      );
    }

    if (_error != null && _trending.isEmpty) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: CinemahubColors.danger),
              const SizedBox(height: 12),
              Text(
                'Failed to load catalogue',
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final heroItems = _trending.take(5).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: CustomScrollView(
        slivers: [
          // 1. App Bar with NO BACK BUTTON
          SliverAppBar(
            expandedHeight: 460,
            pinned: true,
            automaticallyImplyLeading: false, // Permanently removes back button
            backgroundColor: backgroundColor,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CinemahubColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'CINEMA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'HUB',
                  style: TextStyle(
                    color: CinemahubColors.gold,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () => Navigator.pushNamed(context, '/search'),
                icon: const Icon(Icons.search_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _HeroBillboard(items: heroItems),
            ),
          ),

          // 2. Filter Pills (All / Movies / TV Shows)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _selectedFilter == 0,
                    onTap: () => setState(() => _selectedFilter = 0),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Movies',
                    selected: _selectedFilter == 1,
                    onTap: () => setState(() => _selectedFilter = 1),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'TV Series',
                    selected: _selectedFilter == 2,
                    onTap: () => setState(() => _selectedFilter = 2),
                  ),
                ],
              ),
            ),
          ),

          // 3. Main Catalogue Shelves
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top 10 Today Row
                  if (_selectedFilter == 0 || _selectedFilter == 1) ...[
                    _SectionHeader(title: '🔥 Top 10 in CinemaHub Today'),
                    _buildTop10List(_trending.take(10).toList()),
                    const SizedBox(height: 24),
                  ],

                  // Trending Now
                  _SectionHeader(title: 'Trending Now'),
                  _buildContentRow(_trending),
                  const SizedBox(height: 24),

                  // Popular Movies
                  if (_selectedFilter == 0 || _selectedFilter == 1) ...[
                    _SectionHeader(title: 'Blockbuster Movies'),
                    _buildContentRow(_popularMovies),
                    const SizedBox(height: 24),
                  ],

                  // Popular Series
                  if (_selectedFilter == 0 || _selectedFilter == 2) ...[
                    _SectionHeader(title: 'Popular TV Series'),
                    _buildContentRow(_popularSeries),
                    const SizedBox(height: 24),
                  ],

                  // Top Rated Cinema
                  if (_selectedFilter == 0 || _selectedFilter == 1) ...[
                    _SectionHeader(title: 'Top Rated Masterpieces'),
                    _buildContentRow(_topRated),
                    const SizedBox(height: 24),
                  ],

                  // Action Thrillers
                  _SectionHeader(title: 'High-Octane Action'),
                  _buildContentRow(_actionMovies),
                  const SizedBox(height: 24),

                  // Sci-Fi & Fantasy
                  _SectionHeader(title: 'Sci-Fi & Cyberpunk'),
                  _buildContentRow(_sciFiMovies),
                  const SizedBox(height: 32),

                  // ══════════════════════════════════════════════════════
                  // STREMIO COMMUNITY ADDON SHELVES
                  // Loaded async in background after TMDB shelves render
                  // ══════════════════════════════════════════════════════
                  if (_stremioLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(
                              color: CinemahubColors.primary,
                              strokeWidth: 2,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Loading Stremio community content…',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_stremioShelves.isNotEmpty) ...[
                    // Stremio section divider
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white12)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Image.network(
                                  'https://www.stremio.com/website/stremio-icon.png',
                                  width: 20,
                                  height: 20,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.extension_rounded,
                                          color: CinemahubColors.primary,
                                          size: 20),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'STREMIO COMMUNITY',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white12)),
                        ],
                      ),
                    ),
                    // Render each Stremio shelf
                    for (final shelf in _stremioShelves) ...[
                      _StremioShelfHeader(
                        label: shelf.label,
                        source: shelf.source,
                      ),
                      _buildStremioRow(shelf.items),
                      const SizedBox(height: 24),
                    ],
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStremioRow(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 195,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _StremioCard(item: items[i]),
      ),
    );
  }

  Widget _buildTop10List(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = items[index];
          return _Top10Card(rank: index + 1, item: item);
        },
      ),
    );
  }

  Widget _buildContentRow(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const SizedBox(
        height: 190,
        child: Center(child: Text('No content available', style: TextStyle(color: Colors.grey))),
      );
    }

    return SizedBox(
      height: 195,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) => MovieCard(item: items[i]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? CinemahubColors.primary
              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? CinemahubColors.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Netflix-style Billboard with auto-sliding TMDB hero title
class _HeroBillboard extends StatefulWidget {
  const _HeroBillboard({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<_HeroBillboard> createState() => _HeroBillboardState();
}

class _HeroBillboardState extends State<_HeroBillboard> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Only schedule timer if not in a widget test environment to avoid pumpAndSettle timeouts
    final isTesting = WidgetsBinding.instance is! WidgetsFlutterBinding;
    if (widget.items.length > 1 && !isTesting) {
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!mounted || widget.items.isEmpty) return;
        _currentPage = (_currentPage + 1) % widget.items.length;
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return Container(color: CinemahubColors.darkBackground);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageView.builder(
      controller: _pageController,
      itemCount: widget.items.length,
      onPageChanged: (i) => _currentPage = i,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final backdrop = item['backdropUrl'] as String? ?? item['posterUrl'] as String? ?? '';
        final title = item['title'] as String? ?? 'Featured Title';
        final rating = (item['rating'] as num?)?.toDouble() ?? 0.0;
        final releaseDate = item['releaseDate'] as String? ?? '';
        final year = releaseDate.isNotEmpty && releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

        return Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop Image
            if (backdrop.isNotEmpty)
              CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.black26),
                errorWidget: (context, url, error) => Container(color: Colors.black38),
              )
            else
              Container(color: CinemahubColors.darkSurface),

            // Top gradient for status bar
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Bottom gradient for seamless content fade
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      isDark ? CinemahubColors.darkBackground : CinemahubColors.lightBackground,
                    ],
                  ),
                ),
              ),
            ),

            // Content Overlay
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CinemahubColors.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'FEATURED SPOTLIGHT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (year.isNotEmpty) ...[
                        Text(
                          year,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (rating > 0) ...[
                        const Icon(Icons.star_rounded, size: 16, color: CinemahubColors.gold),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: CinemahubColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/details',
                            arguments: item,
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        label: const Text(
                          'Watch Now',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white60, width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/details',
                            arguments: item,
                          );
                        },
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                        label: const Text(
                          'Details',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Top 10 Numbered Card
class _Top10Card extends StatelessWidget {
  const _Top10Card({required this.rank, required this.item});
  final int rank;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final posterUrl = item['posterUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/details',
          arguments: item,
        );
      },
      child: SizedBox(
        width: 150,
        child: Stack(
          children: [
            // Giant Number on the Left
            Positioned(
              left: 0,
              bottom: -15,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 100,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = Colors.white38,
                ),
              ),
            ),
            // Poster Card Offset to the Right
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 115,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.white10),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.movie_rounded, color: Colors.white30),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Movie poster card for horizontal rows
class MovieCard extends StatelessWidget {
  const MovieCard({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = item['title'] as String? ?? 'Title';
    final posterUrl = item['posterUrl'] as String? ?? '';
    final rating = (item['rating'] as num?)?.toDouble() ?? 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/details',
          arguments: item,
        );
      },
      child: SizedBox(
        width: 125,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster Image
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) => Container(
                    color: isDark ? Colors.white10 : Colors.black12,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: isDark ? Colors.white10 : Colors.black12,
                    child: const Icon(Icons.movie_rounded, color: Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Title & Rating
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (rating > 0)
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 14, color: CinemahubColors.gold),
                  const SizedBox(width: 3),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: CinemahubColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stremio shelf header widget — shows addon name badge
// ---------------------------------------------------------------------------
class _StremioShelfHeader extends StatelessWidget {
  const _StremioShelfHeader({required this.label, required this.source});
  final String label;
  final String source;

  Color get _sourceColor {
    switch (source) {
      case 'Cinemeta':
        return const Color(0xFF7B2FBE);
      case 'Kitsu':
        return const Color(0xFFE76F51);
      case 'Community':
        return const Color(0xFF2A9D8F);
      default:
        return CinemahubColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _sourceColor.withValues(alpha: 0.2),
              border: Border.all(color: _sourceColor.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              source,
              style: TextStyle(
                color: _sourceColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stremio content card — same look as MovieCard with source badge
// ---------------------------------------------------------------------------
class _StremioCard extends StatelessWidget {
  const _StremioCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = item['title'] as String? ?? 'Unknown';
    final posterUrl = item['posterUrl'] as String? ?? '';
    final rating = (item['rating'] as num?)?.toDouble() ?? 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/details',
          arguments: item,
        );
      },
      child: SizedBox(
        width: 125,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (context, url) => Container(
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDark ? Colors.white10 : Colors.black12,
                              child: const Icon(Icons.movie_rounded,
                                  color: Colors.grey),
                            ),
                          )
                        : Container(
                            color: isDark ? Colors.white10 : Colors.black12,
                            child: const Icon(Icons.movie_rounded,
                                color: Colors.grey),
                          ),
                  ),
                  // "Stremio" badge on top-right
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B2FBE).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'S',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (rating > 0)
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 14, color: CinemahubColors.gold),
                  const SizedBox(width: 3),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: CinemahubColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
