import 'package:dio/dio.dart';
import '../../../core/services/api_service.dart';

class RoomRepository {
  final ApiService _api;
  RoomRepository({ApiService? api}) : _api = api ?? ApiService();

  // Throws with the backend's message string for any 4xx response.
  void _assertOk(Response res) {
    if ((res.statusCode ?? 0) >= 400) {
      final msg = (res.data as Map?)?['message'] as String?
          ?? 'Request failed (${res.statusCode})';
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> createRoom({bool isPrivate = false, double betAmount = 0}) async {
    final res = await _api.post('/rooms', data: {'isPrivate': isPrivate, 'betAmount': betAmount});
    _assertOk(res);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> joinRoom(String code) async {
    final res = await _api.post('/rooms/join/$code');
    _assertOk(res);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getRoomDetails(String roomId) async {
    final res = await _api.get('/rooms/$roomId');
    _assertOk(res);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> leaveRoom(String roomId) =>
      _api.delete('/rooms/$roomId/leave');

  Future<Map<String, dynamic>> addBot(String roomId, String level) async {
    final res = await _api.post('/rooms/$roomId/bot', data: {'level': level});
    _assertOk(res);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> getPublicRooms() async {
    final res = await _api.get('/rooms/public');
    _assertOk(res);
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> resetBet(String roomId) async {
    final res = await _api.patch('/rooms/$roomId/reset-bet');
    _assertOk(res);
  }
}
