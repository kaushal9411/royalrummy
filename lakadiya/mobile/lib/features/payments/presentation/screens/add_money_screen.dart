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

  static final Map<double, String?> _cardLabels = {
    100.0: null,
    200.0: null,
    500.0: 'Popular',
    1000.0: 'Best Value',
    2000.0: null,
    5000.0: null,
  };

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

  void _showPaymentModal(double amount) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Payment',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogCtx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: _FloatingPaymentCard(
            amount: amount,
            onConfirm: () {
              Navigator.pop(dialogCtx);
              _initiatePayment(amount);
            },
            onCancel: () => Navigator.pop(dialogCtx),
          ),
        ),
      ),
      transitionBuilder: (_, anim, __, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
    );
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
                  final router = GoRouter.of(context);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) router.pop();
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
                              const SizedBox(height: 14),
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
    mainAxisSpacing: 14,
    crossAxisSpacing: 12,
    childAspectRatio: 1.15,
    children: _quickAmounts.map((amt) => _buildPremiumCard(amt, loading)).toList(),
  );

  Widget _buildPremiumCard(double amt, bool loading) {
    final selected = _selectedQuick == amt;
    final label = _cardLabels[amt];
    final coins = (amt * 10).toInt();

    return GestureDetector(
      onTap: loading ? null : () => setState(() {
        _selectedQuick = amt;
        _amountCtl.text = amt.toInt().toString();
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF00E676), Color(0xFF00C853), Color(0xFF007E33)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF18293D), Color(0xFF0D1B2A)],
                    ),
              border: Border.all(
                color: selected
                    ? const Color(0xFF00E676).withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.08),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.38),
                        blurRadius: 18,
                        spreadRadius: 0,
                        offset: const Offset(0, 7),
                      ),
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.14),
                        blurRadius: 32,
                        spreadRadius: 6,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Top row: icon + checkmark
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected)
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 13)
                      else
                        Icon(Icons.account_balance_wallet_outlined,
                            color: Colors.white.withValues(alpha: 0.3), size: 13),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Amount
                  ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: selected
                          ? [Colors.white, Colors.white.withValues(alpha: 0.9)]
                          : [const Color(0xFFDDE6F0), const Color(0xFF8FA8C0)],
                    ).createShader(b),
                    child: Text(
                      '₹${amt.toInt()}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: amt >= 2000 ? 16 : 19,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Coins row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🪙', style: TextStyle(fontSize: selected ? 10 : 9)),
                      const SizedBox(width: 3),
                      Text(
                        coins >= 10000
                            ? '${(coins / 1000).toStringAsFixed(0)}K'
                            : '$coins',
                        style: TextStyle(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Badge
          if (label != null)
            Positioned(
              top: -9,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
      onTap: (loading || !valid) ? null : () => _showPaymentModal(amt),
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

// ── Floating payment confirmation modal ───────────────────────────────────────
class _FloatingPaymentCard extends StatelessWidget {
  final double amount;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _FloatingPaymentCard({
    required this.amount,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final coins = (amount * 10).toInt();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 48,
            spreadRadius: 0,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 70,
            spreadRadius: 12,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.lock_rounded,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Secure Payment',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text('Powered by Razorpay',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ]),
              const Spacer(),
              GestureDetector(
                onTap: onCancel,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 18),
                ),
              ),
            ]),
          ),
          Divider(
              color: Colors.white.withValues(alpha: 0.06), height: 1, thickness: 1),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(children: [
              // Amount display
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00C853)],
                ).createShader(b),
                child: Text(
                  '₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Coins
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🪙', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(
                    '+$coins coins will be added',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              // Payment methods
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PayMethod(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'UPI'),
                      _MethodDivider(),
                      _PayMethod(
                          icon: Icons.credit_card_rounded, label: 'Card'),
                      _MethodDivider(),
                      _PayMethod(
                          icon: Icons.account_balance_rounded, label: 'Bank'),
                    ]),
              ),
              const SizedBox(height: 22),
              // CTA button
              GestureDetector(
                onTap: onConfirm,
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF00E676),
                        Color(0xFF00C853),
                        Color(0xFF007E33)
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.42),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.18),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Pay ₹${amount.toStringAsFixed(0)} Now',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onCancel,
                child: const Text('Cancel',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 13)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PayMethod extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PayMethod({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 15),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      );
}

class _MethodDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        color: Colors.white.withValues(alpha: 0.1),
      );
}

// ── Shared gradient background ────────────────────────────────────────────────
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
