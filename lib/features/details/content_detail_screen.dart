import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/catalogue/catalogue_service.dart';
import '../../core/catalogue/tmdb_service.dart';
import '../../core/player/in_app_adblocked_player.dart';
import '../../core/player/playback_engine.dart';
import '../../core/player/video_player_widget.dart';
import '../../core/providers/provider_registry.dart';
import '../../core/providers/provider_model.dart';
import '../../core/providers/stremio_adapter.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Content detail screen showing metadata from TMDB, season/episode picker for TV series,
/// and categorized streams (FMHY, Stremio/Torrentio, Nuvio, CloudStream).
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

  final String id; // tmdb:id, stremio:id or raw id
  final String type; // "movie" | "series"
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final double? rating;
  final String? releaseDate;
  final List<int>? genreIds;

  /// Extract numeric id for TMDB providers.
  int get tmdbId {
    final parts = id.split(':');
    final last = parts.last;
    return int.tryParse(last) ?? 0;
  }

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  Map<String, dynamic>? _meta;
  int _selectedCategoryTab = 0; // 0: FMHY, 1: Addons (Torrentio), 2: Nuvio, 3: CloudStream
  bool _didAutoFetch = false;

  // TV Series Season & Episode State
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  List<Map<String, dynamic>> _episodes = [];
  bool _loadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_didAutoFetch && mounted) {
        _didAutoFetch = true;
        _autoFetchStreams();
      }
    });
  }

  Future<void> _loadMeta() async {
    final tId = widget.tmdbId;
    if (tId <= 0) return;

    try {
      if (widget.type == 'movie') {
        final result = await context.read<TmdbService>().getMovieDetails(tId);
        if (result != null && mounted) {
          setState(() => _meta = result);
          _autoFetchStreams();
        }
      } else if (widget.type == 'series') {
        final result = await context.read<TmdbService>().getSeriesDetails(tId);
        if (result != null && mounted) {
          setState(() => _meta = result);
          _loadEpisodes(_selectedSeason);
          _autoFetchStreams();
        }
      }
    } catch (_) {
      // Silently handle TMDB fetch errors
    }
  }

  Future<void> _loadEpisodes(int season) async {
    final tId = widget.tmdbId;
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

  void _autoFetchStreams() {
    final engine = context.read<PlaybackEngine>();
    final registry = context.read<ProviderRegistry>();
    _fetchStreams(engine, registry);
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

  List<int> get _genreIds =>
      ((_meta?['genre_ids'] as List?) ?? widget.genreIds ?? const [])
          .cast<int>();

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: CinemahubColors.background(Brightness.dark),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (_backdrop != null)
              Image.network(
                _backdrop!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: CinemahubColors.surface(Brightness.dark),
                ),
              )
            else
              Container(color: CinemahubColors.surface(Brightness.dark)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      CinemahubColors.surface(Brightness.dark).withValues(alpha: 0.95),
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
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.bookmark_border_rounded),
          color: Colors.white,
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.share_rounded),
          color: Colors.white,
        ),
      ],
    );
  }

  Widget _buildOverview() {
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
            if (_releaseDate != null) ...[
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
        if (_overview != null)
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
                    backgroundColor: CinemahubColors.surface(Brightness.dark),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSeasonEpisodeSection() {
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
                    color: Colors.white,
                  ),
            ),
            if (validSeasons.isNotEmpty)
              DropdownButton<int>(
                value: _selectedSeason,
                dropdownColor: CinemahubColors.darkSurface,
                underline: const SizedBox.shrink(),
                items: validSeasons.map((s) {
                  final num = s['season_number'] as int? ?? 1;
                  return DropdownMenuItem<int>(
                    value: num,
                    child: Text('Season $num', style: const TextStyle(color: Colors.white)),
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
              separatorBuilder: (_, __) => const SizedBox(width: 12),
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
                          : CinemahubColors.darkSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? CinemahubColors.primary : Colors.white12,
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
                                  errorBuilder: (_, __, ___) => Container(color: Colors.black45),
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
                              color: isSelected ? Colors.white : Colors.white70,
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
          const Text(
            'Episode details loading from TMDB...',
            style: TextStyle(color: Colors.white54, fontSize: 12),
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
    final engine = context.watch<PlaybackEngine>();
    final registry = context.watch<ProviderRegistry>();

    final fmhyCount = engine.fmhyStreams.length;
    final stremioCount = engine.stremioStreams.length;
    final nuvioCount = engine.nuvioStreams.length;
    final csCount = engine.cloudStreamStreams.length;

    // Pick active list according to selected category tab
    List<StreamResult> activeStreams = [];
    String emptyMessage = 'No streams found';
    switch (_selectedCategoryTab) {
      case 0:
        activeStreams = engine.fmhyStreams;
        emptyMessage = 'No FMHY video servers available';
        break;
      case 1:
        activeStreams = engine.stremioStreams;
        emptyMessage = 'No Community Torrent / Debrid streams available';
        break;
      case 2:
        activeStreams = engine.nuvioStreams;
        emptyMessage = 'No Nuvio plugin streams available';
        break;
      case 3:
        activeStreams = engine.cloudStreamStreams;
        emptyMessage = 'No CloudStream sources available';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title & uBlock Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Watch Options',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Zero-Ad Shield Active',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
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
                tooltip: 'Refresh all sources',
              ),
          ],
        ),
        const SizedBox(height: CinemahubSpacing.sm),

        // 4 Category Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _CategoryTabChip(
                label: 'FMHY Video',
                count: fmhyCount,
                selected: _selectedCategoryTab == 0,
                color: CinemahubColors.primary,
                onTap: () => setState(() => _selectedCategoryTab = 0),
              ),
              const SizedBox(width: 8),
              _CategoryTabChip(
                label: 'Torrents & Debrid',
                count: stremioCount,
                selected: _selectedCategoryTab == 1,
                color: Colors.purpleAccent,
                onTap: () => setState(() => _selectedCategoryTab = 1),
              ),
              const SizedBox(width: 8),
              _CategoryTabChip(
                label: 'Nuvio Plugins',
                count: nuvioCount,
                selected: _selectedCategoryTab == 2,
                color: const Color(0xFF2A9D8F),
                onTap: () => setState(() => _selectedCategoryTab = 2),
              ),
              const SizedBox(width: 8),
              _CategoryTabChip(
                label: 'CloudStream',
                count: csCount,
                selected: _selectedCategoryTab == 3,
                color: Colors.blueAccent,
                onTap: () => setState(() => _selectedCategoryTab = 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: CinemahubSpacing.md),

        // Streams List
        if (engine.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: CinemahubColors.primary),
                  SizedBox(height: 12),
                  Text(
                    'Scraping FMHY, Torrents, Nuvio & CloudStream...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else if (activeStreams.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeStreams.length,
            itemBuilder: (context, index) {
              final stream = activeStreams[index];
              return _StreamCard(stream: stream, contentTitle: widget.title);
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
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _fetchStreams(engine, registry),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Try Refreshing Sources'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _fetchStreams(PlaybackEngine engine, ProviderRegistry registry, {int? season, int? episode}) async {
    final s = season ?? (widget.type == 'series' ? _selectedSeason : null);
    final ep = episode ?? (widget.type == 'series' ? _selectedEpisode : null);
    final imdbId = _meta?['imdb_id'] as String?;

    await engine.fetchStreams(
      registry: registry,
      type: widget.type == 'movie' ? ContentType.movie : ContentType.series,
      id: widget.id,
      season: s,
      episode: ep,
      metaImdbId: imdbId,
      metaTmdbId: widget.tmdbId > 0 ? widget.tmdbId : null,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? color : Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
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
  const _StreamCard({required this.stream, required this.contentTitle});

  final StreamResult stream;
  final String contentTitle;

  @override
  Widget build(BuildContext context) {
    final isTorrent = stream.behaviorHints?['isTorrent'] == true;
    final isDirectHttp = stream.behaviorHints?['isDirectHttp'] == true;
    final isDebrid = stream.behaviorHints?['isDebrid'] == true;
    final isWebEmbed = stream.behaviorHints?['isWebEmbed'] == true;
    final seeders = stream.behaviorHints?['seeders'] as int? ?? 0;
    final speed = stream.behaviorHints?['speed'] as String? ?? '';
    final category = stream.behaviorHints?['category'] as String? ?? '';

    Color iconColor = CinemahubColors.primary;
    IconData iconData = Icons.play_arrow_rounded;

    if (category == 'stremio') {
      iconColor = isDebrid ? CinemahubColors.gold : Colors.purpleAccent;
      iconData = isDebrid ? Icons.bolt_rounded : Icons.stream_rounded;
    } else if (category == 'nuvio') {
      iconColor = const Color(0xFF2A9D8F);
      iconData = Icons.widgets_rounded;
    } else if (category == 'cloudstream') {
      iconColor = Colors.blueAccent;
      iconData = Icons.cloud_rounded;
    }

    return Card(
      elevation: 0,
      color: CinemahubColors.darkSurface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            iconData,
            color: iconColor,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                stream.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ),
            if (isTorrent && seeders > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '⚡ $seeders',
                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            if (isDebrid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CinemahubColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DEBRID',
                  style: TextStyle(color: CinemahubColors.gold, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            if (isWebEmbed && speed.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CinemahubColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  speed,
                  style: const TextStyle(color: CinemahubColors.gold, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            isDebrid
                ? '⚡ 4K Premium Debrid CDN • Zero Buffering / Zero Ads'
                : (isTorrent
                    ? 'P2P Stream • Open in VLC or External Player'
                    : '🛡️ In-App Player • Zero-Ad Sandboxed Shield'),
            style: TextStyle(
              color: isDebrid
                  ? CinemahubColors.gold
                  : (isTorrent ? Colors.white60 : Colors.greenAccent.withValues(alpha: 0.8)),
              fontSize: 11,
            ),
          ),
        ),
        trailing: const Icon(Icons.play_circle_fill_rounded, color: CinemahubColors.primary),
        onTap: () {
          if (isDirectHttp) {
            // Direct MP4 / HLS stream: play natively in Chewie CinemaPlayer!
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  body: CinemaPlayer(
                    stream: stream,
                    title: contentTitle,
                    allowExternalPlayer: true,
                  ),
                ),
              ),
            );
          } else if (stream.url.startsWith('magnet:')) {
            // Torrent Magnet Stream: Offer to play in VLC or copy
            _showMagnetOptions(context, stream.url);
          } else if (isWebEmbed) {
            // Sandboxed uBlock In-App ad-blocked player
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InAppAdBlockedPlayer(
                  url: stream.url,
                  title: contentTitle,
                ),
              ),
            );
          } else {
            // Native fallback
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  body: CinemaPlayer(
                    stream: stream,
                    title: contentTitle,
                    allowExternalPlayer: true,
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  void _showMagnetOptions(BuildContext context, String magnetUri) {
    showModalBottomSheet(
      context: context,
      backgroundColor: CinemahubColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bolt_rounded, color: Colors.purpleAccent, size: 24),
                SizedBox(width: 8),
                Text(
                  'Torrent Stream Options',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'This is a P2P magnet link. You can open it directly in VLC, Nova Video Player, or any installed torrent streaming app.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: CinemahubColors.primary,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(magnetUri);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No torrent player found. Please install VLC or LibreTorrent.')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open in VLC / External Player'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: magnetUri));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Magnet link copied to clipboard!')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Magnet Link'),
            ),
          ],
        ),
      ),
    );
  }
}
