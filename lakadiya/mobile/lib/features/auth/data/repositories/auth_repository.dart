import '../../../../core/services/api_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/user_entity.dart';

class AuthRepository {
  final ApiService _api;
  AuthRepository({ApiService? api}) : _api = api ?? ApiService();

  Future<void> sendOtp({required String mobile}) async {
    final fcmToken = FcmService.instance.token;
    await _api.post('/auth/otp/send', data: {
      'mobile': mobile,
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// Verifies OTP — logs in existing user OR auto-creates account if new.
  Future<UserEntity> verifyAndLogin({
    required String mobile,
    required String otp,
  }) async {
    final res = await _api.post('/auth/otp/verify', data: {
      'mobile': mobile,
      'otp':    otp,
    });
    return _saveAndReturn(res.data);
  }

  Future<UserEntity> guestLogin({required String mobile}) async {
    final res = await _api.post('/auth/guest', data: {'mobile': mobile});
    return _saveAndReturn(res.data);
  }

  Future<UserEntity> googleLogin({
    required String googleId,
    required String email,
    required String name,
    String? avatarUrl,
  }) async {
    final res = await _api.post('/auth/google', data: {
      'googleId':  googleId,
      'email':     email,
      'name':      name,
      'avatarUrl': avatarUrl,
    });
    return _saveAndReturn(res.data);
  }

  Future<void> logout() async => StorageService.clear();

  UserEntity? getCachedUser() {
    final data = StorageService.getUser();
    return data != null ? UserEntity.fromJson(data) : null;
  }

  bool isLoggedIn() => StorageService.getToken() != null;

  Future<UserEntity> _saveAndReturn(dynamic data) async {
    final token = data['token'] as String;
    final user  = UserEntity.fromJson(data['user'] as Map<String, dynamic>);
    await StorageService.saveToken(token);
    await StorageService.saveUser(user.toJson());
    return user;
  }
}
