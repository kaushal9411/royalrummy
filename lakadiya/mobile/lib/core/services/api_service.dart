import 'package:dio/dio.dart';
import '../constants/app_constants.dart';
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: '${AppConstants.baseUrl}${AppConstants.apiVersion}',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      validateStatus: (status) => status != null && status < 500,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = StorageService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        print('[API] ${options.method} ${options.path}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        print('[API] Response: ${response.statusCode} - ${response.data}');
        handler.next(response);
      },
      onError: (error, handler) {
        print('[API] Error: ${error.type} - ${error.message}');
        print('[API] Response: ${error.response?.data}');
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  Future<Response> get(String path, {Map<String, dynamic>? params}) {
    return _dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) {
    return _dio.patch(path, data: data);
  }

  Future<Response> delete(String path) {
    return _dio.delete(path);
  }
}
