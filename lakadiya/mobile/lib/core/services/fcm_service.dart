import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles FCM token retrieval and listens for OTP + other messages
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  String? _token;
  String? get token => _token;

  final _otpController = StreamController<String>.broadcast();
  Stream<String> get otpStream => _otpController.stream;

  // Local notifications plugin for showing rich notifications
  late final FlutterLocalNotificationsPlugin _localNotifications;

  Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission with all features
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _token = await messaging.getToken();
      print('==================================================');
      print('FCM DEVICE TOKEN: $_token');
      print('==================================================');

      // Refresh token when it changes
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        print('FCM Token refreshed: $t');
      });

      // Initialize local notifications for rich display
      _initLocalNotifications();

      // ── Foreground messages ──────────────────────────────────────────────
      FirebaseMessaging.onMessage.listen(_handleMessage);

      // ── Background / terminated — handled in main via onBackgroundMessage ─
    } catch (e) {
      print('FCM initialization error: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    // Android channel for OTP notifications
    const androidChannel = AndroidNotificationChannel(
      'otp_channel',
      'OTP Notifications',
      description: 'Notifications for OTP delivery',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    // Create the channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Initialize with default settings
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(initSettings);
  }

  void _handleMessage(RemoteMessage message) {
    print('Foreground FCM message: ${message.notification?.title}');
    print('Message data: ${message.data}');

    final data = message.data;
    final notification = message.notification;

    // Handle OTP type
    if (data['type'] == 'OTP' || data.containsKey('otp')) {
      final otp = data['otp'] as String?;
      if (otp != null && otp.length == 6) {
        _otpController.add(otp);
        _showOtpNotification(otp);
      }
    } else if (notification != null) {
      // Show other notifications
      _showNotification(
        title: notification.title ?? 'Notification',
        body: notification.body ?? '',
        data: data,
      );
    }
  }

  /// Display OTP notification with app icon and vibration
  Future<void> _showOtpNotification(String otp) async {
    try {
      final bigText = 'Your verification code is:\n$otp\n\nDo not share this code with anyone.';
      
      await _localNotifications.show(
        1, // notification ID
        'Your OTP Code',
        'OTP: $otp',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'otp_channel',
            'OTP Notifications',
            channelDescription: 'Notifications for OTP delivery',
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            color: Colors.green,
            ticker: 'OTP Delivery',
          ),
          iOS: const DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'otp:$otp',
      );
    } catch (e) {
      print('Error showing OTP notification: $e');
    }
  }

  /// Display generic notification
  Future<void> _showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecond,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'General Notifications',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: data != null ? Uri.encodeComponent(Uri(queryParameters: data).toString()) : null,
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  void dispose() {
    _otpController.close();
  }
}

/// Top-level handler for background/terminated FCM messages.
/// Must be a top-level function (not inside a class).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background FCM message received: ${message.notification?.title}');
  print('Message data: ${message.data}');
}
