import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/lobby/presentation/pages/lobby_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/lobby/presentation/pages/room_page.dart';
import '../../features/game/presentation/pages/game_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../features/profile/presentation/pages/age_verification_page.dart';
import '../../features/profile/presentation/pages/kyc_page.dart';
import '../../features/profile/presentation/pages/responsible_gaming_page.dart';
import '../../features/profile/presentation/pages/notification_settings_page.dart';
import '../../features/profile/presentation/pages/data_safety_page.dart';
import '../../features/legal/presentation/pages/legal_page.dart';
import '../../features/leaderboard/presentation/pages/leaderboard_page.dart';
import '../../features/payments/presentation/bloc/payment_bloc.dart';
import '../../features/payments/presentation/screens/wallet_screen.dart';
import '../../features/payments/presentation/screens/add_money_screen.dart';
import '../../features/payments/presentation/screens/withdraw_screen.dart';
import '../../features/profile/presentation/pages/device_token_page.dart';
import '../../features/social/presentation/pages/social_page.dart';
import '../../features/social/presentation/pages/dm_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

GoRouter createRouter(AuthBloc authBloc, PaymentBloc paymentBloc) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/splash',
  redirect: (context, state) {
    if (state.matchedLocation == '/splash') return null;

    // Legal pages are public — accessible without auth (linked from login ToS checkbox)
    const publicRoutes = {'/terms', '/privacy-policy', '/data-safety'};
    if (publicRoutes.contains(state.matchedLocation)) return null;

    final isAuth = authBloc.state is AuthAuthenticated;
    final isAuthRoute = state.matchedLocation.startsWith('/login');

    if (!isAuth && !isAuthRoute) return '/login';
    if (isAuth && isAuthRoute) return '/lobby';
    return null;
  },
  refreshListenable: GoRouterRefreshStream(authBloc.stream),
  routes: [
    GoRoute(path: '/splash',   builder: (_, __) => const SplashPage()),
    GoRoute(path: '/login',    builder: (_, __) => const LoginPage()),
    GoRoute(path: '/register', redirect: (_, __) => '/login'),
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

    // Payment Routes — share the global PaymentBloc so balance stays in sync
    GoRoute(
      path: '/wallet',
      builder: (_, __) => BlocProvider.value(
        value: paymentBloc,
        child: const WalletScreen(),
      ),
    ),
    GoRoute(
      path: '/add-money',
      builder: (_, __) => BlocProvider.value(
        value: paymentBloc,
        child: const AddMoneyScreen(),
      ),
    ),
    GoRoute(
      path: '/withdraw',
      builder: (_, __) => BlocProvider.value(
        value: paymentBloc,
        child: const WithdrawScreen(),
      ),
    ),
    GoRoute(
      path: '/device-token',
      builder: (_, __) => const DeviceTokenPage(),
    ),
    GoRoute(
      path: '/social',
      builder: (_, __) => const SocialPage(),
    ),
    GoRoute(
      path: '/dm/:userId',
      builder: (_, state) => DmScreen(
        userId: state.pathParameters['userId']!,
        username: state.extra as String? ?? 'Player',
      ),
    ),

    // ── Compliance & Settings ──────────────────────────────────────────────
    GoRoute(path: '/settings',              builder: (_, __) => const SettingsPage()),
    GoRoute(path: '/age-verification',      builder: (_, __) => const AgeVerificationPage()),
    GoRoute(path: '/kyc',                   builder: (_, __) => const KycPage()),
    GoRoute(path: '/responsible-gaming',    builder: (_, __) => const ResponsibleGamingPage()),
    GoRoute(path: '/notification-settings', builder: (_, __) => const NotificationSettingsPage()),
    GoRoute(path: '/data-safety',           builder: (_, __) => const DataSafetyPage()),
    GoRoute(
      path: '/privacy-policy',
      builder: (_, __) => const LegalPage(
        title: 'Privacy Policy',
        assetPath: 'assets/legal/privacy_policy.html',
      ),
    ),
    GoRoute(
      path: '/terms',
      builder: (_, __) => const LegalPage(
        title: 'Terms of Service',
        assetPath: 'assets/legal/terms_of_service.html',
      ),
    ),
  ],
);

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
