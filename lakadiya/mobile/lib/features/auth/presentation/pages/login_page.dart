import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_shared.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey  = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passCtl  = TextEditingController();
  bool _obscure   = true;

  late final AnimationController _floatCtrl;
  late final AnimationController _enterCtrl;
  late final Animation<double>   _fadeIn;
  late final Animation<Offset>   _slideIn;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn  = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideIn = Tween(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _enterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _enterCtrl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  void _login() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(AuthLoginRequested(_emailCtl.text.trim(), _passCtl.text));
  }

  Future<void> _googleLogin() async {
    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
    final account = await googleSignIn.signIn();
    if (account == null || !mounted) return;
    context.read<AuthBloc>().add(AuthGoogleRequested(
      account.id, account.email, account.displayName ?? account.email,
      avatarUrl: account.photoUrl,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (ctx, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(state.message), backgroundColor: AppColors.danger,
            ));
          }
        },
        builder: (ctx, state) {
          final loading = state is AuthLoading;
          return Stack(
            children: [
              // ── Gradient bg ──
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF060C1A), Color(0xFF0B1829), Color(0xFF060E18)],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),

              // ── Floating mini cards ──
              AnimatedBuilder(
                animation: Listenable.merge([_floatCtrl, _enterCtrl]),
                builder: (_, __) {
                  final t     = _floatCtrl.value * 2 * math.pi;
                  final enter = _enterCtrl.value;
                  return Stack(
                    children: List.generate(floatingCards.length, (idx) {
                      final c = floatingCards[idx];
                      // Staggered entrance: card idx enters at enter > idx/floatingCards.length*0.6
                      final threshold = idx / floatingCards.length * 0.5;
                      final cardEnter = enter < threshold ? 0.0
                          : Curves.easeOutBack.transform(
                              ((enter - threshold) / (1.0 - threshold)).clamp(0.0, 1.0));

                      final floatY = math.sin(t + c.ph) * c.amp;
                      final rotR   = math.cos(t * 0.7 + c.ph) * c.rot;

                      // Entry direction based on position on screen
                      final entryDx = c.lx < 0.35 ? -100.0 : c.lx > 0.65 ? 100.0 : 0.0;
                      final entryDy = c.ly < 0.25 ? -100.0 : c.ly > 0.75 ?  100.0 : 0.0;
                      final dx = entryDx * (1 - cardEnter);
                      final dy = entryDy * (1 - cardEnter);

                      final baseOpacity = c.w > 58 ? 0.42 : c.w > 46 ? 0.32 : 0.22;

                      return Positioned(
                        left: c.lx * size.width + dx,
                        top:  c.ly * size.height + floatY + dy,
                        child: Transform.rotate(
                          angle: rotR,
                          child: Opacity(
                            opacity: baseOpacity * cardEnter,
                            child: _MiniCard(rank: c.rank, suit: c.suit, suitColor: c.suitColor, width: c.w),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),

              // ── Form ──
              SafeArea(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideIn,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            const SizedBox(height: 36),
                            _buildLogo(),
                            const SizedBox(height: 40),
                            GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Welcome Back',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.textPrimary,
                                          fontSize: 22, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  const Text('Sign in to continue playing',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                  const SizedBox(height: 28),
                                  AuthTextField(
                                    controller: _emailCtl,
                                    label: 'Email',
                                    hint: 'your@email.com',
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) =>
                                        v == null || !v.contains('@') ? 'Enter valid email' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  AuthTextField(
                                    controller: _passCtl,
                                    label: 'Password',
                                    hint: '••••••••',
                                    obscure: _obscure,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                        color: AppColors.textSecondary,
                                      ),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                    validator: (v) =>
                                        v == null || v.length < 6 ? 'Min 6 characters' : null,
                                  ),
                                  const SizedBox(height: 28),
                                  GradientButton(
                                    onTap: loading ? null : _login,
                                    child: loading
                                        ? const SizedBox(height: 22, width: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                        : const Text('Login',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(children: [
                                    const Expanded(child: Divider(color: AppColors.darkBorder)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text('or', style: TextStyle(color: AppColors.textMuted)),
                                    ),
                                    const Expanded(child: Divider(color: AppColors.darkBorder)),
                                  ]),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: loading ? null : _googleLogin,
                                    icon: const Text('G', style: TextStyle(
                                        fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4))),
                                    label: const Text('Continue with Google'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textPrimary,
                                      side: const BorderSide(color: AppColors.darkBorder),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: loading ? null : () =>
                                        context.read<AuthBloc>().add(AuthGuestRequested()),
                                    icon: const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.accent),
                                    label: const Text('Play as Guest',
                                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("Don't have an account? ",
                                    style: TextStyle(color: AppColors.textSecondary)),
                                GestureDetector(
                                  onTap: () => context.go('/register'),
                                  child: const Text('Register',
                                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogo() => AnimatedBuilder(
    animation: _floatCtrl,
    builder: (_, __) {
      final glow = (math.sin(_floatCtrl.value * 2 * math.pi) + 1) / 2;
      return Column(
        children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFF1A3A20), Color(0xFF0A1A10)]),
              boxShadow: [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3 + glow * 0.3),
                blurRadius: 20 + glow * 15, spreadRadius: 2,
              )],
            ),
            child: const Center(child: Text('♠', style: TextStyle(fontSize: 44, color: AppColors.primary))),
          ),
          const SizedBox(height: 16),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [AppColors.accent, AppColors.accentLight, AppColors.accent],
            ).createShader(b),
            child: const Text('LAKADIYA',
                style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4)),
          ),
          const SizedBox(height: 4),
          const Text('Callbreak Card Game',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, letterSpacing: 1.5)),
        ],
      );
    },
  );
}

// ── Mini playing card for floating background ──────────────────────────────
class _MiniCard extends StatelessWidget {
  final String rank;
  final String suit;
  final Color suitColor;
  final double width;
  const _MiniCard({required this.rank, required this.suit, required this.suitColor, required this.width});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    final ts = TextStyle(color: suitColor, fontSize: width * 0.22, fontWeight: FontWeight.bold, height: 1.1);
    final ss = TextStyle(color: suitColor, fontSize: width * 0.18, height: 1.0);
    return Container(
      width: width, height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(2, 3))],
      ),
      child: Stack(
        children: [
          Positioned(top: 3, left: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [Text(rank, style: ts), Text(suit, style: ss)])),
          Center(child: Text(suit, style: TextStyle(color: suitColor, fontSize: width * 0.48, height: 1))),
          Positioned(bottom: 3, right: 4,
            child: RotatedBox(quarterTurns: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                children: [Text(rank, style: ts), Text(suit, style: ss)]))),
        ],
      ),
    );
  }
}
