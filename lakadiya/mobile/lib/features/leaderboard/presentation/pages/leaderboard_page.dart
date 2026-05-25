import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});
  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage>
    with TickerProviderStateMixin {
  late final TabController _tabCtl;
  late final AnimationController _bgCtrl;
  final _api = ApiService();
  List<Map<String, dynamic>> _wins   = [];
  List<Map<String, dynamic>> _scores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 2, vsync: this);
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final wins   = await _api.get('/leaderboard', params: {'type': 'wins'});
      final scores = await _api.get('/leaderboard', params: {'type': 'score'});
      if (mounted) {
        setState(() {
          _wins   = (wins.data   as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _scores = (scores.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _LeaderBg(anim: _bgCtrl),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                _buildTabBar(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : TabBarView(
                          controller: _tabCtl,
                          children: [_buildList(_wins), _buildList(_scores)],
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
            colors: [AppColors.accent, AppColors.accentLight],
          ).createShader(b),
          child: const Text('Leaderboard',
              style: TextStyle(color: Colors.white,
                  fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
          ),
          child: const Text('🏆', style: TextStyle(fontSize: 16)),
        ),
      ],
    ),
  );

  Widget _buildTabBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.darkCard.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: TabBar(
        controller: _tabCtl,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          boxShadow: [BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
          )],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: '🏆  Most Wins'),
          Tab(text: '⭐  Top Scores'),
        ],
      ),
    ),
  );

  Widget _buildList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🃏', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('No data yet',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }

    final hasPodium = data.length >= 3;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: data.length + (hasPodium ? 1 : 0),
      itemBuilder: (_, i) {
        if (hasPodium && i == 0) return _buildPodium(data);
        final idx = hasPodium ? i - 1 : i;
        return _AnimatedLeaderRow(entry: data[idx], index: idx);
      },
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> data) {
    int toInt(dynamic v, int d) => (num.tryParse(v?.toString() ?? '') ?? d).toInt();

    const gold   = Color(0xFFFFD600);
    const silver = Color(0xFFB0BEC5);
    const bronze = Color(0xFFCD7F32);

    Widget column(Map<String, dynamic> entry, int pos, double h, Color c, String medal) {
      final name    = entry['username'] as String? ?? '?';
      final initial = name[0].toUpperCase();
      final wins    = toInt(entry['matches_won'], 0);
      final score   = num.tryParse(entry['total_score']?.toString() ?? '') ?? 0;

      return Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 400 + pos * 100),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(
            scale: v, alignment: Alignment.bottomCenter, child: child,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Avatar
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [c, c.withValues(alpha: 0.7)],
                  ),
                  boxShadow: [BoxShadow(
                    color: c.withValues(alpha: 0.4),
                    blurRadius: 12, spreadRadius: 1,
                  )],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 2),
                ),
                child: Center(
                  child: Text(initial,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 20)),
                ),
              ),
              const SizedBox(height: 4),
              Text(medal, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(
                name.length > 9 ? '${name.substring(0, 9)}…' : name,
                style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              Text('$wins W  •  ${score.toStringAsFixed(0)} pts',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              const SizedBox(height: 6),
              // Podium block
              Container(
                height: h,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.withValues(alpha: 0.35), c.withValues(alpha: 0.1)],
                  ),
                  border: Border.all(color: c.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text('#${pos + 1}',
                      style: TextStyle(color: c,
                          fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1E34), Color(0xFF080F1A)],
        ),
        border: Border.all(color: AppColors.darkBorder),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 16, offset: const Offset(0, 4),
        )],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          column(data[1], 1, 60, silver, '🥈'),
          column(data[0], 0, 90, gold,   '🥇'),
          column(data[2], 2, 45, bronze, '🥉'),
        ],
      ),
    );
  }
}

// ── Background ─────────────────────────────────────────────────────────────────
class _LeaderBg extends StatelessWidget {
  final Animation<double> anim;
  const _LeaderBg({required this.anim});

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
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF060C1A), Color(0xFF0B1829), Color(0xFF060E18)],
              ),
            ),
          ),
          Positioned(
            right: -60, top: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.accent.withValues(alpha: 0.07 + t * 0.05),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            left: -80, bottom: 150,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.05 + t * 0.04),
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

// ── Leaderboard row ────────────────────────────────────────────────────────────
class _AnimatedLeaderRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int index;
  const _AnimatedLeaderRow({required this.entry, required this.index});

  static const _podiumColors = [Color(0xFFFFD600), Color(0xFFB0BEC5), Color(0xFFCD7F32)];
  static const _medals       = ['🥇', '🥈', '🥉'];

  Color get _rankColor => index < 3 ? _podiumColors[index] : AppColors.textMuted;
  bool  get _isPodium  => index < 3;

  @override
  Widget build(BuildContext context) {
    int toInt(dynamic v, int d) => (num.tryParse(v?.toString() ?? '') ?? d).toInt();

    final rank     = toInt(entry['rank'], index + 1);
    final username = entry['username'] as String? ?? '?';
    final wins     = toInt(entry['matches_won'], 0);
    final score    = num.tryParse(entry['total_score']?.toString() ?? '') ?? 0;
    final level    = toInt(entry['level'], 1);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + index * 55),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(30 * (1 - v), 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _isPodium
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _rankColor.withValues(alpha: 0.1),
                    const Color(0xFF0A1422),
                  ],
                )
              : const LinearGradient(
                  colors: [Color(0xFF0E1624), Color(0xFF0A1422)],
                ),
          border: Border.all(
            color: _isPodium
                ? _rankColor.withValues(alpha: 0.3)
                : AppColors.darkBorder,
          ),
          boxShadow: _isPodium
              ? [BoxShadow(
                  color: _rankColor.withValues(alpha: 0.08),
                  blurRadius: 10, offset: const Offset(0, 3),
                )]
              : [const BoxShadow(
                  color: Colors.black26, blurRadius: 4, offset: Offset(0, 2),
                )],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: SizedBox(
            width: 40,
            child: _isPodium
                ? Text(_medals[index],
                    style: const TextStyle(fontSize: 26),
                    textAlign: TextAlign.center)
                : Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.darkCard,
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Center(
                      child: Text('#$rank',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
          ),
          title: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isPodium
                        ? [_rankColor, _rankColor.withValues(alpha: 0.6)]
                        : [AppColors.primary, AppColors.primaryDark],
                  ),
                  boxShadow: _isPodium
                      ? [BoxShadow(
                          color: _rankColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                        )]
                      : null,
                ),
                child: Center(
                  child: Text(username[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username,
                        style: TextStyle(
                          color: _isPodium ? _rankColor : AppColors.textPrimary,
                          fontWeight: FontWeight.bold, fontSize: 14,
                        )),
                    Text('Level $level',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$wins wins',
                  style: TextStyle(
                    color: _isPodium ? _rankColor : AppColors.primaryLight,
                    fontWeight: FontWeight.bold, fontSize: 14,
                  )),
              Text('${score.toStringAsFixed(1)} pts',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
