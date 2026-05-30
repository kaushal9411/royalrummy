import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/socket_service.dart';
import '../../data/social_repository.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key});
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage>
    with SingleTickerProviderStateMixin {
  final _repo = SocialRepository();
  late final TabController _tabs;
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _convos = [];
  int  _totalUnread = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!mounted) return;
      setState(() {});
      // Refresh conversation list + unread count whenever Messages tab is opened
      if (_tabs.index == 3) _loadConvos();
    });
    _load();

    SocketService().on('private_message', _onIncomingMessage);
    SocketService().on('game_invite', _onGameInvite);
    SocketService().on('friend_request', _onFriendRequest);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtl.dispose();
    _debounce?.cancel();
    SocketService().off('private_message');
    SocketService().off('game_invite');
    SocketService().off('friend_request');
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.searchUsers(''),
        _repo.getFriends(),
        _repo.getPendingRequests(),
        _repo.getConversationList(),
        _repo.getUnreadCount(),
      ]);
      if (mounted) {
        setState(() {
          _players       = results[0] as List<Map<String, dynamic>>;
          _friends       = results[1] as List<Map<String, dynamic>>;
          _pendingRequests = results[2] as List<Map<String, dynamic>>;
          _convos        = results[3] as List<Map<String, dynamic>>;
          _totalUnread   = results[4] as int;
          _loading       = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Refresh only conversations + total unread (called when Messages tab opens or DM closes)
  Future<void> _loadConvos() async {
    try {
      final results = await Future.wait([
        _repo.getConversationList(),
        _repo.getUnreadCount(),
      ]);
      if (mounted) {
        setState(() {
          _convos      = results[0] as List<Map<String, dynamic>>;
          _totalUnread = results[1] as int;
        });
      }
    } catch (_) {}
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() { _loading = true; });
      try {
        final users = await _repo.searchUsers(q);
        if (mounted) setState(() { _players = users; _loading = false; });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _onIncomingMessage(dynamic data) {
    if (!mounted) return;
    _loadConvos(); // refresh conversation list + unread badge
  }

  void _onGameInvite(dynamic data) {
    if (!mounted) return;
    final d = Map<String, dynamic>.from(data);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Game Invite',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
        content: Text(
          '${d['fromUsername']} invited you to play!\nRoom: ${d['roomCode'] ?? ''}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Decline', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(context);
              context.go('/room/${d['roomId']}');
            },
            child: const Text('Join Room'),
          ),
        ],
      ),
    );
  }

  void _onFriendRequest(dynamic data) {
    if (!mounted) return;
    _repo.getPendingRequests().then((list) {
      if (mounted) setState(() => _pendingRequests = list);
    });
  }

  void _openDm(Map<String, dynamic> user) {
    // push keeps the Social page alive; when DM screen pops, we reload convos
    context.push('/dm/${user['id']}', extra: user['username'] ?? 'Player')
        .then((_) { if (mounted) _loadConvos(); });
  }

  void _sendInvite(Map<String, dynamic> user) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invite sent to ${user['username']}'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendFriendRequest(Map<String, dynamic> user) async {
    try {
      await _repo.sendFriendRequest(user['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to ${user['username']}'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send request: $e'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _acceptFriendRequest(Map<String, dynamic> request) async {
    try {
      await _repo.acceptFriendRequest(request['from_user_id']);
      if (mounted) {
        await _load();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request accepted!'),
            backgroundColor: AppColors.primary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept request: $e'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _declineFriendRequest(Map<String, dynamic> request) async {
    try {
      await _repo.declineFriendRequest(request['from_user_id']);
      if (mounted) {
        setState(() => _pendingRequests.removeWhere((r) => r['from_user_id'] == request['from_user_id']));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request declined'),
            backgroundColor: AppColors.primary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline request: $e'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
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
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF07101C), Color(0xFF0A1520)],
            ),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary),
          onPressed: () => context.go('/lobby'),
        ),
        title: const Text('Social', style: TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white38,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Players'),
            Tab(text: 'Friends (${_friends.length})'),
            Tab(text: 'Requests (${_pendingRequests.length})'),
            Tab(text: _totalUnread > 0 ? 'Messages ($_totalUnread)' : 'Messages'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_tabs.index == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchCtl,
                onChanged: _onSearch,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search players…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0D1827),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _PlayersList(players: _players, onDm: _openDm, onInvite: _sendFriendRequest, isFriendsTab: false),
                      _PlayersList(players: _friends, onDm: _openDm, onInvite: _sendInvite, isFriendsTab: true),
                      _PendingRequestsList(requests: _pendingRequests, onAccept: _acceptFriendRequest, onDecline: _declineFriendRequest),
                      _ConvoList(convos: _convos, onOpen: _openDm),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Players list ─────────────────────────────────────────────────────────────

class _PlayersList extends StatelessWidget {
  final List<Map<String, dynamic>> players;
  final void Function(Map<String, dynamic>) onDm;
  final void Function(Map<String, dynamic>) onInvite;
  final bool isFriendsTab;

  const _PlayersList({required this.players, required this.onDm, required this.onInvite, required this.isFriendsTab});

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const Center(
        child: Text('No players found', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: players.length,
      itemBuilder: (_, i) => _PlayerCard(player: players[i], onDm: onDm, onInvite: onInvite, isFriendsTab: isFriendsTab),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final Map<String, dynamic> player;
  final void Function(Map<String, dynamic>) onDm;
  final void Function(Map<String, dynamic>) onInvite;
  final bool isFriendsTab;

  const _PlayerCard({required this.player, required this.onDm, required this.onInvite, required this.isFriendsTab});

  @override
  Widget build(BuildContext context) {
    final level = player['level'] ?? 1;
    final avatar = player['avatar_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
            child: avatar == null
                ? Text(
                    (player['username'] as String? ?? 'P')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player['username'] ?? 'Player',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Lv.$level',
                        style: const TextStyle(
                            color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconBtn(
                icon: Icons.chat_bubble_outline_rounded,
                color: AppColors.primary,
                onTap: () => onDm(player),
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: isFriendsTab ? Icons.sports_esports_rounded : Icons.person_add_rounded,
                color: AppColors.accent,
                onTap: () => onInvite(player),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pending Requests list ────────────────────────────────────────────────────

class _PendingRequestsList extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final void Function(Map<String, dynamic>) onAccept;
  final void Function(Map<String, dynamic>) onDecline;

  const _PendingRequestsList({
    required this.requests,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(
        child: Text('No pending requests', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final req = requests[i];
        final avatar = req['from_user_avatar'] as String?;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null
                    ? Text(
                        (req['from_user_name'] as String? ?? 'P')[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req['from_user_name'] ?? 'Player',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text('sent you a friend request',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconBtn(
                    icon: Icons.close_rounded,
                    color: AppColors.danger,
                    onTap: () => onDecline(req),
                  ),
                  const SizedBox(width: 8),
                  _IconBtn(
                    icon: Icons.check_rounded,
                    color: AppColors.primary,
                    onTap: () => onAccept(req),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Conversations list ────────────────────────────────────────────────────────

class _ConvoList extends StatelessWidget {
  final List<Map<String, dynamic>> convos;
  final void Function(Map<String, dynamic>) onOpen;

  const _ConvoList({required this.convos, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (convos.isEmpty) {
      return const Center(
        child: Text('No conversations yet', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: convos.length,
      itemBuilder: (_, i) {
        final c = convos[i];
        final unread = (c['unread_count'] as int?) ?? 0;
        final avatar = c['other_avatar'] as String?;
        return GestureDetector(
          onTap: () => onOpen({
            'id': c['other_id'],
            'username': c['other_name'],
            'avatar_url': c['other_avatar'],
          }),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1827),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: unread > 0
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.07),
              ),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                      backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                      child: avatar == null
                          ? Text(
                              (c['other_name'] as String? ?? 'P')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          width: 16, height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('$unread',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c['other_name'] ?? 'Player',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          )),
                      const SizedBox(height: 2),
                      Text(c['last_text'] ?? '',
                          style: TextStyle(
                            color: unread > 0 ? Colors.white70 : Colors.white38,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (unread > 0)
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Shared icon button ────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 17),
      ),
    );
  }
}
