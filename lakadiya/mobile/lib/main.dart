import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/router/app_router.dart';
import 'core/services/api_service.dart';
import 'core/services/app_settings_service.dart';
import 'core/services/credentials_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/socket_service.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/game/presentation/bloc/game_bloc.dart';
import 'features/payments/data/repository/payment_repository.dart';
import 'features/payments/presentation/bloc/payment_bloc.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  ApiService().init();
  SocketService().connect();

  // Firebase — gracefully skip if not yet configured
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FcmService.instance.init();
    // Crashlytics: route all Flutter framework errors to Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Catch async errors outside the Flutter framework
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    // Firebase not configured — OTP falls back to Fast2SMS or dev console log
  }

  // Load platform settings (maintenance mode, limits, etc.)
  unawaited(AppSettingsService.instance.fetchFromServer());

  runApp(const LakadiyaApp());
}

class LakadiyaApp extends StatefulWidget {
  const LakadiyaApp({super.key});
  @override
  State<LakadiyaApp> createState() => _LakadiyaAppState();
}

class _LakadiyaAppState extends State<LakadiyaApp> {
  late final AuthBloc _authBloc;
  late final GameBloc _gameBloc;
  late final PaymentBloc _paymentBloc;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc(repo: AuthRepository())..add(AuthCheckRequested());
    _gameBloc = GameBloc();
    _paymentBloc = PaymentBloc(PaymentRepository(ApiService()), SocketService());

    // After login: register FCM token and load encrypted credentials from backend
    _authBloc.stream.listen((state) {
      if (state is AuthAuthenticated) {
        _registerFcmToken();
        unawaited(CredentialsService.instance.load());
      }
    });
  }

  Future<void> _registerFcmToken() async {
    final token = FcmService.instance.token;
    if (token == null) return;
    try {
      await ApiService().post('/notifications/device-token', data: {'fcmToken': token, 'deviceType': 'android'});
    } catch (_) {
      // Non-critical — token will be registered on next login
    }
  }

  @override
  void dispose() {
    _authBloc.close();
    _gameBloc.close();
    _paymentBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _gameBloc),
        BlocProvider.value(value: _paymentBloc),
      ],
      child: _AppView(authBloc: _authBloc, paymentBloc: _paymentBloc),
    );
  }
}

class _AppView extends StatefulWidget {
  final AuthBloc authBloc;
  final PaymentBloc paymentBloc;
  const _AppView({required this.authBloc, required this.paymentBloc});
  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  late final router = createRouter(widget.authBloc, widget.paymentBloc);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: AppSettingsService.instance.notifier,
      builder: (_, settings, child) {
        if (settings.maintenanceMode) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const _MaintenanceScreen(),
          );
        }
        return child!;
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        bloc: widget.authBloc,
        buildWhen: (_, s) => s is AuthAuthenticated || s is AuthUnauthenticated,
        builder: (_, __) => MaterialApp.router(
          title:                    'Lakadiya',
          debugShowCheckedModeBanner: false,
          theme:                    AppTheme.light,
          darkTheme:                AppTheme.dark,
          themeMode:                ThemeMode.dark,
          routerConfig:             router,
        ),
      ),
    );
  }
}

class _MaintenanceScreen extends StatefulWidget {
  const _MaintenanceScreen();
  @override
  State<_MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<_MaintenanceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _gearCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _gearCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _gearCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C1A),
      body: Stack(
        children: [
          // Ambient glow blobs
          Positioned(
            top: -120, right: -100,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 380, height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFFFAA00).withValues(alpha: 0.06 + _pulseCtrl.value * 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60, left: -80,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF0066FF).withValues(alpha: 0.05 + _pulseCtrl.value * 0.03),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated gear icon
                    AnimatedBuilder(
                      animation: _gearCtrl,
                      builder: (_, __) => Transform.rotate(
                        angle: _gearCtrl.value * 2 * math.pi,
                        child: Container(
                          width: 104, height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0E1A2E),
                            border: Border.all(
                              color: const Color(0xFFFFAA00).withValues(alpha: 0.45),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFAA00).withValues(alpha: 0.18),
                                blurRadius: 28,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('⚙️', style: TextStyle(fontSize: 46)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ── English block ──────────────────────────────────
                    const Text(
                      'Under Maintenance',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'We\'re upgrading the app for a better\nexperience. Please check back soon.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8899BB),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),

                    // ── Language divider ───────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 26),
                      child: Row(children: [
                        Expanded(
                          child: Container(height: 1, color: const Color(0xFF1A2840)),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0xFF0E1A2E),
                            border: Border.all(color: const Color(0xFF1E3050)),
                          ),
                          child: const Text(
                            'हिंदी',
                            style: TextStyle(color: Color(0xFF6688AA), fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: Container(height: 1, color: const Color(0xFF1A2840)),
                        ),
                      ]),
                    ),

                    // ── Hindi block ────────────────────────────────────
                    const Text(
                      'रखरखाव जारी है',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'हम ऐप को बेहतर बनाने पर काम कर रहे हैं।\nकृपया थोड़ी देर बाद पुनः प्रयास करें।',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8899BB),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Notification notice ────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFF0E1A2E),
                        border: Border.all(color: const Color(0xFF1E3050)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, __) => Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.lerp(
                                const Color(0xFFFFAA00),
                                const Color(0xFFFF6600),
                                _pulseCtrl.value,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFAA00)
                                      .withValues(alpha: 0.5 + _pulseCtrl.value * 0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'You\'ll be notified when we\'re back',
                              style: TextStyle(color: Color(0xFF7799BB), fontSize: 12),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'वापस आने पर आपको सूचित किया जाएगा',
                              style: TextStyle(color: Color(0xFF7799BB), fontSize: 12),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
