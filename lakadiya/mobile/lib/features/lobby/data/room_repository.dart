import '../../../core/services/api_service.dart';

class RoomRepository {
  final ApiService _api;
  RoomRepository({ApiService? api}) : _api = api ?? ApiService();

  Future<Map<String, dynamic>> createRoom({bool isPrivate = false}) async {
    final res = await _api.post('/rooms', data: {'isPrivate': isPrivate});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> joinRoom(String code) async {
    final res = await _api.post('/rooms/join/$code');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getRoomDetails(String roomId) async {
    final res = await _api.get('/rooms/$roomId');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> leaveRoom(String roomId) =>
      _api.delete('/rooms/$roomId/leave');

  Future<Map<String, dynamic>> addBot(String roomId, String level) async {
    final res = await _api.post('/rooms/$roomId/bot', data: {'level': level});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> getPublicRooms() async {
    final res = await _api.get('/rooms/public');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
