# Firebase Integration — RummyRoyale

## 1. Firebase Services Used

| Service            | Purpose                                      |
|--------------------|----------------------------------------------|
| FCM                | Push notifications (game alerts, promotions) |
| Firebase Analytics | User behavior, retention, funnel analysis    |
| Crashlytics        | Crash reporting, ANR detection               |
| Remote Config      | Feature flags, game config without deploys   |
| Dynamic Links      | Referral links, deep links                   |
| App Distribution   | Beta testing builds                          |

---

## 2. Push Notification Architecture

```
Backend Event
    │
    ▼
notification-service
    │
    ├─ Fetch FCM token from user_devices table
    ├─ Build FCM payload
    │
    ▼
Firebase Admin SDK
    │
    ▼
Firebase Cloud Messaging
    │
    ▼
Android Device (FCM)
    │
    ▼
Flutter App (handles notification)
```

---

## 3. Backend: Firebase Admin SDK

```typescript
// libs/firebase/src/firebase.service.ts
import * as admin from 'firebase-admin';

@Injectable()
export class FirebaseService {

  private messaging: admin.messaging.Messaging;

  constructor() {
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        }),
      });
    }
    this.messaging = admin.messaging();
  }

  async sendToUser(
    fcmToken: string,
    notification: NotificationPayload,
    data?: Record<string, string>,
  ): Promise<void> {
    await this.messaging.send({
      token: fcmToken,
      notification: {
        title: notification.title,
        body: notification.body,
        imageUrl: notification.image_url,
      },
      data: {
        type: notification.type,
        ...data,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: this.getChannelId(notification.type),
          sound: 'default',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: notification.badge_count,
          },
        },
      },
    });
  }

  async sendToMultipleUsers(
    fcmTokens: string[],
    notification: NotificationPayload,
  ): Promise<void> {
    // Batch in groups of 500 (FCM limit)
    const chunks = this.chunkArray(fcmTokens, 500);
    for (const chunk of chunks) {
      await this.messaging.sendEachForMulticast({
        tokens: chunk,
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data: { type: notification.type },
      });
    }
  }

  async sendToTopic(topic: string, notification: NotificationPayload): Promise<void> {
    await this.messaging.send({
      topic: topic,
      notification: {
        title: notification.title,
        body: notification.body,
      },
    });
  }

  private getChannelId(type: string): string {
    const channels = {
      game_invite: 'game_channel',
      game_result: 'game_channel',
      tournament: 'tournament_channel',
      wallet: 'wallet_channel',
      promotion: 'promotions_channel',
      system: 'system_channel',
    };
    return channels[type] || 'default_channel';
  }
}
```

---

## 4. Notification Templates

```typescript
// notification-service/src/templates/notification.templates.ts
export const NOTIFICATION_TEMPLATES = {
  game_invite: (inviter: string, tableType: string) => ({
    title: `${inviter} invites you!`,
    body: `Join a ${tableType} game. Table filling up fast!`,
    type: 'game_invite',
  }),

  game_result_win: (amount: number) => ({
    title: 'You Won! 🏆',
    body: `Congratulations! You won ₹${amount.toFixed(2)}`,
    type: 'game_result',
  }),

  game_result_loss: () => ({
    title: 'Better luck next time!',
    body: 'Review your game and sharpen your skills.',
    type: 'game_result',
  }),

  tournament_starting: (name: string, minutesLeft: number) => ({
    title: `${name} starts in ${minutesLeft} minutes!`,
    body: 'Head to the lobby to join your table.',
    type: 'tournament',
  }),

  wallet_credited: (amount: number, type: string) => ({
    title: 'Wallet Credited ✅',
    body: `₹${amount} ${type} added to your wallet.`,
    type: 'wallet',
  }),

  daily_reward_available: (day: number) => ({
    title: `Day ${day} Reward Available!`,
    body: 'Claim your daily login reward now.',
    type: 'daily_reward',
  }),

  referral_joined: (name: string) => ({
    title: 'Referral Joined! 🎉',
    body: `${name} joined using your referral code. Reward incoming!`,
    type: 'referral',
  }),
};
```

---

## 5. Flutter: Notification Handling

