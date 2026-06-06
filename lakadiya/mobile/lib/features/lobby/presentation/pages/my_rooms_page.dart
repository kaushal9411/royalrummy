import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../game/presentation/bloc/game_bloc.dart';
import '../../data/room_repository.dart';

class MyRoomsPage extends StatefulWidget {
  const MyRoomsPage({super.key});
  @override
  State<MyRoomsPage> createState() => _MyRoomsPageState();
}

class _MyRoomsPageState extends State<MyRoomsPage> {
  final _repo = RoomRepository();
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rooms = await _repo.getMyActiveRooms();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _myUserId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : '';
  }

  void _rejoin(Map<String, dynamic> room) {
    final roomId = room['id'] as String;
    context.read<GameBloc>().add(GameJoinRoom(roomId, 0));
    context.go('/room/$roomId');
  }

  @override
  Widget build(BuildContext context) {
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
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => context.go('/lobby'),
        ),
        title: const Text(
          'My Active Rooms',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: const Color(0xFF0D1A28),
              onRefresh: _load,
              child: _rooms.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rooms.length,
                      itemBuilder: (_, i) => _ActiveRoomCard(
                        room: _rooms[i],
                        myUserId: _myUserId,
                        index: i,
                        onRejoin: () => _rejoin(_rooms[i]),
                      ),
                    ),
            ),
    );
  }

  Widget _buildEmpty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18)),
                  ),
                  child: const Center(
                    child: Text('🎮', style: TextStyle(fontSize: 32)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('No active rooms',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Rooms you join will appear here.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: () => context.go('/lobby'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark]),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 12)
                      ],
                    ),
                    child: const Text('Back to Lobby',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

// ── Individual room card ───────────────────────────────────────────────────
class _ActiveRoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final String myUserId;
  final int index;
  final VoidCallback onRejoin;

  const _ActiveRoomCard({
    required this.room,
    required this.myUserId,
    required this.index,
    required this.onRejoin,
  });

  @override
  Widget build(BuildContext context) {
    final count =
        (num.tryParse(room['player_count']?.toString() ?? '') ?? 0).toInt();
    final isPrivate = room['is_private'] == true;
    final isHost = room['host_id'] == myUserId;
    final betAmount =
        (num.tryParse(room['bet_amount']?.toString() ?? '') ?? 0).toDouble();
    final code = room['code'] as String? ?? '';
    final hostName = room['host_name'] as String? ?? 'Room';

    final accentColor = isPrivate ? AppColors.trump : AppColors.accent;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + index * 70),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
          opacity: v,
          child:
              Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              accentColor.withValues(alpha: 0.09),
              const Color(0xFF0A1520),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: accentColor.withValues(alpha: 0.32)),
          boxShadow: [
            BoxShadow(
                color: accentColor.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ───────────────────────────────────────────
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.14),
                    border: Border.all(
                        color: accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Icon(
                      isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                          isPrivate ? 'Private Room' : 'Public Room',
                          style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                        if (isHost) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      AppColors.accent.withValues(alpha: 0.3)),
                            ),
                            child: const Text('HOST',
                                style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text('Host: $hostName',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
                if (betAmount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '₹${betAmount.toInt()}',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ]),

              const SizedBox(height: 14),

              // ── Room code + copy ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: accentColor.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  Icon(Icons.tag_rounded, color: accentColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    code,
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: const Icon(Icons.copy_rounded,
                          color: AppColors.textSecondary, size: 14),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 14),

              // ── Player count + rejoin ─────────────────────────────────
              Row(children: [
                ...List.generate(
                    4,
                    (i) => Container(
                          width: 12,
                          height: 12,
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
                const SizedBox(width: 8),
                Text(
                  '$count / 4 players',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onRejoin,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark]),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Text(
                      'Rejoin',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
