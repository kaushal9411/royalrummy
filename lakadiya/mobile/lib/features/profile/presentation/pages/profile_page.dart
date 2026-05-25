import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  late final AnimationController _enterCtrl;
  late final AnimationController _avatarCtrl;
  late final Animation<double>   _fadeIn;
  late final Animation<double>   _avatarScale;
  late final Animation<double>   _avatarGlow;

  @override
  void initState() {
    super.initState();
    _enterCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _avatarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _fadeIn      = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _avatarScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.08), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0),  weight: 40),
    ]).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut));
    _avatarGlow  = CurvedAnimation(parent: _avatarCtrl, curve: Curves.easeInOut);

    _load();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _avatarCtrl.dispose();
    super.dispose();
  }

  num _n(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;

  Future<void> _load() async {
    try {
      final api     = ApiService();
      final res     = await api.get('/users/me');
      final history = await api.get('/users/me/matches', params: {'limit': '10'});
      if (mounted) {
        setState(() {
          _profile = Map<String, dynamic>.from(res.data as Map);
          _history = (history.data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
        _enterCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => context.go('/lobby'),
        ),
        title: const Text('Profile',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
            color: AppColors.darkCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'logout') context.read<AuthBloc>().add(AuthLogoutRequested());
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
                    SizedBox(width: 10),
                    Text('Logout', style: TextStyle(color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _profile == null
              ? const Center(child: Text('Could not load profile',
                  style: TextStyle(color: AppColors.textSecondary)))
              : FadeTransition(
                  opacity: _fadeIn,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHero(),
                        const SizedBox(height: 20),
                        _buildStats(),
                        const SizedBox(height: 20),
                        _buildHistory(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHero() {
    final p        = _profile!;
    final username = p['username'] as String? ?? 'Player';
    final email    = p['email'] as String?;
    final initial  = username.isNotEmpty ? username[0].toUpperCase() : 'P';

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2818), Color(0xFF0A1A30)],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          // Avatar with animated glow
          AnimatedBuilder(
            animation: _avatarGlow,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2 + _avatarGlow.value * 0.3),
                    blurRadius: 20 + _avatarGlow.value * 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ScaleTransition(
                scale: _avatarScale,
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4 + _avatarGlow.value * 0.4),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: Text(initial,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 36, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(username,
              style: const TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 22)),
          if (email != null) ...[
            const SizedBox(height: 4),
            Text(email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 20),

          // Level / Coins / XP chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip('⚡', 'Level', '${_n(p['level']).toInt()}', AppColors.accent),
              _StatChip('💰', 'Coins', '${_n(p['coins']).toInt()}', AppColors.primary),
              _StatChip('✨', 'XP',    '${_n(p['xp']).toInt()}',    AppColors.trump),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final p      = _profile!;
    final played = _n(p['matches_played']).toInt();
    final won    = _n(p['matches_won']).toInt();
    final rate   = played > 0 ? (won / played * 100).toStringAsFixed(1) : '0';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text('Statistics', style: TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _BigStat('Played', '$played', AppColors.textPrimary)),
              Expanded(child: _BigStat('Won', '$won', AppColors.primary)),
              Expanded(child: _BigStat('Win%', '$rate%', AppColors.accent)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.darkBorder),
          const SizedBox(height: 12),
          _statRow(Icons.scoreboard_rounded,     'Total Score', _n(p['total_score']).toStringAsFixed(1),  AppColors.primaryLight),
          _statRow(Icons.check_circle_rounded,   'Exact Bids',  '${_n(p['bids_exact']).toInt()}',         AppColors.primary),
          _statRow(Icons.cancel_rounded,         'Failed Bids', '${_n(p['bids_failed']).toInt()}',         AppColors.danger),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    ),
  );

  Widget _buildHistory() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          Icon(Icons.history_rounded, color: AppColors.accent, size: 20),
          SizedBox(width: 8),
          Text('Match History', style: TextStyle(color: AppColors.textPrimary,
              fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
      const SizedBox(height: 12),
      if (_history.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: const Center(
            child: Column(
              children: [
                Text('🃏', style: TextStyle(fontSize: 36)),
                SizedBox(height: 10),
                Text('No matches yet', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        )
      else
        ...List.generate(_history.length, (i) {
          final m     = _history[i];
          final won   = m['winner_id'] != null;
          final score = _n(m['my_score']);
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 200 + i * 60),
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: won ? AppColors.primary.withValues(alpha: 0.3) : AppColors.darkBorder,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (won ? AppColors.primary : AppColors.danger).withValues(alpha: 0.12),
                      border: Border.all(
                        color: (won ? AppColors.primary : AppColors.danger).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(won ? '🏆' : '💀', style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(won ? 'Victory' : 'Defeat',
                            style: TextStyle(
                              color: won ? AppColors.primary : AppColors.danger,
                              fontWeight: FontWeight.bold,
                            )),
                        Text('${m['round_count'] ?? 5} rounds',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(
                    score >= 0 ? '+${score.toStringAsFixed(1)}' : score.toStringAsFixed(1),
                    style: TextStyle(
                      color: score >= 0 ? AppColors.primaryLight : AppColors.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
}

// ── Big stat block ─────────────────────────────────────────────────────────
class _BigStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BigStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ],
  );
}

// ── Stat chip ──────────────────────────────────────────────────────────────
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
    ),
    child: Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    ),
  );
}
