import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    if (card.hidden) return _buildBack();

    final color  = card.isRed ? AppColors.suitRed : AppColors.suitBlack;
    final border = isSelected
        ? Border.all(color: AppColors.accent, width: 2.5)
        : isPlayable
            ? Border.all(color: AppColors.primary, width: 1.5)
            : Border.all(color: AppColors.darkBorder, width: 0.5);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width:  width,
        height: height,
        transform: isSelected
            ? Matrix4.translationValues(0, -12, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color:        AppColors.darkCard,
          borderRadius: BorderRadius.circular(6),
          border:       border,
          boxShadow: isPlayable
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(3),
              child: Text(
                card.rank,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            Text(card.symbol, style: TextStyle(color: color, fontSize: 22)),
            Padding(
              padding: const EdgeInsets.all(3),
              child: RotatedBox(
                quarterTurns: 2,
                child: Text(
                  card.rank,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() => Container(
    width:  width,
    height: height,
    decoration: BoxDecoration(
      color:        AppColors.trump,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.darkBorder, width: 0.5),
    ),
    child: const Center(
      child: Text('♠', style: TextStyle(color: Colors.white24, fontSize: 24)),
    ),
  );
}
