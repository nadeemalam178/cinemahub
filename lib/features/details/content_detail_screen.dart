import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalogue/tmdb_service.dart';
import '../../core/player/playback_engine.dart';
import '../../core/player/video_player_widget.dart';
import '../../core/providers/provider_registry.dart';
import '../../core/providers/provider_model.dart';
import '../../core/providers/stremio_adapter.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Content detail screen showing metadata from TMDB and available streams.
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

  final String id; // tmdb:id or provider-specific id
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
    return int.tryParse(parts.last) ?? 0;
  }

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  Map<String, dynamic>? _meta;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      if (widget.type == 'movie') {
        final result = await context.read<TmdbService>().getMovieDetails(widget.tmdbId);
        if (result != null && mounted) {
          setState(() => _meta = result);
        }
      } else if (widget.type == 'series') {
        final result = await context.read<TmdbService>().getSeriesDetails(widget.tmdbId);
        if (result != null && mounted) {
          setState(() => _meta = result);
        }
      }
    } catch (_) {
      // Silently handle TMDB fetch errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: CinemahubSpacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverview(),
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
      expandedHeight: 300,
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
                    stops: const [0.5, 1.0],
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
                label: Text(_releaseDate!.substring(0, 4)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Play',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${registry.enabled.length} provider${registry.enabled.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: CinemahubSpacing.md),
        if (engine.loading)
          const Center(child: CircularProgressIndicator())
        else if (engine.currentStreams.isNotEmpty)
          ...engine.currentStreams.take(3).map((stream) => _StreamCard(stream: stream))
        else if (engine.error != null)
          ErrorState(message: engine.error!)
        else
          CinemaButton(
            label: 'Find Streams',
            icon: Icons.play_arrow_rounded,
            onPressed: () => _fetchStreams(engine, registry),
            expanded: true,
          ),
      ],
    );
  }

  Future<void> _fetchStreams(PlaybackEngine engine, ProviderRegistry registry) async {
    final imdbId = _meta?['imdb_id'] as String?;
    final streamId = (imdbId != null && imdbId.isNotEmpty) ? imdbId : widget.id;
    await engine.loadStreams(
      registry: registry,
      contentType: widget.type == 'movie' ? ContentType.movie : ContentType.series,
      id: streamId,
    );
  }
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({required this.stream});

  final StreamResult stream;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: CinemahubSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: CinemahubColors.primary.withValues(alpha: 0.1),
          child: Icon(
            Icons.play_circle_outline_rounded,
            color: CinemahubColors.primary,
          ),
        ),
        title: Text(stream.name),
        subtitle: Text(stream.type.split('/').last.toUpperCase()),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: CinemaPlayer(
                  stream: stream,
                  title: null,
                  allowExternalPlayer: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}