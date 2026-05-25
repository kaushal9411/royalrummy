import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/api_service.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/lobby/presentation/pages/lobby_page.dart';
import '../../features/lobby/presentation/pages/room_page.dart';
import '../../features/game/presentation/pages/game_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/leaderboard/presentation/pages/leaderboard_page.dart';
import '../../features/payments/presentation/bloc/payment_bloc.dart';
import '../../features/payments/data/repository/payment_repository.dart';
import '../../features/payments/presentation/screens/wallet_screen.dart';
import '../../features/payments/presentation/screens/add_money_screen.dart';
import '../../features/payments/presentation/screens/withdraw_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

GoRouter createRouter(AuthBloc authBloc) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/lobby',
  redirect: (context, state) {
    final isAuth = authBloc.state is AuthAuthenticated;
    final isAuthRoute = state.matchedLocation.startsWith('/login') ||
                        state.matchedLocation.startsWith('/register');

    if (!isAuth && !isAuthRoute) return '/login';
    if (isAuth && isAuthRoute) return '/lobby';
    return null;
  },
  refreshListenable: GoRouterRefreshStream(authBloc.stream),
  routes: [
    GoRoute(path: '/login',    builder: (_, __) => const LoginPage()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
    GoRoute(path: '/lobby',    builder: (_, __) => const LobbyPage()),
    GoRoute(
      path: '/room/:roomId',
      builder: (_, state) => RoomPage(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(
      path: '/game/:roomId',
      builder: (_, state) => GamePage(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(path: '/profile',     builder: (_, __) => const ProfilePage()),
    GoRoute(path: '/leaderboard', builder: (_, __) => const LeaderboardPage()),

    // Payment Routes
    GoRoute(
      path: '/wallet',
      builder: (_, __) => BlocProvider(
        create: (_) => PaymentBloc(PaymentRepository(ApiService())),
        child: const WalletScreen(),
      ),
    ),
    GoRoute(
      path: '/add-money',
      builder: (_, __) => BlocProvider(
        create: (_) => PaymentBloc(PaymentRepository(ApiService())),
        child: const AddMoneyScreen(),
      ),
    ),
    GoRoute(
      path: '/withdraw',
      builder: (_, __) => BlocProvider(
        create: (_) => PaymentBloc(PaymentRepository(ApiService())),
        child: const WithdrawScreen(),
      ),
    ),
  ],
);

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
