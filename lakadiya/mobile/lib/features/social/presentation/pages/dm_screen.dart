import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/socket_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/social_repository.dart';

// 32 emojis covering the most-used categories
const _kEmojis = [
  '😄', '😂', '😍', '😎', '🥰', '😭', '🤩', '😡',
  '😮', '🤔', '😅', '😬', '🤣', '🫠', '💀', '🤯',
  '👍', '👎', '👏', '🙌', '🤝', '🫶', '✌️', '👋',
  '❤️', '🔥', '🎉', '⭐', '💎', '🃏', '🎮', '🎲',
];

class DmScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? avatarUrl;
  const DmScreen(
      {super.key,
      required this.userId,
      required this.username,
      this.avatarUrl});
  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final _repo   = SocialRepository();
  final _msgCtl = TextEditingController();
  final _scroll = ScrollController();
  final _focus  = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  final Set<dynamic> _seenIds = {};

  bool _loading    = true;
  bool _sending    = false;
  bool _showEmoji  = false;
  bool _showFab    = false;

  String? _myId;

  // Store callback refs so we only remove OUR listener, not everyone else's
  late final SocketCallback _msgCb;
  late final SocketCallback _readCb;

  @override
  void initState() {
    super.initState();
    // Read from Hive first (sync, fast). If null, _resolveMyId() fetches from API.
    _myId = StorageService.getUser()?['id']?.toString();

    // Suppress FCM banners for this conversation while it's on screen.
    FcmService.activeDmUserId = widget.userId;

    _msgCb  = _onSocketMessage;
    _readCb = _onSocketRead;
    SocketService().on('private_message', _msgCb);
    SocketService().on('messages_read',   _readCb);

    _scroll.addListener(_scrollListener);

    _focus.addListener(() {
      if (_focus.hasFocus && _showEmoji) {
        setState(() => _showEmoji = false);
      }
      if (_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
      }
    });

    _resolveMyId().then((_) => _load());
  }

  // Ensures _myId is set before loading messages. Falls back to API /users/me
  // if Hive returned null (can happen right after an account switch).
  Future<void> _resolveMyId() async {
    if (_myId != null) return;
    try {
      final res = await ApiService().get('/users/me');
      final id = (res.data as Map?)?['id']?.toString();
      if (id != null && mounted) {
        _myId = id;
        // Also persist so next open is instant
        final stored = StorageService.getUser();
        if (stored != null) {
          await StorageService.saveUser({...stored, 'id': id});
        }
      }
    } catch (_) {
      // If API also fails, messages will still load but left/right may be wrong
    }
  }

  @override
  void dispose() {
    // Clear only if it's still pointing at us (guards against a newer screen).
    if (FcmService.activeDmUserId == widget.userId) {
      FcmService.activeDmUserId = null;
    }
    SocketService().offCallback('private_message', _msgCb);
    SocketService().offCallback('messages_read',   _readCb);
    _scroll.removeListener(_scrollListener);
    _scroll.dispose();
    _msgCtl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─── Scroll FAB visibility ────────────────────────────────────────────────

  void _scrollListener() {
    if (!_scroll.hasClients) return;
    final dist = _scroll.position.maxScrollExtent - _scroll.offset;
    final show = dist > 150;
    if (show != _showFab) setState(() => _showFab = show);
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final msgs = await _repo.getConversation(widget.userId);
      await _repo.markRead(widget.userId);
      if (!mounted) return;
      final list = (msgs as List).map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        final id = map['id'];
        if (id != null) _seenIds.add(id);
        return map;
      }).toList();
      setState(() {
        _messages = list;
        _loading  = false;
      });
      _scrollToBottom(animated: false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Socket handlers ──────────────────────────────────────────────────────

  void _onSocketMessage(dynamic data) {
    if (!mounted) return;
    final raw = Map<String, dynamic>.from(data as Map);
    final sid = raw['sender_id'] as String?;
    final rid = raw['receiver_id'] as String?;
    final id  = raw['id'];

    // Only accept messages sent BY the other user TO me in this conversation
    if (sid != widget.userId || rid != _myId) return;

    // Deduplicate — guard against duplicate events
    if (id != null && _seenIds.contains(id)) return;
    if (id != null) _seenIds.add(id);

    // Guarantee is_read field is present
    final msg = Map<String, dynamic>.from(raw)..putIfAbsent('is_read', () => false);

    setState(() => _messages.add(msg));
    _repo.markRead(widget.userId);
    _scrollToBottom();
  }

  void _onSocketRead(dynamic data) {
    if (!mounted) return;
    final d = Map<String, dynamic>.from(data as Map);
    if (d['byUserId'] != widget.userId) return;
    // Mark all messages I sent as read (show double-blue tick)
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        if (_messages[i]['sender_id'] == _myId) {
          _messages[i] = Map<String, dynamic>.from(_messages[i])
            ..['is_read'] = true;
        }
      }
    });
  }

  // ─── Scroll helpers ───────────────────────────────────────────────────────

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(max,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  // ─── Send ─────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _msgCtl.text.trim();
    if (text.isEmpty || _sending) return;

    // Unique temp key so we can find & replace the optimistic bubble
    final tempKey = DateTime.now().microsecondsSinceEpoch.toString();
    final optimistic = <String, dynamic>{
      '_tempKey': tempKey,
      'id': null,
      'sender_id': _myId,
      'receiver_id': widget.userId,
      'text': text,
      'created_at': DateTime.now().toIso8601String(),
      'is_read': false,
    };

    _msgCtl.clear();
    if (_showEmoji) setState(() => _showEmoji = false);
    setState(() {
      _messages.add(optimistic);
      _sending = true;
    });
    _scrollToBottom();

    try {
      // REST API → saves to DB, emits socket to recipient, returns real msg with ID
      final saved = await _repo.sendMessage(widget.userId, text);
      final id = saved['id'];
      if (id != null) _seenIds.add(id);
      if (mounted) {
        final idx =
            _messages.indexWhere((m) => m['_tempKey'] == tempKey);
        if (idx >= 0) setState(() => _messages[idx] = saved);
      }
    } catch (_) {
      // On failure mark the optimistic bubble as errored
      if (mounted) {
        final idx =
            _messages.indexWhere((m) => m['_tempKey'] == tempKey);
        if (idx >= 0) {
          setState(() => _messages[idx] =
              Map<String, dynamic>.from(_messages[idx])
                ..['_failed'] = true);
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─── Emoji picker ─────────────────────────────────────────────────────────

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _showEmoji = true);
      });
    }
  }

  void _insertEmoji(String emoji) {
    final sel  = _msgCtl.selection;
    final text = _msgCtl.text;
    final pos  = sel.isValid ? sel.end : text.length;
    final next = text.substring(0, pos) + emoji + text.substring(pos);
    _msgCtl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + emoji.length),
    );
  }

  // ─── Grouping helpers ─────────────────────────────────────────────────────

  bool _needsDateSep(Map? prev, Map curr) {
    if (prev == null) return true;
    try {
      final a = DateTime.parse(prev['created_at'] as String).toLocal();
      final b = DateTime.parse(curr['created_at'] as String).toLocal();
      return a.day != b.day || a.month != b.month || a.year != b.year;
    } catch (_) {
      return false;
    }
  }

  bool _sameGroup(Map? prev, Map curr) {
    if (prev == null) return false;
    if (prev['sender_id'] != curr['sender_id']) return false;
    try {
      final a = DateTime.parse(prev['created_at'] as String);
      final b = DateTime.parse(curr['created_at'] as String);
      return b.difference(a).inMinutes < 3;
    } catch (_) {
      return false;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B15),
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildMessageList(),
                  if (_showFab)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: _ScrollFab(onTap: _scrollToBottom),
                    ),
                ],
              ),
            ),
            if (_showEmoji) _buildEmojiGrid(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: const Color(0xFF07101C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              username: widget.username,
              avatarUrl: widget.avatarUrl,
              size: 36,
              solidColor: AppColors.primary.withValues(alpha: 0.2),
              textColor: AppColors.primary,
              fontSize: 13,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                  const Text('tap to view profile',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildMessageList() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              username: widget.username,
              avatarUrl: widget.avatarUrl,
              size: 72,
              solidColor: AppColors.primary.withValues(alpha: 0.15),
              textColor: AppColors.primary,
              fontSize: 28,
            ),
            const SizedBox(height: 16),
            Text(widget.username,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 6),
            const Text('No messages yet. Say hello! 👋',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg  = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final next =
            i < _messages.length - 1 ? _messages[i + 1] : null;

        final showDate    = _needsDateSep(prev, msg);
        final isGrouped   = !showDate && _sameGroup(prev, msg);
        final lastInGroup = next == null || !_sameGroup(msg, next);
        final isMe        = msg['sender_id'] == _myId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate) _DateSep(iso: msg['created_at'] as String?),
            _Bubble(
              msg: msg,
              isMe: isMe,
              grouped: isGrouped,
              lastInGroup: lastInGroup,
              otherUsername: widget.username,
              otherAvatar: widget.avatarUrl,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmojiGrid() => Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF07101C),
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            childAspectRatio: 1,
          ),
          itemCount: _kEmojis.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _insertEmoji(_kEmojis[i]),
            child: Center(
                child: Text(_kEmojis[i],
                    style: const TextStyle(fontSize: 24))),
          ),
        ),
      );

  Widget _buildInputBar() => SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFF07101C),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Emoji / keyboard toggle
              IconButton(
                icon: Icon(
                  _showEmoji
                      ? Icons.keyboard_rounded
                      : Icons.emoji_emotions_outlined,
                  color: AppColors.accent,
                  size: 24,
                ),
                onPressed: _toggleEmoji,
              ),
              // Text input (multiline up to 120px)
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: TextField(
                    controller: _msgCtl,
                    focusNode: _focus,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF0D1827),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendBtn(sending: _sending, onTap: _send),
            ],
          ),
        ),
      );
}

