import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/socket_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/social_repository.dart';

const _kEmojis = ['😄', '👍', '🔥', '😂', '❤️', '😮', '👏', '🎉'];

class DmScreen extends StatefulWidget {
  final String userId;
  final String username;
  const DmScreen({super.key, required this.userId, required this.username});
  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final _repo = SocialRepository();
  final _msgCtl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _showEmoji = false;
  String? _myId;

  @override
  void initState() {
    super.initState();
    _myId = _decodeUserId();
    _load();
    SocketService().on('private_message', _onMessage);
  }

  String? _decodeUserId() {
    final token = StorageService.getToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = String.fromCharCodes(
        base64Url.decode(base64Url.normalize(parts[1])));
      final Map<String, dynamic> json = _parseJson(payload);
      return json['userId'] as String?;
    } catch (_) { return null; }
  }

  Map<String, dynamic> _parseJson(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    // Fallback naive parser
    final map = <String, dynamic>{};
    final trimmed = s.trim().replaceAll('{', '').replaceAll('}', '').replaceAll('"', '');
    for (final part in trimmed.split(',')) {
      final kv = part.trim().split(':');
      if (kv.length >= 2) map[kv[0].trim()] = kv.sublist(1).join(':').trim();
    }
    return map;
  }

  @override
  void dispose() {
    _msgCtl.dispose();
    _scroll.dispose();
    SocketService().off('private_message');
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final msgs = await _repo.getConversation(widget.userId);
      await _repo.markRead(widget.userId);
      if (mounted) setState(() { _messages = msgs; _loading = false; });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onMessage(dynamic data) {
    if (!mounted) return;
    final msg = Map<String, dynamic>.from(data);
    final senderId = msg['sender_id'] as String?;
    final receiverId = msg['receiver_id'] as String?;
    if ((senderId == widget.userId && receiverId == _myId) ||
        (senderId == _myId && receiverId == widget.userId)) {
      setState(() => _messages.add(msg));
      if (senderId == widget.userId) _repo.markRead(widget.userId);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _msgCtl.text.trim();
    if (text.isEmpty) return;
    
    // Add message to list immediately (optimistic update)
    final myMsg = {
      'sender_id': _myId,
      'receiver_id': widget.userId,
      'text': text,
      'sender_name': 'You',
      'created_at': DateTime.now().toIso8601String(),
    };
    
    setState(() {
      _messages.add(myMsg);
      _showEmoji = false;
    });
    
    _msgCtl.clear();
    _scrollToBottom();
    SocketService().sendPrivateMessage(widget.userId, text);
  }

  void _sendEmoji(String e) {
    _msgCtl.text += e;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF050B15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07101C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary),
          onPressed: () => context.go('/social'),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: Text(
                widget.username[0].toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(width: 10),
            Text(widget.username,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _messages.isEmpty
                      ? const Center(
                          child: Text('Say hello!', style: TextStyle(color: Colors.white38, fontSize: 16)))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _BubbleRow(
                            msg: _messages[i],
                            isMe: _messages[i]['sender_id'] == _myId,
                          ),
                        ),
            ),
            // Emoji quick-pick
            if (_showEmoji)
              Container(
                height: 52,
                color: const Color(0xFF0A1520),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _kEmojis.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _sendEmoji(_kEmojis[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Text(_kEmojis[i], style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
              ),
            // Input bar
            Container(
              color: const Color(0xFF07101C),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, color: AppColors.accent),
                    onPressed: () => setState(() => _showEmoji = !_showEmoji),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgCtl,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF0D1827),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 42, height: 42,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _BubbleRow extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  const _BubbleRow({required this.msg, required this.isMe});

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      if (isToday) return '$h:$m';
      return '${dt.day}/${dt.month} $h:$m';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final text = msg['text'] as String? ?? '';
    final timeLabel = _formatTime(msg['created_at'] as String?);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: Text(
                (msg['sender_name'] as String? ?? 'P')[0].toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : const Color(0xFF0D1827),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isMe ? null : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (timeLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Text(
                      timeLabel,
                      style: const TextStyle(color: Colors.white30, fontSize: 10),
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
