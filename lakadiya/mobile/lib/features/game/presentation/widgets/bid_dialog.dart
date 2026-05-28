import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class BidDialog extends StatefulWidget {
  final void Function(int bid) onBid;

  const BidDialog({super.key, required this.onBid});

  @override
  State<BidDialog> createState() => _BidDialogState();
}

class _BidDialogState extends State<BidDialog> {
  int _selected = 0; // 0 = nothing picked yet

  @override
  Widget build(BuildContext context) {
    final confirmed = _selected > 0;

    return PopScope(
      canPop: false, // block Android back button
      child: Dialog(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Place Your Bid',
                style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'How many tricks will you win?',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Number grid 1–13
              Wrap(
                spacing: 8, runSpacing: 8,
                children: List.generate(13, (i) {
                  final n = i + 1;
                  final sel = _selected == n;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.darkCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel ? AppColors.primary : AppColors.darkBorder,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$n',
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              if (!confirmed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Tap a number to select your bid',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: confirmed
                      ? () {
                          Navigator.pop(context);
                          widget.onBid(_selected);
                        }
                      : null,
                  child: const Text('Confirm Bid'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