// ── Date separator ─────────────────────────────────────────────────────────────

class _DateSep extends StatelessWidget {
  final String? iso;
  const _DateSep({this.iso});

  String get _label {
    if (iso == null) return '';
    try {
      final dt  = DateTime.parse(iso!).toLocal();
      final now = DateTime.now();
      final today  = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final diff   = today.difference(msgDay).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      const mo = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final year = dt.year != now.year ? ', ${dt.year}' : '';
      return '${mo[dt.month - 1]} ${dt.day}$year';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
              child: Divider(
                  color: Colors.white.withValues(alpha: 0.08),
                  thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
              child: Divider(
                  color: Colors.white.withValues(alpha: 0.08),
                  thickness: 1)),
        ],
      ),
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  final bool grouped;
  final bool lastInGroup;
  final String otherUsername;
  final String? otherAvatar;

  const _Bubble({
    required this.msg,
    required this.isMe,
    required this.grouped,
    required this.lastInGroup,
    required this.otherUsername,
    this.otherAvatar,
  });

  String _time(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text        = msg['text'] as String? ?? '';
    final time        = _time(msg['created_at'] as String?);
    final isSending   = msg['id'] == null && msg['_failed'] == null;
    final isFailed    = msg['_failed'] == true;
    final isRead      = msg['is_read'] == true;

    return Padding(
      padding: EdgeInsets.only(
        top:    grouped ? 2 : 8,
        bottom: lastInGroup ? 4 : 0,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Other user avatar — only on the last bubble in a group
          if (!isMe) ...[
            if (lastInGroup)
              UserAvatar(
                username: otherUsername,
                avatarUrl: otherAvatar,
                size: 28,
                solidColor: AppColors.primary.withValues(alpha: 0.2),
                textColor: AppColors.primary,
                fontSize: 10,
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 6),
          ],

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  decoration: BoxDecoration(
                    color: isFailed
                        ? AppColors.danger.withValues(alpha: 0.3)
                        : isMe
                            ? AppColors.primary
                            : const Color(0xFF0D1827),
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:
                          Radius.circular(isMe ? 18 : (lastInGroup ? 4 : 18)),
                      bottomRight:
                          Radius.circular(isMe ? (lastInGroup ? 4 : 18) : 18),
                    ),
                    border: isMe
                        ? null
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.87),
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                ),
                // Timestamp + tick (only last in group)
                if (lastInGroup && (time.isNotEmpty || isMe))
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (time.isNotEmpty)
                          Text(time,
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 10)),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          if (isFailed)
                            const Icon(Icons.error_outline_rounded,
                                size: 12, color: AppColors.danger)
                          else if (isSending)
                            const Icon(Icons.access_time_rounded,
                                size: 12, color: Colors.white30)
                          else if (isRead)
                            Icon(Icons.done_all_rounded,
                                size: 13,
                                color: AppColors.primary
                                    .withValues(alpha: 0.9))
                          else
                            const Icon(Icons.done_rounded,
                                size: 13, color: Colors.white38),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),

          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Scroll-to-bottom FAB ───────────────────────────────────────────────────────

class _ScrollFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollFab({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1827),
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10)
            ],
          ),
          child: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary, size: 22),
        ),
      );
}

// ── Send button ────────────────────────────────────────────────────────────────

class _SendBtn extends StatelessWidget {
  final bool sending;
  final VoidCallback onTap;
  const _SendBtn({required this.sending, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 10)
            ],
          ),
          child: sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded,
                  color: Colors.white, size: 20),
        ),
      );
}
