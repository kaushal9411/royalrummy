import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../game/presentation/bloc/game_bloc.dart';
import '../../data/room_repository.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});
  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> with TickerProviderStateMixin {
  final _repo = RoomRepository();
  final _codeCtl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _publicRooms = [];

  late final AnimationController _enterCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
    _fadeIn = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _loadPublicRooms();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _enterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPublicRooms() async {
    try {
      final rooms = await _repo.getPublicRooms();
      if (mounted) setState(() => _publicRooms = rooms);
    } catch (_) {}
  }

  void _showBetPicker({required bool isPrivate}) {
    if (_loading) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BetPickerSheet(
        onPicked: (betAmount) {
          Navigator.pop(context);
          _createRoom(isPrivate: isPrivate, betAmount: betAmount);
        },
      ),
    );
  }

  Future<void> _createRoom(
      {bool isPrivate = false, double betAmount = 0}) async {
    setState(() => _loading = true);
    try {
      final room =
          await _repo.createRoom(isPrivate: isPrivate, betAmount: betAmount);
      if (mounted) {
        context.read<GameBloc>().add(GameJoinRoom(room['id'] as String, 0));
        context.go('/room/${room['id']}');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Quick Play with bots ───────────────────────────────────────────────────
  void _showLevelPicker() {
    if (_loading) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LevelPickerSheet(
        onPicked: (level) {
          Navigator.pop(context);
          _quickPlay(level);
        },
      ),
    );
  }

  Future<void> _quickPlay(String level) async {
    setState(() => _loading = true);
    try {
      final room = await _repo.createRoom(isPrivate: true);
      final roomId = room['id'] as String;
      if (!mounted) return;
      context.read<GameBloc>().add(GameJoinRoom(roomId, 0));
      // Add 3 bots sequentially
      for (int i = 0; i < 3; i++) {
        await _repo.addBot(roomId, level);
      }
      if (!mounted) return;
      context.read<GameBloc>().add(GameStartGame(roomId));
      context.go('/game/$roomId');
    } catch (e) {
      _showError('Could not start game');
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
      if (mounted) {
        context.read<GameBloc>().add(GameJoinRoom(room['id'] as String, 0));
        context.go('/room/${room['id']}');
      }
    } catch (_) {
      _showError('Room not found or full');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.danger,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final username = auth is AuthAuthenticated ? auth.user.username : 'Player';
    final level = auth is AuthAuthenticated ? auth.user.level : 1;
    final coins = auth is AuthAuthenticated ? auth.user.coins : 0;
    final xp = auth is AuthAuthenticated ? auth.user.xp : 0;

    return Scaffold(
      backgroundColor: const Color(0xFF050B15),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF07101C), Color(0xFF0A1520)],
            ),
            border: Border(
                bottom:
                    BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [AppColors.accent, AppColors.accentLight],
          ).createShader(b),
          child: const Text('♠ LAKADIYA',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: 20)),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.leaderboard_rounded, color: AppColors.accent),
            onPressed: () => context.go('/leaderboard'),
          ),
          IconButton(
            icon: const Icon(Icons.person_rounded, color: AppColors.primary),
            onPressed: () => context.go('/profile'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          _LobbyBg(pulse: _pulseCtrl),
          FadeTransition(
            opacity: _fadeIn,
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.darkCard,
              onRefresh: _loadPublicRooms,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WelcomeBanner(
                        username: username, level: level, coins: coins, xp: xp),
                    const SizedBox(height: 24),
                    const _SectionLabel(
                        title: 'Quick Play', icon: Icons.flash_on_rounded),
                    const SizedBox(height: 12),
                    _PlayNowCard(loading: _loading, onTap: _showLevelPicker),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _ActionCard(
                        suit: '♠',
                        label: 'Create Room',
                        subtitle: 'Public game',
                        colors: const [Color(0xFF00C853), Color(0xFF007E33)],
                        onTap: _loading
                            ? null
                            : () => _showBetPicker(isPrivate: false),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _ActionCard(
                        suit: '♦',
                        label: 'Private Room',
                        subtitle: 'Invite only',
                        colors: const [Color(0xFFFFD600), Color(0xFFC79E00)],
                        onTap: _loading
                            ? null
                            : () => _showBetPicker(isPrivate: true),
                      )),
                    ]),
                    const SizedBox(height: 16),
                    _JoinCodeCard(
                        ctl: _codeCtl, loading: _loading, onJoin: _joinByCode),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionLabel(
                            title: 'Open Rooms',
                            icon: Icons.meeting_room_rounded),
                        GestureDetector(
                          onTap: _loadPublicRooms,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.darkCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.darkBorder),
                            ),
                            child: const Icon(Icons.refresh_rounded,
                                color: AppColors.textSecondary, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_publicRooms.isEmpty)
                      _EmptyRoomsCard()
                    else
                      ...List.generate(
                          _publicRooms.length,
                          (i) => _RoomCard(
                                room: _publicRooms[i],
                                index: i,
                                onJoin: () async {
                                  setState(() => _loading = true);
                                  try {
                                    final r = await _repo.joinRoom(
                                        _publicRooms[i]['code'] as String);
                                    if (!context.mounted) return;
                                    context.read<GameBloc>().add(
                                        GameJoinRoom(r['id'] as String, 0));
                                    context.go('/room/${r['id']}');
                                  } catch (_) {
                                    _showError('Could not join room');
                                  } finally {
                                    if (mounted)
                                      setState(() => _loading = false);
                                  }
                                },
                              )),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated gradient background ────────────────────────────────────────────
