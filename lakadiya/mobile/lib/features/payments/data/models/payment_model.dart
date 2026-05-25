class PaymentOrder {
  final String orderId;
  final int amount;
  final String currency;
  final String transactionId;
  final int coins;

  PaymentOrder({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.transactionId,
    required this.coins,
  });

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    return PaymentOrder(
      orderId: json['orderId']?.toString() ?? '',
      amount: _toInt(json['amount']),
      currency: json['currency']?.toString() ?? 'INR',
      transactionId: json['transactionId']?.toString() ?? '',
      coins: _toInt(json['coins']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'amount': amount,
      'currency': currency,
      'transactionId': transactionId,
      'coins': coins,
    };
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

class PaymentVerification {
  final bool success;
  final String transactionId;
  final String paymentId;
  final int coins;
  final double amount;
  final String type;
  final String message;

  PaymentVerification({
    required this.success,
    required this.transactionId,
    required this.paymentId,
    required this.coins,
    required this.amount,
    required this.type,
    required this.message,
  });

  factory PaymentVerification.fromJson(Map<String, dynamic> json) {
    print('[PaymentVerification] Parsing JSON: $json');
    
    try {
      final verification = PaymentVerification(
        success: json['success'] == true || json['success'] == 'true',
        transactionId: json['transactionId']?.toString() ?? '',
        paymentId: json['paymentId']?.toString() ?? '',
        coins: _toInt(json['coins']),
        amount: _toDouble(json['amount']),
        type: json['type']?.toString() ?? 'add',
        message: json['message']?.toString() ?? '',
      );
      print('[PaymentVerification] Parsed successfully: $verification');
      return verification;
    } catch (e) {
      print('[PaymentVerification] Error parsing: $e');
      rethrow;
    }
  }

  @override
  String toString() =>
      'PaymentVerification(success: $success, transactionId: $transactionId, paymentId: $paymentId, coins: $coins, amount: $amount, type: $type, message: $message)';

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'transactionId': transactionId,
      'paymentId': paymentId,
      'coins': coins,
      'amount': amount,
      'type': type,
      'message': message,
    };
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

class WalletBalance {
  final int coins;
  final double totalAdded;
  final double totalWithdrawn;
  final double currentBalance;

  WalletBalance({
    required this.coins,
    required this.totalAdded,
    required this.totalWithdrawn,
    required this.currentBalance,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    print('[WalletBalance] Parsing JSON: $json');
    
    try {
      final balance = WalletBalance(
        coins: _toInt(json['coins']),
        totalAdded: _toDouble(json['total_added']),
        totalWithdrawn: _toDouble(json['total_withdrawn']),
        currentBalance: _toDouble(json['current_balance']),
      );
      print('[WalletBalance] Parsed successfully: $balance');
      return balance;
    } catch (e) {
      print('[WalletBalance] Error parsing: $e');
      rethrow;
    }
  }

  @override
  String toString() =>
      'WalletBalance(coins: $coins, totalAdded: $totalAdded, totalWithdrawn: $totalWithdrawn, currentBalance: $currentBalance)';

  Map<String, dynamic> toJson() {
    return {
      'coins': coins,
      'total_added': totalAdded,
      'total_withdrawn': totalWithdrawn,
      'current_balance': currentBalance,
    };
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

class Transaction {
  final String id;
  final double amount;
  final int coins;
  final String type;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Transaction({
    required this.id,
    required this.amount,
    required this.coins,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    print('[Transaction] Parsing JSON: $json');
    
    try {
      DateTime _parseDateTime(dynamic value) {
        if (value == null) return DateTime.now();
        if (value is DateTime) return value;
        if (value is String) {
          try {
            return DateTime.parse(value);
          } catch (e) {
            print('[Transaction] Failed to parse datetime: $value, error: $e');
            return DateTime.now();
          }
        }
        return DateTime.now();
      }

      final transaction = Transaction(
        id: json['id']?.toString() ?? '',
        amount: _toDouble(json['amount']),
        coins: _toInt(json['coins']),
        type: json['type']?.toString() ?? 'add',
        status: json['status']?.toString() ?? 'pending',
        createdAt: _parseDateTime(json['createdAt']),
        updatedAt: _parseDateTime(json['updatedAt']),
      );
      print('[Transaction] Parsed successfully: $transaction');
      return transaction;
    } catch (e) {
      print('[Transaction] Error parsing: $e');
      rethrow;
    }
  }

  @override
  String toString() =>
      'Transaction(id: $id, amount: $amount, coins: $coins, type: $type, status: $status, createdAt: $createdAt, updatedAt: $updatedAt)';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'coins': coins,
      'type': type,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
