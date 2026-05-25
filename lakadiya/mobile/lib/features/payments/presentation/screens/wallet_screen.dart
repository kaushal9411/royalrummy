import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_theme.dart';
import '../bloc/payment_bloc.dart';
import '../../data/models/payment_model.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    context.read<PaymentBloc>().add(const FetchWalletBalanceEvent());
    context.read<PaymentBloc>().add(const FetchTransactionHistoryEvent());
  }

  @override
  void dispose() { _bgCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _PayBg(anim: _bgCtrl),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.darkCard,
                    onRefresh: () async {
                      context.read<PaymentBloc>().add(const FetchWalletBalanceEvent());
                      context.read<PaymentBloc>().add(const FetchTransactionHistoryEvent());
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Column(
                        children: [
                          BlocBuilder<PaymentBloc, PaymentState>(
                            builder: (_, state) {
                              if (state is WalletBalanceFetched) {
                                return _buildBalanceCard(state.balance);
                              }
                              if (state is PaymentError) {
                                return _buildErrorCard(state.message);
                              }
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: CircularProgressIndicator(color: AppColors.primary),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          _buildSectionLabel(Icons.receipt_long_rounded, 'Transaction History'),
                          const SizedBox(height: 12),
                          BlocBuilder<PaymentBloc, PaymentState>(
                            builder: (_, state) {
                              if (state is TransactionHistoryFetched) {
                                if (state.transactions.isEmpty) return _buildEmpty('No transactions yet');
                                return Column(
                                  children: List.generate(state.transactions.length, (i) =>
                                    _TransactionTile(tx: state.transactions[i], index: i)),
                                );
                              }
                              if (state is PaymentError) return _buildErrorCard(state.message);
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: CircularProgressIndicator(color: AppColors.primary),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => context.go('/profile'),
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
            colors: [AppColors.primary, AppColors.primaryLight],
          ).createShader(b),
          child: const Text('Wallet',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );

  Widget _buildBalanceCard(WalletBalance balance) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2818), Color(0xFF091E30), Color(0xFF0A1520)],
          stops: [0, 0.5, 1],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.12),
          blurRadius: 24, offset: const Offset(0, 8),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Available Balance',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: balance.currentBalance),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (_, v, __) => Text(
              '₹${v.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.primary, fontSize: 38, fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text('${balance.coins} coins',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 18),
          Row(children: [
            _BalanceStat('Total Added',     '₹${balance.totalAdded.toStringAsFixed(2)}',     AppColors.primary),
            Container(width: 1, height: 36, color: AppColors.darkBorder, margin: const EdgeInsets.symmetric(horizontal: 16)),
            _BalanceStat('Total Withdrawn', '₹${balance.totalWithdrawn.toStringAsFixed(2)}', AppColors.danger),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _PayBtn(
              label: 'Add Money',
              icon: Icons.arrow_downward_rounded,
              colors: const [Color(0xFF00E676), Color(0xFF00C853), Color(0xFF007E33)],
              onTap: () => context.push('/add-money'),
            )),
            const SizedBox(width: 12),
            Expanded(child: _PayBtn(
              label: 'Withdraw',
              icon: Icons.arrow_upward_rounded,
              colors: const [AppColors.accent, AppColors.accentDark],
              onTap: () => context.push('/withdraw'),
            )),
          ]),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(IconData icon, String title) => Row(
    children: [
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
    ],
  );

  Widget _buildEmpty(String msg) => Container(
    padding: const EdgeInsets.symmetric(vertical: 36),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(
          colors: [Color(0xFF0E1A2E), Color(0xFF0A1422)]),
      border: Border.all(color: AppColors.darkBorder),
    ),
    child: Center(child: Column(children: [
      const Text('🧾', style: TextStyle(fontSize: 32)),
      const SizedBox(height: 10),
      Text(msg, style: const TextStyle(color: AppColors.textSecondary)),
    ])),
  );

  Widget _buildErrorCard(String msg) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: AppColors.danger.withValues(alpha: 0.08),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(msg,
          style: const TextStyle(color: AppColors.danger, fontSize: 13))),
    ]),
  );
}

// ── Transaction tile ───────────────────────────────────────────────────────────
class _TransactionTile extends StatelessWidget {
  final Transaction tx;
  final int index;
  const _TransactionTile({required this.tx, required this.index});

  @override
  Widget build(BuildContext context) {
    final isAdd     = tx.type == 'add';
    final color     = isAdd ? AppColors.primary : AppColors.danger;
    final statusColor = tx.status == 'success'
        ? AppColors.primary
        : tx.status == 'pending' ? AppColors.accent : AppColors.danger;
    final statusIcon  = tx.status == 'success'
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
            colors: [color.withValues(alpha: 0.07), const Color(0xFF0A1422)],
          ),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(
              isAdd ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: color, size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${isAdd ? 'Added' : 'Withdrawn'} ₹${tx.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(DateFormat('MMM dd, yyyy  HH:mm').format(tx.createdAt),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${isAdd ? '+' : '-'}${tx.coins} coins',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
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

// ── Balance stat column ────────────────────────────────────────────────────────
class _BalanceStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BalanceStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
    ],
  );
}

// ── Shared payment action button ───────────────────────────────────────────────
class _PayBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _PayBtn({required this.label, required this.icon, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: colors),
        boxShadow: [BoxShadow(
          color: colors[0].withValues(alpha: 0.35),
          blurRadius: 10, offset: const Offset(0, 4),
        )],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    ),
  );
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
          child: Container(
            width: 300, height: 300,
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
          child: Container(
            width: 250, height: 250,
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
