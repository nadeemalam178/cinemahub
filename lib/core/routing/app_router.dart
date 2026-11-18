import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/pending_access_screen.dart';
import '../../features/shell/app_shell.dart';

/// Maps [AuthState] to the root route for the app shell.
class AppRouter {
  AppRouter(this._auth);

  final AuthService _auth;

  Route<dynamic>? onGenerateRoute(RouteSettings settings, AuthState authState) {
    final route = _routeFor(settings, authState);
    return route;
  }

  Route<dynamic> _routeFor(RouteSettings settings, AuthState authState) {
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

  void _onSplashFinished() {}

  Route<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 600),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  Route<T> _slide<T>(Widget page) => PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
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