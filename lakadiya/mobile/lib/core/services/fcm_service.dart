import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_settings_service.dart';

// ── Top-level background handler (must be top-level, not a class method) ──────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM auto-displays messages that have a `notification` key — no code needed.
  // For data-only messages (no `notification` key) we must show the notification ourselves.
  if (message.notification != null) return;

  final data  = message.data;
  final title = data['title'] as String? ?? '';
  final body  = data['body']  as String? ?? '';
  if (title.isEmpty && body.isEmpty) return;

  final type = data['type'] as String? ?? '';

  // Pick channel based on type
  final channelId = _channelIdForType(type);

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelNameForType(type),
        importance:      Importance.high,
        priority:        Priority.high,
        enableVibration: true,
        playSound:       true,
        icon:            '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        sound:        'default',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

String _channelIdForType(String type) {
  if (type == 'OTP') return 'otp_channel';
  if (type == 'NEW_ROOM' || type == 'GAME_INVITE') return 'room_channel';
  if (type.startsWith('WALLET') || type.startsWith('WITHDRAWAL')) return 'wallet_channel';
  if (type == 'MESSAGE_RECEIVED') return 'message_channel';
  return 'default_channel';
}

String _channelNameForType(String type) {
  if (type == 'OTP') return 'OTP Notifications';
  if (type == 'NEW_ROOM' || type == 'GAME_INVITE') return 'Game Room Alerts';
  if (type.startsWith('WALLET') || type.startsWith('WITHDRAWAL')) return 'Wallet & Payments';
  if (type == 'MESSAGE_RECEIVED') return 'Direct Messages';
  return 'General Notifications';
}

