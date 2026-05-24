import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/user_entity.dart';

// ─── Events ───────────────────────────────────────────────────────────────────

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthRegisterRequested extends AuthEvent {
  final String username, email, password;
  AuthRegisterRequested(this.username, this.email, this.password);
  @override List<Object?> get props => [username, email, password];
}

class AuthLoginRequested extends AuthEvent {
  final String email, password;
  AuthLoginRequested(this.email, this.password);
  @override List<Object?> get props => [email, password];
}

class AuthGuestRequested extends AuthEvent {}

class AuthGoogleRequested extends AuthEvent {
  final String googleId, email, name;
  final String? avatarUrl;
  AuthGoogleRequested(this.googleId, this.email, this.name, {this.avatarUrl});
  @override List<Object?> get props => [googleId, email, name];
}

class AuthLogoutRequested extends AuthEvent {}

// ─── States ───────────────────────────────────────────────────────────────────

abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserEntity user;
  AuthAuthenticated(this.user);
  @override List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
  @override List<Object?> get props => [message];
}

// ─── BLoC ─────────────────────────────────────────────────────────────────────

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repo;

  AuthBloc({required AuthRepository repo})
      : _repo = repo,
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheck);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthLoginRequested>(_onLogin);
    on<AuthGuestRequested>(_onGuest);
    on<AuthGoogleRequested>(_onGoogle);
    on<AuthLogoutRequested>(_onLogout);
  }

  void _onCheck(AuthCheckRequested event, Emitter<AuthState> emit) {
    final user = _repo.getCachedUser();
    if (user != null && _repo.isLoggedIn()) {
      emit(AuthAuthenticated(user));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onRegister(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.register(
        username: event.username,
        email:    event.email,
        password: event.password,
      );
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(_parseError(e)));
    }
  }

  Future<void> _onLogin(AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.login(email: event.email, password: event.password);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(_parseError(e)));
    }
  }

  Future<void> _onGuest(AuthGuestRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.guestLogin();
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(_parseError(e)));
    }
  }

  Future<void> _onGoogle(AuthGoogleRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.googleLogin(
        googleId:  event.googleId,
        email:     event.email,
        name:      event.name,
        avatarUrl: event.avatarUrl,
      );
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(_parseError(e)));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await _repo.logout();
    emit(AuthUnauthenticated());
  }

  String _parseError(dynamic e) {
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return 'Something went wrong';
  }
}
