import '../../../core/services/api_service.dart';

class SocialRepository {
  final ApiService _api;
  SocialRepository({ApiService? api}) : _api = api ?? ApiService();

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final res = await _api.get('/users/search', params: {'q': q});
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getFriends() async {
    final res = await _api.get('/users/me/friends');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> sendFriendRequest(String userId) =>
      _api.post('/users/friends/$userId');

  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final res = await _api.get('/users/me/friend-requests');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> acceptFriendRequest(String userId) =>
      _api.post('/users/friends/$userId/accept');

  Future<void> declineFriendRequest(String userId) =>
      _api.post('/users/friends/$userId/decline');

  Future<List<Map<String, dynamic>>> getConversationList() async {
    final res = await _api.get('/messages');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getConversation(String userId, {int? beforeId}) async {
    final params = <String, String>{};
    if (beforeId != null) params['before'] = beforeId.toString();
    final res = await _api.get('/messages/$userId', params: params);
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> markRead(String userId) => _api.patch('/messages/$userId/read');

  Future<int> getUnreadCount() async {
    final res = await _api.get('/messages/unread');
    return (res.data as Map)['count'] as int? ?? 0;
  }
}
