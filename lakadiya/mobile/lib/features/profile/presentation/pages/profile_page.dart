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

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiService();
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
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout, color: AppColors.danger),
            label: const Text('Logout', style: TextStyle(color: AppColors.danger)),
            onPressed: () {
              context.read<AuthBloc>().add(AuthLogoutRequested());
              context.go('/login');
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Failed to load profile'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _buildStats(),
                        const SizedBox(height: 20),
                        _buildHistory(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    final p = _profile!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primary,
            child: Text(
              (p['username'] as String).substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(p['username'] as String,
              style: Theme.of(context).textTheme.titleLarge),
          if (p['email'] != null)
            Text(p['email'] as String,
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statChip('Level', '${p['level']}', AppColors.accent),
              _statChip('Coins', '${p['coins']}', AppColors.primary),
              _statChip('XP', '${p['xp']}', AppColors.trump),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final p = _profile!;
    final played = (p['matches_played'] as num?)?.toInt() ?? 0;
    final won    = (p['matches_won'] as num?)?.toInt() ?? 0;
    final rate   = played > 0 ? (won / played * 100).toStringAsFixed(1) : '0';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Statistics', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _statRow('Matches Played', '$played'),
          _statRow('Matches Won', '$won'),
          _statRow('Win Rate', '$rate%'),
          _statRow('Total Score', '${(p['total_score'] as num?)?.toStringAsFixed(1) ?? '0'}'),
          _statRow('Exact Bids', '${p['bids_exact'] ?? 0}'),
          _statRow('Failed Bids', '${p['bids_failed'] ?? 0}'),
        ],
      ),
    );
  }

  Widget _buildHistory() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Match History', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (_history.isEmpty)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('No matches yet', style: TextStyle(color: AppColors.textSecondary)),
          ),
        )
      else
        ..._history.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Match · ${m['status']}',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    if (m['winner_name'] != null)
                      Text('Winner: ${m['winner_name']}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(m['final_score'] as num?)?.toStringAsFixed(1) ?? '0'}',
                  style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        )),
    ],
  );

  Widget _statChip(String label, String value, Color color) => Column(
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
    ],
  );

  Widget _statRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
