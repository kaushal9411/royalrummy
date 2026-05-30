import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:lakadiya/core/services/api_service.dart';
import '../models/payment_model.dart';

// Only log in debug builds — payment IDs, amounts, balances must not appear in
// release logcat (accessible via adb by anyone with physical device access).
void _log(String msg) { if (kDebugMode) debugPrint(msg); }

class PaymentRepository {
  final ApiService _apiService;

  PaymentRepository(this._apiService);

  Future<PaymentOrder> initiateAddMoney(double amount) async {
    try {
      _log('[PaymentRepo] Initiating payment for amount: $amount');
      final response = await _apiService.post(
        '/payments/initiate',
        data: {'amount': amount},
      );
      _log('[PaymentRepo] Order created successfully');
      return PaymentOrder.fromJson(response.data);
    } on DioException catch (e) {
      _log('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      _log('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<PaymentVerification> verifyPayment({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    try {
      _log('[PaymentRepo] Verifying payment');
      final response = await _apiService.post(
        '/payments/verify',
        data: {
          'paymentId': paymentId,
          'orderId': orderId,
          'signature': signature,
        },
      );
      _log('[PaymentRepo] Verification successful');
      return PaymentVerification.fromJson(response.data);
    } on DioException catch (e) {
      _log('[PaymentRepo Error] DioException during verify: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      _log('[PaymentRepo Error] Unexpected error during verify: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<WalletBalance> getWalletBalance() async {
    try {
      _log('[PaymentRepo] Getting wallet balance');
      final response = await _apiService.get('/payments/balance');
      return WalletBalance.fromJson(response.data);
    } on DioException catch (e) {
      _log('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      _log('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<List<Transaction>> getTransactionHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      _log('[PaymentRepo] Getting transaction history');
      final response = await _apiService.get(
        '/payments/transactions',
        params: {'limit': limit, 'offset': offset},
      );
      return (response.data as List)
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _log('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      _log('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<List<Transaction>> getWithdrawalRequests({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      _log('[PaymentRepo] Getting withdrawal requests');
      final response = await _apiService.get(
        '/payments/withdrawals',
        params: {'limit': limit, 'offset': offset},
      );
      return (response.data as List)
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _log('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      _log('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<Map<String, dynamic>> requestWithdrawal(double amount) async {
    try {
      _log('[PaymentRepo] Requesting withdrawal');
      final response = await _apiService.post(
        '/payments/withdraw',
        data: {'amount': amount},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _log('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      _log('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  String _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Check your internet connection.';
      case DioExceptionType.sendTimeout:
        return 'Request timeout. Try again.';
      case DioExceptionType.receiveTimeout:
        return 'Server response timeout. Try again.';
      case DioExceptionType.badResponse:
        if (error.response != null) {
          final statusCode = error.response!.statusCode;
          final data = error.response!.data;
          if (data is Map && data.containsKey('message')) {
            return '${data['message']} (Error $statusCode)';
          }
          return 'Server error (Error $statusCode)';
        }
        return 'Server error occurred';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return 'Network error. Check your connection.';
        }
        return 'Unknown error: ${error.message}';
      default:
        return 'Error: ${error.message}';
    }
  }
}
