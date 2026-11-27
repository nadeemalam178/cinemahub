import 'dart:async';

import 'package:dio/dio.dart' hide Response;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/admin/admin_service.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/firebase_options.dart';
import 'core/catalogue/catalogue_service.dart';
import 'core/catalogue/id_resolver.dart';
import 'core/catalogue/tmdb_service.dart';
import 'core/network/connectivity_provider.dart';
import 'core/notifications/notification_service.dart';
import 'core/player/playback_engine.dart';
import 'core/providers/provider_registry.dart';
import 'core/providers/stremio_adapter.dart';
import 'core/routing/app_router.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/theme_provider.dart';
import 'core/update/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        await Firebase.initializeApp();
        firebaseConfigured = true;
      }
    } catch (e) {
      debugPrint('Firebase initialization note: $e');
      firebaseConfigured = e.toString().contains('duplicate-app');
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
      firebaseConfigured = e.toString().contains('duplicate-app');
    }
  }

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
  final updateService = UpdateService();

  // Only load Firestore-gated services once the user is approved; reset on sign-out.
  AuthState? lastHandledAuthState;
  void handleAuthTransition() {
    final current = authProvider.state;
    if (current == lastHandledAuthState) {
      if (current == AuthState.approved) {
        unawaited(adminService.checkAdminStatus());
      }
      return;
    }
    lastHandledAuthState = current;
    if (current == AuthState.approved) {
      registry.load();
      unawaited(adminService.checkAdminStatus());
      unawaited(syncService.onConnectivityRestored());
    } else if (current == AuthState.signedOut || current == AuthState.suspended) {
      registry.reset();
      adminService.reset();
    }
  }

  authProvider.addListener(handleAuthTransition);
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

class CinemaHubApp extends StatefulWidget {
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
  State<CinemaHubApp> createState() => _CinemaHubAppState();
}

class _CinemaHubAppState extends State<CinemaHubApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late AuthState _lastAuthState;

  @override
  void initState() {
    super.initState();
    _lastAuthState = widget.authProvider.state;
    widget.authProvider.addListener(_onAuthChanged);
  }

  @override
  void didUpdateWidget(covariant CinemaHubApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authProvider != widget.authProvider) {
      oldWidget.authProvider.removeListener(_onAuthChanged);
      _lastAuthState = widget.authProvider.state;
      widget.authProvider.addListener(_onAuthChanged);
    }
  }

  @override
  void dispose() {
    widget.authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final nextState = widget.authProvider.state;
    if (nextState == _lastAuthState) return;
    _lastAuthState = nextState;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeForAuth(nextState),
        (_) => false,
      );
    });
  }

  String _routeForAuth(AuthState state) => switch (state) {
    AuthState.approved => '/home',
    AuthState.signedOut => '/signIn',
    AuthState.pendingApproval => '/pending',
    AuthState.suspended => '/suspended',
    AuthState.loading => '/splash',
  };

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'CinemaHub',
          debugShowCheckedModeBanner: false,
          theme: theme.buildTheme(Brightness.light),
          darkTheme: theme.buildTheme(Brightness.dark),
          themeMode: theme.themeMode,
          onGenerateRoute: (settings) =>
              widget.router.onGenerateRoute(settings, widget.authProvider.state),
          initialRoute: _routeForAuth(widget.authProvider.state),
        );
      },
    );
  }
}
