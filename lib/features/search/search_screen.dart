import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalogue/catalogue_service.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';
import '../home/home_screen.dart' show MovieCard;

/// Search across movies and series with TMDB integration.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  bool _loading = false;
  List<Map<String, dynamic>> _movies = [];
  List<Map<String, dynamic>> _series = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = context.read<CatalogueService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: CinemahubSpacing.pagePadding,
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                setState(() => _query = v);
                if (v.trim().isNotEmpty) {
                  _performSearch(catalogue, v.trim());
                } else {
                  setState(() {
                    _movies = [];
                    _series = [];
                    _loading = false;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: 'Movies, series, genres…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _query = '';
                            _movies = [];
                            _series = [];
                            _loading = false;
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: CinemahubRadius.allPill,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty) ...[
            Expanded(
              child: _buildSearchResults(catalogue),
            ),
          ] else ...[
            const Expanded(
              child: _EmptySearch(),
            ),
          ],
        ],
      ),
    );
  }

  void _performSearch(CatalogueService catalogue, String query) {
    setState(() => _loading = true);

    catalogue.search(
      query: query,
      onMovies: (movies) {
        if (!mounted) return;
        setState(() {
          _movies = movies;
        });
      },
      onSeries: (series) {
        if (!mounted) return;
        setState(() {
          _series = series;
          _loading = false;
        });
      },
    );
  }

  Widget _buildSearchResults(CatalogueService catalogue) {
    if (_loading) {
      return const LoadingState(message: 'Searching…');
    }

    final hasResults = _movies.isNotEmpty || _series.isNotEmpty;
    if (!hasResults) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        message: 'Try a different search term.',
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: CinemahubSpacing.md,
      ),
      children: [
        if (_movies.isNotEmpty) ...[
          SectionHeader(
            title: 'Movies (${_movies.length})',
            trailing: null,
          ),
          const SizedBox(height: CinemahubSpacing.md),
          _buildResultsGrid(_movies),
          const SizedBox(height: CinemahubSpacing.lg),
        ],
        if (_series.isNotEmpty) ...[
          SectionHeader(
            title: 'TV Series (${_series.length})',
            trailing: null,
          ),
          const SizedBox(height: CinemahubSpacing.md),
          _buildResultsGrid(_series),
        ],
      ],
    );
  }

  Widget _buildResultsGrid(List<Map<String, dynamic>> items) {
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          return MovieCard(item: item);
        },
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.travel_explore_rounded,
      title: 'Search CinemaHub',
      message:
          'Find movies and series by title. Metadata is '
          'provided by TMDB and cached locally.',
    );
  }
}