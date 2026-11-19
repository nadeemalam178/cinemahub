import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/auth/auth_service.dart';
import 'package:cinemahub/core/routing/app_router.dart';
import 'package:cinemahub/features/auth/sign_in_screen.dart';
import 'package:cinemahub/features/auth/pending_access_screen.dart';
import 'package:cinemahub/features/details/content_detail_screen.dart';
import 'package:cinemahub/features/search/search_screen.dart';
import 'package:cinemahub/features/shell/app_shell.dart';
import 'package:cinemahub/core/theme/theme_provider.dart';
import 'package:cinemahub/core/catalogue/catalogue_service.dart';
import 'package:cinemahub/core/catalogue/tmdb_service.dart';
import 'package:cinemahub/core/admin/admin_service.dart';
import 'package:cinemahub/core/providers/provider_registry.dart';
import 'package:cinemahub/core/providers/stremio_adapter.dart';
import 'package:cinemahub/core/player/playback_engine.dart';
import 'package:cinemahub/core/sync/sync_service.dart';
import 'package:cinemahub/core/network/connectivity_provider.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

Widget createTestApp({
  required AuthService auth,
  required AppRouter router,
  required AuthState authState,
  String initialRoute = '/',
}) {
  final tmdb = TmdbService(apiKey: 'test_key');
  final dio = Dio();
  final adapter = StremioAdapter(dio: dio);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<AdminService>.value(
        value: AdminService(
          auth: auth,
          userStream: const Stream.empty(),
          providerStream: const Stream.empty(),
        ),
      ),
      ChangeNotifierProvider<CatalogueService>.value(value: CatalogueService(tmdb: tmdb)),
      ChangeNotifierProvider<ProviderRegistry>.value(value: ProviderRegistry()),
      ChangeNotifierProvider<PlaybackEngine>.value(value: PlaybackEngine(adapter: adapter)),
      ChangeNotifierProvider<SyncService>.value(
        value: SyncService(auth: auth, connectivity: ConnectivityProvider()),
      ),
      Provider<TmdbService>.value(value: tmdb),
      Provider<StremioAdapter>.value(value: adapter),
    ],
    child: MaterialApp(
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => router.onGenerateRoute(settings, authState),
    ),
  );
}

void main() {
  group('AppRouter Route Generation & Gating', () {
    late AuthService mockAuth;
    late AppRouter router;

    setUp(() {
      mockAuth = AuthService.test();
      router = AppRouter(mockAuth);
    });

    testWidgets('Signed out user gets SignInScreen regardless of requested path', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          auth: mockAuth,
          router: router,
          authState: AuthState.signedOut,
          initialRoute: '/details',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(ContentDetailScreen), findsNothing);
    });

    testWidgets('Pending approval user gets PendingAccessScreen', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          auth: mockAuth,
          router: router,
          authState: AuthState.pendingApproval,
          initialRoute: '/home',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PendingAccessScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('Approved user routes to ContentDetailScreen with args', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            return createTestApp(
              auth: mockAuth,
              router: router,
              authState: AuthState.approved,
              initialRoute: '/home',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      navState.pushNamed(
        '/details',
        arguments: {
          'id': 'tmdb:550',
          'type': 'movie',
          'title': 'Fight Club',
        },
      );
      await tester.pumpAndSettle();

      expect(find.byType(ContentDetailScreen), findsOneWidget);
      expect(find.text('Fight Club'), findsOneWidget);
    });

    testWidgets('Approved user routes to SearchScreen', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          auth: mockAuth,
          router: router,
          authState: AuthState.approved,
          initialRoute: '/home',
        ),
      );
      await tester.pumpAndSettle();

      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      navState.pushNamed('/search');
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('Approved user reaches AppShell on home', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          auth: mockAuth,
          router: router,
          authState: AuthState.approved,
          initialRoute: '/home',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
    });
  });
}
