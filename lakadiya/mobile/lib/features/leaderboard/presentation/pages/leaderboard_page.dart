import 'package:flutter/material.dart';
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
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final wins   = await _api.get('/leaderboard', params: {'type': 'wins'});
      final scores = await _api.get('/leaderboard', params: {'type': 'score'});
      if (mounted) {
        setState(() {
          _wins   = (wins.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      appBar: AppBar(
        title: const Text('Leaderboard'),
        bottom: TabBar(
          controller: _tabCtl,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Most Wins'),
            Tab(text: 'Top Scores'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtl,
              children: [
                _buildList(_wins),
                _buildList(_scores),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No data yet', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final p    = data[i];
        final rank = (p['rank'] as num?)?.toInt() ?? (i + 1);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: rank <= 3 ? _podiumColor(rank).withValues(alpha: 0.1) : AppColors.darkSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: rank <= 3 ? _podiumColor(rank).withValues(alpha: 0.4) : AppColors.darkBorder,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  rank <= 3 ? _medal(rank) : '#$rank',
                  style: TextStyle(
                    fontSize: rank <= 3 ? 20 : 14,
                    fontWeight: FontWeight.bold,
                    color: rank <= 3 ? _podiumColor(rank) : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary,
                child: Text(
                  (p['username'] as String).substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['username'] as String,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                    Text('Level ${p['level']}  •  ${p['matches_played']} matches',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${p['matches_won']} wins',
                      style: const TextStyle(
                          color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                  Text('${(p['total_score'] as num?)?.toStringAsFixed(1) ?? '0'} pts',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _medal(int rank) => switch (rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '#$rank' };

  Color _podiumColor(int rank) => switch (rank) {
    1 => AppColors.accent,
    2 => AppColors.textSecondary,
    3 => const Color(0xFFCD7F32),
    _ => AppColors.darkBorder,
  };
}
