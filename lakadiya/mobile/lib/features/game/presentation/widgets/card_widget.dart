import 'package:flutter/material.dart';
import '../../domain/entities/card_entity.dart';

class CardWidget extends StatelessWidget {
  final CardEntity card;
  final bool isPlayable;
  final bool isSelected;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const CardWidget({
    super.key,
    required this.card,
    this.isPlayable = false,
    this.isSelected = false,
    this.onTap,
    this.width  = 52,
    this.height = 76,
  });

  static const _red   = Color(0xFFD32F2F);
  static const _black = Color(0xFF1A1A2E);

  Color get _suitColor => card.isRed ? _red : _black;

  static const _faceRanks = {'K', 'Q', 'J'};

  static final _suitCode = {
    'spades': 'S', 'hearts': 'H', 'diamonds': 'D', 'clubs': 'C',
  };

  bool get _isFace => _faceRanks.contains(card.rank);

  String? get _faceAsset {
    final s = _suitCode[card.suit];
    if (s == null) return null;
    return 'assets/cards/${card.rank}$s.png';
  }

  @override
  Widget build(BuildContext context) {
    if (card.hidden) return _buildBack();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width:  width,
        height: height,
        transform: isSelected
            ? Matrix4.translationValues(0, -14, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: isSelected
              ? Border.all(color: const Color(0xFFFFD700), width: 2.5)
              : isPlayable
                  ? Border.all(color: const Color(0xFF4CAF50), width: 1.5)
                  : Border.all(color: const Color(0xFFBDBDBD), width: 0.8),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                blurRadius: 10,
                spreadRadius: 1,
              )
            else if (isPlayable)
              BoxShadow(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                blurRadius: 8,
              )
            else
              const BoxShadow(
                color: Colors.black26,
                blurRadius: 3,
                offset: Offset(1, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.5),
          child: _isFace ? _buildFace() : _buildPip(),
        ),
      ),
    );
  }

  // ── Face card (K / Q / J) ──────────────────────────────────────────────────
  Widget _buildFace() {
    final asset = _faceAsset;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (asset != null)
          Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPip(), // fallback
          ),
        // Corner label overlaid on top of the image
        Positioned(
          top: 2, left: 3,
          child: _cornerLabel(card.rank, card.symbol),
        ),
        Positioned(
          bottom: 2, right: 3,
          child: RotatedBox(
            quarterTurns: 2,
            child: _cornerLabel(card.rank, card.symbol),
          ),
        ),
      ],
    );
  }

  // ── Pip card (A, 2–10) ─────────────────────────────────────────────────────
  Widget _buildPip() => Stack(
    children: [
      Positioned(
        top: 2, left: 3,
        child: _cornerLabel(card.rank, card.symbol),
      ),
      Center(
        child: Text(
          card.symbol,
          style: TextStyle(fontSize: width * 0.52, color: _suitColor, height: 1),
        ),
      ),
      Positioned(
        bottom: 2, right: 3,
        child: RotatedBox(
          quarterTurns: 2,
          child: _cornerLabel(card.rank, card.symbol),
        ),
      ),
    ],
  );

  Widget _cornerLabel(String rank, String sym) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        rank,
        style: TextStyle(
          color: _suitColor,
          fontSize: width * 0.22,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
      Text(
        sym,
        style: TextStyle(
          color: _suitColor,
          fontSize: width * 0.18,
          height: 1,
        ),
      ),
    ],
  );

  Widget _buildBack() => Container(
    width:  width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xFFBDBDBD), width: 0.8),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(1, 2)),
      ],
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6.5),
      child: Stack(
        children: [
          // Diagonal pattern
          CustomPaint(
            size: Size(width, height),
            painter: _CardBackPainter(),
          ),
          // Center emblem
          Center(
            child: Container(
              width: width * 0.55,
              height: height * 0.55,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                border: Border.all(color: Colors.white24, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: Text('♠', style: TextStyle(color: Colors.white54, fontSize: 18)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const spacing = 8.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
