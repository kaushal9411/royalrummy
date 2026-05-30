import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';

class StorageService {
  static late Box _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('lakadiya_prefs');
  }

  static Future<void> saveToken(String token) =>
      _box.put(AppConstants.tokenKey, token);

  static String? getToken() => _box.get(AppConstants.tokenKey);

  static Future<void> saveUser(Map<String, dynamic> user) =>
      _box.put(AppConstants.userKey, user);

  static Map<String, dynamic>? getUser() {
    final raw = _box.get(AppConstants.userKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  static Future<void> clear() => _box.clear();

  static bool getBool(String key, {bool defaultValue = false}) =>
      _box.get(key, defaultValue: defaultValue) as bool;

  static Future<void> setBool(String key, bool value) => _box.put(key, value);

  static Future<void> saveTheme(String mode) =>
      _box.put(AppConstants.themeKey, mode);

  static String getTheme() => _box.get(AppConstants.themeKey, defaultValue: 'dark');
}
