import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/user_entity.dart';

// ─── Events ───────────────────────────────────────────────────────────────────

abstract class AuthEvent extends Equatable {
  @override List<Object?> get props => [];
}

class AuthCheckRequested    extends AuthEvent {}
class AuthLogoutRequested   extends AuthEvent {}

class AuthOtpSendRequested extends AuthEvent {
  final String mobile;
  AuthOtpSendRequested(this.mobile);
  @override List<Object?> get props => [mobile];
}

class AuthOtpVerifyRequested extends AuthEvent {
  final String mobile, otp;
  AuthOtpVerifyRequested(this.mobile, this.otp);
  @override List<Object?> get props => [mobile, otp];
}

class AuthGuestRequested extends AuthEvent {
  final String mobile;
  AuthGuestRequested(this.mobile);
  @override List<Object?> get props => [mobile];
}

class AuthGoogleRequested extends AuthEvent {
  final String googleId, email, name;
  final String? avatarUrl;
  AuthGoogleRequested(this.googleId, this.email, this.name, {this.avatarUrl});
  @override List<Object?> get props => [googleId, email, name];
}

// ─── States ───────────────────────────────────────────────────────────────────

abstract class AuthState extends Equatable {
  @override List<Object?> get props => [];
}

class AuthInitial        extends AuthState {}
class AuthLoading        extends AuthState {}
class AuthUnauthenticated extends AuthState {}

class OtpSent extends AuthState {
  final String mobile;
  OtpSent(this.mobile);
  @override List<Object?> get props => [mobile];
}

class AuthAuthenticated extends AuthState {
  final UserEntity user;
  AuthAuthenticated(this.user);
  @override List<Object?> get props => [user];
}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
  @override List<Object?> get props => [message];
}

// ─── BLoC ─────────────────────────────────────────────────────────────────────

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repo;

  AuthBloc({required AuthRepository repo})
      : _repo = repo, super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheck);
    on<AuthOtpSendRequested>(_onOtpSend);
    on<AuthOtpVerifyRequested>(_onOtpVerify);
    on<AuthGuestRequested>(_onGuest);
    on<AuthGoogleRequested>(_onGoogle);
    on<AuthLogoutRequested>(_onLogout);
  }

  void _onCheck(AuthCheckRequested _, Emitter<AuthState> emit) {
    final user = _repo.getCachedUser();
    if (user != null && _repo.isLoggedIn()) {
      emit(AuthAuthenticated(user));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onOtpSend(AuthOtpSendRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _repo.sendOtp(mobile: event.mobile);
      emit(OtpSent(event.mobile));
    } catch (e) { emit(AuthError(_err(e))); }
  }

  Future<void> _onOtpVerify(AuthOtpVerifyRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.verifyAndLogin(mobile: event.mobile, otp: event.otp);
      emit(AuthAuthenticated(user));
    } catch (e) { emit(AuthError(_err(e))); }
  }

  Future<void> _onGuest(AuthGuestRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.guestLogin(mobile: event.mobile);
      emit(AuthAuthenticated(user));
    } catch (e) { emit(AuthError(_err(e))); }
  }

  Future<void> _onGoogle(AuthGoogleRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.googleLogin(
        googleId: event.googleId, email: event.email,
        name: event.name, avatarUrl: event.avatarUrl,
      );
      emit(AuthAuthenticated(user));
    } catch (e) { emit(AuthError(_err(e))); }
  }

  Future<void> _onLogout(AuthLogoutRequested _, Emitter<AuthState> emit) async {
    await _repo.logout();
    emit(AuthUnauthenticated());
  }

  String _err(dynamic e) {
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return 'Something went wrong';
  }
}
