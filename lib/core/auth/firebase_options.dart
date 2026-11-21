// Copyright 2024 CinemaHub. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


/// Default Firebase options for CinemaHub using --dart-define injection.
///
/// Build with:
///   flutter run --dart-define=FIREBASE_API_KEY=xxx \
///               --dart-define=FIREBASE_APP_ID=xxx \
///               --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxx \
///               --dart-define=FIREBASE_PROJECT_ID=xxx \
///               --dart-define=FIREBASE_STORAGE_BUCKET=xxx \
///               --dart-define=FIREBASE_AUTH_DOMAIN=xxx \
///               --dart-define=FIREBASE_DATABASE_URL=xxx \
///               --dart-define=FIREBASE_MEASUREMENT_ID=xxx
///
/// For iOS, also add:
///   --dart-define=FIREBASE_IOS_API_KEY=xxx \
///               --dart-define=FIREBASE_IOS_APP_ID=xxx \
///               --dart-define=FIREBASE_IOS_MESSAGING_SENDER_ID=xxx \
///               --dart-define=FIREBASE_IOS_PROJECT_ID=xxx \
///               --dart-define=FIREBASE_IOS_STORAGE_BUCKET=xxx \
///               --dart-define=FIREBASE_IOS_AUTH_DOMAIN=xxx \
///               --dart-define=FIREBASE_IOS_DATABASE_URL=xxx \
///               --dart-define=FIREBASE_IOS_MEASUREMENT_ID=xxx \
///               --dart-define=FIREBASE_IOS_BUNDLE_ID=com.cinemahub.app
///
/// For Web, also add:
///   --dart-define=FIREBASE_WEB_API_KEY=xxx \
///               --dart-define=FIREBASE_WEB_APP_ID=xxx \
///               --dart-define=FIREBASE_WEB_MESSAGING_SENDER_ID=xxx \
///               --dart-define=FIREBASE_WEB_PROJECT_ID=xxx \
///               --dart-define=FIREBASE_WEB_STORAGE_BUCKET=xxx \
///               --dart-define=FIREBASE_WEB_AUTH_DOMAIN=xxx \
///               --dart-define=FIREBASE_WEB_DATABASE_URL=xxx \
///               --dart-define=FIREBASE_WEB_MEASUREMENT_ID=xxx
///
/// For macOS, also add:
///   --dart-define=FIREBASE_MACOS_API_KEY=xxx \
///               --dart-define=FIREBASE_MACOS_APP_ID=xxx \
///               --dart-define=FIREBASE_MACOS_MESSAGING_SENDER_ID=xxx \
///               --dart-define=FIREBASE_MACOS_PROJECT_ID=xxx \
///               --dart-define=FIREBASE_MACOS_STORAGE_BUCKET=xxx \
///               --dart-define=FIREBASE_MACOS_AUTH_DOMAIN=xxx \
///               --dart-define=FIREBASE_MACOS_DATABASE_URL=xxx \
///               --dart-define=FIREBASE_MACOS_MEASUREMENT_ID=xxx \
///               --dart-define=FIREBASE_MACOS_BUNDLE_ID=com.cinemahub.app
///
/// For Windows, also add:
///   --dart-define=FIREBASE_WINDOWS_API_KEY=xxx \
///               --dart-define=FIREBASE_WINDOWS_APP_ID=xxx \
///               --dart-define=FIREBASE_WINDOWS_MESSAGING_SENDER_ID=xxx \
///               --dart-define=FIREBASE_WINDOWS_PROJECT_ID=xxx \
///               --dart-define=FIREBASE_WINDOWS_STORAGE_BUCKET=xxx \
///               --dart-define=FIREBASE_WINDOWS_AUTH_DOMAIN=xxx \
///               --dart-define=FIREBASE_WINDOWS_DATABASE_URL=xxx \
///               --dart-define=FIREBASE_WINDOWS_MEASUREMENT_ID=xxx
library;


