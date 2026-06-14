import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // Choreographs the entrance: card deal → brand reveal → tagline.
  late final AnimationController _intro;
  // Slow ambient background glow.
  late final AnimationController _ambient;
  // Bottom loading shimmer.
  late final AnimationController _loader;
  // Clean fade-out before handing off to the lobby.
  late final AnimationController _exit;

  // Staged intervals off the single intro controller.
  late final Animation<double> _deal;     // card fan + emblem
  late final Animation<double> _brand;     // LAKADIYA wordmark
  late final Animation<double> _tagline;   // sub text

  // Optional splash video (assets/videos/splash.mp4). Falls back to the coded
  // animation when the file is missing or fails to decode.
  VideoPlayerController? _video;
  bool _videoReady = false;
  Timer? _navTimer;
  bool _navigating = false;

  // 9-card spread — centre card (index 4) is the A♠ hero.
  static const _cards = [
    ['K',  '♥', true],
    ['Q',  '♦', true],
    ['J',  '♣', false],
    ['10', '♥', true],
    ['A',  '♠', false],
    ['10', '♦', true],
    ['J',  '♠', false],
    ['Q',  '♣', false],
    ['K',  '♦', true],
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _intro   = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
    _loader  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
    _exit    = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

    _deal    = CurvedAnimation(parent: _intro, curve: const Interval(0.00, 0.55, curve: Curves.easeOutBack));
    _brand   = CurvedAnimation(parent: _intro, curve: const Interval(0.45, 0.82, curve: Curves.easeOut));
    _tagline = CurvedAnimation(parent: _intro, curve: const Interval(0.70, 1.00, curve: Curves.easeOut));

    _initSplash();
  }

  Future<void> _initSplash() async {
    final controller = VideoPlayerController.asset('assets/videos/splash.mp4');
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted) { controller.dispose(); return; }
      controller
        ..setLooping(false)
        ..setVolume(1.0)
        ..play();
      controller.addListener(_videoListener);
      setState(() => _videoReady = true);
      // Safety net: leave when the video ends, or after its duration + buffer.
      final ms = controller.value.duration.inMilliseconds;
      _navTimer = Timer(Duration(milliseconds: (ms > 0 ? ms : 6000) + 500), _goNext);
    } catch (_) {
      // No video / decode failed → run the coded animated splash instead.
      _video?.dispose();
      _video = null;
      if (!mounted) return;
      _intro.forward();
      _navTimer = Timer(const Duration(milliseconds: 2900), _goNext);
    }
  }

  void _videoListener() {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    final d = v.value.duration;
    if (d > Duration.zero && v.value.position >= d) _goNext();
  }

  Future<void> _goNext() async {
    if (_navigating || !mounted) return;
    _navigating = true;
    _navTimer?.cancel();
    await _exit.forward();
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    if (mounted) context.go('/lobby');
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _video?.removeListener(_videoListener);
    _video?.dispose();
    _intro.dispose();
    _ambient.dispose();
    _loader.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04090F),
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _ambient, _loader, _exit]),
        builder: (context, _) {
          return Opacity(
            opacity: 1 - _exit.value,
            child: Transform.scale(
              scale: 1 + _exit.value * 0.06,
              child: (_videoReady && _video != null)
                  // ── Full-screen splash video ──
                  ? _videoView()
                  // ── Image artwork / coded animation + sparkles + loader ──
                  : Stack(
                      children: [
                        _backgroundOrFallback(),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _SparklePainter(_ambient.value)),
                          ),
                        ),
                        _bottomLoader(),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  // Full-bleed video, cropped to fill the screen regardless of aspect ratio.
  Widget _videoView() {
    final v = _video!;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: v.value.size.width,
          height: v.value.size.height,
          child: VideoPlayer(v),
        ),
      ),
    );
  }

  // Uses the designer artwork when present; otherwise the coded animation.
  Widget _backgroundOrFallback() {
    return Image.asset(
      'assets/images/splash_bg.png',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _codedContent(),
    );
  }

  // The fully-coded animated splash (felt + dealt cards + emblem + wordmark).
  Widget _codedContent() {
    return Stack(
      children: [
        _background(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _emblemAndCards(),
              const SizedBox(height: 38),
              _wordmark(),
              const SizedBox(height: 12),
              _taglineWidget(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Ambient gradient + drifting glow orbs ───────────────────────────────────
  Widget _background() {
    final a = _ambient.value;
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A1A12), Color(0xFF061018), Color(0xFF03070C)],
              stops: [0, 0.5, 1],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -120 + a * 30, right: -90,
          child: _orb(320, AppColors.primary.withValues(alpha: 0.10 + a * 0.05)),
        ),
        Positioned(
          bottom: -100 - a * 30, left: -80,
          child: _orb(300, AppColors.accent.withValues(alpha: 0.07 + a * 0.04)),
        ),
      ],
    );
  }

  Widget _orb(double size, Color color) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      );

  // ── Spade emblem with a rotating gold ring + a wide fan of cards ────────────
  Widget _emblemAndCards() {
    final d = _deal.value.clamp(0.0, 1.0);
    // The emblem appears once most of the cards have dealt in.
    final emblem = Curves.easeOutBack.transform(((d - 0.55) / 0.45).clamp(0.0, 1.0));
    return SizedBox(
      width: 340, height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow behind the emblem
          Opacity(
            opacity: emblem.clamp(0.0, 1.0),
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.22 + _ambient.value * 0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          // Fanned cards (dealt one-by-one with a flip-in)
          for (int i = 0; i < _cards.length; i++) _fannedCard(i, d),
          // Rotating gold ring + spade — rises above the centre of the fan
          Transform.translate(
            offset: const Offset(0, -6),
            child: Transform.scale(
              scale: emblem.clamp(0.0, 1.05),
              child: _spadeBadge(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fannedCard(int i, double d) {
    final n = _cards.length;
    // Each card deals in sequence, left to right.
    const step = 0.06;
    final start = i * step;
    final span  = 1 - (n - 1) * step;
    final p  = ((d - start) / span).clamp(0.0, 1.0);
    final cp = Curves.easeOutCubic.transform(p);

    final mid   = i - (n - 1) / 2;          // -4..4
    final angle = mid * 0.12 * cp;          // spread fan
    final dx    = mid * 27.0 * cp;          // horizontal spread
    final dy    = mid.abs() * 7.0 * cp - 12 * cp; // gentle arc, lifted up
    final flipX = 0.12 + 0.88 * cp;         // edge-on → full (flip-in)

    return Opacity(
      opacity: cp,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: angle,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scaleByDouble(flipX, 0.8 + 0.2 * cp, 1.0, 1.0),
            child: _MiniCard(
              rank: _cards[i][0] as String,
              suit: _cards[i][1] as String,
              red: _cards[i][2] as bool,
            ),
          ),
        ),
      ),
    );
  }

  Widget _spadeBadge() {
    return Container(
      width: 78, height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0F2A1C), Color(0xFF07140D)],
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 22),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Slowly rotating dashed gold ring
          Transform.rotate(
            angle: _ambient.value * math.pi,
            child: CustomPaint(size: const Size(70, 70), painter: _RingPainter()),
          ),
          const Text('♠', style: TextStyle(
            color: Colors.white, fontSize: 38, height: 1,
            shadows: [Shadow(color: Color(0xFFFFD600), blurRadius: 14)],
          )),
        ],
      ),
    );
  }

  // ── Wordmark ────────────────────────────────────────────────────────────────
  Widget _wordmark() {
    final v = _brand.value.clamp(0.0, 1.0);
    return Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, (1 - v) * 18),
        child: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFFFF59D), AppColors.accent, Color(0xFFC79E00)],
          ).createShader(b),
          child: const Text(
            'LAKADIYA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _taglineWidget() {
    final v = _tagline.value.clamp(0.0, 1.0);
    return Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, (1 - v) * 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _diamond(),
            const SizedBox(width: 10),
            Text(
              'THE ROYAL CARD GAME',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            _diamond(),
          ],
        ),
      ),
    );
  }

  Widget _diamond() => Container(
        width: 5, height: 5,
        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
      );

  // ── Bottom shimmer loader ───────────────────────────────────────────────────
  Widget _bottomLoader() {
    return Positioned(
      left: 0, right: 0, bottom: 54,
      child: Opacity(
        opacity: _tagline.value.clamp(0.0, 1.0),
        child: Column(
          children: [
            SizedBox(
              width: 120, height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.08)),
                    Align(
                      alignment: Alignment(-1 + 2 * _loader.value, 0),
                      child: Container(
                        width: 46, height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(colors: [
                            Colors.transparent, AppColors.primary, Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Shuffling the deck…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11, letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── A small premium playing card ──────────────────────────────────────────────
class _MiniCard extends StatelessWidget {
  final String rank;
  final String suit;
  final bool red;
  const _MiniCard({required this.rank, required this.suit, required this.red});

  @override
  Widget build(BuildContext context) {
    final pip = red ? const Color(0xFFE53935) : const Color(0xFF1A1A2E);
    return Container(
      width: 58, height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFEDEFF4)],
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(rank, style: TextStyle(color: pip, fontSize: 13, fontWeight: FontWeight.bold, height: 1)),
                Text(suit, style: TextStyle(color: pip, fontSize: 11, height: 1)),
              ]),
            ),
            Center(child: Text(suit, style: TextStyle(color: pip, fontSize: 26))),
          ],
        ),
      ),
    );
  }
}

