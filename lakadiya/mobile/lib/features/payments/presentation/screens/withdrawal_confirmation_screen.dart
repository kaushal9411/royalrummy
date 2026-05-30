import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/app_settings_service.dart';
import '../bloc/payment_bloc.dart';

/// Call this instead of directly dispatching RequestWithdrawalEvent.
/// Shows a confirmation dialog before proceeding.
Future<void> showWithdrawalConfirmation(
    BuildContext context, double amount, double balance) async {
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Withdraw',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogCtx, _, __) => Center(
      child: Material(
        color: Colors.transparent,
        child: _WithdrawalConfirmCard(amount: amount, balance: balance,
          onConfirm: () => Navigator.pop(dialogCtx, true),
          onCancel:  () => Navigator.pop(dialogCtx, false),
        ),
      ),
    ),
    transitionBuilder: (_, anim, __, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
  if (confirmed == true && context.mounted) {
    context.read<PaymentBloc>().add(RequestWithdrawalEvent(amount));
  }
}

class _WithdrawalConfirmCard extends StatelessWidget {
  final double amount;
  final double balance;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _WithdrawalConfirmCard({
    required this.amount,
    required this.balance,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final s           = AppSettingsService.instance.current;
    final feePct      = s.platformFeePct;
    final platformFee = double.parse((amount * feePct / 100).toStringAsFixed(2));
    final netAmount   = amount - platformFee;
    final remaining   = balance - amount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 60, spreadRadius: 10),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            gradient: LinearGradient(colors: [
              AppColors.accent.withValues(alpha: 0.1), Colors.transparent,
            ]),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: AppColors.accent, size: 18),
            ),
            const SizedBox(width: 14),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Confirm Withdrawal',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Please review before proceeding',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
              ),
            ),
          ]),
        ),
        Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),

        // Body
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            // Big "you receive" number
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF00B0FF), Color(0xFF0088CC)],
              ).createShader(b),
              child: Text(netAmount.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white, fontSize: 52,
                      fontWeight: FontWeight.w900, letterSpacing: -1, height: 1)),
            ),
            const SizedBox(height: 6),
            const Text('you will receive',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),

            // Fee breakdown card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(children: [
                _SummaryRow('Withdrawal Request', amount.toStringAsFixed(0), Colors.white),
                const SizedBox(height: 8),
                _SummaryRow(
                  'Platform Fee (${feePct.toStringAsFixed(1)}%)',
                  '−${platformFee.toStringAsFixed(2)}',
                  AppColors.danger,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF1E3050)),
                ),
                _SummaryRow('You Will Receive', netAmount.toStringAsFixed(2),
                    const Color(0xFF00B0FF)),
              ]),
            ),
            const SizedBox(height: 12),

            // Wallet impact
            _SummaryRow('Current Balance', balance.toStringAsFixed(2), Colors.white),
            const SizedBox(height: 6),
            _SummaryRow('Remaining Balance', remaining.toStringAsFixed(2), AppColors.accent),
            const SizedBox(height: 16),

            // Processing note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1A2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(children: [
                Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text('Processed within 24–48 hours after admin review',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
              ]),
            ),
            const SizedBox(height: 20),

            // Confirm button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Confirm — Receive ${netAmount.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onCancel,
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _SummaryRow(this.label, this.value, this.valueColor);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 13)),
    ],
  );
}