class _LobbyBg extends StatelessWidget {
  final AnimationController pulse;
  const _LobbyBg({required this.pulse});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          final p = pulse.value;
          return Stack(children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF060D1A),
                    Color(0xFF08121E),
                    Color(0xFF050A13)
                  ],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.primary.withValues(alpha: 0.07 + p * 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: 200,
              left: -80,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.accent.withValues(alpha: 0.05 + p * 0.03),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ]);
        },
      );
}

// ── Welcome banner ──────────────────────────────────────────────────────────
class _WelcomeBanner extends StatelessWidget {
  final String username;
  final int level, coins, xp;
  const _WelcomeBanner(
      {required this.username,
      required this.level,
      required this.coins,
      required this.xp});

  @override
  Widget build(BuildContext context) {
    final xpPct = (xp % 1000) / 1000.0;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'P';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2A1A), Color(0xFF091E30), Color(0xFF0A1520)],
          stops: [0, 0.5, 1],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(children: [
        Row(children: [
          // Avatar with gradient ring
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark]),
              ),
              child: Center(
                  child: Text(initial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22))),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome back',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              Text(username,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Level $level · ${xp % 1000}/1000 XP',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ],
          )),
          // Coins badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 5),
              Text('$coins',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('XP',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          Text('Lv $level → ${level + 1}',
              style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: xpPct),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Section label ───────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionLabel({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: AppColors.accent, size: 15),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
      ]);
}

// ── Action card ─────────────────────────────────────────────────────────────
class _ActionCard extends StatefulWidget {
  final String suit, label, subtitle;
  final List<Color> colors;
  final VoidCallback? onTap;
  const _ActionCard(
      {required this.suit,
      required this.label,
      required this.subtitle,
      required this.colors,
      this.onTap});
  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) {
          if (widget.onTap != null) _ctrl.forward();
        },
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap?.call();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.colors[0].withValues(alpha: 0.18),
                  widget.colors[1].withValues(alpha: 0.08)
                ],
              ),
              border:
                  Border.all(color: widget.colors[0].withValues(alpha: 0.38)),
              boxShadow: [
                BoxShadow(
                    color: widget.colors[0].withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 5))
              ],
            ),
            child: Stack(children: [
              Positioned(
                right: -4,
                bottom: -10,
                child: Text(widget.suit,
                    style: TextStyle(
                        color: widget.colors[0].withValues(alpha: 0.09),
                        fontSize: 64,
                        fontWeight: FontWeight.bold)),
              ),
              Column(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: widget.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    boxShadow: [
                      BoxShadow(
                          color: widget.colors[0].withValues(alpha: 0.5),
                          blurRadius: 12)
                    ],
                  ),
                  child: Center(
                      child: Text(widget.suit,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold))),
                ),
                const SizedBox(height: 12),
                Text(widget.label,
                    style: TextStyle(
                        color: widget.colors[0],
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Text(widget.subtitle,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ]),
            ]),
          ),
        ),
      );
}

