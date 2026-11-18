import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalogue/catalogue_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

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
                  _performSearch(catalogue, v);
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
                          setState(() => _query = '');
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
    if (_loading) return;
    setState(() => _loading = true);

    catalogue.search(
      query: query,
      onMovies: (movies) {
        setState(() => _loading = false);
      },
      onSeries: (series) {
        setState(() => _loading = false);
      },
    );
  }

  Widget _buildSearchResults(CatalogueService catalogue) {
    if (_loading) {
      return const LoadingState(message: 'Searching…');
    }

    // This is a simplified UI. In a real implementation, you would
    // show the actual search results from the catalogue service.
    return const Center(
      child: Text('Search results would appear here'),
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