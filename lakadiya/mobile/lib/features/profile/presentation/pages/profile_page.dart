import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/auth_guard.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../payments/presentation/bloc/payment_bloc.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  // Complete Profile form
  bool _editingProfile = false;
  bool _savingProfile  = false;
  final _editUsernameCtl = TextEditingController();
  final _editEmailCtl    = TextEditingController();

  late final AnimationController _enterCtrl;
  late final AnimationController _avatarCtrl;
  late final AnimationController _xpCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _avatarScale;
  late final Animation<double> _avatarGlow;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _avatarCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
    _xpCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _fadeIn = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _avatarScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.08), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut));
    _avatarGlow = CurvedAnimation(parent: _avatarCtrl, curve: Curves.easeInOut);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        context.read<PaymentBloc>().add(const FetchWalletBalanceEvent());
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _avatarCtrl.dispose();
    _xpCtrl.dispose();
    _editUsernameCtl.dispose();
    _editEmailCtl.dispose();
    super.dispose();
  }

  bool get _needsCompletion {
    if (_profile == null) return false;
    final username = _profile!['username'] as String? ?? '';
    final email    = _profile!['email']    as String?;
    // Auto-generated usernames match e.g. "RoyalPlayer1234"
    final isAuto = RegExp(r'^[A-Za-z]+\d{4}$').hasMatch(username);
    return isAuto || (email == null || email.isEmpty);
  }

  Future<void> _saveProfile() async {
    final username = _editUsernameCtl.text.trim();
    final email    = _editEmailCtl.text.trim();
    if (username.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Username must be at least 3 characters'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _savingProfile = true);
    try {
      final api = ApiService();
      await api.patch('/users/me', data: {
        'username': username,
        if (email.isNotEmpty) 'email': email,
      });
      setState(() {
        _profile!['username'] = username;
        if (email.isNotEmpty) _profile!['email'] = email;
        _editingProfile = false;
        _savingProfile  = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (_) {
      setState(() => _savingProfile = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update profile'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  num _n(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;

  double get _xpPct {
    if (_profile == null) return 0;
    final xp = _n(_profile!['xp']).toDouble();
    final level = _n(_profile!['level']).toInt().clamp(1, 100);
    final threshold = level * 500.0;
    return ((xp % threshold) / threshold).clamp(0.0, 1.0);
  }

  Future<void> _load() async {
    try {
      final api = ApiService();
      final res = await api.get('/users/me');
      final history =
          await api.get('/users/me/matches', params: {'limit': '10'});
      if (mounted) {
        setState(() {
          _profile = Map<String, dynamic>.from(res.data as Map);
          _history = (history.data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
        _enterCtrl.forward();
        _xpCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentBloc, PaymentState>(
      listenWhen: (_, s) => s is WalletBalanceFetched,
      listener: (_, state) {
        if (state is WalletBalanceFetched && _profile != null) {
          setState(() => _profile!['coins'] = state.balance.coins);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            _ProfileBg(anim: _avatarGlow),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary))
                        : _profile == null
                            ? const Center(
                                child: Text('Could not load profile',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)))
                            : FadeTransition(
                                opacity: _fadeIn,
                                child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildHero(),
                                      if (_needsCompletion) ...[
                                        const SizedBox(height: 16),
                                        _buildCompleteProfile(),
                                      ],
                                      const SizedBox(height: 16),
                                      _buildStats(),
                                      const SizedBox(height: 16),
                                      _buildWallet(),
                                      const SizedBox(height: 16),
                                      _buildHistory(),
                                      const SizedBox(height: 24),
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.go('/lobby'),
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
                colors: [AppColors.textPrimary, AppColors.textSecondary],
              ).createShader(b),
              child: const Text('Profile',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textSecondary),
              color: AppColors.darkCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'logout')
                  context.read<AuthBloc>().add(AuthLogoutRequested());
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout_rounded,
                        color: AppColors.danger, size: 18),
                    SizedBox(width: 10),
                    Text('Logout', style: TextStyle(color: AppColors.danger)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildHero() {
    final p = _profile!;
    final username = p['username'] as String? ?? 'Player';
    final email = p['email'] as String?;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'P';
    final level = _n(p['level']).toInt();
    final coins = _n(p['coins']).toInt();
    final xp = _n(p['xp']).toInt();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2818), Color(0xFF0A1A30)],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 28,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          // Suit decoration row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _SuitDot('♠', Colors.white70),
              SizedBox(width: 10),
              _SuitDot('♥', AppColors.suitRed),
              SizedBox(width: 10),
              _SuitDot('♦', AppColors.suitRed),
              SizedBox(width: 10),
              _SuitDot('♣', Colors.white70),
            ],
          ),
          const SizedBox(height: 16),

          // Avatar with animated glow ring
          AnimatedBuilder(
            animation: _avatarGlow,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary
                        .withValues(alpha: 0.2 + _avatarGlow.value * 0.3),
                    blurRadius: 22 + _avatarGlow.value * 16,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: ScaleTransition(
                scale: _avatarScale,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    border: Border.all(
                      color: AppColors.primary
                          .withValues(alpha: 0.4 + _avatarGlow.value * 0.4),
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Text(username,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 0.3)),
          if (email != null) ...[
            const SizedBox(height: 3),
            Text(email,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 20),

          // Level / Coins / XP
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip('⚡', 'Level', '$level', AppColors.accent),
              _StatChip('💰', 'Coins', '$coins', AppColors.primary),
              _StatChip('✨', 'XP', '$xp', AppColors.trump),
            ],
          ),
          const SizedBox(height: 20),

          // XP progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Level $level',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                  AnimatedBuilder(
                    animation: _xpCtrl,
                    builder: (_, __) {
                      final pct =
                          Curves.easeOutCubic.transform(_xpCtrl.value) * _xpPct;
                      return Text(
                          '${(pct * 100).toStringAsFixed(0)}%  →  Level ${level + 1}',
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.darkBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _xpCtrl,
                    builder: (_, __) {
                      final pct =
                          Curves.easeOutCubic.transform(_xpCtrl.value) * _xpPct;
                      return FractionallySizedBox(
                        widthFactor: pct.clamp(0.01, 1.0),
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.primaryDark,
                                AppColors.primary,
                                AppColors.primaryLight
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.6),
                                blurRadius: 6,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteProfile() {
    final currentUsername = _profile!['username'] as String? ?? '';
    final isAuto = RegExp(r'^[A-Za-z]+\d{4}$').hasMatch(currentUsername);
    if (!_editingProfile) {
      _editUsernameCtl.text = isAuto ? '' : currentUsername;
      _editEmailCtl.text    = _profile!['email'] as String? ?? '';
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1200), Color(0xFF2A1F00)],
        ),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.08),
            blurRadius: 16, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_rounded, color: Color(0xFFFFD700), size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Complete Your Profile',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Text('Set a username and email to personalise your account',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _editingProfile = !_editingProfile),
              child: Icon(
                _editingProfile ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: AppColors.textMuted,
              ),
            ),
          ]),
          if (_editingProfile) ...[
            const SizedBox(height: 16),
            // Username field
            TextField(
              controller: _editUsernameCtl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'Enter a username (min 3 chars)',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.person_rounded, color: AppColors.textMuted, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            // Email field
            TextField(
              controller: _editEmailCtl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Email (optional)',
                hintText: 'you@example.com',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.email_rounded, color: AppColors.textMuted, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _savingProfile ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _savingProfile
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                    : const Text('Save Profile',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats() {
    final p = _profile!;
    final played = _n(p['matches_played']).toInt();
    final won = _n(p['matches_won']).toInt();
    final rate = played > 0 ? (won / played * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1A2E), Color(0xFF0A1422)],
        ),
        border: Border.all(color: AppColors.darkBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Statistics',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
            ],
          ),
          const SizedBox(height: 18),

          // Big 3 stats
          Row(
            children: [
              Expanded(
                  child: _BigStat('Played', '$played', AppColors.textPrimary)),
              Container(width: 1, height: 40, color: AppColors.darkBorder),
              Expanded(child: _BigStat('Won', '$won', AppColors.primary)),
              Container(width: 1, height: 40, color: AppColors.darkBorder),
              Expanded(
                  child: _BigStat(
                      'Win%', '${rate.toStringAsFixed(1)}%', AppColors.accent)),
            ],
          ),
          const SizedBox(height: 16),

          // Win rate bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Win Rate',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  Text('${rate.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: rate / 100),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Stack(
                  children: [
                    Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.darkBorder,
                          borderRadius: BorderRadius.circular(3),
                        )),
                    FractionallySizedBox(
                      widthFactor: v.clamp(0.0, 1.0),
                      child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: const LinearGradient(
                              colors: [AppColors.primaryDark, AppColors.accent],
                            ),
                          )),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Divider(color: AppColors.darkBorder.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          _statRow(Icons.scoreboard_rounded, 'Total Score',
              _n(p['total_score']).toStringAsFixed(1), AppColors.primaryLight),
          _statRow(Icons.check_circle_rounded, 'Exact Bids',
              '${_n(p['bids_exact']).toInt()}', AppColors.primary),
          _statRow(Icons.cancel_rounded, 'Failed Bids',
              '${_n(p['bids_failed']).toInt()}', AppColors.danger),
        ],
      ),
    );
  }

  Widget _buildWallet() {
    final coins = _n(_profile!['coins']).toInt();
    final balance = coins.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1A2E), Color(0xFF0A1422)],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Wallet',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.monetization_on_rounded,
                      color: AppColors.primary, size: 13),
                  const SizedBox(width: 5),
                  Text('$coins',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Balance card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.14),
                  AppColors.primary.withValues(alpha: 0.05),
                ],
              ),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Available Balance',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: balance),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => Text(
                      '₹${v.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ]),
                const Spacer(),
                const Text('💰', style: TextStyle(fontSize: 34)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Add / Withdraw buttons
          Row(children: [
            Expanded(
                child: _WalletBtn(
              label: 'Add Money',
              icon: Icons.arrow_downward_rounded,
              colors: const [
                Color(0xFF00E676),
                Color(0xFF00C853),
                Color(0xFF007E33)
              ],
              onTap: () =>
                  requireAuth(context, () => context.push('/add-money')),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _WalletBtn(
              label: 'Withdraw',
              icon: Icons.arrow_upward_rounded,
              colors: const [AppColors.accent, AppColors.accentDark],
              onTap: () =>
                  requireAuth(context, () => context.push('/withdraw')),
            )),
          ]),
          const SizedBox(height: 10),

          // History button
          GestureDetector(
            onTap: () => requireAuth(context, () => context.push('/wallet')),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.darkCard,
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded,
                      color: AppColors.textSecondary, size: 16),
                  SizedBox(width: 8),
                  Text('Transaction History',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14))),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );

  Widget _buildHistory() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Match History',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
            ],
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E1A2E), Color(0xFF0A1422)],
                ),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Text('🃏', style: TextStyle(fontSize: 36)),
                    SizedBox(height: 10),
                    Text('No matches yet',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_history.length, (i) {
              final m = _history[i];
              final won = m['winner_id'] != null;
              final score = _n(m['my_score']);
              final color = won ? AppColors.primary : AppColors.danger;

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 200 + i * 60),
                builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                      offset: Offset(0, 12 * (1 - v)), child: child),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        color.withValues(alpha: 0.06),
                        const Color(0xFF0A1422),
                      ],
                    ),
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.12),
                          border:
                              Border.all(color: color.withValues(alpha: 0.35)),
                        ),
                        child: Center(
                          child: Text(won ? '🏆' : '💀',
                              style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(won ? 'Victory' : 'Defeat',
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text('${m['round_count'] ?? 5} rounds',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            score >= 0
                                ? '+${score.toStringAsFixed(1)}'
                                : score.toStringAsFixed(1),
                            style: TextStyle(
                              color: score >= 0
                                  ? AppColors.primaryLight
                                  : AppColors.danger,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const Text('pts',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      );
}

// ── Animated gradient background ──────────────────────────────────────────────
class _ProfileBg extends StatelessWidget {
  final Animation<double> anim;
  const _ProfileBg({required this.anim});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: anim,
        builder: (_, __) {
          final t = anim.value;
          return Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF060C1A),
                      Color(0xFF0B1829),
                      Color(0xFF060E18)
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -80,
                top: -80,
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.primary.withValues(alpha: 0.08 + t * 0.06),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: -60,
                bottom: 180,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.accent.withValues(alpha: 0.04 + t * 0.04),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.trump.withValues(alpha: 0.03 + t * 0.03),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

// ── Suit decoration dot ────────────────────────────────────────────────────────
class _SuitDot extends StatelessWidget {
  final String suit;
  final Color color;
  const _SuitDot(this.suit, this.color);

  @override
  Widget build(BuildContext context) => Text(
        suit,
        style: TextStyle(color: color.withValues(alpha: 0.55), fontSize: 16),
      );
}

// ── Big stat block ─────────────────────────────────────────────────────────────
class _BigStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BigStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (_, v, __) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - v)),
                child: Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      );
}

// ── Stat chip ──────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String emoji, label, value;
  final Color color;
  const _StatChip(this.emoji, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 8,
            )
          ],
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      );
}

// ── Wallet action button ───────────────────────────────────────────────────────
class _WalletBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _WalletBtn(
      {required this.label,
      required this.icon,
      required this.colors,
      required this.onTap});
  @override
  State<_WalletBtn> createState() => _WalletBtnState();
}

class _WalletBtnState extends State<_WalletBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: widget.colors),
              boxShadow: [
                BoxShadow(
                  color: widget.colors[0].withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 17),
                const SizedBox(width: 7),
                Text(widget.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ],
            ),
          ),
        ),
      );
}
