import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sms_autofill/sms_autofill.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_shared.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin, CodeAutoFill {
  int _step = 1; // 1 = mobile, 2 = OTP
  String _mobile = '';

  final _mobileCtl = TextEditingController();
  final _otpCtl    = TextEditingController();

  late final AnimationController _floatCtrl;
  late final AnimationController _enterCtrl;
  late final Animation<double>   _fadeIn;
  late final Animation<Offset>   _slideIn;

  StreamSubscription<String>? _fcmOtpSub;

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
    // Listen for OTP delivered via Firebase notification (fallback when Fast2SMS not set)
    _fcmOtpSub = FcmService.instance.otpStream.listen((otp) {
      if (mounted && _step == 2) {
        _otpCtl.text = otp;
        Future.microtask(_verifyOtp);
      }
    });
  }

  @override
  void codeUpdated() {
    // Called by sms_autofill when OTP is detected from SMS
    if (code != null && code!.length == 6 && mounted) {
      _otpCtl.text = code!;
    }
  }

  @override
  void dispose() {
    _fcmOtpSub?.cancel();
    cancel(); // stop SMS listener
    _floatCtrl.dispose();
    _enterCtrl.dispose();
    _mobileCtl.dispose();
    _otpCtl.dispose();
    super.dispose();
  }

  void _sendOtp() {
    final m = _mobileCtl.text.trim();
    if (m.length < 10) { _err('Enter a valid 10-digit mobile number'); return; }
    context.read<AuthBloc>().add(AuthOtpSendRequested('+91$m'));
  }

  void _verifyOtp() {
    final otp = _otpCtl.text.trim();
    if (otp.length != 6) { _err('Enter the 6-digit OTP'); return; }
    context.read<AuthBloc>().add(AuthOtpVerifyRequested(_mobile, otp));
  }

  void _resendOtp() {
    _otpCtl.clear();
    context.read<AuthBloc>().add(AuthOtpSendRequested(_mobile));
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
  );

  void _showGuestDialog() {
    final ctl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Play as Guest',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter your mobile to continue. If you\'ve played before, your progress will be restored.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                counterText: '',
                hintText: '10-digit mobile number',
                hintStyle: TextStyle(color: AppColors.textMuted),
                prefixText: '+91  ',
                prefixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: const Color(0xFF162230),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final m = ctl.text.trim();
              if (m.length < 10) return;
              Navigator.pop(ctx);
              context.read<AuthBloc>().add(AuthGuestRequested('+91$m'));
            },
            child: const Text('Continue', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _googleLogin() async {
    final gs = GoogleSignIn(scopes: ['email', 'profile']);
    final account = await gs.signIn();
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
          if (state is OtpSent) {
            setState(() { _step = 2; _mobile = state.mobile; });
            // Start listening for OTP in incoming SMS
            listenForCode();
          } else if (state is AuthError) {
            _err(state.message);
          }
        },
        builder: (ctx, state) {
          final loading = state is AuthLoading;
          return Stack(
            children: [
              _buildBg(),
              _buildFloatingCards(size),
              SafeArea(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideIn,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 36),
                          _buildLogo(),
                          const SizedBox(height: 40),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0.08, 0), end: Offset.zero)
                                    .animate(anim),
                                child: child,
                              ),
                            ),
                            child: _step == 1
                                ? _buildMobileStep(loading)
                                : _buildOtpStep(loading),
                          ),
                          const SizedBox(height: 20),
                        ],
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

  Widget _buildMobileStep(bool loading) => GlassCard(
    key: const ValueKey('mobile'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Welcome to Lakadiya',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Enter your mobile number to continue',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 28),
        // Mobile input
        TextField(
          controller: _mobileCtl,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, letterSpacing: 2),
          decoration: InputDecoration(
            counterText: '',
            labelText: 'Mobile Number',
            hintText: 'Enter 10-digit number',
            prefixText: '+91  ',
            prefixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 28),
        GradientButton(
          onTap: loading ? null : _sendOtp,
          child: loading
              ? const SizedBox(height: 22, width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Get OTP',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(height: 20),
        _divider(),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: loading ? null : _googleLogin,
          icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4))),
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
          onPressed: loading ? null : _showGuestDialog,
          icon: const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.accent),
          label: const Text('Play as Guest', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  Widget _buildOtpStep(bool loading) => GlassCard(
    key: const ValueKey('otp'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () { cancel(); setState(() { _step = 1; _otpCtl.clear(); }); },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Enter OTP',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        RichText(
          text: TextSpan(
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            children: [
              const TextSpan(text: 'OTP sent to '),
              TextSpan(
                text: _mobile,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        // OTP PIN field with auto-fill
        PinFieldAutoFill(
          controller: _otpCtl,
          codeLength: 6,
          autoFocus: true,
          decoration: UnderlineDecoration(
            textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
            colorBuilder: FixedColorBuilder(AppColors.primary),
            bgColorBuilder: FixedColorBuilder(const Color(0xFF162230)),
          ),
          onCodeChanged: (v) {
            if (v != null && v.length == 6) {
              // Auto-submit when 6 digits entered
              Future.microtask(_verifyOtp);
            }
          },
          onCodeSubmitted: (_) => _verifyOtp(),
        ),
        const SizedBox(height: 32),
        GradientButton(
          onTap: loading ? null : _verifyOtp,
          child: loading
              ? const SizedBox(height: 22, width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Verify & Continue',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Didn't receive OTP? ",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            GestureDetector(
              onTap: loading ? null : _resendOtp,
              child: const Text('Resend',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildBg() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF060C1A), Color(0xFF0B1829), Color(0xFF060E18)],
        stops: [0.0, 0.5, 1.0],
      ),
    ),
  );

  Widget _buildFloatingCards(Size size) => AnimatedBuilder(
    animation: Listenable.merge([_floatCtrl, _enterCtrl]),
    builder: (_, __) {
      final t     = _floatCtrl.value * 2 * math.pi;
      final enter = _enterCtrl.value;
      return Stack(
        children: List.generate(floatingCards.length, (i) {
          final c = floatingCards[i];
          final th = i / floatingCards.length * 0.5;
          final ce = enter < th ? 0.0
              : Curves.easeOutBack.transform(((enter - th) / (1.0 - th)).clamp(0.0, 1.0));
          final fy = math.sin(t + c.ph) * c.amp;
          final r  = math.cos(t * 0.7 + c.ph) * c.rot;
          final ex = c.lx < 0.35 ? -100.0 : c.lx > 0.65 ? 100.0 : 0.0;
          final ey = c.ly < 0.25 ? -100.0 : c.ly > 0.75 ?  100.0 : 0.0;
          final op = c.w > 58 ? 0.42 : c.w > 46 ? 0.32 : 0.22;
          return Positioned(
            left: c.lx * size.width  + ex * (1 - ce),
            top:  c.ly * size.height + fy + ey * (1 - ce),
            child: Transform.rotate(
              angle: r,
              child: Opacity(
                opacity: op * ce,
                child: _MiniCard(rank: c.rank, suit: c.suit, suitColor: c.suitColor, width: c.w),
              ),
            ),
          );
        }),
      );
    },
  );

  Widget _buildLogo() => AnimatedBuilder(
    animation: _floatCtrl,
    builder: (_, __) {
      final glow = (math.sin(_floatCtrl.value * 2 * math.pi) + 1) / 2;
      return Column(children: [
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
      ]);
    },
  );

  Widget _divider() => Row(children: [
    const Expanded(child: Divider(color: AppColors.darkBorder)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('or', style: TextStyle(color: AppColors.textMuted)),
    ),
    const Expanded(child: Divider(color: AppColors.darkBorder)),
  ]);
}

class _MiniCard extends StatelessWidget {
  final String rank, suit;
  final Color suitColor;
  final double width;
  const _MiniCard({required this.rank, required this.suit, required this.suitColor, required this.width});

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