// ── Join code card ──────────────────────────────────────────────────────────
class _JoinCodeCard extends StatelessWidget {
  final TextEditingController ctl;
  final bool loading;
  final VoidCallback onJoin;
  const _JoinCodeCard(
      {required this.ctl, required this.loading, required this.onJoin});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E1B2E), Color(0xFF0A1520)],
          ),
          border: Border.all(color: AppColors.trump.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: AppColors.trump.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.trump,
                  AppColors.trump.withValues(alpha: 0.7)
                ]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.vpn_key_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Join with Code',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text('Enter room code to join friends',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: TextField(
              controller: ctl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  letterSpacing: 6),
              decoration: InputDecoration(
                hintText: '• • • • • •',
                hintStyle: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.4),
                    letterSpacing: 4,
                    fontSize: 16),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.darkBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.darkBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.trump, width: 2)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            )),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: loading ? null : onJoin,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: loading
                          ? [AppColors.textMuted, AppColors.textMuted]
                          : [
                              AppColors.trump,
                              AppColors.trump.withValues(alpha: 0.8)
                            ]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: loading
                      ? null
                      : [
                          BoxShadow(
                              color: AppColors.trump.withValues(alpha: 0.4),
                              blurRadius: 8)
                        ],
                ),
                child: const Text('Join',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ]),
        ]),
      );
}

// ── Empty rooms ─────────────────────────────────────────────────────────────
class _EmptyRoomsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 44),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1520), Color(0xFF080F18)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.08),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child:
                const Center(child: Text('🃏', style: TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 14),
          const Text('No open rooms',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Create one and invite friends!',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      );
}

// ── Play Now card (full-width prominent button) ─────────────────────────────
class _PlayNowCard extends StatefulWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _PlayNowCard({required this.loading, this.onTap});
  @override
  State<_PlayNowCard> createState() => _PlayNowCardState();
}

class _PlayNowCardState extends State<_PlayNowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 110));
    _scale = Tween(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onTap == null;
    return GestureDetector(
      onTapDown: (_) {
        if (!disabled) _ctrl.forward();
      },
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: disabled
                ? const LinearGradient(
                    colors: [Color(0xFF1A2A1A), Color(0xFF101A10)])
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF00E676),
                      Color(0xFF00C853),
                      Color(0xFF007E33)
                    ],
                  ),
            border: Border.all(
              color: disabled
                  ? AppColors.darkBorder
                  : AppColors.primary.withValues(alpha: 0.6),
            ),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              // Watermark suits
              Positioned(
                right: -6,
                top: -8,
                child: Text('♠',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.07),
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                    )),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 26),
                    ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.loading ? 'Starting game…' : 'Play Now',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Play instantly with AI bots',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (!widget.loading)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.smart_toy_rounded,
                          color: Colors.white, size: 20),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bet amount picker bottom sheet ───────────────────────────────────────────
class _BetPickerSheet extends StatelessWidget {
  final void Function(double) onPicked;
  const _BetPickerSheet({required this.onPicked});

  static const _bets = [
    {
      'amount': 0.0,
      'label': 'Free',
      'sub': 'No real money',
      'icon': '🆓',
      'color': AppColors.textSecondary
    },
    {
      'amount': 10.0,
      'label': '₹10',
      'sub': 'Pot: ₹40 for winner',
      'icon': '💰',
      'color': AppColors.primary
    },
    {
      'amount': 25.0,
      'label': '₹25',
      'sub': 'Pot: ₹100 for winner',
      'icon': '💎',
      'color': AppColors.accent
    },
    {
      'amount': 50.0,
      'label': '₹50',
      'sub': 'Pot: ₹200 for winner',
      'icon': '🔥',
      'color': Color(0xFFFF7043)
    },
    {
      'amount': 100.0,
      'label': '₹100',
      'sub': 'Pot: ₹400 for winner',
      'icon': '👑',
      'color': Color(0xFFFFD700)
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2C), Color(0xFF080F18)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF1E3050)),
          left: BorderSide(color: Color(0xFF1E3050)),
          right: BorderSide(color: Color(0xFF1E3050)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.accent, Color(0xFFC79E00)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.monetization_on_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set Bet Amount',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                  Text('Requires wallet balance > ₹100',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ]),
          ]),
          const SizedBox(height: 20),
          ..._bets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BetOption(
                  label: b['label'] as String,
                  sub: b['sub'] as String,
                  icon: b['icon'] as String,
                  color: b['color'] as Color,
                  onTap: () => onPicked(b['amount'] as double),
                ),
              )),
        ],
      ),
    );
  }
}

class _BetOption extends StatefulWidget {
  final String label, sub, icon;
  final Color color;
  final VoidCallback onTap;
  const _BetOption(
      {required this.label,
      required this.sub,
      required this.icon,
      required this.color,
      required this.onTap});
  @override
  State<_BetOption> createState() => _BetOptionState();
}

