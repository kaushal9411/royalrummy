import 'package:flutter/foundation.dart';
import 'api_service.dart';

class AppSettings {
  final bool maintenanceMode;
  final bool registrationEnabled;
  final double minWithdrawal;
  final double maxWithdrawal;
  final double welcomeBonus;
  final double maxBetAmount;
  final double platformFeePct;
  final double paymentGatewayFeePct;

  const AppSettings({
    required this.maintenanceMode,
    required this.registrationEnabled,
    required this.minWithdrawal,
    required this.maxWithdrawal,
    required this.welcomeBonus,
    required this.maxBetAmount,
    required this.platformFeePct,
    required this.paymentGatewayFeePct,
  });

  factory AppSettings.defaults() => const AppSettings(
    maintenanceMode: false,
    registrationEnabled: true,
    minWithdrawal: 100,
    maxWithdrawal: 10000,
    welcomeBonus: 50,
    maxBetAmount: 100,
    platformFeePct: 0,
    paymentGatewayFeePct: 2,
  );
}

class AppSettingsService {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  final _notifier = ValueNotifier<AppSettings>(AppSettings.defaults());
  ValueNotifier<AppSettings> get notifier => _notifier;
  AppSettings get current => _notifier.value;

  Future<void> fetchFromServer() async {
    try {
      final res = await ApiService().get('/settings/public');
      final data = res.data as Map<String, dynamic>;
      updateFromData(data);
    } catch (_) {}
  }

  void updateFromData(Map<String, dynamic> data) {
    final s = _notifier.value;
    _notifier.value = AppSettings(
      maintenanceMode:     _parseBool(data['maintenance_mode'],     s.maintenanceMode),
      registrationEnabled: _parseBool(data['registration_enabled'], s.registrationEnabled),
      minWithdrawal:       _parseDouble(data['min_withdrawal'],      s.minWithdrawal),
      maxWithdrawal:       _parseDouble(data['max_withdrawal'],      s.maxWithdrawal),
      welcomeBonus:        _parseDouble(data['welcome_bonus'],       s.welcomeBonus),
      maxBetAmount:           _parseDouble(data['max_bet_amount'],           s.maxBetAmount),
      platformFeePct:         _parseDouble(data['platform_fee_pct'],        s.platformFeePct),
      paymentGatewayFeePct:   _parseDouble(data['payment_gateway_fee_pct'], s.paymentGatewayFeePct),
    );
    debugPrint('[AppSettings] Updated: maintenance=${_notifier.value.maintenanceMode}, maxBet=${_notifier.value.maxBetAmount}');
  }

  static bool _parseBool(dynamic v, bool fallback) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is String) return v == 'true' || v == '1';
    return fallback;
  }

  static double _parseDouble(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
}
