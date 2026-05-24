import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../game/presentation/bloc/game_bloc.dart';
import '../../data/room_repository.dart';

class RoomPage extends StatefulWidget {
  final String roomId;
  const RoomPage({super.key, required this.roomId});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final _repo  = RoomRepository();
  Map<String, dynamic>? _room;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRoom();
    // Listen for game start via socket
    context.read<GameBloc>().add(GameJoinRoom(widget.roomId, 0));
  }

  Future<void> _loadRoom() async {
    try {
      final room = await _repo.getRoomDetails(widget.roomId);
      if (mounted) setState(() => _room = room);
    } catch (_) {}
  }

  bool get _isHost {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return false;
    return _room?['host_id'] == auth.user.id;
  }

  int get _playerCount =>
      (_room?['players'] as List?)?.length ?? 0;

  Future<void> _addBot(String level) async {
    setState(() => _loading = true);
    try {
      final room = await _repo.addBot(widget.roomId, level);
      if (mounted) setState(() => _room = room);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startGame() {
    context.read<GameBloc>().add(GameJoinRoom(widget.roomId, _mySeat()));
    // start_game is triggered via socket from GameBloc
    // Actually send via socket directly
    final socket = context.read<GameBloc>();
    socket.add(GameJoinRoom(widget.roomId, _mySeat()));
    // emit start_game
    context.go('/game/${widget.roomId}');
  }

  int _mySeat() {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return 0;
    final players = _room?['players'] as List? ?? [];
    for (final p in players) {
      if ((p as Map)['user_id'] == auth.user.id) {
        return (p['seat'] as num).toInt();
      }
    }
    return 0;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final code    = _room!['code'] as String;
    final players = (_room!['players'] as List?) ?? [];
    final isHost  = _isHost;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting Room'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRoom),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Room code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Room Code',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Text(code,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 28, fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          )),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.textSecondary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Players list
            Text('Players ($_playerCount / 4)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: 4,
                itemBuilder: (_, i) {
                  final player = i < players.length ? players[i] as Map : null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: player != null ? AppColors.darkSurface : AppColors.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: player != null
                              ? (player['is_bot'] == true ? AppColors.trump : AppColors.primary)
                              : AppColors.darkBorder,
                          child: Text(
                            player != null
                                ? (player['username'] as String? ?? 'B').substring(0, 1).toUpperCase()
                                : '${i + 1}',
                            style: TextStyle(
                              color: player != null ? Colors.white : AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          player != null
                              ? (player['is_bot'] == true
                                  ? '🤖 Bot (${player['bot_level']})'
                                  : player['username'] as String? ?? 'Player')
                              : 'Waiting…',
                          style: TextStyle(
                            color: player != null ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                        const Spacer(),
                        if (player != null && player['user_id'] == _room!['host_id'])
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Host',
                                style: TextStyle(color: AppColors.accent, fontSize: 11)),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Host controls
            if (isHost) ...[
              const SizedBox(height: 8),
              if (_playerCount < 4)
                PopupMenuButton<String>(
                  onSelected: _loading ? null : _addBot,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'easy',   child: Text('Easy Bot')),
                    PopupMenuItem(value: 'medium', child: Text('Medium Bot')),
                    PopupMenuItem(value: 'hard',   child: Text('Hard Bot')),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Add Bot'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.darkBorder),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _playerCount == 4 ? _startGame : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_playerCount < 4
                    ? 'Need ${4 - _playerCount} more player(s)'
                    : 'Start Game'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
