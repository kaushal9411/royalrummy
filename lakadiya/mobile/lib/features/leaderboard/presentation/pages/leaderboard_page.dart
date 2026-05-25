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
    with SingleTickerProviderStateMixin {
  late TabController _tabCtl;
  final _api = ApiService();
  List<Map<String, dynamic>> _wins   = [];
  List<Map<String, dynamic>> _scores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtl.dispose(); super.dispose(); }

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
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => context.go('/lobby'),
        ),
        title: const Text('Leaderboard',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabCtl,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: '🏆  Most Wins'),
                Tab(text: '⭐  Top Scores'),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabCtl,
              children: [_buildList(_wins), _buildList(_scores)],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🃏', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('No data yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: data.length,
      itemBuilder: (_, i) => _AnimatedLeaderRow(entry: data[i], index: i),
    );
  }
}

class _AnimatedLeaderRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int index;
  const _AnimatedLeaderRow({required this.entry, required this.index});

  static const _podiumColors = [Color(0xFFFFD600), Color(0xFFB0BEC5), Color(0xFFCD7F32)];
  static const _medals = ['🥇', '🥈', '🥉'];

  Color get _rankColor => index < 3 ? _podiumColors[index] : AppColors.textMuted;
  bool get _isPodium   => index < 3;

  @override
  Widget build(BuildContext context) {
    int    toInt(dynamic v, int d) => (num.tryParse(v?.toString() ?? '') ?? d).toInt();
    final rank     = toInt(entry['rank'], index + 1);
    final username = entry['username'] as String? ?? '?';
    final wins     = toInt(entry['matches_won'], 0);
    final score    = num.tryParse(entry['total_score']?.toString() ?? '') ?? 0;
    final level    = toInt(entry['level'], 1);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + index * 60),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(30 * (1 - v), 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _isPodium
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _rankColor.withValues(alpha: 0.12),
                    AppColors.darkSurface,
                  ],
                )
              : null,
          color: _isPodium ? null : AppColors.darkSurface,
          border: Border.all(
            color: _isPodium ? _rankColor.withValues(alpha: 0.35) : AppColors.darkBorder,
          ),
          boxShadow: _isPodium
              ? [BoxShadow(color: _rankColor.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))]
              : [const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                          style: const TextStyle(color: AppColors.textSecondary,
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
          ),
          title: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isPodium
                        ? [_rankColor, _rankColor.withValues(alpha: 0.6)]
                        : [AppColors.primary, AppColors.primaryDark],
                  ),
                ),
                child: Center(
                  child: Text(username[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
                          fontWeight: FontWeight.bold, fontSize: 15,
                        )),
                    Text('Level $level',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
