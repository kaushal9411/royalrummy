import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _repo    = RoomRepository();
  final _codeCtl = TextEditingController();
  bool _loading  = false;
  List<Map<String, dynamic>> _publicRooms = [];

  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _loadPublicRooms();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _enterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
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
    final level     = authState is AuthAuthenticated ? authState.user.level : 1;
    final coins     = authState is AuthAuthenticated ? authState.user.coins : 0;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [AppColors.accent, AppColors.accentLight],
          ).createShader(b),
          child: const Text('♠ LAKADIYA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 20)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_rounded, color: AppColors.accent),
            onPressed: () => context.go('/leaderboard'),
          ),
          IconButton(
            icon: const Icon(Icons.person_rounded, color: AppColors.primary),
            onPressed: () => context.go('/profile'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FadeTransition(
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
                // ── Welcome banner ──
                _WelcomeBanner(username: username, level: level, coins: coins),
                const SizedBox(height: 24),

                // ── Quick play ──
                const _SectionHeader(title: 'Quick Play', icon: Icons.flash_on_rounded),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedActionCard(
                        icon: Icons.add_circle_rounded,
                        label: 'Create Room',
                        subtitle: 'Public game',
                        gradient: const [Color(0xFF00C853), Color(0xFF007E33)],
                        iconBg: const Color(0xFF00C853),
                        onTap: _loading ? null : () => _createRoom(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedActionCard(
                        icon: Icons.lock_rounded,
                        label: 'Private Room',
                        subtitle: 'Invite only',
                        gradient: const [Color(0xFFFFD600), Color(0xFFC7A600)],
                        iconBg: const Color(0xFFFFD600),
                        onTap: _loading ? null : () => _createRoom(isPrivate: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Join by code ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.darkBorder),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.trump.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.vpn_key_rounded, color: AppColors.trump, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text('Join with Code',
                              style: TextStyle(color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codeCtl,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                letterSpacing: 4,
                              ),
                              decoration: InputDecoration(
                                hintText: 'ENTER CODE',
                                hintStyle: const TextStyle(color: AppColors.textMuted, letterSpacing: 2, fontSize: 14),
                                filled: true,
                                fillColor: AppColors.darkCard,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.darkBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.darkBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.trump, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _loading ? null : _joinByCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.trump,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Open Rooms ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionHeader(title: 'Open Rooms', icon: Icons.meeting_room_rounded),
                    GestureDetector(
                      onTap: _loadPublicRooms,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_publicRooms.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: const Column(
                      children: [
                        Text('🃏', style: TextStyle(fontSize: 36)),
                        SizedBox(height: 12),
                        Text('No open rooms yet',
                            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Create one and invite friends!',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  )
                else
                  ...List.generate(_publicRooms.length, (i) => _AnimatedRoomCard(
                    room: _publicRooms[i],
                    index: i,
                    onJoin: () async {
                      setState(() => _loading = true);
                      try {
                        final r = await _repo.joinRoom(_publicRooms[i]['code'] as String);
                        if (mounted) {
                          context.read<GameBloc>().add(GameJoinRoom(r['id'] as String, 0));
                          context.go('/room/${r['id']}');
                        }
                      } catch (_) {
                        _showError('Could not join room');
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
                  )),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Welcome banner ─────────────────────────────────────────────────────────
class _WelcomeBanner extends StatelessWidget {
  final String username;
  final int level;
  final int coins;
  const _WelcomeBanner({required this.username, required this.level, required this.coins});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D2818), Color(0xFF0A1E30)],
      ),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      boxShadow: [
        BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4)),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 10)],
          ),
          child: Center(
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : 'P',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Text(username,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatPill(Icons.bolt_rounded, 'Lv $level', AppColors.accent),
            const SizedBox(height: 6),
            _StatPill(Icons.monetization_on_rounded, '$coins', AppColors.primary),
          ],
        ),
      ],
    ),
  );
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

// ── Section header ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppColors.accent, size: 20),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
    ],
  );
}

// ── Animated action card ───────────────────────────────────────────────────
class _AnimatedActionCard extends StatefulWidget {
  final IconData icon;
  final String label, subtitle;
  final List<Color> gradient;
  final Color iconBg;
  final VoidCallback? onTap;
  const _AnimatedActionCard({
    required this.icon, required this.label, required this.subtitle,
    required this.gradient, required this.iconBg, this.onTap,
  });
  @override
  State<_AnimatedActionCard> createState() => _AnimatedActionCardState();
}

class _AnimatedActionCardState extends State<_AnimatedActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.93).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (_) { if (widget.onTap != null) _ctrl.forward(); },
    onTapUp:     (_) { _ctrl.reverse(); widget.onTap?.call(); },
    onTapCancel: ()  => _ctrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.gradient[0].withValues(alpha: 0.15),
              widget.gradient[1].withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: widget.gradient[0].withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(color: widget.gradient[0].withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: widget.gradient),
                boxShadow: [BoxShadow(color: widget.gradient[0].withValues(alpha: 0.4), blurRadius: 10)],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 12),
            Text(widget.label,
                style: TextStyle(color: widget.gradient[0], fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(widget.subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    ),
  );
}

// ── Animated room card ─────────────────────────────────────────────────────
class _AnimatedRoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final int index;
  final VoidCallback onJoin;
  const _AnimatedRoomCard({required this.room, required this.index, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final count = (num.tryParse(room['player_count']?.toString() ?? '') ?? 0).toInt();
    final isFull = count >= 4;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 80),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Center(child: Text('♠', style: TextStyle(color: AppColors.primary, fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room['host_name'] as String? ?? 'Room',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.people_rounded, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text('$count / 4 players',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(width: 10),
                      Icon(Icons.circle, size: 6, color: isFull ? AppColors.danger : AppColors.primary),
                      const SizedBox(width: 4),
                      Text(isFull ? 'Full' : 'Open',
                          style: TextStyle(
                            color: isFull ? AppColors.danger : AppColors.primary,
                            fontSize: 11, fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: isFull ? null : onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.darkBorder,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(isFull ? 'Full' : 'Join',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
