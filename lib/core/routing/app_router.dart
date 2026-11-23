import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/pending_access_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/details/content_detail_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/admin/admin_dashboard.dart';
import '../../features/settings/playback_diagnostics_screen.dart';

/// Maps [AuthState] and route names to views for the app shell.
class AppRouter {
  AppRouter(this._auth);

  final AuthService _auth;

  Route<dynamic>? onGenerateRoute(RouteSettings settings, AuthState authState) {
    if (settings.name == '/diagnostics') {
      return _slide(const PlaybackDiagnosticsScreen());
    }

    // If user is not approved, always restrict navigation to the appropriate auth view
    if (authState != AuthState.approved) {
      return _routeForAuthState(authState);
    }

    switch (settings.name) {
      case '/details':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return _slide(
          ContentDetailScreen(
            id: args['id'] as String? ?? '',
            type: args['type'] as String? ?? 'movie',
            title: args['title'] as String? ?? 'Details',
            posterUrl: args['posterUrl'] as String?,
            backdropUrl: args['backdropUrl'] as String?,
            overview: args['overview'] as String?,
            rating: (args['rating'] as num?)?.toDouble(),
            releaseDate: args['releaseDate'] as String?,
            genreIds: (args['genreIds'] as List?)?.cast<int>(),
          ),
        );
      case '/search':
        return _slide(const SearchScreen());
      case '/admin':
        return _slide(const AdminDashboard());
      case '/home':
      case '/':
      default:
        return _slide(const AppShell());
    }
  }

  Route<dynamic> _routeForAuthState(AuthState authState) {
    switch (authState) {
      case AuthState.loading:
        return _fade(SplashScreen(onFinished: _onSplashFinished));
      case AuthState.signedOut:
        return _fade(
          SignInScreen(
            auth: _auth,
            configError: _auth.configError,
          ),
        );
      case AuthState.pendingApproval:
        return _fade(PendingAccessScreen(auth: _auth));
      case AuthState.suspended:
        return _fade(PendingAccessScreen(auth: _auth, suspended: true));
      case AuthState.approved:
        return _slide(const AppShell());
    }
  }

  void _onSplashFinished() {
    _auth.onSplashFinished();
  }

  Route<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 600),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  Route<T> _slide<T>(Widget page) => PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final offset = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      );
      return SlideTransition(position: offset, child: child);
    },
  );
}