// ── Drifting, twinkling golden sparkles overlay ───────────────────────────────
class _SparklePainter extends CustomPainter {
  final double t; // 0..1 ambient loop
  _SparklePainter(this.t);

  static final math.Random _rng = math.Random(99);
  static final List<Offset> _pts =
      List.generate(46, (_) => Offset(_rng.nextDouble(), _rng.nextDouble()));
  static final List<double> _phase =
      List.generate(46, (_) => _rng.nextDouble());
  static final List<double> _size =
      List.generate(46, (_) => 0.7 + _rng.nextDouble() * 2.4);

  @override
  void paint(Canvas canvas, Size size) {
    final core = Paint();
    final glow = Paint();
    for (int i = 0; i < _pts.length; i++) {
      final ph = (t + _phase[i]) % 1.0;
      final twinkle = (math.sin(ph * 2 * math.pi)).abs(); // 0..1
      final drift = ph * 60.0; // slow upward drift
      final x = _pts[i].dx * size.width;
      final y = (_pts[i].dy * size.height - drift) % size.height;
      final r = _size[i] * (0.6 + twinkle * 0.9);

      glow.color = const Color(0xFFFFD600).withValues(alpha: 0.04 + twinkle * 0.12);
      canvas.drawCircle(Offset(x, y), r * 3.2, glow);
      core.color = const Color(0xFFFFF3B0).withValues(alpha: 0.15 + twinkle * 0.6);
      canvas.drawCircle(Offset(x, y), r, core);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

// ── Dashed rotating ring around the spade emblem ──────────────────────────────
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent.withValues(alpha: 0.6);

    const dashes = 24;
    const sweep = (2 * math.pi) / dashes;
    for (int i = 0; i < dashes; i++) {
      if (i.isOdd) continue;
      final start = i * sweep;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start, sweep * 0.6, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
