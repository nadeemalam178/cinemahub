// CinemaHub smoke test — verifies the app tree builds and the initial route
// renders without throwing. Firebase is deliberately unconfigured in tests, so
// any real Firestore/Auth call will surface as an assertion — we only check
// that the first frame paints.

import 'package:cinemahub/core/auth/auth_service.dart';
import 'package:cinemahub/core/routing/app_router.dart';
import 'package:cinemahub/core/theme/theme_provider.dart';
import 'package:cinemahub/core/catalogue/tmdb_service.dart';
import 'package:cinemahub/features/auth/splash_screen.dart';
import 'package:cinemahub/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('CinemaHubApp pumps a frame', (WidgetTester tester) async {
    // Set up mock SharedPreferences to avoid async issues in tests
    SharedPreferences.setMockInitialValues({});

    // Initialize theme provider synchronously - use default mode to avoid async load()
    final themeProvider = ThemeProvider();

    final authProvider = AuthService();
    // Initialize with unconfigured Firebase - this synchronously sets state to signedOut
    authProvider.initialize(firebaseConfigured: false);

    final router = AppRouter(authProvider);
    final tmdbService = TmdbService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AuthService>.value(value: authProvider),
          Provider<TmdbService>.value(value: tmdbService),
        ],
        child: CinemaHubApp(
          themeProvider: themeProvider,
          router: router,
          authProvider: authProvider,
          tmdbService: tmdbService,
        ),
      ),
    );

    // After pumpWidget, the app should show the appropriate screen.
    // Since auth state was set to signedOut before pumpWidget was called,
    // the initialRoute will be '/splash' (not '/home'), but the MaterialApp
    // will rebuild with the signedOut route via onGenerateRoute.
    // We verify the widget tree builds without errors.
    await tester.pump(); // Single frame pump
    expect(find.byType(SplashScreen), findsOneWidget);

    // Pump a few more frames to allow the state change to propagate
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify no build errors occurred - splash screen should still be visible
    // since we're navigating away from it after the animation completes
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
