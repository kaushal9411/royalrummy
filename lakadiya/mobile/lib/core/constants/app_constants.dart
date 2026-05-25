class AppConstants {
  AppConstants._();

  static const String appName = 'Lakadiya';

  // API
  static const String baseUrl = 'http://172.20.10.2:3001';
  static const String socketUrl = 'http://172.20.10.2:3001';
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