import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    if (Platform.isAndroid) {
      return android;
    }
    if (Platform.isIOS) {
      return ios;
    }
    if (Platform.isMacOS) {
      return macos;
    }
    if (Platform.isWindows) {
      return windows;
    }
    // Default to web for any other platform (Linux, Fuchsia, etc.)
    return web;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _androidApiKey,
    appId: _androidAppId,
    messagingSenderId: _androidMessagingSenderId,
    projectId: _androidProjectId,
    storageBucket: _androidStorageBucket,
    authDomain: _androidAuthDomain,
    databaseURL: _androidDatabaseUrl,
    measurementId: _androidMeasurementId,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: _iosApiKey,
    appId: _iosAppId,
    messagingSenderId: _iosMessagingSenderId,
    projectId: _iosProjectId,
    storageBucket: _iosStorageBucket,
    authDomain: _iosAuthDomain,
    databaseURL: _iosDatabaseUrl,
    measurementId: _iosMeasurementId,
    iosBundleId: _iosBundleId,
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: _macosApiKey,
    appId: _macosAppId,
    messagingSenderId: _macosMessagingSenderId,
    projectId: _macosProjectId,
    storageBucket: _macosStorageBucket,
    authDomain: _macosAuthDomain,
    databaseURL: _macosDatabaseUrl,
    measurementId: _macosMeasurementId,
    iosBundleId: _macosBundleId,
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: _windowsApiKey,
    appId: _windowsAppId,
    messagingSenderId: _windowsMessagingSenderId,
    projectId: _windowsProjectId,
    storageBucket: _windowsStorageBucket,
    authDomain: _windowsAuthDomain,
    databaseURL: _windowsDatabaseUrl,
    measurementId: _windowsMeasurementId,
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _webApiKey,
    appId: _webAppId,
    messagingSenderId: _webMessagingSenderId,
    projectId: _webProjectId,
    storageBucket: _webStorageBucket,
    authDomain: _webAuthDomain,
    databaseURL: _webDatabaseUrl,
    measurementId: _webMeasurementId,
  );

  // Android values from --dart-define
  static const String _androidApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const String _androidAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
  static const String _androidMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '');
  static const String _androidProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
  static const String _androidStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: '');
  static const String _androidAuthDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN', defaultValue: '');
  static const String _androidDatabaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL', defaultValue: '');
  static const String _androidMeasurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID', defaultValue: '');

  // iOS values from --dart-define
  static const String _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY', defaultValue: '');
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID', defaultValue: '');
  static const String _iosMessagingSenderId = String.fromEnvironment('FIREBASE_IOS_MESSAGING_SENDER_ID', defaultValue: '');
  static const String _iosProjectId = String.fromEnvironment('FIREBASE_IOS_PROJECT_ID', defaultValue: '');
  static const String _iosStorageBucket = String.fromEnvironment('FIREBASE_IOS_STORAGE_BUCKET', defaultValue: '');
  static const String _iosAuthDomain = String.fromEnvironment('FIREBASE_IOS_AUTH_DOMAIN', defaultValue: '');
  static const String _iosDatabaseUrl = String.fromEnvironment('FIREBASE_IOS_DATABASE_URL', defaultValue: '');
  static const String _iosMeasurementId = String.fromEnvironment('FIREBASE_IOS_MEASUREMENT_ID', defaultValue: '');
  static const String _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: 'com.cinemahub.app');

  // macOS values from --dart-define
  static const String _macosApiKey = String.fromEnvironment('FIREBASE_MACOS_API_KEY', defaultValue: '');
  static const String _macosAppId = String.fromEnvironment('FIREBASE_MACOS_APP_ID', defaultValue: '');
  static const String _macosMessagingSenderId = String.fromEnvironment('FIREBASE_MACOS_MESSAGING_SENDER_ID', defaultValue: '');
  static const String _macosProjectId = String.fromEnvironment('FIREBASE_MACOS_PROJECT_ID', defaultValue: '');
  static const String _macosStorageBucket = String.fromEnvironment('FIREBASE_MACOS_STORAGE_BUCKET', defaultValue: '');
  static const String _macosAuthDomain = String.fromEnvironment('FIREBASE_MACOS_AUTH_DOMAIN', defaultValue: '');
  static const String _macosDatabaseUrl = String.fromEnvironment('FIREBASE_MACOS_DATABASE_URL', defaultValue: '');
  static const String _macosMeasurementId = String.fromEnvironment('FIREBASE_MACOS_MEASUREMENT_ID', defaultValue: '');
  static const String _macosBundleId = String.fromEnvironment('FIREBASE_MACOS_BUNDLE_ID', defaultValue: 'com.cinemahub.app');

  // Windows values from --dart-define
  static const String _windowsApiKey = String.fromEnvironment('FIREBASE_WINDOWS_API_KEY', defaultValue: '');
  static const String _windowsAppId = String.fromEnvironment('FIREBASE_WINDOWS_APP_ID', defaultValue: '');
  static const String _windowsMessagingSenderId = String.fromEnvironment('FIREBASE_WINDOWS_MESSAGING_SENDER_ID', defaultValue: '');
  static const String _windowsProjectId = String.fromEnvironment('FIREBASE_WINDOWS_PROJECT_ID', defaultValue: '');
  static const String _windowsStorageBucket = String.fromEnvironment('FIREBASE_WINDOWS_STORAGE_BUCKET', defaultValue: '');
  static const String _windowsAuthDomain = String.fromEnvironment('FIREBASE_WINDOWS_AUTH_DOMAIN', defaultValue: '');
  static const String _windowsDatabaseUrl = String.fromEnvironment('FIREBASE_WINDOWS_DATABASE_URL', defaultValue: '');
  static const String _windowsMeasurementId = String.fromEnvironment('FIREBASE_WINDOWS_MEASUREMENT_ID', defaultValue: '');

  // Web values from --dart-define
  static const String _webApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY', defaultValue: '');
  static const String _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID', defaultValue: '');
  static const String _webMessagingSenderId = String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID', defaultValue: '');
  static const String _webProjectId = String.fromEnvironment('FIREBASE_WEB_PROJECT_ID', defaultValue: '');
  static const String _webStorageBucket = String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET', defaultValue: '');
  static const String _webAuthDomain = String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN', defaultValue: '');
  static const String _webDatabaseUrl = String.fromEnvironment('FIREBASE_WEB_DATABASE_URL', defaultValue: '');
  static const String _webMeasurementId = String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID', defaultValue: '');

  /// Checks if Firebase is properly configured for the current platform.
  static bool get isConfigured {
    final options = currentPlatform;
    return options.apiKey.isNotEmpty &&
        options.appId.isNotEmpty &&
        options.projectId.isNotEmpty;
  }

  /// Returns a human-readable description of missing configuration.
  static String get configurationStatus {
    final options = currentPlatform;
    final missing = <String>[];
    if (options.apiKey.isEmpty) missing.add('API Key');
    if (options.appId.isEmpty) missing.add('App ID');
    if (options.projectId.isEmpty) missing.add('Project ID');
    if ((options.storageBucket ?? '').isEmpty) missing.add('Storage Bucket');
    if ((options.authDomain ?? '').isEmpty) missing.add('Auth Domain');
    final osName = kIsWeb ? 'web' : Platform.operatingSystem;
    if (missing.isEmpty) {
      return 'Firebase is configured for $osName.';
    }
    return 'Firebase is NOT configured for $osName. Missing: ${missing.join(', ')}. '
        'Add --dart-define values at build time.';
  }
}