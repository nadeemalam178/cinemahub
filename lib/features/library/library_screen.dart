import 'package:flutter/material.dart';

import '../../core/theme/widgets.dart';

/// My List / Watch History (wired in Milestone 5).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My List')),
      body: const EmptyState(
        icon: Icons.bookmark_outline_rounded,
        title: 'Your list is empty',
        message:
            'Add movies and series to your watchlist to see them here. '
            'They sync across all your devices.',
      ),
    );
  }
}