import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_shared.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with TickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtl    = TextEditingController();
  final _emailCtl   = TextEditingController();
  final _passCtl    = TextEditingController();
  final _confirmCtl = TextEditingController();
  bool _obscure = true;

  late final AnimationController _floatCtrl;
  late final AnimationController _enterCtrl;
  late final Animation<double>   _fadeIn;
  late final Animation<Offset>   _slideIn;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn  = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideIn = Tween(begin: const Offset(0, 0.10), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _enterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _floatCtrl.dispose(); _enterCtrl.dispose();
    _nameCtl.dispose(); _emailCtl.dispose();
    _passCtl.dispose(); _confirmCtl.dispose();
    super.dispose();
  }

  void _register() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
      AuthRegisterRequested(_nameCtl.text.trim(), _emailCtl.text.trim(), _passCtl.text),
    );
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
              // Background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF060C1A), Color(0xFF0B1829), Color(0xFF060E18)],
                  ),
                ),
              ),

              // Floating cards
              AnimatedBuilder(
                animation: _floatCtrl,
                builder: (_, __) {
                  final t = _floatCtrl.value * 2 * math.pi;
                  return Stack(
                    children: floatingCards.map((c) {
                      final y = math.sin(t + c.ph + 1.0) * c.amp;
                      final r = math.cos(t * 0.6 + c.ph) * c.rot;
                      final opacity = c.w > 58 ? 0.38 : c.w > 46 ? 0.28 : 0.18;
                      return Positioned(
                        left: c.lx * size.width,
                        top:  c.ly * size.height + y,
                        child: Transform.rotate(
                          angle: r,
                          child: Opacity(
                            opacity: opacity,
                            child: _RegMiniCard(rank: c.rank, suit: c.suit, suitColor: c.suitColor, width: c.w),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              SafeArea(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideIn,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            // Header row
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => context.go('/login'),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.darkCard,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.darkBorder),
                                    ),
                                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                                        size: 18, color: AppColors.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                ShaderMask(
                                  shaderCallback: (b) => const LinearGradient(
                                    colors: [AppColors.primary, AppColors.primaryLight],
                                  ).createShader(b),
                                  child: const Text('Create Account',
                                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Padding(
                              padding: EdgeInsets.only(left: 54),
                              child: Text("Join the game — it's free!",
                                  style: TextStyle(color: AppColors.textSecondary)),
                            ),
                            const SizedBox(height: 28),

                            GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Suit row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      SuitChip('♠', Colors.white),
                                      SuitChip('♥', AppColors.suitRed),
                                      SuitChip('♦', AppColors.suitRed),
                                      SuitChip('♣', Colors.white),
                                    ],
                                  ),
                                  const SizedBox(height: 24),

                                  AuthTextField(
                                    controller: _nameCtl,
                                    label: 'Username',
                                    hint: 'coolplayer123',
                                    validator: (v) {
                                      if (v == null || v.length < 3) return 'Min 3 characters';
                                      if (v.length > 30) return 'Max 30 characters';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  AuthTextField(
                                    controller: _emailCtl,
                                    label: 'Email',
                                    hint: 'you@example.com',
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) =>
                                        v == null || !v.contains('@') ? 'Enter valid email' : null,
                                  ),
                                  const SizedBox(height: 14),
                                  AuthTextField(
                                    controller: _passCtl,
                                    label: 'Password',
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
                                  const SizedBox(height: 14),
                                  AuthTextField(
                                    controller: _confirmCtl,
                                    label: 'Confirm Password',
                                    obscure: true,
                                    validator: (v) =>
                                        v != _passCtl.text ? 'Passwords do not match' : null,
                                  ),
                                  const SizedBox(height: 28),
                                  GradientButton(
                                    onTap: loading ? null : _register,
                                    child: loading
                                        ? const SizedBox(height: 22, width: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                        : const Text('Create Account',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Already have an account? ',
                                    style: TextStyle(color: AppColors.textSecondary)),
                                GestureDetector(
                                  onTap: () => context.go('/login'),
                                  child: const Text('Login',
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
}

class _RegMiniCard extends StatelessWidget {
  final String rank, suit;
  final Color suitColor;
  final double width;
  const _RegMiniCard({required this.rank, required this.suit, required this.suitColor, required this.width});

  @override
  Widget build(BuildContext context) {
    final h  = width * 1.4;
    final ts = TextStyle(color: suitColor, fontSize: width * 0.22, fontWeight: FontWeight.bold, height: 1.1);
    final ss = TextStyle(color: suitColor, fontSize: width * 0.18, height: 1.0);
    return Container(
      width: width, height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(2, 3))],
      ),
      child: Stack(children: [
        Positioned(top: 3, left: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [Text(rank, style: ts), Text(suit, style: ss)])),
        Center(child: Text(suit, style: TextStyle(color: suitColor, fontSize: width * 0.48, height: 1))),
        Positioned(bottom: 3, right: 4,
          child: RotatedBox(quarterTurns: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [Text(rank, style: ts), Text(suit, style: ss)]))),
      ]),
    );
  }
}
