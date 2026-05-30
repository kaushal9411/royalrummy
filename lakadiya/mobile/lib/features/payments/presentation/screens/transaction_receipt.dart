import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../data/models/payment_model.dart';

// ── Entry point ────────────────────────────────────────────────────────────────

Future<void> showTransactionReceipt(BuildContext context, Transaction tx) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReceiptModal(tx: tx),
  );
}

// ── Modal wrapper ──────────────────────────────────────────────────────────────

class _ReceiptModal extends StatefulWidget {
  final Transaction tx;
  const _ReceiptModal({required this.tx});
  @override
  State<_ReceiptModal> createState() => _ReceiptModalState();
}

class _ReceiptModalState extends State<_ReceiptModal> {
  final _receiptKey = GlobalKey();
  bool _sharing = false;
  bool _saving  = false;

  Future<Uint8List?> _capture() async {
    try {
      await Future.delayed(const Duration(milliseconds: 80)); // let GPU flush
      final boundary =
          _receiptKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<File?> _writeTempFile(Uint8List bytes) async {
    final dir  = await getTemporaryDirectory();
    final name = 'receipt_${widget.tx.id.substring(0, 8)}.png';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final bytes = await _capture();
      if (bytes == null) { _snack('Could not capture receipt', AppColors.danger); return; }
      final file  = await _writeTempFile(bytes);
      if (file == null) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Transaction Receipt',
        text: 'My Lakadiya wallet transaction receipt',
      );
    } catch (e) {
      _snack('Share failed: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _download() async {
    setState(() => _saving = true);
    try {
      final bytes = await _capture();
      if (bytes == null) { _snack('Could not capture receipt', AppColors.danger); return; }
      final dir  = await getApplicationDocumentsDirectory();
      final name = 'receipt_${widget.tx.id.substring(0, 8)}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      _snack('Receipt saved to Documents folder', AppColors.primary);
    } catch (e) {
      _snack('Save failed: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 32 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // receipt card
            RepaintBoundary(
              key: _receiptKey,
              child: _ReceiptCard(tx: widget.tx),
            ),
            const SizedBox(height: 24),
            // action buttons
            Row(children: [
              Expanded(child: _ActionBtn(
                icon: Icons.share_rounded,
                label: 'Share',
                loading: _sharing,
                color: AppColors.primary,
                onTap: _share,
              )),
              const SizedBox(width: 12),
              Expanded(child: _ActionBtn(
                icon: Icons.download_rounded,
                label: 'Save Receipt',
                loading: _saving,
                color: AppColors.accent,
                onTap: _download,
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Receipt card (captured as image) ──────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final Transaction tx;
  const _ReceiptCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isAdd       = tx.type == 'add';
    final meta        = tx.metadata;

    // fee values from metadata (null-safe — old txns won't have these)
    final baseAmount  = (meta?['baseAmount']  as num?)?.toDouble();
    final gatewayFee  = (meta?['gatewayFee']  as num?)?.toDouble();
    final gwFeePct    = (meta?['gatewayFeePct'] as num?)?.toDouble();
    final platformFee = (meta?['platformFee'] as num?)?.toDouble();
    final pfFeePct    = (meta?['platformFeePct'] as num?)?.toDouble();
    final netAmount   = (meta?['netAmount']   as num?)?.toDouble();

    final accentColor = isAdd ? AppColors.primary : AppColors.accent;
    final statusColor = tx.status == 'success'
        ? AppColors.primary
        : tx.status == 'pending' ? AppColors.accent : AppColors.danger;

    final shortId = tx.id.length > 12 ? tx.id.substring(0, 12).toUpperCase() : tx.id.toUpperCase();
    final payRef  = tx.razorpayPaymentId;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1520),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [accentColor.withValues(alpha: 0.14), Colors.transparent],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  isAdd ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  color: accentColor, size: 24,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isAdd ? 'Money Added' : 'Withdrawal Request',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_statusIcon(tx.status), color: statusColor, size: 11),
                  const SizedBox(width: 5),
                  Text(tx.status.toUpperCase(),
                      style: TextStyle(
                          color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
          ),

          _DashedLine(),

          // ── Amount ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(children: [
              Text(
                tx.amount.toStringAsFixed(2),
                style: TextStyle(
                  color: accentColor, fontSize: 44,
                  fontWeight: FontWeight.w900, letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAdd
                    ? '${tx.coins} coins added to wallet'
                    : '${tx.coins} coins deducted from wallet',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ]),
          ),

          // ── Fee breakdown ───────────────────────────────────────────────
          if (isAdd && baseAmount != null && gatewayFee != null)
            _FeeSection(rows: [
              _FeeItem('Base Amount',          baseAmount.toStringAsFixed(2),        AppColors.textSecondary),
              _FeeItem('Gateway Fee (${gwFeePct?.toStringAsFixed(1) ?? '?'}%)',
                        '+${gatewayFee.toStringAsFixed(2)}',                         AppColors.textMuted),
              _FeeItem('Total Charged',        tx.amount.toStringAsFixed(2),         AppColors.primary, bold: true),
            ])
          else if (!isAdd && platformFee != null && netAmount != null)
            _FeeSection(rows: [
              _FeeItem('Requested',            tx.amount.toStringAsFixed(2),         AppColors.textSecondary),
              _FeeItem('Platform Fee (${pfFeePct?.toStringAsFixed(1) ?? '?'}%)',
                        '−${platformFee.toStringAsFixed(2)}',                        AppColors.danger),
              _FeeItem('You Will Receive',     netAmount.toStringAsFixed(2),         const Color(0xFF00B0FF), bold: true),
            ]),

          _DashedLine(),

          // ── Transaction details ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(children: [
              _DetailRow('Transaction ID', '#$shortId'),
              const SizedBox(height: 8),
              if (payRef != null) ...[
                _DetailRow('Payment Ref', payRef),
                const SizedBox(height: 8),
              ],
              _DetailRow('Date & Time',
                  DateFormat('dd MMM yyyy, hh:mm a').format(tx.createdAt.toLocal())),
              const SizedBox(height: 8),
              _DetailRow('Method', isAdd ? 'Razorpay' : 'Bank Transfer'),
            ]),
          ),

          // ── Footer ─────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: const Center(
              child: Text(
                'Lakadiya  •  Secure & Verified',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
    'success' => Icons.check_circle_rounded,
    'pending' => Icons.schedule_rounded,
    _ => Icons.cancel_rounded,
  };
}

// ── Fee section ────────────────────────────────────────────────────────────────

class _FeeItem {
  final String label, value;
  final Color color;
  final bool bold;
  const _FeeItem(this.label, this.value, this.color, {this.bold = false});
}

class _FeeSection extends StatelessWidget {
  final List<_FeeItem> rows;
  const _FeeSection({required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      children: rows.asMap().entries.map((e) {
        final isLast = e.key == rows.length - 1;
        return Column(children: [
          if (isLast) ...[
            Divider(color: Colors.white.withValues(alpha: 0.07), height: 14),
          ] else if (e.key > 0)
            const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.value.label,
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: e.value.bold ? 12.5 : 12)),
              Text(e.value.value,
                  style: TextStyle(
                      color: e.value.color,
                      fontSize: e.value.bold ? 13 : 12,
                      fontWeight: e.value.bold ? FontWeight.bold : FontWeight.w500)),
            ],
          ),
        ]);
      }).toList(),
    ),
  );
}

// ── Detail row ─────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(value,
            textAlign: TextAlign.end,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    ],
  );
}

// ── Dashed separator ───────────────────────────────────────────────────────────

class _DashedLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: CustomPaint(
      painter: _DashedPainter(),
      child: const SizedBox(width: double.infinity, height: 1),
    ),
  );
}

class _DashedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), paint);
      x += 12;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Action button ──────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon, required this.label,
    required this.loading, required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: loading ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: loading
            ? SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 14)),
              ]),
      ),
    ),
  );
}
