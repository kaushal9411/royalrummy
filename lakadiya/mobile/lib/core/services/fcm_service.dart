import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _token = await messaging.getToken();
      print('==================================================');
      print('FCM DEVICE TOKEN: $_token');
      print('==================================================');

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        print('FCM Token refreshed: $t');
      });

      await _initLocalNotifications();

      FirebaseMessaging.onMessage.listen(_handleMessage);
    } catch (e) {
      print('FCM initialization error: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    const otpChannel = AndroidNotificationChannel(
      'otp_channel',
      'OTP Notifications',
      description: 'One-time password delivery',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    const roomChannel = AndroidNotificationChannel(
      'room_channel',
      'Game Room Alerts',
      description: 'Alerts for new open bet rooms',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    const walletChannel = AndroidNotificationChannel(
      'wallet_channel',
      'Wallet & Payments',
      description: 'Wallet top-up, withdrawal and payment updates',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(otpChannel);
    await androidPlugin?.createNotificationChannel(roomChannel);
    await androidPlugin?.createNotificationChannel(walletChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);
  }

  void _handleMessage(RemoteMessage message) {
    print('Foreground FCM message: ${message.data}');
    final data = message.data;

    if (data['type'] == 'OTP' || data.containsKey('otp')) {
      final otp = data['otp'] as String?;
      if (otp != null && otp.length == 6) {
        _otpController.add(otp);
        _showOtpNotification(otp: otp, bigText: data['bigText']);
      }
    } else if (data['type'] == 'NEW_ROOM') {
      _showRoomNotification(
        roomCode:  data['roomCode']  ?? '',
        betAmount: data['betAmount'] ?? '0',
        hostName:  data['hostName'],
        bigText:   data['bigText'],
      );
    } else if (const {'WALLET_ADD', 'WITHDRAWAL_REQUESTED', 'WITHDRAWAL_APPROVED', 'WITHDRAWAL_REJECTED'}
        .contains(data['type'])) {
      _showWalletNotification(
        title: data['title'] ?? message.notification?.title ?? '',
        body:  data['body']  ?? message.notification?.body  ?? '',
        type:  data['type']  as String,
      );
    } else if (message.notification != null) {
      final n = message.notification!;
      _showGenericNotification(title: n.title ?? '', body: n.body ?? '', data: data);
    }
  }

  Future<void> _showOtpNotification({
    required String otp,
    String? bigText,
  }) async {
    try {
      final style = BigTextStyleInformation(
        bigText ?? 'Your one-time password:\n\n       $otp\n\nValid for 10 minutes. Do not share this code with anyone.',
        contentTitle: '<b>🔐 Lakadiya – Verification Code</b>',
        summaryText:  'Tap to open the app and auto-fill',
      );

      await _localNotifications.show(
        1,
        '🔐 Lakadiya – Verification Code',
        'OTP: $otp  •  Tap to auto-fill',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'otp_channel',
            'OTP Notifications',
            channelDescription: 'One-time password delivery',
            icon:               '@mipmap/ic_launcher',
            importance:         Importance.max,
            priority:           Priority.high,
            enableVibration:    true,
            playSound:          true,
            color:              const Color(0xFF00C853),
            ticker:             'OTP Received',
            styleInformation:   style,
          ),
          iOS: const DarwinNotificationDetails(
            sound:         'default',
            presentAlert:  true,
            presentBadge:  true,
            presentSound:  true,
            subtitle:      'Tap to auto-fill',
          ),
        ),
        payload: 'otp:$otp',
      );
    } catch (e) {
      print('Error showing OTP notification: $e');
    }
  }

  Future<void> _showRoomNotification({
    required String roomCode,
    required String betAmount,
    String? hostName,
    String? bigText,
  }) async {
    try {
      final bet  = double.tryParse(betAmount) ?? 0;
      final betText = '₹${bet.toStringAsFixed(0)}';
      final host = hostName ?? 'A player';

      final style = BigTextStyleInformation(
        bigText ?? '$host just opened a $betText bet room!\n\n'
            '  🎯  Room Code:  $roomCode\n'
            '  💰  Bet Amount: $betText\n\n'
            'Join before it fills up!',
        contentTitle: '<b>🎮 New Bet Room Available!</b>',
        summaryText:  '$betText Bet • Tap to join',
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '🎮 New Bet Room – Join Now!',
        'Code: $roomCode  •  $betText Bet',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'room_channel',
            'Game Room Alerts',
            channelDescription: 'Alerts for new open bet rooms',
            icon:               '@mipmap/ic_launcher',
            importance:         Importance.high,
            priority:           Priority.high,
            enableVibration:    true,
            playSound:          true,
            color:              const Color(0xFFFF6F00),
            ticker:             'New Bet Room',
            styleInformation:   style,
          ),
          iOS: const DarwinNotificationDetails(
            sound:        'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            subtitle:     'Tap to join the room',
          ),
        ),
        payload: 'room:$roomCode',
      );
    } catch (e) {
      print('Error showing room notification: $e');
    }
  }

  Future<void> _showWalletNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      Color color;
      if (type == 'WALLET_ADD') {
        color = const Color(0xFF00C853);
      } else if (type == 'WITHDRAWAL_APPROVED') {
        color = const Color(0xFF4CAF50);
      } else if (type == 'WITHDRAWAL_REJECTED') {
        color = const Color(0xFFE53935);
      } else {
        color = const Color(0xFF2196F3); // WITHDRAWAL_REQUESTED
      }

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'wallet_channel',
            'Wallet & Payments',
            channelDescription: 'Wallet top-up, withdrawal and payment updates',
            icon:            '@mipmap/ic_launcher',
            importance:      Importance.high,
            priority:        Priority.high,
            enableVibration: true,
            playSound:       true,
            color:           color,
            ticker:          title,
          ),
          iOS: const DarwinNotificationDetails(
            sound:        'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      print('Error showing wallet notification: $e');
    }
  }

  Future<void> _showGenericNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'General Notifications',
            icon:            '@mipmap/ic_launcher',
            importance:      Importance.high,
            priority:        Priority.high,
            enableVibration: true,
            playSound:       true,
          ),
          iOS: DarwinNotificationDetails(
            sound:        'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  void dispose() {
    _otpController.close();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background FCM message: ${message.data}');
}
