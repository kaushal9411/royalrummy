class AppConstants {
  AppConstants._();

  static const String appName = 'Lakadiya';

  // API
  // ── ngrok tunnel for remote testing (forwards to local backend :3001) ──
  // Revert to the LAN IP (http://192.168.1.39:3001) for local-network builds.
  static const String baseUrl = 'https://preheated-mowing-almighty.ngrok-free.dev';
  static const String socketUrl = 'https://preheated-mowing-almighty.ngrok-free.dev';
  static const String apiVersion = '/api';

  // Storage keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String themeKey = 'theme_mode';

  // Game constants
  static const int totalRounds = 5;
  static const int totalPlayers = 4;
  static const int cardsPerPlayer = 13;
  static const String trumpSuit = 'spades';
  static const int botDelayMs = 1200;

  // Suits
  static const List<String> suits = ['spades', 'hearts', 'diamonds', 'clubs'];
  static const Map<String, String> suitSymbols = {
    'spades':   '♠',
    'hearts':   '♥',
    'diamonds': '♦',
    'clubs':    '♣',
  };
  static const List<String> ranks = [
    '2','3','4','5','6','7','8','9','10','J','Q','K','A'
  ];

  // Durations
  static const Duration cardAnimDuration = Duration(milliseconds: 300);
  static const Duration turnTimerDuration = Duration(seconds: 30);
}
