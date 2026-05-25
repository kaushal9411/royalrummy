import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../../../core/theme/app_theme.dart';
import '../bloc/payment_bloc.dart';
import '../../data/models/payment_model.dart';

class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});
  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen>
    with SingleTickerProviderStateMixin {
  late final Razorpay _razorpay;
  late final AnimationController _bgCtrl;
  final _amountCtl = TextEditingController();
  PaymentOrder? _currentOrder;
  double? _selectedQuick;

  static const _quickAmounts = [100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,   _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _razorpay.clear();
    _amountCtl.dispose();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse r) {
    if (_currentOrder == null) {
      _snack('Order details not found', AppColors.danger);
      return;
    }
    final paymentId = r.paymentId ?? '';
    final signature = r.signature ?? '';
    if (paymentId.isEmpty || signature.isEmpty) {
      _snack('Payment details incomplete', AppColors.danger);
      return;
    }
    context.read<PaymentBloc>().add(VerifyPaymentEvent(
      paymentId: paymentId,
      orderId:   _currentOrder!.orderId,
      signature: signature,
    ));
  }

  void _handlePaymentError(PaymentFailureResponse r) =>
      _snack('Payment failed: ${r.message}', AppColors.danger);

  void _handleExternalWallet(ExternalWalletResponse r) =>
      _snack('Wallet: ${r.walletName}', AppColors.accent);

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  void _initiatePayment(double amount) {
    if (amount <= 0) { _snack('Enter a valid amount', AppColors.danger); return; }
    context.read<PaymentBloc>().add(InitiatePaymentEvent(amount));
  }

  void _openRazorpay(PaymentOrder order) {
    _razorpay.open({
      'key':         'rzp_test_SrD9RqGOrFNN3c',
      'order_id':    order.orderId,
      'amount':      order.amount,
      'currency':    order.currency,
      'name':        'Lakadiya',
      'description': 'Add Money to Wallet',
      'timeout':     300,
      'prefill':     {'contact': '', 'email': ''},
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _PayBg(anim: _bgCtrl),
          SafeArea(
            child: BlocListener<PaymentBloc, PaymentState>(
              listener: (_, state) {
                if (state is PaymentOrderCreated) {
                  _currentOrder = state.order;
                  _openRazorpay(state.order);
                } else if (state is PaymentVerified) {
                  _snack(
                    '₹${state.verification.amount} added! (+${state.verification.coins} coins)',
                    AppColors.primary,
                  );
                  _amountCtl.clear();
                  setState(() => _selectedQuick = null);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) context.pop();
                  });
                } else if (state is PaymentError) {
                  _snack(state.message, AppColors.danger);
                }
              },
              child: BlocBuilder<PaymentBloc, PaymentState>(
                builder: (_, state) {
                  final loading = state is PaymentLoading;
                  return Column(
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoBanner(),
                              const SizedBox(height: 20),
                              _buildSectionLabel(Icons.bolt_rounded, 'Quick Select'),
                              const SizedBox(height: 12),
                              _buildQuickGrid(loading),
                              const SizedBox(height: 22),
                              _buildSectionLabel(Icons.edit_rounded, 'Custom Amount'),
                              const SizedBox(height: 12),
                              _buildAmountField(loading),
                              const SizedBox(height: 20),
                              _buildPayButton(loading),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(children: [
      GestureDetector(
        onTap: () => context.pop(),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.darkCard.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppColors.textPrimary),
        ),
      ),
      const SizedBox(width: 14),
      ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFF00E676), AppColors.primary],
        ).createShader(b),
        child: const Text('Add Money',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ),
    ]),
  );

  Widget _buildInfoBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(
        colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.primary.withValues(alpha: 0.04)],
      ),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 16),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          '₹1 = 10 coins  •  Powered by Razorpay  •  Secure & Instant',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    ]),
  );

  Widget _buildSectionLabel(IconData icon, String title) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: AppColors.primary, size: 15),
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(
        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
  ]);

  Widget _buildQuickGrid(bool loading) => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: 1.5,
    children: _quickAmounts.map((amt) {
      final selected = _selectedQuick == amt;
      return GestureDetector(
        onTap: loading ? null : () {
          setState(() {
            _selectedQuick = amt;
            _amountCtl.text = amt.toInt().toString();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF00C853), Color(0xFF007E33)])
                : LinearGradient(colors: [
                    AppColors.primary.withValues(alpha: 0.1),
                    const Color(0xFF0A1422),
                  ]),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.darkBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 10, offset: const Offset(0, 4),
                  )]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('₹${amt.toInt()}',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w900, fontSize: 17,
                  )),
              const SizedBox(height: 2),
              Text('${(amt * 10).toInt()} coins',
                  style: TextStyle(
                    color: selected ? Colors.white70 : AppColors.textMuted,
                    fontSize: 11,
                  )),
            ],
          ),
        ),
      );
    }).toList(),
  );

  Widget _buildAmountField(bool loading) => TextField(
    controller: _amountCtl,
    keyboardType: TextInputType.number,
    enabled: !loading,
    onChanged: (_) => setState(() => _selectedQuick = null),
    style: const TextStyle(
        color: AppColors.accent, fontWeight: FontWeight.bold,
        fontSize: 22, letterSpacing: 2),
    decoration: InputDecoration(
      hintText: '0',
      hintStyle: TextStyle(
          color: AppColors.textMuted.withValues(alpha: 0.5),
          fontSize: 22, letterSpacing: 2),
      prefixText: '₹  ',
      prefixStyle: const TextStyle(
          color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 18),
      filled: true,
      fillColor: AppColors.darkCard.withValues(alpha: 0.7),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
  );

  Widget _buildPayButton(bool loading) {
    final amt = double.tryParse(_amountCtl.text) ?? 0;
    final valid = amt > 0;
    return GestureDetector(
      onTap: (loading || !valid) ? null : () {
        final a = double.tryParse(_amountCtl.text);
        if (a == null || a <= 0) { _snack('Enter a valid amount', AppColors.danger); return; }
        _initiatePayment(a);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: (loading || !valid)
              ? const LinearGradient(colors: [AppColors.textMuted, AppColors.textMuted])
              : const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00C853), Color(0xFF007E33)]),
          boxShadow: (loading || !valid) ? null : [BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 14, offset: const Offset(0, 5),
          )],
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    valid ? 'Pay ₹${amt.toStringAsFixed(0)} Securely' : 'Enter Amount',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ]),
        ),
      ),
    );
  }
}

// ── Shared gradient background (reused across all payment screens) ─────────────
class _PayBg extends StatelessWidget {
  final Animation<double> anim;
  const _PayBg({required this.anim});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: anim,
    builder: (_, __) {
      final t = anim.value;
      return Stack(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF060C1A), Color(0xFF0B1829), Color(0xFF060E18)],
            ),
          ),
        ),
        Positioned(right: -80, top: -80,
          child: Container(width: 300, height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.07 + t * 0.05),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        Positioned(left: -60, bottom: 150,
          child: Container(width: 250, height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.accent.withValues(alpha: 0.04 + t * 0.04),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ]);
    },
  );
}
