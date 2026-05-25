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

class _RoomPageState extends State<RoomPage> with TickerProviderStateMixin {
  final _repo  = RoomRepository();
  Map<String, dynamic>? _room;
  bool _loading = false;

  late final AnimationController _pulseCtrl;
  late final AnimationController _enterCtrl;
  late final Animation<double>   _pulseAnim;
  late final Animation<double>   _fadeIn;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _fadeIn    = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);

    _loadRoom();
    context.read<GameBloc>().add(GameJoinRoom(widget.roomId, 0));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _enterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
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

  int get _playerCount => (_room?['players'] as List?)?.length ?? 0;

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
    context.read<GameBloc>().add(GameStartGame(widget.roomId));
    context.go('/game/${widget.roomId}');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBg,
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final code    = _room!['code'] as String;
    final players = (_room!['players'] as List?) ?? [];
    final isHost  = _isHost;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => context.go('/lobby'),
        ),
        title: const Text('Waiting Room',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: _loadRoom,
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Room code card ──
              _buildCodeCard(code),
              const SizedBox(height: 24),

              // ── Players ──
              Row(
                children: [
                  const Icon(Icons.people_rounded, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Players ($_playerCount / 4)',
                      style: const TextStyle(color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 14),
              ...List.generate(4, (i) => _AnimatedPlayerSlot(
                player: i < players.length ? players[i] as Map : null,
                index: i,
                hostId: _room!['host_id'] as String?,
              )),

              const SizedBox(height: 24),

              // ── Host controls ──
              if (isHost) ...[
                if (_playerCount < 4)
                  _buildAddBotButton(),
                const SizedBox(height: 12),
                _buildStartButton(),
              ] else ...[
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: AppColors.darkSurface,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2 + _pulseAnim.value * 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.05 + _pulseAnim.value * 0.08),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary.withValues(alpha: 0.5 + _pulseAnim.value * 0.5),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text('Waiting for host to start…',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeCard(String code) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D2030), Color(0xFF0A1A28)],
      ),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      boxShadow: [
        BoxShadow(color: AppColors.accent.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.tag_rounded, color: AppColors.accent, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Room Code', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              Text(code,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  )),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code copied!'), duration: Duration(seconds: 1)),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Icon(Icons.copy_rounded, color: AppColors.textSecondary, size: 18),
          ),
        ),
      ],
    ),
  );

  Widget _buildAddBotButton() => PopupMenuButton<String>(
    onSelected: _loading ? null : _addBot,
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'easy',
          child: Row(children: [
            Text('🤖 ', style: TextStyle(fontSize: 18)),
            Text('Easy Bot', style: TextStyle(color: AppColors.primaryLight)),
          ])),
      const PopupMenuItem(value: 'medium',
          child: Row(children: [
            Text('🤖 ', style: TextStyle(fontSize: 18)),
            Text('Medium Bot', style: TextStyle(color: AppColors.accent)),
          ])),
      const PopupMenuItem(value: 'hard',
          child: Row(children: [
            Text('🤖 ', style: TextStyle(fontSize: 18)),
            Text('Hard Bot', style: TextStyle(color: AppColors.danger)),
          ])),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
        color: AppColors.darkSurface,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy_rounded, color: AppColors.textSecondary, size: 20),
          SizedBox(width: 10),
          Text('Add Bot', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          SizedBox(width: 6),
          Icon(Icons.expand_more_rounded, color: AppColors.textSecondary, size: 18),
        ],
      ),
    ),
  );

  Widget _buildStartButton() {
    final canStart = _playerCount == 4;
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => GestureDetector(
        onTap: canStart ? _startGame : null,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: canStart
                ? LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.9 + _pulseAnim.value * 0.1),
                      AppColors.primaryDark,
                    ],
                  )
                : null,
            color: canStart ? null : AppColors.darkCard,
            boxShadow: canStart
                ? [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3 + _pulseAnim.value * 0.2),
                    blurRadius: 16 + _pulseAnim.value * 8,
                    offset: const Offset(0, 4),
                  )]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                canStart ? Icons.play_circle_filled_rounded : Icons.hourglass_empty_rounded,
                color: canStart ? Colors.white : AppColors.textMuted,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                canStart ? 'Start Game' : 'Need ${4 - _playerCount} more player(s)',
                style: TextStyle(
                  color: canStart ? Colors.white : AppColors.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated player slot ───────────────────────────────────────────────────
class _AnimatedPlayerSlot extends StatelessWidget {
  final Map? player;
  final int index;
  final String? hostId;
  const _AnimatedPlayerSlot({this.player, required this.index, this.hostId});

  @override
  Widget build(BuildContext context) {
    final filled  = player != null;
    final isBot   = player?['is_bot'] == true;
    final isHost  = filled && player!['user_id'] == hostId;
    final name    = filled ? (player!['username'] as String? ?? 'Player') : null;
    final botLvl  = player?['bot_level'] as String?;
    final initial = name?.isNotEmpty == true ? name![0].toUpperCase() : '?';
    final avatarColor = isBot
        ? AppColors.trump
        : [AppColors.primary, AppColors.accent, Color(0xFF9C27B0), Color(0xFFFF5722)][index % 4];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 200 + index * 100),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(-20 * (1 - v), 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: filled ? AppColors.darkSurface : AppColors.darkCard,
          border: Border.all(
            color: filled
                ? (isHost ? AppColors.accent.withValues(alpha: 0.4) : AppColors.darkBorder)
                : AppColors.darkBorder.withValues(alpha: 0.4),
          ),
          boxShadow: filled ? [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2)),
          ] : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? avatarColor.withValues(alpha: 0.15) : AppColors.darkBorder.withValues(alpha: 0.3),
                border: Border.all(
                  color: filled ? avatarColor.withValues(alpha: 0.5) : AppColors.darkBorder.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: filled
                    ? Text(isBot ? '🤖' : initial,
                        style: TextStyle(
                          color: avatarColor,
                          fontSize: isBot ? 20 : 18,
                          fontWeight: FontWeight.bold,
                        ))
                    : Icon(Icons.person_outline_rounded, color: AppColors.textMuted, size: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filled
                        ? (isBot ? 'Bot ${botLvl != null ? "(${botLvl[0].toUpperCase()}${botLvl.substring(1)})" : ""}' : name!)
                        : 'Waiting…',
                    style: TextStyle(
                      color: filled ? AppColors.textPrimary : AppColors.textMuted,
                      fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 15,
                    ),
                  ),
                  if (filled && !isBot)
                    Text('Seat ${index + 1}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (isHost)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Text('HOST',
                    style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              )
            else if (isBot)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.trump.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.trump.withValues(alpha: 0.3)),
                ),
                child: Text(
                  (botLvl ?? 'bot').toUpperCase(),
                  style: const TextStyle(color: AppColors.trump, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              )
            else if (!filled)
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textMuted.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
