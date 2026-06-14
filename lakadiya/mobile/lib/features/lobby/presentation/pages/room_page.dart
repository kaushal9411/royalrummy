import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/socket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
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
  bool _starting = false;     // host pressed Start, waiting for game_started
  bool _navigated = false;    // guard against double navigation to /game
  Timer? _startTimeout;

  // Socket listener refs (so we remove only OURS in dispose)
  late final SocketCallback _roomCb;
  late final SocketCallback _startedCb;
  late final SocketCallback _errCb;

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

    // Real-time room updates: reload roster on join/leave/bot changes, and
    // navigate everyone to the table the moment the host starts the game.
    _roomCb    = (_) { if (mounted) _loadRoom(); };
    _startedCb = (_) => _goToGame();
    _errCb     = _onSocketError;
    SocketService().on('room_updated',  _roomCb);
    SocketService().on('player_joined', _roomCb);
    SocketService().on('game_started',  _startedCb);
    SocketService().on('error',         _errCb);

    _loadRoom();
    context.read<GameBloc>().add(GameJoinRoom(widget.roomId, 0));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _enterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _startTimeout?.cancel();
    SocketService().offCallback('room_updated',  _roomCb);
    SocketService().offCallback('player_joined', _roomCb);
    SocketService().offCallback('game_started',  _startedCb);
    SocketService().offCallback('error',         _errCb);
    _pulseCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  void _goToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _startTimeout?.cancel();
    context.go('/game/${widget.roomId}');
  }

  void _onSocketError(dynamic data) {
    if (!mounted || !_starting) return;
    // A start attempt failed (e.g. not host / not enough players / bet escrow).
    _startTimeout?.cancel();
    setState(() => _starting = false);
    final msg = (data is Map ? data['message'] as String? : null) ?? 'Could not start the game';
    _showError(msg);
  }

  Future<void> _loadRoom() async {
    try {
      final room = await _repo.getRoomDetails(widget.roomId);
      if (mounted) setState(() => _room = room);
    } catch (_) {}
  }

  Future<void> _onLeavePressed() async {
    if (_isHost) {
      await _showHostLeaveOptions();
    } else {
      await _showLeaveConfirmation();
    }
  }

  Future<void> _showLeaveConfirmation() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _PlayerLeaveSheet(),
    );
    if (!mounted) return;
    if (result == 'leave') {
      // Temporary — seat preserved, can rejoin without a code.
      if (mounted) context.go('/lobby');
    } else if (result == 'leave_perm') {
      await _repo.leaveRoom(widget.roomId);
      if (mounted) context.go('/lobby');
    }
  }

  Future<void> _showHostLeaveOptions() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _HostLeaveSheet(),
    );
    if (!mounted) return;
    if (result == 'leave') {
      // Temporary leave — host stays in room_players, just navigate away.
      if (mounted) context.go('/lobby');
    } else if (result == 'leave_perm') {
      // Permanent leave — removes host from room_players, transfers crown.
      await _repo.leaveRoom(widget.roomId);
      if (mounted) context.go('/lobby');
    } else if (result == 'delete') {
      await _repo.deleteRoom(widget.roomId);
      if (mounted) context.go('/lobby');
    }
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

  double get _betAmount =>
      (num.tryParse(_room?['bet_amount']?.toString() ?? '') ?? 0).toDouble();

  bool get _hasBot =>
      ((_room?['players'] as List?) ?? []).any((p) => p['is_bot'] == true);

  void _startGame() {
    if (_starting) return;
    if (_betAmount > 0 && _hasBot) {
      _showBotBetWarning();
      return;
    }
    _beginStart();
  }

  /// Emits start_game and waits for the server's `game_started` (which
  /// navigates everyone via the socket listener). Does NOT navigate optimistically
  /// so a rejected start no longer strands the host on an empty game loader.
  void _beginStart() {
    if (!mounted || _navigated) return;
    setState(() => _starting = true);
    context.read<GameBloc>().add(GameStartGame(widget.roomId));
    _startTimeout?.cancel();
    _startTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted && _starting && !_navigated) {
        setState(() => _starting = false);
        _showError('Start timed out. Please check your connection and try again.');
      }
    });
  }

  void _showBotBetWarning() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BotBetWarningSheet(
        betAmount: _betAmount,
        onPlayFree: () {
          Navigator.pop(context);
          _playFreeWithBots();
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _playFreeWithBots() async {
    setState(() => _loading = true);
    try {
      await _repo.resetBet(widget.roomId);
      if (!mounted) return;
      setState(() => _loading = false);
      _beginStart(); // emit start, navigate on game_started
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            _RoomBg(anim: _pulseAnim),
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ],
        ),
      );
    }

    final code    = _room!['code'] as String;
    final players = (_room!['players'] as List?) ?? [];
    final isHost  = _isHost;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: _onLeavePressed,
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
      body: Stack(
        children: [
          _RoomBg(anim: _pulseAnim),
          FadeTransition(
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
    ],
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
    final canStart = _playerCount == 4 && !_starting;
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
              if (_starting)
                const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              else
                Icon(
                  canStart ? Icons.play_circle_filled_rounded : Icons.hourglass_empty_rounded,
                  color: canStart ? Colors.white : AppColors.textMuted,
                  size: 24,
                ),
              const SizedBox(width: 10),
              Text(
                _starting
                    ? 'Starting…'
                    : (_playerCount == 4 ? 'Start Game' : 'Need ${4 - _playerCount} more player(s)'),
                style: TextStyle(
                  color: (_playerCount == 4 || _starting) ? Colors.white : AppColors.textMuted,
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

// ── Animated gradient background ───────────────────────────────────────────────
class _RoomBg extends StatelessWidget {
  final Animation<double> anim;
  const _RoomBg({required this.anim});

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
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                  AppColors.accent.withValues(alpha: 0.06 + t * 0.05),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            left: -80, bottom: 120,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.05 + t * 0.05),
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

// ── Animated player slot ───────────────────────────────────────────────────
class _AnimatedPlayerSlot extends StatelessWidget {
  final Map? player;
  final int index;
  final String? hostId;
  const _AnimatedPlayerSlot({this.player, required this.index, this.hostId});

  @override
  Widget build(BuildContext context) {
    final filled  = player != null;
    final isBot     = player?['is_bot'] == true;
    final isHost    = filled && player!['user_id'] == hostId;
    final name      = filled ? (player!['username'] as String? ?? 'Player') : null;
    final botLvl    = player?['bot_level'] as String?;
    final avatarUrl = filled && !isBot ? player!['avatar_url'] as String? : null;
    final avatarColor = isBot
        ? AppColors.trump
        : [AppColors.primary, AppColors.accent, const Color(0xFF9C27B0), const Color(0xFFFF5722)][index % 4];

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
            if (!filled)
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.darkBorder.withValues(alpha: 0.3),
                  border: Border.all(color: AppColors.darkBorder.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.person_outline_rounded, color: AppColors.textMuted, size: 22),
              )
            else if (isBot)
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarColor.withValues(alpha: 0.15),
                  border: Border.all(color: avatarColor.withValues(alpha: 0.5)),
                ),
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 20))),
              )
            else
              UserAvatar(
                username: name ?? '?',
                avatarUrl: avatarUrl,
                size: 44,
                solidColor: avatarColor.withValues(alpha: 0.15),
                border: Border.all(color: avatarColor.withValues(alpha: 0.5)),
                textColor: avatarColor,
                fontSize: 18,
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

// ── Host leave / delete room bottom sheet ────────────────────────────────────
class _PlayerLeaveSheet extends StatelessWidget {
  const _PlayerLeaveSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2C), Color(0xFF080F18)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top:   BorderSide(color: Color(0xFF1E3050)),
          left:  BorderSide(color: Color(0xFF1E3050)),
          right: BorderSide(color: Color(0xFF1E3050)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),

          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: const Center(child: Icon(Icons.meeting_room_rounded, color: AppColors.primary, size: 28)),
          ),
          const SizedBox(height: 14),

          const Text(
            'Leave Room?',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose how you want to leave.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 28),

          // Leave Temporarily
          GestureDetector(
            onTap: () => Navigator.pop(context, 'leave'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.darkSurface,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.exit_to_app_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leave Temporarily',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Your seat is saved. Rejoin anytime with the room code.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Leave Permanently
          GestureDetector(
            onTap: () => Navigator.pop(context, 'leave_perm'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.darkSurface,
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leave Permanently',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Your seat is freed. You will need to rejoin with the code.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Stay button
          GestureDetector(
            onTap: () => Navigator.pop(context, null),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkBorder),
                color: Colors.transparent,
              ),
              child: const Text(
                'Stay in Room',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostLeaveSheet extends StatelessWidget {
  const _HostLeaveSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2C), Color(0xFF080F18)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top:   BorderSide(color: Color(0xFF1E3050)),
          left:  BorderSide(color: Color(0xFF1E3050)),
          right: BorderSide(color: Color(0xFF1E3050)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),

          // Icon
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
            ),
            child: const Center(child: Text('👑', style: TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 14),

          const Text(
            'You are the Host',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'What would you like to do?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 28),

          // Leave Room option
          GestureDetector(
            onTap: () => Navigator.pop(context, 'leave'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.darkSurface,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.exit_to_app_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leave Temporarily',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('You remain host. Room stays open — rejoin anytime.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Leave Permanently option
          GestureDetector(
            onTap: () => Navigator.pop(context, 'leave_perm'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.darkSurface,
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leave Permanently',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Leave the room. Crown passes to next player.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Delete Room option
          GestureDetector(
            onTap: () => Navigator.pop(context, 'delete'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.darkSurface,
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.danger.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 20),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Delete Room',
                          style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Closes the room for everyone permanently.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Stay button
          GestureDetector(
            onTap: () => Navigator.pop(context, null),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkBorder),
                color: Colors.transparent,
              ),
              child: const Text(
                'Stay in Room',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bot + Bet warning bottom sheet ────────────────────────────────────────────
class _BotBetWarningSheet extends StatelessWidget {
  final double betAmount;
  final VoidCallback onPlayFree;
  final VoidCallback onCancel;

  const _BotBetWarningSheet({
    required this.betAmount,
    required this.onPlayFree,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2C), Color(0xFF080F18)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top:   BorderSide(color: Color(0xFF1E3050)),
          left:  BorderSide(color: Color(0xFF1E3050)),
          right: BorderSide(color: Color(0xFF1E3050)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Warning icon
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
            ),
            child: const Center(
              child: Text('⚠️', style: TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Bots Can\'t Join Paid Games',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'Your room has a '),
                  TextSpan(
                    text: '₹${betAmount.toInt()} bet',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text: ' but bots don\'t have wallets.\nPlay free with bots or remove them to keep the bet.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Play Free with Bots button
          GestureDetector(
            onTap: onPlayFree,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF007E33)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🤖', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Text(
                    'Play Free with Bots',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cancel button
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkBorder),
                color: AppColors.darkSurface,
              ),
              child: const Text(
                'Cancel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
