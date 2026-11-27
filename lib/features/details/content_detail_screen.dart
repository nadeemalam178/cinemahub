import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/catalogue/catalogue_service.dart';
import '../../core/catalogue/tmdb_service.dart';
import '../../core/player/playback_engine.dart';
import '../../core/providers/provider_model.dart';
import '../../core/providers/provider_registry.dart';
import '../../core/providers/stremio_adapter.dart';
import '../../core/streaming/models/stream_source.dart';
import '../../core/streaming/player/player_router.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Content detail screen showing metadata from TMDB, season/episode picker for TV series,
/// watchlist/share actions, and categorized streaming sources.
class ContentDetailScreen extends StatefulWidget {
  const ContentDetailScreen({
    super.key,
    required this.id,
    required this.type,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.rating,
    this.releaseDate,
    this.genreIds,
  });

  final String id; // tmdb:id, stremio:imdb:tt..., or raw id
  final String type; // "movie" | "series"
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final double? rating;
  final String? releaseDate;
  final List<int>? genreIds;

  /// Extract numeric id for TMDB providers if present directly in [id].
  int get tmdbId {
    final parts = id.split(':');
    final last = parts.last;
    return int.tryParse(last) ?? 0;
  }

  /// Extract IMDb ID if present directly in [id] (e.g. `stremio:imdb:tt0137523`).
  String? get rawImdbId => RegExp(r'tt\d+').firstMatch(id)?.group(0);

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  Map<String, dynamic>? _meta;
  int? _resolvedTmdbId;
  int _selectedCategoryTab = 0; // 0: Direct & Embeds, 1: P2P Torrents, 2: All Sources
  bool _inWatchlist = false;

