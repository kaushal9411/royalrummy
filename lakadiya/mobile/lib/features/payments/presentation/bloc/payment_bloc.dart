import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../../core/services/socket_service.dart';
import '../../data/models/payment_model.dart';
import '../../data/repository/payment_repository.dart';

// Events
abstract class PaymentEvent extends Equatable {
  const PaymentEvent();
  @override
  List<Object> get props => [];
}

class InitiatePaymentEvent extends PaymentEvent {
  final double amount;
  const InitiatePaymentEvent(this.amount);
  @override
  List<Object> get props => [amount];
}

class VerifyPaymentEvent extends PaymentEvent {
  final String paymentId;
  final String orderId;
  final String signature;
  const VerifyPaymentEvent({required this.paymentId, required this.orderId, required this.signature});
  @override
  List<Object> get props => [paymentId, orderId, signature];
}

class FetchWalletBalanceEvent extends PaymentEvent {
  const FetchWalletBalanceEvent();
}

class FetchTransactionHistoryEvent extends PaymentEvent {
  final int limit;
  final int offset;
  const FetchTransactionHistoryEvent({this.limit = 20, this.offset = 0});
  @override
  List<Object> get props => [limit, offset];
}

class FetchWithdrawalRequestsEvent extends PaymentEvent {
  final int limit;
  final int offset;
  const FetchWithdrawalRequestsEvent({this.limit = 20, this.offset = 0});
  @override
  List<Object> get props => [limit, offset];
}

class RequestWithdrawalEvent extends PaymentEvent {
  final double amount;
  const RequestWithdrawalEvent(this.amount);
  @override
  List<Object> get props => [amount];
}

// States
abstract class PaymentState extends Equatable {
  const PaymentState();
  @override
  List<Object?> get props => [];
}

class PaymentInitial extends PaymentState {
  const PaymentInitial();
}

class PaymentLoading extends PaymentState {
  const PaymentLoading();
}

class PaymentOrderCreated extends PaymentState {
  final PaymentOrder order;
  const PaymentOrderCreated(this.order);
  @override
  List<Object> get props => [order];
}

class PaymentVerified extends PaymentState {
  final PaymentVerification verification;
  const PaymentVerified(this.verification);
  @override
  List<Object> get props => [verification];
}

class WalletBalanceFetched extends PaymentState {
  final WalletBalance balance;
  const WalletBalanceFetched(this.balance);
  @override
  List<Object> get props => [balance];
}

class TransactionHistoryFetched extends PaymentState {
  final List<Transaction> transactions;
  const TransactionHistoryFetched(this.transactions);
  @override
  List<Object> get props => [transactions];
}

class WithdrawalRequestsFetched extends PaymentState {
  final List<Transaction> withdrawals;
  const WithdrawalRequestsFetched(this.withdrawals);
  @override
  List<Object> get props => [withdrawals];
}

class WithdrawalRequested extends PaymentState {
  final String message;
  const WithdrawalRequested(this.message);
  @override
  List<Object> get props => [message];
}

class PaymentError extends PaymentState {
  final String message;
  const PaymentError(this.message);
  @override
  List<Object> get props => [message];
}

// BLoC
class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  final PaymentRepository repository;
  final SocketService _socket;

  WalletBalance? _cachedBalance;

  // Cached getter so widgets can read latest balance without subscribing to state
  WalletBalance? get cachedBalance => _cachedBalance;

  PaymentBloc(this.repository, this._socket) : super(const PaymentInitial()) {
    on<InitiatePaymentEvent>(_onInitiatePayment);
    on<VerifyPaymentEvent>(_onVerifyPayment);
    on<FetchWalletBalanceEvent>(_onFetchWalletBalance);
    on<FetchTransactionHistoryEvent>(_onFetchTransactionHistory);
    on<FetchWithdrawalRequestsEvent>(_onFetchWithdrawalRequests);
    on<RequestWithdrawalEvent>(_onRequestWithdrawal);

    // Auto-refresh whenever the server signals a balance change
    _socket.on('balance_updated', (_) => add(const FetchWalletBalanceEvent()));
  }

  @override
  Future<void> close() {
    _socket.off('balance_updated');
    return super.close();
  }

  Future<void> _onInitiatePayment(
    InitiatePaymentEvent event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentLoading());
    try {
      final order = await repository.initiateAddMoney(event.amount);
      emit(PaymentOrderCreated(order));
    } catch (e) {
      emit(PaymentError(e.toString()));
    }
  }

  Future<void> _onVerifyPayment(
    VerifyPaymentEvent event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentLoading());
    try {
      final verification = await repository.verifyPayment(
        paymentId: event.paymentId,
        orderId: event.orderId,
        signature: event.signature,
      );
      emit(PaymentVerified(verification));
      // Refresh balance immediately after successful payment
      add(const FetchWalletBalanceEvent());
    } catch (e) {
      emit(PaymentError(e.toString()));
    }
  }

  Future<void> _onFetchWalletBalance(
    FetchWalletBalanceEvent event,
    Emitter<PaymentState> emit,
  ) async {
    // Show loading only on first fetch — subsequent refreshes update silently
    if (_cachedBalance == null) emit(const PaymentLoading());
    try {
      final balance = await repository.getWalletBalance();
      _cachedBalance = balance;
      emit(WalletBalanceFetched(balance));
    } catch (e) {
      // Only surface error if we have nothing cached yet
      if (_cachedBalance == null) emit(PaymentError(e.toString()));
    }
  }

  Future<void> _onFetchTransactionHistory(
    FetchTransactionHistoryEvent event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentLoading());
    try {
      final transactions = await repository.getTransactionHistory(
        limit: event.limit,
        offset: event.offset,
      );
      emit(TransactionHistoryFetched(transactions));
    } catch (e) {
      emit(PaymentError(e.toString()));
    }
  }

  Future<void> _onFetchWithdrawalRequests(
    FetchWithdrawalRequestsEvent event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentLoading());
    try {
      final withdrawals = await repository.getWithdrawalRequests(
        limit: event.limit,
        offset: event.offset,
      );
      emit(WithdrawalRequestsFetched(withdrawals));
    } catch (e) {
      emit(PaymentError(e.toString()));
    }
  }

  Future<void> _onRequestWithdrawal(
    RequestWithdrawalEvent event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentLoading());
    try {
      final result = await repository.requestWithdrawal(event.amount);
      emit(WithdrawalRequested(result['message']));
      // Refresh balance and withdrawal list after request
      add(const FetchWalletBalanceEvent());
      final withdrawals = await repository.getWithdrawalRequests();
      emit(WithdrawalRequestsFetched(withdrawals));
    } catch (e) {
      emit(PaymentError(e.toString()));
    }
  }
}