class _BetOptionState extends State<_BetOption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.96)
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  widget.color.withValues(alpha: 0.12),
                  const Color(0xFF0A1422)
                ],
              ),
              border: Border.all(color: widget.color.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              Text(widget.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(widget.label,
                        style: TextStyle(
                            color: widget.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(widget.sub,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ])),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.arrow_forward_ios_rounded,
                    color: widget.color, size: 14),
              ),
            ]),
          ),
        ),
      );
}

// ── Level picker bottom sheet ────────────────────────────────────────────────
class _LevelPickerSheet extends StatelessWidget {
  final void Function(String) onPicked;
  const _LevelPickerSheet({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2C), Color(0xFF080F18)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF1E3050)),
          left: BorderSide(color: Color(0xFF1E3050)),
          right: BorderSide(color: Color(0xFF1E3050)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose Bot Difficulty',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      )),
                  Text('3 bots will be added automatically',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _LevelOption(
            level: 'easy',
            label: 'Easy',
            description: 'Relaxed play — perfect for beginners',
            icon: '🟢',
            color: AppColors.primary,
            onTap: () => onPicked('easy'),
          ),
          const SizedBox(height: 10),
          _LevelOption(
            level: 'medium',
            label: 'Medium',
            description: 'Balanced challenge — good competition',
            icon: '🟡',
            color: AppColors.accent,
            onTap: () => onPicked('medium'),
          ),
          const SizedBox(height: 10),
          _LevelOption(
            level: 'hard',
            label: 'Hard',
            description: 'Pro-level AI — for experienced players',
            icon: '🔴',
            color: AppColors.danger,
            onTap: () => onPicked('hard'),
          ),
        ],
      ),
    );
  }
}

// ── Single level option row ───────────────────────────────────────────────────
class _LevelOption extends StatefulWidget {
  final String level, label, description, icon;
  final Color color;
  final VoidCallback onTap;
  const _LevelOption({
    required this.level,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  State<_LevelOption> createState() => _LevelOptionState();
}

class _LevelOptionState extends State<_LevelOption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.96)
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  widget.color.withValues(alpha: 0.12),
                  const Color(0xFF0A1422),
                ],
              ),
              border: Border.all(color: widget.color.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(widget.icon, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          style: TextStyle(
                            color: widget.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          )),
                      const SizedBox(height: 2),
                      Text(widget.description,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.arrow_forward_ios_rounded,
                      color: widget.color, size: 14),
                ),
              ],
            ),
          ),
        ),
      );
}

// ── Room card ───────────────────────────────────────────────────────────────
class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final int index;
  final VoidCallback onJoin;
  const _RoomCard(
      {required this.room, required this.index, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final count =
        (num.tryParse(room['player_count']?.toString() ?? '') ?? 0).toInt();
    final isFull = count >= 4;
    final host = room['host_name'] as String? ?? 'Room';
    final betAmount =
        (num.tryParse(room['bet_amount']?.toString() ?? '') ?? 0).toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + index * 80),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
              offset: Offset(0, 20 * (1 - v)), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF0D1A28), Color(0xFF0A1520)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
              color: isFull
                  ? AppColors.darkBorder
                  : AppColors.primary.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: isFull
                  ? Colors.transparent
                  : AppColors.primary.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isFull
                    ? [AppColors.darkCard, AppColors.darkCard]
                    : [AppColors.primary, AppColors.primaryDark],
              ),
              border: Border.all(
                  color: isFull
                      ? AppColors.darkBorder
                      : AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Center(
                child: Text(
              host.isNotEmpty ? host[0].toUpperCase() : '?',
              style: TextStyle(
                  color: isFull ? AppColors.textMuted : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            )),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(host,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 6),
                Row(children: [
                  // Player slot dots
                  ...List.generate(
                      4,
                      (i) => Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < count
                                  ? AppColors.primary
                                  : AppColors.darkBorder,
                              boxShadow: i < count
                                  ? [
                                      BoxShadow(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4)
                                    ]
                                  : null,
                            ),
                          )),
                  const SizedBox(width: 6),
                  Text('$count/4',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isFull ? AppColors.danger : AppColors.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isFull ? 'Full' : 'Open',
                        style: TextStyle(
                            color:
                                isFull ? AppColors.danger : AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  if (betAmount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Text('₹${betAmount.toInt()}',
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
              ])),
          GestureDetector(
            onTap: isFull ? null : onJoin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: isFull
                    ? null
                    : const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark]),
                color: isFull ? AppColors.darkCard : null,
                boxShadow: isFull
                    ? null
                    : [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
              ),
              child: Text(isFull ? 'Full' : 'Join',
                  style: TextStyle(
                      color: isFull ? AppColors.textMuted : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ),
        ]),
      ),
    );
  }
}
