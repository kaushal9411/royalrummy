import 'api_service.dart';

class CredentialsService {
  static final CredentialsService _instance = CredentialsService._();
  static CredentialsService get instance => _instance;
  CredentialsService._();

  String? _razorpayKeyId;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final res = await ApiService().get('/credentials/app-keys');
      _razorpayKeyId = res.data['razorpay_key_id'] as String?;
      _loaded = true;
    } catch (_) {
      // Fall back to empty — payment will fail with a clear Razorpay error
    }
  }

  String get razorpayKeyId {
    assert(_razorpayKeyId != null && _razorpayKeyId!.isNotEmpty,
        'Razorpay key not loaded. Call CredentialsService.instance.load() after login.');
    return _razorpayKeyId ?? '';
  }

  bool get isLoaded => _loaded && (_razorpayKeyId?.isNotEmpty ?? false);
}
