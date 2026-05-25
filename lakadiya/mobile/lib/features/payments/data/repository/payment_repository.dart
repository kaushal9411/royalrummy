import 'package:dio/dio.dart';
import 'dart:io';
import 'package:lakadiya/core/services/api_service.dart';
import '../models/payment_model.dart';

class PaymentRepository {
  final ApiService _apiService;

  PaymentRepository(this._apiService);

  Future<PaymentOrder> initiateAddMoney(double amount) async {
    try {
      print('[PaymentRepo] Initiating payment for amount: $amount');
      final response = await _apiService.post(
        '/payments/initiate',
        data: {'amount': amount},
      );
      print('[PaymentRepo] Response data: ${response.data}');
      return PaymentOrder.fromJson(response.data);
    } on DioException catch (e) {
      print('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      print('[PaymentRepo Error] Response: ${e.response?.data}');
      throw _handleDioError(e);
    } catch (e) {
      print('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<PaymentVerification> verifyPayment({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    try {
      print('[PaymentRepo] Verifying payment - PaymentID: $paymentId, OrderID: $orderId');
      final response = await _apiService.post(
        '/payments/verify',
        data: {
          'paymentId': paymentId,
          'orderId': orderId,
          'signature': signature,
        },
      );
      print('[PaymentRepo] Verification response data: ${response.data}');
      final verification = PaymentVerification.fromJson(response.data);
      print('[PaymentRepo] Verification object: $verification');
      return verification;
    } on DioException catch (e) {
      print('[PaymentRepo Error] DioException during verify: ${e.type} - ${e.message}');
      print('[PaymentRepo Error] Response: ${e.response?.data}');
      throw _handleDioError(e);
    } catch (e) {
      print('[PaymentRepo Error] Unexpected error during verify: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<WalletBalance> getWalletBalance() async {
    try {
      print('[PaymentRepo] Getting wallet balance');
      final response = await _apiService.get('/payments/balance');
      print('[PaymentRepo] Balance response data: ${response.data}');
      return WalletBalance.fromJson(response.data);
    } on DioException catch (e) {
      print('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      print('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<List<Transaction>> getTransactionHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print('[PaymentRepo] Getting transaction history - limit: $limit, offset: $offset');
      final response = await _apiService.get(
        '/payments/transactions',
        params: {
          'limit': limit,
          'offset': offset,
        },
      );
      print('[PaymentRepo] History response data: ${response.data}');
      return (response.data as List)
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      print('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      print('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<List<Transaction>> getWithdrawalRequests({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print('[PaymentRepo] Getting withdrawal requests - limit: $limit, offset: $offset');
      final response = await _apiService.get(
        '/payments/withdrawals',
        params: {
          'limit': limit,
          'offset': offset,
        },
      );
      print('[PaymentRepo] Withdrawals response data: ${response.data}');
      return (response.data as List)
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      print('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      print('[PaymentRepo Error] Unexpected error: $e');
      throw 'Unexpected error: ${e.toString()}';
    }
  }

  Future<Map<String, dynamic>> requestWithdrawal(double amount) async {
    try {
      print('[PaymentRepo] Requesting withdrawal for amount: $amount');
      final response = await _apiService.post(
        '/payments/withdraw',
        data: {'amount': amount},
      );
      print('[PaymentRepo] Withdrawal response data: ${response.data}');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      print('[PaymentRepo Error] DioException: ${e.type} - ${e.message}');
      throw _handleDioError(e);
    } catch (e) {
      print('[PaymentRepo Error] Unexpected error: $e');
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
