import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/room_repository.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  final _repo      = RoomRepository();
  final _codeCtl   = TextEditingController();
  bool _loading    = false;
  List<Map<String, dynamic>> _publicRooms = [];

  @override
  void initState() {
    super.initState();
    _loadPublicRooms();
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPublicRooms() async {
    try {
      final rooms = await _repo.getPublicRooms();
      if (mounted) setState(() => _publicRooms = rooms);
    } catch (_) {}
  }

  Future<void> _createRoom({bool isPrivate = false}) async {
    setState(() => _loading = true);
    try {
      final room = await _repo.createRoom(isPrivate: isPrivate);
      if (mounted) context.go('/room/${room['id']}');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinByCode() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final room = await _repo.joinRoom(code);
      if (mounted) context.go('/room/${room['id']}');
    } catch (e) {
      _showError('Room not found or full');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final username  = authState is AuthAuthenticated ? authState.user.username : 'Player';

    return Scaffold(
      appBar: AppBar(
        title: const Text('♠ Lakadiya'),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            onPressed: () => context.go('/leaderboard'),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPublicRooms,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(username.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome, $username!',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (authState is AuthAuthenticated)
                          Text('Level ${authState.user.level} · ${authState.user.coins} coins',
                              style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Quick actions
              Text('Quick Play', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.add_circle_outline,
                      label: 'Create Room',
                      color: AppColors.primary,
                      onTap: _loading ? null : () => _createRoom(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.lock_outline,
                      label: 'Private Room',
                      color: AppColors.accent,
                      onTap: _loading ? null : () => _createRoom(isPrivate: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Join by code
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Join with Code', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeCtl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'Enter room code',
                              prefixIcon: Icon(Icons.vpn_key_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _loading ? null : _joinByCode,
                          child: const Text('Join'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Public rooms
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Open Rooms', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPublicRooms),
                ],
              ),
              const SizedBox(height: 8),
              if (_publicRooms.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No open rooms. Create one!',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                ...(_publicRooms.map((room) => _RoomCard(
                  room: room,
                  onJoin: () async {
                    setState(() => _loading = true);
                    try {
                      final r = await _repo.joinRoom(room['code'] as String);
                      if (mounted) context.go('/room/${r['id']}');
                    } catch (e) {
                      _showError('Could not join room');
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
                ))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon, required this.label,
    required this.color, this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}

class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onJoin;
  const _RoomCard({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              Text(room['host_name'] as String? ?? 'Room',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              Text('Code: ${room['code']}  •  ${room['player_count']}/4 players',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        ElevatedButton(onPressed: onJoin, child: const Text('Join')),
      ],
    ),
  );
}
