import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

// ── Floating card config ────────────────────────────────────────────────────
class FloatCardConfig {
  final String rank;
  final String suit;
  final Color suitColor;
  final double lx, ly, w, ph, amp, rot;
  const FloatCardConfig(this.rank, this.suit, this.suitColor,
      this.lx, this.ly, this.w, this.ph, this.amp, this.rot);
}

// lx/ly = fractional position, w = card width px, ph = phase, amp = float px, rot = max rotation rad
const floatingCards = [
  // large (close depth)
  FloatCardConfig('A', '♠', Color(0xFF1A1A2E),   0.03, 0.06, 68, 0.0,  22, 0.18),
  FloatCardConfig('K', '♥', Color(0xFFE53935),   0.72, 0.04, 62, 1.1,  18, -0.14),
  FloatCardConfig('Q', '♦', Color(0xFFE53935),   0.81, 0.40, 58, 2.3,  25, 0.22),
  FloatCardConfig('J', '♣', Color(0xFF1A1A2E),   0.01, 0.56, 64, 0.7,  20, -0.19),
  // medium
  FloatCardConfig('A', '♥', Color(0xFFE53935),   0.75, 0.68, 50, 1.8,  27, 0.10),
  FloatCardConfig('K', '♠', Color(0xFF1A1A2E),   0.10, 0.80, 54, 3.0,  16, -0.08),
  FloatCardConfig('Q', '♣', Color(0xFF263238),   0.55, 0.87, 46, 2.0,  21, 0.23),
  FloatCardConfig('J', '♦', Color(0xFFE53935),   0.42, 0.01, 48, 0.4,  19, -0.12),
  // small (far depth)
  FloatCardConfig('10','♠', Color(0xFF1A1A2E),   0.30, 0.33, 38, 1.5,  14, 0.30),
  FloatCardConfig('9', '♥', Color(0xFFE53935),   0.63, 0.20, 36, 2.7,  17, -0.24),
  FloatCardConfig('8', '♦', Color(0xFFE53935),   0.88, 0.14, 34, 0.9,  20, 0.15),
  FloatCardConfig('7', '♣', Color(0xFF1A1A2E),   0.19, 0.26, 40, 3.5,  13, -0.17),
];

// ── Glass card container ───────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const GlassCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        padding: padding ?? const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
        ),
        child: child,
      ),
    ),
  );
}

// ── Gradient press button ──────────────────────────────────────────────────
class GradientButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final List<Color>? colors;
  const GradientButton({super.key, required this.child, this.onTap, this.colors});

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.95).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (_) { if (widget.onTap != null) _ctrl.forward(); },
    onTapUp:     (_) { _ctrl.reverse(); widget.onTap?.call(); },
    onTapCancel: ()  => _ctrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: widget.onTap == null
              ? const LinearGradient(colors: [AppColors.textMuted, AppColors.textMuted])
              : LinearGradient(
                  colors: widget.colors ?? [const Color(0xFF00C853), const Color(0xFF007E33)],
                ),
          boxShadow: widget.onTap == null ? null : [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(child: widget.child),
      ),
    ),
  );
}

// ── Suit chip (register page header) ──────────────────────────────────────
class SuitChip extends StatelessWidget {
  final String suit;
  final Color color;
  const SuitChip(this.suit, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Text(suit, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
  );
}
