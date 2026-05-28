import '../../../../core/services/api_service.dart';

class NotificationRepository {
  final ApiService _apiService;

  NotificationRepository(this._apiService);

  /// Store device FCM token on backend after login/signup
  Future<bool> storeDeviceToken(String fcmToken, {String deviceType = 'android'}) async {
    try {
      final response = await _apiService.post(
        '/notifications/device-token',
        data: {
          'fcmToken': fcmToken,
          'deviceType': deviceType,
        },
      );
      
      print('[Notification] Device token stored: ${response.data['success']}');
      return response.data['success'] == true;
    } catch (e) {
      print('[Notification] Error storing device token: $e');
      return false;
    }
  }

  /// Send test OTP notification (for development)
  Future<bool> sendTestOtp(String otp) async {
    try {
      final response = await _apiService.post(
        '/notifications/send-test-otp',
        data: { 'otp': otp },
      );
      
      print('[Notification] Test OTP sent: ${response.data['success']}');
      return response.data['success'] == true;
    } catch (e) {
      print('[Notification] Error sending test OTP: $e');
      return false;
    }
  }

  /// Get notification logs
  Future<List<Map<String, dynamic>>> getNotificationLogs({int limit = 20}) async {
    try {
      final response = await _apiService.get(
        '/notifications/logs',
        params: { 'limit': limit.toString() },
      );
      
      final logs = List<Map<String, dynamic>>.from(response.data['logs'] ?? []);
      print('[Notification] Fetched ${logs.length} notification logs');
      return logs;
    } catch (e) {
      print('[Notification] Error fetching logs: $e');
      return [];
    }
  }
}
