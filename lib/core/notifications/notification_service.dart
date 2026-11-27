import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isNotEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  static const String channelId = 'cinemahub_alerts';
  static const String channelName = 'CinemaHub Alerts';
  static const String channelDesc =
      'Notifications for releases, friend approvals, and updates';

  Future<void> initialize() async {
    if (_initialized) return;

    // 1. Initialize local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _localNotifs.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Notification clicked: ${response.payload}');
      },
    );

    // 2. Create notification channel for Android
    if (!kIsWeb && Platform.isAndroid) {
      final androidImplementation = _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        const channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        await androidImplementation.createNotificationChannel(channel);
        await androidImplementation.requestNotificationsPermission();
      }
    }

    // 3. Initialize Firebase Cloud Messaging if Firebase is configured
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler);

        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          try {
            // ignore: deprecated_member_use
            _fcmToken = await messaging.getToken();
            debugPrint('CinemaHub FCM Token: $_fcmToken');
          } catch (e) {
            debugPrint('FCM Token error: $e');
          }

          // Listen for foreground FCM messages and display heads-up banner
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            final notification = message.notification;
            if (notification != null) {
              showLocalNotification(
                title: notification.title ?? 'CinemaHub Update',
                body: notification.body ?? 'You have a new update in CinemaHub.',
                payload: message.data.toString(),
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Firebase messaging init note: $e');
    }

    _initialized = true;
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _localNotifs.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notifDetails,
      payload: payload,
    );
  }

  Future<void> sendTestNotification() async {
    await showLocalNotification(
      title: '🎬 CinemaHub Alert',
      body: 'Notifications are configured & working smoothly!',
      payload: 'cinemahub://test',
    );
  }
}
