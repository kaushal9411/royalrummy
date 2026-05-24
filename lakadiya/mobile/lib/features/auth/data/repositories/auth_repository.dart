import '../../../../core/services/api_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/user_entity.dart';

class AuthRepository {
  final ApiService _api;
  AuthRepository({ApiService? api}) : _api = api ?? ApiService();

  Future<UserEntity> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _api.post('/auth/register', data: {
      'username': username,
      'email':    email,
      'password': password,
    });
    final token = res.data['token'] as String;
    final user  = UserEntity.fromJson(res.data['user'] as Map<String, dynamic>);
    await StorageService.saveToken(token);
    await StorageService.saveUser(user.toJson());
    return user;
  }

  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.post('/auth/login', data: {
      'email':    email,
      'password': password,
    });
    final token = res.data['token'] as String;
    final user  = UserEntity.fromJson(res.data['user'] as Map<String, dynamic>);
    await StorageService.saveToken(token);
    await StorageService.saveUser(user.toJson());
    return user;
  }

  Future<UserEntity> guestLogin() async {
    final res  = await _api.post('/auth/guest');
    final token = res.data['token'] as String;
    final user  = UserEntity.fromJson(res.data['user'] as Map<String, dynamic>);
    await StorageService.saveToken(token);
    await StorageService.saveUser(user.toJson());
    return user;
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
    final token = res.data['token'] as String;
    final user  = UserEntity.fromJson(res.data['user'] as Map<String, dynamic>);
    await StorageService.saveToken(token);
    await StorageService.saveUser(user.toJson());
    return user;
  }

  Future<void> logout() async {
    await StorageService.clear();
  }

  UserEntity? getCachedUser() {
    final data = StorageService.getUser();
    return data != null ? UserEntity.fromJson(data) : null;
  }

  bool isLoggedIn() => StorageService.getToken() != null;
}
