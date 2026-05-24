import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/game_state_entity.dart';

class PlayerSeatWidget extends StatelessWidget {
  final PlayerInfo player;
  final int? bid;
  final int tricksWon;
  final double score;
  final bool isCurrentTurn;
  final bool isDealer;

  const PlayerSeatWidget({
    super.key,
    required this.player,
    this.bid,
    required this.tricksWon,
    required this.score,
    required this.isCurrentTurn,
    required this.isDealer,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrentTurn
            ? AppColors.primary.withValues(alpha: 0.2)
            : AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn ? AppColors.primary : AppColors.darkBorder,
          width: isCurrentTurn ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.darkSurface,
                child: Text(
                  player.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isDealer)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Text('D',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
              if (player.isBot)
                Positioned(
                  left: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.trump,
                      shape: BoxShape.circle,
                    ),
                    child: const Text('🤖', style: TextStyle(fontSize: 8)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            player.username.length > 8
                ? '${player.username.substring(0, 8)}…'
                : player.username,
            style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pill('B:${bid ?? '?'}', AppColors.accent),
              const SizedBox(width: 4),
              _pill('W:$tricksWon', AppColors.primary),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            score >= 0 ? '+${score.toStringAsFixed(1)}' : score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 11,
              color: score >= 0 ? AppColors.primaryLight : AppColors.danger,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
  );
}
