import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lakadiya/core/services/api_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../bloc/payment_bloc.dart';
import '../../data/models/payment_model.dart';

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  final _amountCtl = TextEditingController();
  WalletBalance? _balance;
  List<Transaction> _withdrawals = [];
  bool _loadingWithdrawals = false;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _fetchData();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _amountCtl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() {
    context.read<PaymentBloc>().add(const FetchWalletBalanceEvent());
    return _fetchWithdrawals();
  }

  Future<void> _fetchWithdrawals() async {
    try {
      setState(() => _loadingWithdrawals = true);
      final apiService = ApiService();
      final response = await apiService.get('/payments/withdrawals');
      final withdrawals = (response.data as List)
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _withdrawals = withdrawals;
          _loadingWithdrawals = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingWithdrawals = false);
        _snack('Error loading withdrawals: $e', AppColors.danger);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  void _requestWithdrawal() {
    final amount = double.tryParse(_amountCtl.text);
    if (amount == null || amount <= 0) {
      _snack('Enter a valid amount', AppColors.danger);
      return;
    }
    if (_balance != null && amount > _balance!.currentBalance) {
      _snack('Insufficient balance', AppColors.danger);
      return;
    }
    context.read<PaymentBloc>().add(RequestWithdrawalEvent(amount));
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
                if (state is WithdrawalRequested) {
                  _snack(state.message, AppColors.primary);
                  _amountCtl.clear();
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) _fetchData();
                  });
                } else if (state is PaymentError) {
                  _snack(state.message, AppColors.danger);
                }
              },
              child: BlocBuilder<PaymentBloc, PaymentState>(
                builder: (_, state) {
                  if (state is WalletBalanceFetched) _balance = state.balance;
                  final loading = state is PaymentLoading;

                  return Column(
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.darkCard,
                          onRefresh: _fetchData,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildBalanceCard(),
                                const SizedBox(height: 20),
                                _buildSectionLabel(Icons.edit_rounded, 'Withdrawal Amount'),
                                const SizedBox(height: 12),
                                _buildAmountField(loading),
                                const SizedBox(height: 16),
                                _buildInfoBanner(),
                                const SizedBox(height: 20),
                                _buildWithdrawButton(loading),
                                const SizedBox(height: 28),
                                _buildSectionLabel(Icons.receipt_long_rounded, 'Withdrawal Requests'),
                                const SizedBox(height: 12),
                                _buildHistorySection(),
                              ],
                            ),
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
          colors: [AppColors.accent, AppColors.accentDark],
        ).createShader(b),
        child: const Text('Withdraw',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ),
    ]),
  );

  Widget _buildBalanceCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.accent.withValues(alpha: 0.12),
          const Color(0xFF091E30),
          const Color(0xFF0A1520),
        ],
      ),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      boxShadow: [BoxShadow(
        color: AppColors.accent.withValues(alpha: 0.1),
        blurRadius: 20, offset: const Offset(0, 6),
      )],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.account_balance_wallet_rounded,
            color: AppColors.accent, size: 22),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Available Balance',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        if (_balance != null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _balance!.currentBalance),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (_, v, __) => Text(
              '₹${v.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.accent, fontSize: 26, fontWeight: FontWeight.w900),
            ),
          )
        else
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.accent),
          ),
      ]),
      const Spacer(),
      if (_balance != null)
        GestureDetector(
          onTap: () => _amountCtl.text = _balance!.currentBalance.toStringAsFixed(2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.accent.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: const Text('Max',
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
    ]),
  );

  Widget _buildSectionLabel(IconData icon, String title) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: AppColors.accent, size: 15),
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(
        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
  ]);

  Widget _buildAmountField(bool loading) => TextField(
    controller: _amountCtl,
    keyboardType: TextInputType.number,
    enabled: !loading,
    onChanged: (_) => setState(() {}),
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

  Widget _buildInfoBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(
        colors: [AppColors.accent.withValues(alpha: 0.08), AppColors.accent.withValues(alpha: 0.03)],
      ),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.schedule_rounded, color: AppColors.accent, size: 16),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'Requests are reviewed within 24–48 hours and transferred to your registered bank account.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    ]),
  );

  Widget _buildWithdrawButton(bool loading) {
    final amt = double.tryParse(_amountCtl.text) ?? 0;
    final valid = amt > 0 && (_balance == null || amt <= _balance!.currentBalance);
    return GestureDetector(
      onTap: (loading || !valid) ? null : _requestWithdrawal,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: (loading || !valid)
              ? const LinearGradient(colors: [AppColors.textMuted, AppColors.textMuted])
              : const LinearGradient(
                  colors: [Color(0xFF00B0FF), Color(0xFF0088CC), Color(0xFF005A99)]),
          boxShadow: (loading || !valid)
              ? null
              : [BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  blurRadius: 14, offset: const Offset(0, 5),
                )],
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    valid ? 'Withdraw ₹${amt.toStringAsFixed(0)}' : 'Enter Amount',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_loadingWithdrawals) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    if (_withdrawals.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFF0E1A2E), Color(0xFF0A1422)]),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: const Center(child: Column(children: [
          Text('💸', style: TextStyle(fontSize: 32)),
          SizedBox(height: 10),
          Text('No withdrawal requests yet',
              style: TextStyle(color: AppColors.textSecondary)),
        ])),
      );
    }
    return Column(
      children: List.generate(_withdrawals.length, (i) =>
        _WithdrawalTile(tx: _withdrawals[i], index: i)),
    );
  }
}

// ── Withdrawal history tile ────────────────────────────────────────────────────
class _WithdrawalTile extends StatelessWidget {
  final Transaction tx;
  final int index;
  const _WithdrawalTile({required this.tx, required this.index});

  @override
  Widget build(BuildContext context) {
    final statusColor = tx.status == 'success'
        ? AppColors.primary
        : tx.status == 'pending' ? AppColors.accent : AppColors.danger;
    final statusIcon = tx.status == 'success'
        ? Icons.check_circle_rounded
        : tx.status == 'pending' ? Icons.schedule_rounded : Icons.cancel_rounded;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 200 + index * 50),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [AppColors.danger.withValues(alpha: 0.07), const Color(0xFF0A1422)],
          ),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.arrow_upward_rounded,
                color: AppColors.danger, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Withdrew ₹${tx.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(DateFormat('MMM dd, yyyy  HH:mm').format(tx.createdAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('-${tx.coins} coins',
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withValues(alpha: 0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, color: statusColor, size: 10),
                const SizedBox(width: 3),
                Text(tx.status,
                    style: TextStyle(
                        color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Animated gradient background ───────────────────────────────────────────────
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
                AppColors.accent.withValues(alpha: 0.06 + t * 0.05),
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
                AppColors.primary.withValues(alpha: 0.04 + t * 0.04),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ]);
    },
  );
}
