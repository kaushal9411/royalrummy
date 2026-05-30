import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';

class StorageService {
  static late Box _box;

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> init() async {
    await Hive.initFlutter();

    // Load (or generate) the AES-256 encryption key from the platform secure store.
    // On Android this uses EncryptedSharedPreferences (hardware-backed Keystore).
    // On iOS this uses the Keychain. The key never leaves the secure enclave.
    final encryptionKey = await _loadOrCreateHiveKey();

    _box = await Hive.openBox(
      'lakadiya_prefs',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Future<List<int>> _loadOrCreateHiveKey() async {
    const keyName = 'hive_encryption_key';
    final stored = await _secureStorage.read(key: keyName);
    if (stored != null) {
      return base64Decode(stored);
    }
    // First run — generate a cryptographically random 32-byte (256-bit) key
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _secureStorage.write(key: keyName, value: base64Encode(key));
    return key;
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
