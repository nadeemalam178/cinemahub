import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/routing/app_router.dart';
import 'core/theme/theme_provider.dart';
import 'core/notifications/notification_service.dart';
import 'core/network/connectivity_provider.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/firebase_options.dart';
import 'core/sync/sync_service.dart';
import 'core/catalogue/tmdb_service.dart';
import 'core/catalogue/catalogue_service.dart';
import 'core/admin/admin_service.dart';
import 'core/update/update_service.dart';
import 'core/providers/provider_registry.dart';
import 'core/providers/stremio_adapter.dart';
import 'core/catalogue/id_resolver.dart';
import 'core/player/playback_engine.dart';
import 'package:dio/dio.dart' hide Response;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase if configured via --dart-define or native google-services.json
  bool firebaseConfigured = false;
  if (!kIsWeb) {
    try {
      if (Firebase.apps.isNotEmpty) {
        firebaseConfigured = true;
      } else if (DefaultFirebaseOptions.isConfigured) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseConfigured = true;
      } else {
        // Attempt native initialization (e.g. from google-services.json on Android)
        await Firebase.initializeApp();
        firebaseConfigured = true;
      }
    } catch (e) {
      debugPrint('Firebase initialization note: $e');
      if (e.toString().contains('duplicate-app')) {
        firebaseConfigured = true;
      } else {
        firebaseConfigured = false;
      }
    }
  } else {
    try {
      if (Firebase.apps.isNotEmpty) {
        firebaseConfigured = true;
      } else if (DefaultFirebaseOptions.isConfigured) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseConfigured = true;
      }
    } catch (e) {
      debugPrint('Firebase web initialization note: $e');
      if (e.toString().contains('duplicate-app')) {
        firebaseConfigured = true;
      } else {
        firebaseConfigured = false;
      }
    }
  }

  // Theme is loaded before first frame to avoid a flash of the wrong theme.
  final themeProvider = ThemeProvider();
  await themeProvider.load();

  final connectivityProvider = ConnectivityProvider();
  final authProvider = firebaseConfigured
      ? AuthService.production()
      : AuthService.test();
  final syncService = SyncService(
    auth: authProvider,
    connectivity: connectivityProvider,
  );

  final tmdbService = TmdbService();
  final catalogueService = CatalogueService(tmdb: tmdbService);
  final adminService = AdminService(auth: authProvider);
  final dio = Dio();
  final adapter = StremioAdapter(dio: dio);
  final idResolver = IdResolver(tmdb: tmdbService, dio: dio);
  final playbackEngine = PlaybackEngine(adapter: adapter, idResolver: idResolver);
  final registry = ProviderRegistry();
  registry.load();
  final updateService = UpdateService();

  authProvider.initialize(firebaseConfigured: firebaseConfigured);
  NotificationService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<ConnectivityProvider>.value(
          value: connectivityProvider,
        ),
        ChangeNotifierProvider<AuthService>.value(value: authProvider),
        ChangeNotifierProvider<SyncService>.value(value: syncService),
        ChangeNotifierProvider<CatalogueService>.value(
          value: catalogueService,
        ),
        ChangeNotifierProvider<AdminService>.value(value: adminService),
        ChangeNotifierProvider<ProviderRegistry>.value(value: registry),
        ChangeNotifierProvider<PlaybackEngine>.value(value: playbackEngine),
        ChangeNotifierProvider<UpdateService>.value(value: updateService),
        Provider<StremioAdapter>.value(value: adapter),
        Provider<TmdbService>.value(value: tmdbService),
        Provider<NotificationService>.value(value: NotificationService.instance),
      ],
      child: CinemaHubApp(
        themeProvider: themeProvider,
        router: AppRouter(authProvider),
        authProvider: authProvider,
        tmdbService: tmdbService,
      ),
    ),
  );
}

class CinemaHubApp extends StatelessWidget {
  const CinemaHubApp({
    super.key,
    required this.themeProvider,
    required this.router,
    required this.authProvider,
    required this.tmdbService,
  });

  final ThemeProvider themeProvider;
  final AppRouter router;
  final AuthService authProvider;
  final TmdbService tmdbService;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Consumer<AuthService>(
          builder: (context, auth, _) {
            return MaterialApp(
              key: ValueKey(auth.state),
              title: 'CinemaHub',
              debugShowCheckedModeBanner: false,
              theme: theme.buildTheme(Brightness.light),
              darkTheme: theme.buildTheme(Brightness.dark),
              themeMode: theme.themeMode,
              onGenerateRoute: (settings) =>
                  router.onGenerateRoute(settings, auth.state),
              initialRoute: switch (auth.state) {
                AuthState.approved => '/home',
                AuthState.signedOut => '/signIn',
                AuthState.pendingApproval => '/pending',
                AuthState.suspended => '/suspended',
                AuthState.loading => '/splash',
              },
            );
          },
        );
      },
    );
  }
}