  // TV Series Season & Episode State
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  List<Map<String, dynamic>> _episodes = [];
  bool _loadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _resolvedTmdbId = widget.tmdbId > 0 ? widget.tmdbId : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkWatchlist();
        _loadMetaAndStreams();
      }
    });
  }

  Future<void> _checkWatchlist() async {
    try {
      final exists = await context.read<SyncService>().isInWatchlist(widget.id);
      if (mounted) {
        setState(() => _inWatchlist = exists);
      }
    } catch (_) {}
  }

  Future<void> _toggleWatchlist() async {
    final sync = context.read<SyncService>();
    final nextState = !_inWatchlist;
    setState(() => _inWatchlist = nextState);
    try {
      if (nextState) {
        await sync.addToWatchlist({
          'id': widget.id,
          'type': widget.type,
          'title': widget.title,
          'posterUrl': _posterUrl ?? widget.posterUrl,
          'backdropUrl': _backdrop ?? widget.backdropUrl,
          'overview': _overview,
          'rating': _rating,
          'releaseDate': _releaseDate,
        });
      } else {
        await sync.removeFromWatchlist(widget.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextState ? 'Added to Watchlist' : 'Removed from Watchlist'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _inWatchlist = !nextState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Watchlist update failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _shareTitle() async {
    final year = (_releaseDate != null && _releaseDate!.length >= 4)
        ? ' (${_releaseDate!.substring(0, 4)})'
        : '';
    final imdb = _imdbId;
    final link = imdb != null && imdb.isNotEmpty
        ? 'https://www.imdb.com/title/$imdb/'
        : (_resolvedTmdbId != null
            ? 'https://www.themoviedb.org/${widget.type == 'series' ? 'tv' : 'movie'}/$_resolvedTmdbId'
            : '');
    final text = link.isNotEmpty
        ? 'Watch ${widget.title}$year on CinemaHub\n$link'
        : 'Check out ${widget.title}$year on CinemaHub';
    await SharePlus.instance.share(ShareParams(text: text, subject: widget.title));
  }

  Future<void> _loadMetaAndStreams() async {
    final tmdb = context.read<TmdbService>();
    int tId = _resolvedTmdbId ?? widget.tmdbId;

    try {
      // Resolve TMDB ID from IMDb ID when navigated from Stremio community shelves
      if (tId <= 0 && widget.rawImdbId != null) {
        final match = await tmdb.findByImdbId(widget.rawImdbId!);
        final matchedId = (match?['id'] as num?)?.toInt();
        if (matchedId != null && matchedId > 0) {
          tId = matchedId;
          if (mounted) {
            setState(() => _resolvedTmdbId = tId);
          }
        }
      }

      if (tId > 0) {
        final details = widget.type == 'movie'
            ? await tmdb.getMovieDetails(tId)
            : await tmdb.getSeriesDetails(tId);
        if (details != null && mounted) {
          setState(() => _meta = details);
          if (widget.type == 'series') {
            unawaited(_loadEpisodes(_selectedSeason, tmdbIdOverride: tId));
          }
        }
      }
    } catch (_) {
      // Proceed to stream fetching even if TMDB metadata lookup fails
    }

    if (!mounted) return;
    final engine = context.read<PlaybackEngine>();
    final registry = context.read<ProviderRegistry>();
    await _fetchStreams(engine, registry);
  }

  Future<void> _loadEpisodes(int season, {int? tmdbIdOverride}) async {
    final tId = tmdbIdOverride ?? _resolvedTmdbId ?? widget.tmdbId;
    if (tId <= 0) return;
    setState(() {
      _selectedSeason = season;
      _loadingEpisodes = true;
    });

    try {
      final episodes = await context.read<CatalogueService>().getSeasonEpisodes(tId, season);
      if (mounted) {
        setState(() {
          _episodes = episodes;
          _loadingEpisodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEpisodes = false);
    }
  }

  void _onEpisodeSelected(int epNumber) {
    setState(() => _selectedEpisode = epNumber);
    final engine = context.read<PlaybackEngine>();
    final registry = context.read<ProviderRegistry>();
    _fetchStreams(engine, registry, season: _selectedSeason, episode: _selectedEpisode);
  }

  String? get _imdbId {
    final direct = _meta?['imdb_id'] as String?;
    if (direct != null && direct.startsWith('tt')) return direct;
    final ext = _meta?['external_ids'];
    if (ext is Map) {
      final extImdb = ext['imdb_id'] as String?;
      if (extImdb != null && extImdb.startsWith('tt')) return extImdb;
    }
    return widget.rawImdbId;
  }

  String? get _posterUrl =>
      _meta?['poster_path'] != null
          ? 'https://image.tmdb.org/t/p/w500${_meta!['poster_path']}'
          : widget.posterUrl;

  String? get _backdrop =>
      _meta?['backdrop_path'] != null
          ? 'https://image.tmdb.org/t/p/w780${_meta!['backdrop_path']}'
          : widget.backdropUrl;

  String? get _overview =>
      _meta?['overview'] as String? ?? widget.overview;

  double? get _rating =>
      (_meta?['vote_average'] as num?)?.toDouble() ?? widget.rating;

  String? get _releaseDate =>
      _meta?['release_date'] as String? ??
      _meta?['first_air_date'] as String? ??
      widget.releaseDate;

  List<int> get _genreIds {
    final rawIds = _meta?['genre_ids'] as List?;
    if (rawIds != null && rawIds.isNotEmpty) {
      return rawIds.whereType<num>().map((e) => e.toInt()).toList();
    }
    final detailGenres = _meta?['genres'] as List?;
    if (detailGenres != null && detailGenres.isNotEmpty) {
      return detailGenres
          .whereType<Map>()
          .map((g) => (g['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();
    }
    return widget.genreIds ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: CinemahubSpacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverview(),
                  if (widget.type == 'series') ...[
                    const SizedBox(height: CinemahubSpacing.lg),
                    _buildSeasonEpisodeSection(),
                  ],
                  const SizedBox(height: CinemahubSpacing.lg),
                  _buildProviderSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: CinemahubColors.background(Theme.of(context).brightness),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (_backdrop != null && _backdrop!.isNotEmpty)
              Image.network(
                _backdrop!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: CinemahubColors.surface(Theme.of(context).brightness),
                ),
              )
            else
              Container(color: CinemahubColors.surface(Theme.of(context).brightness)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      isDark
                          ? CinemahubColors.surface(Brightness.dark).withValues(alpha: 0.95)
                          : CinemahubColors.surface(Brightness.light).withValues(alpha: 0.95),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          widget.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _toggleWatchlist,
          icon: Icon(_inWatchlist ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
          color: _inWatchlist
              ? CinemahubColors.primary
              : (isDark ? Colors.white : Colors.black87),
          tooltip: _inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist',
        ),
        IconButton(
          onPressed: _shareTitle,
          icon: const Icon(Icons.share_rounded),
          color: isDark ? Colors.white : Colors.black87,
          tooltip: 'Share',
        ),
      ],
    );
  }

  Widget _buildOverview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_rating != null) ...[
              Chip(
                avatar: const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                label: Text(_rating!.toStringAsFixed(1)),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: CinemahubSpacing.sm),
            ],
            if (_releaseDate != null && _releaseDate!.isNotEmpty) ...[
              Chip(
                label: Text(
                  _releaseDate!.length >= 4 ? _releaseDate!.substring(0, 4) : _releaseDate!,
                ),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: CinemahubSpacing.sm),
            ],
            Chip(
              label: Text(widget.type.toUpperCase()),
              visualDensity: VisualDensity.compact,
              backgroundColor: CinemahubColors.primary.withValues(alpha: 0.2),
            ),
          ],
        ),
        const SizedBox(height: CinemahubSpacing.md),
        if (_overview != null && _overview!.isNotEmpty)
          Text(
            _overview!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        if (_genreIds.isNotEmpty) ...[
          const SizedBox(height: CinemahubSpacing.md),
          Wrap(
            spacing: CinemahubSpacing.sm,
            runSpacing: CinemahubSpacing.xs,
            children: _genreIds
                .map(
                  (id) => Chip(
                    label: Text(_genreName(id)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: isDark
                        ? CinemahubColors.surface(Brightness.dark)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSeasonEpisodeSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final seasons = (_meta?['seasons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final validSeasons = seasons.where((s) => (s['season_number'] as int? ?? 0) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Episodes (Season $_selectedSeason)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
            ),
            if (validSeasons.isNotEmpty)
              DropdownButton<int>(
                value: _selectedSeason,
                dropdownColor:
                    isDark ? CinemahubColors.darkSurface : CinemahubColors.lightSurface,
                underline: const SizedBox.shrink(),
                items: validSeasons.map((s) {
                  final num = s['season_number'] as int? ?? 1;
                  return DropdownMenuItem<int>(
                    value: num,
                    child: Text(
                      'Season $num',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    ),
                  );
                }).toList(),
                onChanged: (s) {
                  if (s != null) {
                    _loadEpisodes(s);
                    _onEpisodeSelected(1);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_loadingEpisodes)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: CinemahubColors.primary, strokeWidth: 2),
            ),
          )
        else if (_episodes.isNotEmpty)
          SizedBox(
            height: 125,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _episodes.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (ctx, index) {
                final ep = _episodes[index];
                final epNum = ep['episode_number'] as int? ?? (index + 1);
                final name = ep['name'] as String? ?? 'Episode $epNum';
                final isSelected = epNum == _selectedEpisode;
                final stillPath = ep['still_path'] as String?;

                return GestureDetector(
                  onTap: () => _onEpisodeSelected(epNum),
                  child: Container(
                    width: 155,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? CinemahubColors.primary.withValues(alpha: 0.25)
                          : (isDark ? CinemahubColors.darkSurface : CinemahubColors.lightSurface),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? CinemahubColors.primary
                            : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (stillPath != null)
                                Image.network(
                                  'https://image.tmdb.org/t/p/w300$stillPath',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(color: Colors.black45),
                                )
                              else
                                Container(
                                  color: Colors.black45,
                                  child: const Icon(Icons.movie_rounded, color: Colors.white30),
                                ),
                              if (isSelected)
                                const Center(
                                  child: Icon(Icons.play_circle_fill_rounded,
                                      color: CinemahubColors.primary, size: 28),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text(
                            'EP $epNum: $name',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? (isDark ? Colors.white : CinemahubColors.primary)
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        else
          Text(
            'Episode details unavailable for this title.',
            style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12),
          ),
      ],
    );
  }

  static const Map<int, String> _genreMap = {
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
    80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
    14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
    9648: 'Mystery', 10749: 'Romance', 878: 'Science Fiction',
    10770: 'TV Movie', 53: 'Thriller', 10752: 'War',
  };

  String _genreName(int id) => _genreMap[id] ?? 'Genre $id';

  Widget _buildProviderSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final engine = context.watch<PlaybackEngine>();
    final registry = context.watch<ProviderRegistry>();

    final directEmbedStreams = [
      ...engine.fmhyStreams,
      ...engine.nuvioStreams,
      ...engine.cloudStreamStreams,
    ];
    final magnetStreams = engine.stremioStreams;

    List<StreamResult> activeStreams = [];
    String emptyMessage = 'No sources found for this title';
    switch (_selectedCategoryTab) {
      case 0:
        activeStreams = directEmbedStreams;
        emptyMessage = 'No Direct or Embed sources found';
        break;
      case 1:
        activeStreams = magnetStreams;
        emptyMessage = 'No P2P Torrent sources found';
        break;
      case 2:
        activeStreams = engine.currentStreams;
        emptyMessage = 'No streaming sources available';
        break;
    }

    final preparedSources = activeStreams
        .map((s) => MapEntry(s, StreamSource.fromStreamResult(s)))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Sources',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Ad-Shield & P2P',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (engine.currentStreams.isNotEmpty)
              IconButton(
                onPressed: () => _fetchStreams(engine, registry),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh sources',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: CinemahubSpacing.sm),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _CategoryTabChip(
                label: 'Direct & Embeds',
                count: directEmbedStreams.length,
                selected: _selectedCategoryTab == 0,
                color: CinemahubColors.primary,
                onTap: () => setState(() => _selectedCategoryTab = 0),
              ),
              const SizedBox(width: 8),
              _CategoryTabChip(
                label: 'P2P Torrents',
                count: magnetStreams.length,
                selected: _selectedCategoryTab == 1,
                color: const Color(0xFF8B5CF6),
                onTap: () => setState(() => _selectedCategoryTab = 1),
              ),
              const SizedBox(width: 8),
              _CategoryTabChip(
                label: 'All Sources',
                count: engine.currentStreams.length,
                selected: _selectedCategoryTab == 2,
                color: const Color(0xFF38BDF8),
                onTap: () => setState(() => _selectedCategoryTab = 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: CinemahubSpacing.md),

        if (engine.loading)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: CinemahubColors.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Searching stream providers...',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (preparedSources.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: preparedSources.length,
            itemBuilder: (context, index) {
              final entry = preparedSources[index];
              return _StreamCard(
                stream: entry.key,
                source: entry.value,
                contentTitle: widget.title,
                contentId: widget.id,
                imdbId: _imdbId,
                contentType: widget.type,
                season: widget.type == 'series' ? _selectedSeason : null,
                episode: widget.type == 'series' ? _selectedEpisode : null,
                posterUrl: _posterUrl,
                releaseDate: _releaseDate,
                rating: _rating,
                onStreamFailed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                          'Source failed to load. Please try another source from the list.'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.orange.shade800,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                },
              );
            },
          )
        else if (engine.error != null && engine.currentStreams.isEmpty)
          ErrorState(message: engine.error!)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(
                    emptyMessage,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _fetchStreams(engine, registry),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Searching Sources'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _fetchStreams(
    PlaybackEngine engine,
    ProviderRegistry registry, {
    int? season,
    int? episode,
  }) async {
    final s = season ?? (widget.type == 'series' ? _selectedSeason : null);
    final ep = episode ?? (widget.type == 'series' ? _selectedEpisode : null);
    final effectiveTmdb = _resolvedTmdbId ?? widget.tmdbId;

    await engine.fetchStreams(
      registry: registry,
      type: widget.type == 'movie' ? ContentType.movie : ContentType.series,
      id: widget.id,
      season: s,
      episode: ep,
      metaImdbId: _imdbId,
      metaTmdbId: effectiveTmdb > 0 ? effectiveTmdb : null,
      title: widget.title,
    );
  }
}

class _CategoryTabChip extends StatelessWidget {
  const _CategoryTabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.16)
              : (isDark ? const Color(0xFF14141E) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.7)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08)),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? (isDark ? Colors.white : color)
                    : (isDark ? Colors.white70 : Colors.black87),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.4)
                      : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.stream,
    required this.source,
    required this.contentTitle,
    required this.contentId,
    this.imdbId,
    required this.contentType,
    this.season,
    this.episode,
    this.posterUrl,
    this.releaseDate,
    this.rating,
    this.onStreamFailed,
  });

  final StreamResult stream;
  final StreamSource source;
  final String contentTitle;
  final String contentId;
  final String? imdbId;
  final String contentType;
  final int? season;
  final int? episode;
  final String? posterUrl;
  final String? releaseDate;
  final double? rating;
  final VoidCallback? onStreamFailed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isTorrent = source.type == StreamType.magnet;
    final isEmbed = source.type == StreamType.embed;
    final isWebsite = source.type == StreamType.website;

    final quality = source.quality;
    final language = source.language;
    final seeders = (isTorrent && source.seeders != null && source.seeders! > 0)
        ? source.seeders
        : null;
    final size = source.formattedSize;

    Color accentColor = CinemahubColors.primary;
    String typeLabel = 'DIRECT';
    IconData iconData = Icons.play_arrow_rounded;

    if (isTorrent) {
      accentColor = const Color(0xFF8B5CF6);
      typeLabel = 'TORRENT';
      iconData = Icons.bolt_rounded;
    } else if (isEmbed) {
      accentColor = const Color(0xFF0EA5E9);
      typeLabel = 'EMBED';
      iconData = Icons.layers_outlined;
    } else if (isWebsite) {
      accentColor = const Color(0xFFF59E0B);
      typeLabel = 'WEB';
      iconData = Icons.open_in_browser_rounded;
    }

    final cleanTitle = stream.description?.split('\n').first ?? source.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13131D) : CinemahubColors.lightSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.07),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            try {
              await const PlayerRouter().navigateToPlayer(
                context: context,
                source: source,
                title: contentTitle,
                contentId: contentId,
                imdbId: imdbId,
                contentType: contentType,
                season: season,
                episode: episode,
                posterUrl: posterUrl,
                releaseDate: releaseDate,
                rating: rating,
              );
            } catch (e) {
              onStreamFailed?.call();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(iconData, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              source.provider,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildBadge(label: typeLabel, color: accentColor),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cleanTitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (quality != null && quality.isNotEmpty)
                            _buildBadge(
                              label: quality,
                              color: quality.contains('4K')
                                  ? CinemahubColors.gold
                                  : const Color(0xFF38BDF8),
                            ),
                          if (language != null && language.isNotEmpty)
                            _buildBadge(
                              label: language,
                              color: const Color(0xFF10B981),
                              icon: Icons.translate_rounded,
                            ),
                          if (seeders != null)
                            _buildBadge(
                              label: '$seeders seeds',
                              color: const Color(0xFF8B5CF6),
                              icon: Icons.people_outline_rounded,
                            ),
                          if (size != null)
                            _buildBadge(
                              label: size,
                              color: isDark ? Colors.white60 : Colors.black45,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