// ── FcmService ─────────────────────────────────────────────────────────────────
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  String? _token;
  String? get token => _token;

  final _otpController = StreamController<String>.broadcast();
  Stream<String> get otpStream => _otpController.stream;

  late final FlutterLocalNotificationsPlugin _localNotifications;

  Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
      );

      // On Android 13+ background delivery requires this
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      _token = await messaging.getToken();
      debugPrint('==================================================');
      debugPrint('FCM DEVICE TOKEN: $_token');
      debugPrint('==================================================');

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        debugPrint('[FCM] Token refreshed: $t');
      });

      await _initLocalNotifications();

      // Foreground messages
      FirebaseMessaging.onMessage.listen(_handleMessage);

      // App opened from a notification tap (background → foreground)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    } catch (e) {
      debugPrint('[FCM] Initialization error: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Register ALL channels the app will ever use
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'otp_channel', 'OTP Notifications',
      description: 'One-time password delivery',
      importance: Importance.max,
      enableVibration: true, playSound: true,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'room_channel', 'Game Room Alerts',
      description: 'Alerts for new open bet rooms',
      importance: Importance.high,
      enableVibration: true, playSound: true,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'wallet_channel', 'Wallet & Payments',
      description: 'Wallet top-up, withdrawal and payment updates',
      importance: Importance.high,
      enableVibration: true, playSound: true,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'default_channel', 'General Notifications',
      description: 'Platform announcements and general updates',
      importance: Importance.high,
      enableVibration: true, playSound: true,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'message_channel', 'Direct Messages',
      description: 'Private messages from friends',
      importance: Importance.high,
      enableVibration: true, playSound: true,
    ));

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);
  }

  // ── Message router ────────────────────────────────────────────────────────────
  void _handleMessage(RemoteMessage message) {
    debugPrint('[FCM] Message received — type: ${message.data['type']} | notification: ${message.notification?.title}');

    final data = message.data;
    final type = data['type'] as String? ?? '';

    if (type == 'SETTINGS_UPDATE') {
      AppSettingsService.instance.updateFromData(data);
      return;
    }

    if (type == 'OTP' || data.containsKey('otp')) {
      final otp = data['otp'] as String?;
      if (otp != null && otp.length == 6) {
        _otpController.add(otp);
        _showOtpNotification(otp: otp, bigText: data['bigText']);
      }
      return;
    }

    if (type == 'NEW_ROOM') {
      _showRoomNotification(
        roomCode:  data['roomCode']  ?? '',
        betAmount: data['betAmount'] ?? '0',
        hostName:  data['hostName'],
        bigText:   data['bigText'],
      );
      return;
    }

    if (type == 'MESSAGE_RECEIVED') {
      _showMessageNotification(
        senderName: data['senderName'] ?? data['title'] ?? 'New message',
        text:       data['messageText'] ?? data['body'] ?? '',
      );
      return;
    }

    if (type == 'GAME_INVITE') {
      _showGameInviteNotification(
        fromUsername: data['fromUsername'] ?? data['title'] ?? 'A player',
        roomCode:     data['roomCode'] ?? '',
      );
      return;
    }

    if (const {'WALLET_ADD', 'WITHDRAWAL_REQUESTED', 'WITHDRAWAL_APPROVED', 'WITHDRAWAL_REJECTED'}.contains(type)) {
      _showWalletNotification(
        title: data['title'] ?? message.notification?.title ?? '',
        body:  data['body']  ?? message.notification?.body  ?? '',
        type:  type,
      );
      return;
    }

    // Admin broadcast: GENERAL, PROMO, ALERT, EVENT — or any other notification.
    // Always read title/body from data first (we always set them in backend),
    // then fall back to the notification payload.
    final title = (data['title'] as String?)?.isNotEmpty == true
        ? data['title'] as String
        : message.notification?.title ?? '';
    final body = (data['body'] as String?)?.isNotEmpty == true
        ? data['body'] as String
        : message.notification?.body ?? '';

    if (title.isNotEmpty || body.isNotEmpty) {
      _showGenericNotification(title: title, body: body);
    }
  }

  // ── Show helpers ──────────────────────────────────────────────────────────────

  Future<void> _showOtpNotification({required String otp, String? bigText}) async {
    try {
      await _localNotifications.show(
        1,
        '🔐 Lakadiya – Verification Code',
        'OTP: $otp  •  Tap to auto-fill',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'otp_channel', 'OTP Notifications',
            channelDescription: 'One-time password delivery',
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            color: const Color(0xFF00C853),
            ticker: 'OTP Received',
            styleInformation: BigTextStyleInformation(
              bigText ?? 'Your one-time password:\n\n       $otp\n\nValid for 10 minutes. Do not share this code with anyone.',
              contentTitle: '<b>🔐 Lakadiya – Verification Code</b>',
              summaryText: 'Tap to open the app and auto-fill',
            ),
          ),
          iOS: const DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true, presentBadge: true, presentSound: true,
            subtitle: 'Tap to auto-fill',
          ),
        ),
        payload: 'otp:$otp',
      );
    } catch (e) {
      debugPrint('[FCM] Error showing OTP notification: $e');
    }
  }

  Future<void> _showRoomNotification({
    required String roomCode,
    required String betAmount,
    String? hostName,
    String? bigText,
  }) async {
    try {
      final bet     = double.tryParse(betAmount) ?? 0;
      final betText = '₹${bet.toStringAsFixed(0)}';
      final host    = hostName ?? 'A player';

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '🎮 New Bet Room – Join Now!',
        'Code: $roomCode  •  $betText Bet',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'room_channel', 'Game Room Alerts',
            channelDescription: 'Alerts for new open bet rooms',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            color: const Color(0xFFFF6F00),
            ticker: 'New Bet Room',
            styleInformation: BigTextStyleInformation(
              bigText ?? '$host just opened a $betText bet room!\n\n'
                  '  🎯  Room Code:  $roomCode\n'
                  '  💰  Bet Amount: $betText\n\n'
                  'Join before it fills up!',
              contentTitle: '<b>🎮 New Bet Room Available!</b>',
              summaryText: '$betText Bet • Tap to join',
            ),
          ),
          iOS: const DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true, presentBadge: true, presentSound: true,
            subtitle: 'Tap to join the room',
          ),
        ),
        payload: 'room:$roomCode',
      );
    } catch (e) {
      debugPrint('[FCM] Error showing room notification: $e');
    }
  }

  Future<void> _showWalletNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final color = type == 'WALLET_ADD'
          ? const Color(0xFF00C853)
          : type == 'WITHDRAWAL_APPROVED'
              ? const Color(0xFF4CAF50)
              : type == 'WITHDRAWAL_REJECTED'
                  ? const Color(0xFFE53935)
                  : const Color(0xFF2196F3);

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'wallet_channel', 'Wallet & Payments',
            channelDescription: 'Wallet top-up, withdrawal and payment updates',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            color: color,
            ticker: title,
          ),
          iOS: const DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FCM] Error showing wallet notification: $e');
    }
  }

  Future<void> _showGenericNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel', 'General Notifications',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FCM] Error showing generic notification: $e');
    }
  }

  Future<void> _showMessageNotification({
    required String senderName,
    required String text,
  }) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '💬 $senderName',
        text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'message_channel', 'Direct Messages',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FCM] Error showing message notification: $e');
    }
  }

  Future<void> _showGameInviteNotification({
    required String fromUsername,
    required String roomCode,
  }) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '🎮 $fromUsername invited you!',
        roomCode.isNotEmpty ? 'Join room $roomCode — tap to play' : 'Tap to join the game',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'room_channel', 'Game Room Alerts',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FCM] Error showing game invite notification: $e');
    }
  }

  void dispose() {
    _otpController.close();
  }
}