```dart
// mobile/lib/core/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // Request permission
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Setup notification channels
    await _setupNotificationChannels();

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle app opened from terminated via notification
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // Get and upload FCM token
    final token = await _fcm.getToken();
    if (token != null) {
      await _uploadFcmToken(token);
    }

    // Listen for token refresh
    _fcm.onTokenRefresh.listen(_uploadFcmToken);
  }

  Future<void> _setupNotificationChannels() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Create channels
    final channels = [
      AndroidNotificationChannel(
        'game_channel', 'Game Notifications',
        description: 'Game invites and results',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('game_sound'),
      ),
      AndroidNotificationChannel(
        'wallet_channel', 'Wallet Updates',
        description: 'Deposits, withdrawals, winnings',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'tournament_channel', 'Tournaments',
        description: 'Tournament alerts and results',
        importance: Importance.max,
      ),
    ];

    for (final channel in channels) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Show local notification when app is in foreground
    _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _getChannelId(message.data['type']),
          'Notifications',
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'];
    final data = message.data;

    // Navigate based on notification type
    switch (type) {
      case 'game_invite':
        NavigationService.pushNamed('/game/table', args: {'table_id': data['table_id']});
        break;
      case 'game_result':
        NavigationService.pushNamed('/game/result', args: {'match_id': data['match_id']});
        break;
      case 'tournament':
        NavigationService.pushNamed('/tournament/detail', args: {'id': data['tournament_id']});
        break;
      case 'wallet':
        NavigationService.pushNamed('/wallet');
        break;
    }
  }
}
```

---

## 6. Remote Config

```typescript
// Backend: Update remote config
await admin.remoteConfig().template.then(template => {
  template.parameters['min_withdrawal_amount'] = {
    defaultValue: { value: '100' },
  };
  template.parameters['bot_fill_wait_seconds'] = {
    defaultValue: { value: '30' },
  };
  template.parameters['maintenance_mode'] = {
    defaultValue: { value: 'false' },
    conditionalValues: {
      'android_beta': { value: 'false' },
    },
  };
  return admin.remoteConfig().publishTemplate(template);
});
```

```dart
// Flutter: Use remote config values
class RemoteConfigService {
  final FirebaseRemoteConfig _config = FirebaseRemoteConfig.instance;

  Future<void> initialize() async {
    await _config.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    await _config.setDefaults({
      'min_withdrawal_amount': 100,
      'maintenance_mode': false,
      'points_rummy_entry_fees': '[10,25,50,100,500]',
      'new_user_bonus': 50,
    });

    await _config.fetchAndActivate();
  }

  bool get maintenanceMode => _config.getBool('maintenance_mode');
  int get minWithdrawal => _config.getInt('min_withdrawal_amount');
  List<int> get pointsRummyEntryFees =>
      List<int>.from(jsonDecode(_config.getString('points_rummy_entry_fees')));
}
```

---

## 7. Analytics Events

```dart
// Track key game analytics events
class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> trackGameStarted({
    required String gameType,
    required double entryFee,
    required int playerCount,
  }) => _analytics.logEvent(
    name: 'game_started',
    parameters: {
      'game_type': gameType,
      'entry_fee': entryFee,
      'player_count': playerCount,
    },
  );

  Future<void> trackDeposit({
    required double amount,
    required String method,
  }) => _analytics.logEvent(
    name: 'deposit_completed',
    parameters: {'amount': amount, 'method': method},
  );

  Future<void> trackTournamentJoined(String tournamentId) =>
      _analytics.logEvent(
        name: 'tournament_joined',
        parameters: {'tournament_id': tournamentId},
      );

  Future<void> setUserProperties(String userId, String level) async {
    await _analytics.setUserId(id: userId);
    await _analytics.setUserProperty(name: 'player_level', value: level);
  }
}
```

---

## 8. Dynamic Links (Referral)

```dart
// Generate referral link
Future<String> createReferralLink(String referralCode) async {
  final dynamicLinkParams = DynamicLinkParameters(
    uriPrefix: 'https://rummyroyale.page.link',
    link: Uri.parse('https://rummyroyale.com/join?ref=$referralCode'),
    androidParameters: const AndroidParameters(
      packageName: 'com.rummyroyale.app',
      minimumVersion: 1,
    ),
    socialMetaTagParameters: SocialMetaTagParameters(
      title: 'Join me on RummyRoyale!',
      description: 'Get ₹50 bonus when you join using my referral code.',
      imageUrl: Uri.parse('https://cdn.rummyroyale.com/share-banner.jpg'),
    ),
  );

  final link = await FirebaseDynamicLinks.instance.buildShortLink(
    dynamicLinkParams,
    shortLinkType: ShortDynamicLinkType.unguessable,
  );

  return link.shortUrl.toString();
}
```
