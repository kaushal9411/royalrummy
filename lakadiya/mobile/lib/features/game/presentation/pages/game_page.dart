import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/services/socket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/card_entity.dart';
import '../../domain/entities/game_state_entity.dart';
import '../bloc/game_bloc.dart';
import '../widgets/card_widget.dart';
import '../widgets/bid_dialog.dart';
import '../../../social/data/social_repository.dart';

// ── Sound helper ───────────────────────────────────────────────────────────────
class _Sfx {
  static AudioPlayer? _player;

  static Future<void> _play(String name) async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(AssetSource('sounds/$name.ogg'));
    } catch (_) {
      HapticFeedback.lightImpact();
    }
  }

  static void cardDrop() => _play('card_play');
  static void trickWin() => _play('trick_win');
  static void gameWin() => _play('game_win');

  static void cleanup() {
    _player?.dispose();
    _player = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class GamePage extends StatefulWidget {
  final String roomId;
  const GamePage({super.key, required this.roomId});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  late final AnimationController _trickAnimCtrl;
  TrickResultData? _animatingTrick;
  TrickResultData? _lastTriggered;
  bool _gameWinSoundPlayed = false;

  // ── In-room chat ──
  final List<Map<String, dynamic>> _chatMessages = [];
  final List<String> _floatingEmojis = [];
  final TextEditingController _chatInputCtl = TextEditingController();
  final ScrollController _chatScrollCtl = ScrollController();
  StateSetter? _chatModalSetState;
  bool _bidDialogOpen = false;
  bool _roundResultDialogOpen = false;
  bool _addBotDialogOpen = false;
  int? _addBotDialogSeat;
  // Seats whose player left and are awaiting host action (add bot / wait).
  final Set<int> _abandonedSeats = {};
  final Map<int, String> _abandonedNames = {};
  final Map<int, Timer> _rePromptTimers = {};

  // Responsible gaming: show a reminder every 30 minutes of continuous play
  Timer? _reminderTimer;

  // ── In-game private DMs ──
  String? _myUserId;
  String? _myUsername;
  final Map<String, List<Map<String, dynamic>>> _inboxMsgs = {};
  final List<Map<String, dynamic>> _dmToasts = [];
  final List<Map<String, dynamic>> _floatingMsgs = [];

  // Unread DM count per sender userId — drives the pulsing badge on seats.
  final Map<String, int> _unreadBySender = {};

  // ── Inline quick-chat (message icon tap) ──
  int? _activeInlineSeat;
  PlayerInfo? _activeInlinePlayer;
  final TextEditingController _inlineChatCtl = TextEditingController();
  final FocusNode _inlineChatFocus = FocusNode();
  final ScrollController _inlineScrollCtl = ScrollController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _trickAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _trickAnimCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _animatingTrick = null);
      }
    });
    context.read<GameBloc>().add(GameJoinRoom(widget.roomId, 0));

    SocketService().on('chat_message', _onRoomChat);
    SocketService().on('emoji_reaction', _onEmojiReaction);
    SocketService().on('game_dm', _onGameDm);
    SocketService().on('player_left_game', _onPlayerLeftGame);
    SocketService().on('player_replaced_by_bot', _onPlayerReplacedByBot);
    SocketService().on('player_rejoined_game', _onPlayerRejoinedGame);

    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _myUserId   = authState.user.id;
      _myUsername = authState.user.username;
    }

    // Responsible gaming reminder — fires after 30 min, then every 30 min
    _reminderTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) _showReminderBanner();
    });
  }

  void _showReminderBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0E1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Responsible Gaming Reminder',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('You\'ve been playing for 30+ minutes. Take a break if needed.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            const Text('Help: iCare 1800-599-0019',
                style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _onRoomChat(dynamic data) {
    if (!mounted) return;
    final msg = Map<String, dynamic>.from(data as Map);
    // Own messages are added optimistically — ignore the socket echo
    if ((msg['username'] as String?) == _myUsername) return;
    setState(() => _chatMessages.add(msg));
    _chatModalSetState?.call(() {});
    _scrollChatToBottom();
    // Public indicator: float the message near the sender's seat so everyone
    // notices even with the chat sheet closed.
    final relSeat = _relSeatForUser(msg['userId'] as String?);
    if (relSeat != null && relSeat != 0) {
      _showFloatingNearSeat(relSeat, msg['message'] as String? ?? '');
    }
  }

  // Relative seat (0=me,1=right,2=top,3=left) for a userId, or null if absent.
  int? _relSeatForUser(String? uid) {
    if (uid == null) return null;
    final st = context.read<GameBloc>().state;
    if (st is! GameInProgress) return null;
    for (final p in st.state.players) {
      if (p.userId == uid) return (p.seat - st.state.mySeat + 4) % 4;
    }
    return null;
  }

  void _showFloatingNearSeat(int relSeat, String text) {
    final id = DateTime.now().microsecondsSinceEpoch;
    setState(() => _floatingMsgs.add({'text': text, 'relSeat': relSeat, 'id': id}));
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _floatingMsgs.removeWhere((m) => m['id'] == id));
    });
  }

  void _onEmojiReaction(dynamic data) {
    if (!mounted) return;
    final emoji = (data as Map)['emoji'] as String? ?? '😊';
    setState(() => _floatingEmojis.add(emoji));
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _floatingEmojis.remove(emoji));
    });
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtl.hasClients) {
        _chatScrollCtl.animateTo(
          _chatScrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Private, ephemeral in-game DM (only sender + receiver). The server echoes
  // our own sends back; we ignore those because we add them optimistically.
  void _onGameDm(dynamic data) {
    if (!mounted) return;
    final d = Map<String, dynamic>.from(data as Map);
    final from = d['from'] as String?;
    final fromMe = from == _myUserId;
    if (fromMe) return; // ignore echo of our own message
    final partner = from; // for a received DM, the partner is the sender
    if (partner == null) return;

    final entry = <String, dynamic>{
      'fromMe':   false,
      'text':     d['text'] as String? ?? '',
      'fromName': d['fromName'] as String? ?? 'Player',
      'ts':       d['ts'] ?? DateTime.now().millisecondsSinceEpoch,
    };
    final convoOpen = _activeInlinePlayer?.userId == partner;
    final toastId = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _inboxMsgs[partner] ??= [];
      _inboxMsgs[partner]!.add(entry);
      if (!convoOpen) {
        _unreadBySender[partner] = (_unreadBySender[partner] ?? 0) + 1;
        _dmToasts.add({
          'sender_id':   partner,
          'sender_name': entry['fromName'],
          'text':        entry['text'],
          '\$toastId':   toastId,
        });
      }
    });
    HapticFeedback.lightImpact(); // subtle buzz so the player notices
    if (convoOpen) {
      _scrollInlineToBottom();
    } else {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _dmToasts.removeWhere((t) => t['\$toastId'] == toastId));
      });
    }
  }

  void _scrollInlineToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inlineScrollCtl.hasClients) {
        _inlineScrollCtl.jumpTo(_inlineScrollCtl.position.maxScrollExtent);
      }
    });
  }

  // ── A player left mid-game ──────────────────────────────────────────────────
  void _onPlayerLeftGame(dynamic data) {
    if (!mounted) return;
    final d = Map<String, dynamic>.from(data as Map);
    final seat     = (d['seat'] as num?)?.toInt();
    final username = d['username'] as String? ?? 'A player';
    final hostId   = d['hostId'] as String?;
    if (seat == null) return;

    _abandonedSeats.add(seat);
    _abandonedNames[seat] = username;

    // Notify everyone.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$username left the game'),
        backgroundColor: const Color(0xFF6A3DF0),
        duration: const Duration(seconds: 3),
      ));

    // Only the (possibly new) host is asked to drop in a bot.
    if (hostId != null && hostId == _myUserId) {
      _showAddBotPrompt(seat, username);
    }
  }

  void _onPlayerReplacedByBot(dynamic data) {
    if (!mounted) return;
    final d = Map<String, dynamic>.from(data as Map);
    final seat = (d['seat'] as num?)?.toInt();
    final name = d['username'] as String? ?? 'A bot';
    if (seat != null) _resolveAbandonedSeat(seat);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$name took over the empty seat'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ));
  }

  // The left player came back → stop pestering the host to add a bot.
  void _onPlayerRejoinedGame(dynamic data) {
    if (!mounted) return;
    final d = Map<String, dynamic>.from(data as Map);
    final seat     = (d['seat'] as num?)?.toInt();
    final username = d['username'] as String? ?? 'A player';
    if (seat == null) return;
    _resolveAbandonedSeat(seat);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$username is back in the game'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ));
  }

  // Clears all tracking for a seat and closes the prompt if it's showing for it.
  void _resolveAbandonedSeat(int seat) {
    _abandonedSeats.remove(seat);
    _abandonedNames.remove(seat);
    _rePromptTimers.remove(seat)?.cancel();
    if (_addBotDialogOpen && _addBotDialogSeat == seat) {
      Navigator.of(context, rootNavigator: true).pop();
      _addBotDialogOpen = false;
      _addBotDialogSeat = null;
    }
  }

  void _showAddBotPrompt(int seat, String username) {
    if (_addBotDialogOpen) return;
    _addBotDialogOpen = true;
    _addBotDialogSeat = seat;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        title: const Text('Player left',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(
          '$username left the game. Add a Medium bot to take their seat and continue, '
          'or wait — we\'ll ask again in 10s if they don\'t return.',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _addBotDialogOpen = false;
              _addBotDialogSeat = null;
              Navigator.of(dctx).pop();
              _scheduleRePrompt(seat); // ask again in 10s if still gone
            },
            child: const Text('Wait', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              _addBotDialogOpen = false;
              _addBotDialogSeat = null;
              _resolveAbandonedSeat(seat);
              Navigator.of(dctx).pop();
              SocketService().replaceWithBot(widget.roomId, seat);
            },
            icon: const Icon(Icons.smart_toy_rounded, size: 18, color: Colors.white),
            label: const Text('Add Medium Bot', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) => _addBotDialogOpen = false);
  }

  // Re-ask the host after 10s if the seat is still abandoned (no bot, not back).
  void _scheduleRePrompt(int seat) {
    _rePromptTimers.remove(seat)?.cancel();
    _rePromptTimers[seat] = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_abandonedSeats.contains(seat) && !_addBotDialogOpen) {
        _showAddBotPrompt(seat, _abandonedNames[seat] ?? 'A player');
      }
    });
  }

  // ── Leaving an active game ──────────────────────────────────────────────────
  bool _isGameActive() {
    final st = context.read<GameBloc>().state;
    return st is GameInProgress && st.state.phase != 'game_end';
  }

  void _leaveGame() {
    if (_isGameActive()) {
      // Tell the table so others are notified and the host can add a bot.
      SocketService().leaveGame(widget.roomId);
    }
    context.read<GameBloc>().add(GameLeave());
    context.go('/lobby');
  }

  Future<void> _confirmLeaveGame() async {
    if (!_isGameActive()) { _leaveGame(); return; }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        title: const Text('Leave the game?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text(
          'The game is still in progress. Your seat will be offered to a bot so the others can keep playing.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Stay', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (leave == true) _leaveGame();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _trickAnimCtrl.dispose();
    _chatInputCtl.dispose();
    _chatScrollCtl.dispose();
    _inlineChatCtl.dispose();
    _inlineChatFocus.dispose();
    _inlineScrollCtl.dispose();
    SocketService().off('chat_message');
    SocketService().off('emoji_reaction');
    SocketService().off('game_dm');
    SocketService().off('player_left_game');
    SocketService().off('player_replaced_by_bot');
    SocketService().off('player_rejoined_game');
    for (final t in _rePromptTimers.values) { t.cancel(); }
    _Sfx.cleanup();
    super.dispose();
  }

  // ── Inline quick-chat controls ─────────────────────────────────────────────
  void _openInlineChat(PlayerInfo player, int relSeat) {
    setState(() {
      _activeInlineSeat   = relSeat;
      _activeInlinePlayer = player;
      if (player.userId != null) _unreadBySender.remove(player.userId); // mark read
    });
    _inlineChatCtl.clear();
    _scrollInlineToBottom();
    Future.microtask(() => _inlineChatFocus.requestFocus());
  }

  // Opens the private chat with a player identified by userId (used by toasts).
  void _openInlineChatByUserId(String uid) {
    final st = context.read<GameBloc>().state;
    if (st is! GameInProgress) return;
    PlayerInfo? player;
    for (final p in st.state.players) {
      if (p.userId == uid) { player = p; break; }
    }
    if (player == null) return;
    final relSeat = (player.seat - st.state.mySeat + 4) % 4;
    _openInlineChat(player, relSeat);
  }

  void _closeInlineChat() {
    setState(() { _activeInlineSeat = null; _activeInlinePlayer = null; });
    _inlineChatFocus.unfocus();
  }

  void _submitInlineChat() {
    final text   = _inlineChatCtl.text.trim();
    final player = _activeInlinePlayer;
    if (text.isEmpty || player == null || player.userId == null) {
      _inlineChatCtl.clear();
      return;
    }
    final uid = player.userId!;
    setState(() {
      _inboxMsgs[uid] ??= [];
      _inboxMsgs[uid]!.add({
        'fromMe':   true,
        'text':     text,
        'fromName': _myUsername ?? 'You',
        'ts':       DateTime.now().millisecondsSinceEpoch,
      });
    });
    // Private — delivered ONLY to this player (+ echoed to us, which we ignore).
    SocketService().sendGameDm(widget.roomId, uid, text);
    _inlineChatCtl.clear();
    _scrollInlineToBottom();
    // Keep the panel open so the conversation/history stays visible.
  }

  // ── Player profile dialog ──────────────────────────────────────────────────
  void _showPlayerProfile(BuildContext ctx, PlayerInfo player) {
    if (player.isBot || player.userId == null) return;
    showDialog(
      context: ctx,
      builder: (_) => _PlayerProfileDialog(player: player),
    );
  }

  void _showBidDialog() {
    if (_bidDialogOpen) return;
    _bidDialogOpen = true;
    var bidWasPlaced = false;
    final bloc = context.read<GameBloc>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BidDialog(
        onBid: (bid) {
          bidWasPlaced = true;
          _bidDialogOpen = false;
          bloc.add(GamePlaceBid(bid));
        },
      ),
    ).then((_) {
      _bidDialogOpen = false;
      // Don't reopen if the user already confirmed a bid — state just hasn't
      // updated yet (server round-trip pending), so the check below would
      // incorrectly think the bid is still missing.
      if (!mounted || bidWasPlaced) return;
      final gs = bloc.state;
      if (gs is GameInProgress &&
          gs.state.isBidding &&
          gs.state.isMyTurn &&
          !gs.state.bids.containsKey(gs.state.mySeat)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showBidDialog());
      }
    });
  }

  // ── Open half-screen WhatsApp-style room chat ──────────────────────────────
  void _openChatModal(BuildContext ctx) {
    _scrollChatToBottom();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.90,
        minChildSize: 0.50,
        maxChildSize: 0.98,
        expand: false,
        builder: (_, __) => StatefulBuilder(
          builder: (_, setMs) {
            _chatModalSetState = setMs;
            return _ChatSheetContent(
              messages: _chatMessages,
              scrollCtl: _chatScrollCtl,
              inputCtl: _chatInputCtl,
              myUsername: _myUsername,
              onSend: (text) {
                _chatMessages.add({
                  'username': _myUsername ?? 'You',
                  'message': text,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });
                SocketService().sendChat(widget.roomId, text);
                setMs(() {});
                _scrollChatToBottom();
              },
            );
          },
        ),
      ),
    ).then((_) => _chatModalSetState = null);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          if (_isGameActive()) SocketService().leaveGame(widget.roomId);
          context.read<GameBloc>().add(GameLeave());
        }
      },
      child: Scaffold(
        body: BlocConsumer<GameBloc, GameState>(
          listener: (ctx, state) {
            if (state is GameInProgress) {
              if (state.state.isBidding &&
                  state.state.isMyTurn &&
                  !state.state.bids.containsKey(state.state.mySeat) &&
                  !_roundResultDialogOpen) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _showBidDialog());
              }
              if (state.lastTrickResult != null &&
                  !identical(state.lastTrickResult, _lastTriggered) &&
                  state.lastTrickResult!.trickCards.isNotEmpty) {
                _lastTriggered = state.lastTrickResult;
                _Sfx.trickWin();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _animatingTrick = state.lastTrickResult);
                    _trickAnimCtrl.forward(from: 0);
                  }
                });
              }
              if (state.lastRoundResult != null &&
                  state.state.phase == 'round_end') {
                _showRoundResult(ctx, state.lastRoundResult!, state.state.players);
              }
              if (state.gameResult != null &&
                  state.state.phase == 'game_end') {
                if (!_gameWinSoundPlayed) {
                  _gameWinSoundPlayed = true;
                  _Sfx.gameWin();
                }
                _showGameResult(ctx, state.gameResult!);
              }
              if (state.errorMessage != null) {
                ScaffoldMessenger.of(ctx)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: Text(state.errorMessage!),
                    backgroundColor: AppColors.danger,
                    duration: const Duration(seconds: 2),
                  ));
              }
            }
            if (state is GameErrorState) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppColors.danger),
              );
            }
          },
          builder: (ctx, state) {
            final inGame = state is GameInProgress;
            final child = inGame ? _buildGame(ctx, state) : _buildLoader();
            // Cross-fade + gentle zoom when the table first appears.
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 480),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
                  child: c,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(inGame), child: child),
            );
          },
        ),
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Widget _buildLoader() => const Stack(
    children: [
      _WoodBackground(),
      Center(child: CircularProgressIndicator(color: Colors.white)),
    ],
  );

  // ── Main game layout ───────────────────────────────────────────────────────
  Widget _buildGame(BuildContext context, GameInProgress gip) {
    final gs        = gip.state;
    final mySeat    = gs.mySeat;
    final topSeat   = (mySeat + 2) % 4;
    final rightSeat = (mySeat + 1) % 4;
    final leftSeat  = (mySeat + 3) % 4;

    PlayerInfo? playerAt(int seat) {
      try { return gs.players.firstWhere((p) => p.seat == seat); }
      catch (_) { return null; }
    }

    final topP   = playerAt(topSeat);
    final leftP  = playerAt(leftSeat);
    final rightP = playerAt(rightSeat);
    final myP    = playerAt(mySeat);

    final totalTricks = gs.tricksWon.values.fold(0, (a, b) => a + b);
    final botCards    = (13 - totalTricks).clamp(1, 13);

    return Stack(
      children: [
        const _WoodBackground(),
        SafeArea(
          child: Column(
            children: [
              _buildTopRow(context, gs, topP, topSeat, gs.bids[topSeat],
                  gs.tricksWon[topSeat] ?? 0, botCards),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSideBot(context, leftP, leftSeat, gs.bids[leftSeat],
                        gs.tricksWon[leftSeat] ?? 0, botCards,
                        isLeft: true, isTurn: gs.currentTurn == leftSeat),
                    Expanded(
                      child: _buildTrickArea(gs, gs.isMyTurn && gs.isPlaying),
                    ),
                    _buildSideBot(context, rightP, rightSeat, gs.bids[rightSeat],
                        gs.tricksWon[rightSeat] ?? 0, botCards,
                        isLeft: false, isTurn: gs.currentTurn == rightSeat),
                  ],
                ),
              ),
              _buildPlayerHand(context, gip, myP, mySeat),
            ],
          ),
        ),
        if (_animatingTrick != null)
          _TrickWinOverlay(
            trick: _animatingTrick!,
            mySeat: mySeat,
            animation: _trickAnimCtrl,
          ),
        if (_floatingEmojis.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: _floatingEmojis
                    .map((e) => _FloatingEmoji(key: ValueKey(e + DateTime.now().millisecondsSinceEpoch.toString()), emoji: e))
                    .toList(),
              ),
            ),
          ),
        // ── Floating room-chat messages (card-click sends) ───────────────
        if (_floatingMsgs.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: _floatingMsgs.map((m) => _FloatingChatMsg(
                  key: ValueKey(m['id']),
                  text: m['text'] as String,
                  relSeat: m['relSeat'] as int,
                )).toList(),
              ),
            ),
          ),
        // ── DM toast notifications ───────────────────────────────────────
        if (_dmToasts.isNotEmpty)
          Positioned(
            top: 72, left: 0, right: 0,
            child: IgnorePointer(
              ignoring: false,
              child: Column(
                children: _dmToasts.map((t) => _DmToastBubble(
                  toast: t,
                  onTap: () {
                    final uid = t['sender_id'] as String?;
                    setState(() => _dmToasts.remove(t));
                    if (uid != null) _openInlineChatByUserId(uid);
                  },
                  onDismiss: () => setState(() => _dmToasts.remove(t)),
                )).toList(),
              ),
            ),
          ),
        // ── Inline quick-chat bar (message icon tap) ─────────────────────
        if (_activeInlineSeat != null && _activeInlinePlayer != null)
          Positioned(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
            left: 8, right: 8,
            child: _InlineChatBar(
              player: _activeInlinePlayer!,
              controller: _inlineChatCtl,
              focusNode: _inlineChatFocus,
              scrollController: _inlineScrollCtl,
              history: _inboxMsgs[_activeInlinePlayer!.userId] ?? const [],
              onSend: _submitInlineChat,
              onClose: _closeInlineChat,
            ),
          ),
      ],
    );
  }



  // ── Top row ────────────────────────────────────────────────────────────────
  Widget _buildTopRow(BuildContext ctx, GameStateEntity gs, PlayerInfo? player,
      int seat, int? bid, int tricks, int cardCount) {
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: Close + Trump badge ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
            child: Row(children: [
              GestureDetector(
                onTap: _confirmLeaveGame,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 17),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('♠', style: TextStyle(color: Colors.white, fontSize: 13, height: 1)),
                  Text('TRUMP', style: TextStyle(color: Colors.white54, fontSize: 7, height: 1.1)),
                ]),
              ),
            ]),
          ),
          // ── Center: top player (card fan clickable) ────────────────────
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: player != null ? () => _showPlayerProfile(ctx, player) : null,
                  child: _CardFan(cardCount, baseRotation: math.pi),
                ),
                const SizedBox(width: 8),
                if (player != null) ...[
                  Flexible(child: Text(player.username,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)]))),
                  const SizedBox(width: 4),
                  _ScoreBadge(tricks, bid: bid, isTurn: gs.currentTurn == seat),
                  if (!player.isBot && player.userId != null) ...[
                    const SizedBox(width: 4),
                    _MailButton(
                      unread: _unreadBySender[player.userId] ?? 0,
                      onTap: () => _openInlineChat(player, 2),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Side player column ─────────────────────────────────────────────────────
  Widget _buildSideBot(BuildContext ctx, PlayerInfo? player, int seat, int? bid,
      int tricks, int cardCount, {required bool isLeft, required bool isTurn}) {
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: player != null ? () => _showPlayerProfile(ctx, player) : null,
            child: _CardFan(cardCount, baseRotation: isLeft ? -math.pi / 2 : math.pi / 2),
          ),
          const SizedBox(height: 4),
          if (player != null) ...[
            Text(player.username,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            _ScoreBadge(tricks, bid: bid, isTurn: isTurn),
            if (!player.isBot && player.userId != null) ...[
              const SizedBox(height: 4),
              _MailButton(
                unread: _unreadBySender[player.userId] ?? 0,
                onTap: () => _openInlineChat(player, isLeft ? 3 : 1),
                width: 26, height: 22,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Trick area ─────────────────────────────────────────────────────────────
  Widget _buildTrickArea(GameStateEntity gs, bool canPlay) {
    final trick = gs.currentTrick;

    return DragTarget<CardEntity>(
      onWillAcceptWithDetails: (_) => canPlay,
      onAcceptWithDetails: (details) {
        _Sfx.cardDrop();
        context.read<GameBloc>().add(GamePlayCard(details.data));
      },
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: hovering
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            border: hovering
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.7), width: 2)
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (trick.isEmpty)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      gs.isBidding
                          ? 'Bidding…'
                          : (canPlay ? 'Drop card here' : 'Waiting…'),
                      style: TextStyle(
                        color: hovering ? AppColors.primaryLight : Colors.white54,
                        fontSize: 13,
                        fontWeight:
                            hovering ? FontWeight.bold : FontWeight.normal,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                      ),
                    ),
                    if (canPlay && !gs.isBidding) ...[
                      const SizedBox(height: 5),
                      Icon(Icons.arrow_downward_rounded,
                          color: hovering ? AppColors.primary : Colors.white24,
                          size: 18),
                    ],
                  ],
                )
              else
                Stack(
                  alignment: Alignment.center,
                  children: List.generate(trick.length, (i) {
                    const angles  = [-0.15, 0.08, -0.05, 0.12];
                    const offsets = [
                      Offset(-18, -10), Offset(10, -14),
                      Offset(-6, 12),   Offset(16, 8),
                    ];
                    return Transform.translate(
                      offset: i < offsets.length ? offsets[i] : Offset.zero,
                      child: Transform.rotate(
                        angle: i < angles.length ? angles[i] : 0,
                        child: CardWidget(card: trick[i].card, width: 58, height: 84),
                      ),
                    );
                  }),
                ),
              if (gs.isBidding)
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Bidding',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Player hand — overlapping landscape layout ─────────────────────────────
  Widget _buildPlayerHand(BuildContext context, GameInProgress gip,
      PlayerInfo? myPlayer, int mySeat) {
    final gs       = gip.state;
    final hand     = gs.hand;
    final canPlay  = gs.isMyTurn && gs.isPlaying;
    final myBid    = gs.bids[mySeat];
    final myTricks = gs.tricksWon[mySeat] ?? 0;

    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        border: const Border(top: BorderSide(color: Colors.black26, width: 1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 3, 10, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  myPlayer?.username ?? 'You',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
                Row(
                  children: [
                    if (myBid != null)
                      _ScoreBadge(myTricks, bid: myBid, isTurn: gs.isMyTurn),
                    if (canPlay) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Tap or drag to play',
                            style: TextStyle(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _openChatModal(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.chat_bubble_rounded, color: AppColors.primaryLight, size: 10),
                          const SizedBox(width: 3),
                          Text(
                            _chatMessages.isEmpty ? 'Chat' : 'Chat (${_chatMessages.length})',
                            style: const TextStyle(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Overlapping card stack
          Expanded(
            child: hand.isEmpty
                ? const Center(
                    child: Text('No cards',
                        style: TextStyle(color: Colors.white38)))
                : LayoutBuilder(
                    builder: (_, constraints) {
                      const cardW = 58.0;
                      final n = hand.length;
                      final availW = constraints.maxWidth - 16;
                      final step = n <= 1
                          ? 0.0
                          : ((availW - cardW) / (n - 1))
                              .clamp(20.0, cardW + 4.0);
                      final totalW = cardW + step * (n - 1);

                      return Center(
                        child: SizedBox(
                          width: totalW,
                          height: constraints.maxHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: List.generate(n, (i) {
                              final card = hand[i];
                              return Positioned(
                                left: i * step,
                                bottom: 0,
                                child: _HandCard(
                                  key: ValueKey(
                                      '${card.suit}_${card.rank}_$i'),
                                  card: card,
                                  canPlay: canPlay,
                                  onPlay: () {
                                    _Sfx.cardDrop();
                                    context
                                        .read<GameBloc>()
                                        .add(GamePlayCard(card));
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Round result dialog ────────────────────────────────────────────────────
  void _showRoundResult(BuildContext context, RoundResultData rr, List<PlayerInfo> players) {
    if (_roundResultDialogOpen) return;
    _roundResultDialogOpen = true;
    final bloc = context.read<GameBloc>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) {
          final rows = rr.roundScores.map((s) {
            final seat  = (s['seat'] as num).toInt();
            final bid   = s['bid'];
            final won   = s['won'];
            final score = (s['score'] as num).toDouble();
            final name  = players
                .firstWhere((p) => p.seat == seat,
                    orElse: () => PlayerInfo(seat: seat, username: 'P${seat+1}', isBot: false))
                .username;
            final isPos = score >= 0;
            return _RoundRow(name: name, bid: bid, won: won, score: score, isPos: isPos);
          }).toList();

          return Dialog(
            backgroundColor: const Color(0xFF1A2035),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Round ${rr.round} Result',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 10),
                  // Header row
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Row(children: [
                      Expanded(child: Text('Player',
                          style: TextStyle(color: Colors.white38, fontSize: 10))),
                      SizedBox(width: 36,
                          child: Text('Bid', textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, fontSize: 10))),
                      SizedBox(width: 36,
                          child: Text('Won', textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, fontSize: 10))),
                      SizedBox(width: 44,
                          child: Text('Score', textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.white38, fontSize: 10))),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  ...rows,
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(dCtx).pop();
                        bloc.add(GameNextRound());
                      },
                      child: const Text('Next Round',
                          style: TextStyle(color: AppColors.primary, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ).then((_) {
        _roundResultDialogOpen = false;
        if (!mounted) return;
        // If bidding started while result was showing, open bid dialog now
        final gs = bloc.state;
        if (gs is GameInProgress &&
            gs.state.isBidding &&
            gs.state.isMyTurn &&
            !gs.state.bids.containsKey(gs.state.mySeat)) {
          _showBidDialog();
        }
      });
    });
  }

  // ── Game result dialog ─────────────────────────────────────────────────────
  void _showGameResult(BuildContext context, GameResultData gr) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (ctx) => _GameResultDialog(
          gr: gr,
          mySeat: context.read<GameBloc>().mySeat,
          onBack: () {
            Navigator.pop(ctx);
            context.read<GameBloc>().add(GameLeave());
            context.go('/lobby');
          },
        ),
      );
    });
  }
}

// ── Game Result Dialog ─────────────────────────────────────────────────────────
class _GameResultDialog extends StatefulWidget {
  final GameResultData gr;
  final int mySeat;
  final VoidCallback onBack;
  const _GameResultDialog({required this.gr, required this.mySeat, required this.onBack});
  @override
  State<_GameResultDialog> createState() => _GameResultDialogState();
}

class _GameResultDialogState extends State<_GameResultDialog>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _xpCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _scaleIn;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _xpCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _scaleIn = CurvedAnimation(parent: _enterCtrl, curve: Curves.elasticOut);
    _fadeIn  = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);

    _enterCtrl.forward();
    // Delay XP bar animation so it runs after the dialog settles
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _xpCtrl.forward();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _xpCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gr        = widget.gr;
    final reward    = gr.myReward;
    final isWinner  = gr.winnerSeat == widget.mySeat;

    // XP progress bar: 0–500 per level, showing old → new within current level
    const xpPerLevel  = 500;
    final oldXpInLvl  = reward != null ? (reward.oldLevel > 1 ? reward.newXp - reward.xpEarned - (reward.oldLevel - 1) * xpPerLevel : reward.newXp - reward.xpEarned) : 0;
    final newXpInLvl  = reward != null ? (reward.newXp - (reward.newLevel - 1) * xpPerLevel).clamp(0, xpPerLevel) : 0;
    final oldPct      = (oldXpInLvl / xpPerLevel).clamp(0.0, 1.0).toDouble();
    final newPct      = (newXpInLvl / xpPerLevel).clamp(0.0, 1.0).toDouble();

    return ScaleTransition(
      scale: _scaleIn,
      child: FadeTransition(
        opacity: _fadeIn,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0E1A2E), Color(0xFF080F1A)],
              ),
              border: Border.all(
                color: isWinner
                    ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                    : const Color(0xFF1E3050),
                width: isWinner ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isWinner
                      ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                      : Colors.black54,
                  blurRadius: 32,
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Win / Lose badge ────────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, child) => Transform.scale(
                      scale: isWinner ? (1.0 + _pulseCtrl.value * 0.05) : 1.0,
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        gradient: LinearGradient(
                          colors: isWinner
                              ? const [Color(0xFFFFD700), Color(0xFFFFA000)]
                              : const [Color(0xFF334466), Color(0xFF1E2E44)],
                        ),
                        boxShadow: isWinner ? [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                            blurRadius: 18,
                          ),
                        ] : null,
                      ),
                      child: Text(
                        isWinner ? '🏆  Victory!' : '😔  Defeat',
                        style: TextStyle(
                          color: isWinner ? Colors.black : Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${gr.winnerName} wins the game',
                    style: const TextStyle(color: Color(0xFF7799BB), fontSize: 13),
                  ),

                  const SizedBox(height: 20),

                  // ── Scores table ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF060D18),
                      border: Border.all(color: const Color(0xFF1A2840)),
                    ),
                    child: Column(
                      children: gr.finalScores.entries.map((e) {
                        final isMine = e.key == widget.mySeat;
                        final isW    = e.key == gr.winnerSeat;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isW
                                    ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                                    : const Color(0xFF1A2840),
                                border: Border.all(
                                  color: isW
                                      ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  isW ? '🏆' : 'S${e.key + 1}',
                                  style: TextStyle(
                                    fontSize: isW ? 12 : 10,
                                    color: isMine ? Colors.white : const Color(0xFF7799BB),
                                    fontWeight: isMine ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isMine ? 'You' : 'Seat ${e.key + 1}',
                                style: TextStyle(
                                  color: isMine ? Colors.white : const Color(0xFF7799BB),
                                  fontWeight: isMine ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              e.value >= 0 ? '+${e.value.toStringAsFixed(1)}' : e.value.toStringAsFixed(1),
                              style: TextStyle(
                                color: e.value >= 0 ? AppColors.primary : AppColors.danger,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),

                  // ── Bet result ──────────────────────────────────────
                  if (gr.hasBet) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF0D1A08),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Text('💰', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          'Pot: ₹${gr.totalPot.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        )),
                        Text(
                          isWinner ? '+₹${gr.totalPot.toStringAsFixed(0)} won!' : '-₹${gr.betAmount.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: isWinner ? AppColors.primary : AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ]),
                    ),
                  ],

                  // ── Rewards: XP + Coins ────────────────────────────
                  if (reward != null) ...[
                    const SizedBox(height: 16),

                    // Level-up banner
                    if (reward.leveledUp) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                          ),
                        ),
                        child: Column(children: [
                          const Text('⬆️  LEVEL UP!',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 1)),
                          Text(
                            'Level ${reward.oldLevel}  →  Level ${reward.newLevel}',
                            style: const TextStyle(color: Colors.black87, fontSize: 12),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // XP + coins row
                    Row(children: [
                      Expanded(child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF0A1020),
                          border: Border.all(color: const Color(0xFF1A2840)),
                        ),
                        child: Column(children: [
                          Text(
                            '+${reward.xpEarned} XP',
                            style: const TextStyle(
                                color: Color(0xFF88CCFF),
                                fontSize: 16,
                                fontWeight: FontWeight.w900),
                          ),
                          const Text('Experience', style: TextStyle(color: Color(0xFF4466AA), fontSize: 10)),
                        ]),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF0A1020),
                          border: Border.all(color: const Color(0xFF1A2840)),
                        ),
                        child: Column(children: [
                          Text(
                            '+${reward.coinsEarned} 🪙',
                            style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 16,
                                fontWeight: FontWeight.w900),
                          ),
                          const Text('Coins', style: TextStyle(color: Color(0xFF8B7020), fontSize: 10)),
                        ]),
                      )),
                    ]),

                    const SizedBox(height: 12),

                    // XP progress bar
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(
                          'Level ${reward.leveledUp ? reward.newLevel : reward.oldLevel}',
                          style: const TextStyle(color: Color(0xFF7799BB), fontSize: 11),
                        ),
                        Text(
                          '${reward.newXp} / ${reward.newLevel * 500} XP',
                          style: const TextStyle(color: Color(0xFF7799BB), fontSize: 11),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(children: [
                          // Background
                          Container(height: 10, color: const Color(0xFF1A2840)),
                          // Old XP
                          FractionallySizedBox(
                            widthFactor: oldPct,
                            child: Container(
                              height: 10,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [Color(0xFF2244AA), Color(0xFF3366CC)]),
                              ),
                            ),
                          ),
                          // New XP gain animated
                          AnimatedBuilder(
                            animation: _xpCtrl,
                            builder: (_, __) {
                              final width = oldPct + (newPct - oldPct) * _xpCtrl.value;
                              return FractionallySizedBox(
                                widthFactor: width,
                                child: Container(
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF3399FF), Color(0xFF00CCFF)],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ]),
                      ),
                    ]),
                  ],

                  const SizedBox(height: 20),

                  // ── Back to Lobby button ────────────────────────────
                  GestureDetector(
                    onTap: widget.onBack,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A5A), Color(0xFF162840)],
                        ),
                        border: Border.all(color: const Color(0xFF2A4A6A)),
                      ),
                      child: const Center(
                        child: Text(
                          '← Back to Lobby',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Draggable card with lift animation ────────────────────────────────────────
class _HandCard extends StatefulWidget {
  final CardEntity card;
  final bool canPlay;
  final VoidCallback? onPlay;
  const _HandCard({
    super.key,
    required this.card,
    this.canPlay = false,
    this.onPlay,
  });
  @override
  State<_HandCard> createState() => _HandCardState();
}

class _HandCardState extends State<_HandCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _liftCtrl;
  static const double _cardW = 58.0;
  static const double _cardH = 84.0;

  @override
  void initState() {
    super.initState();
    _liftCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      upperBound: 14.0,
    );
  }

  @override
  void dispose() {
    _liftCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canPlay) {
      return CardWidget(card: widget.card, width: _cardW, height: _cardH);
    }

    return AnimatedBuilder(
      animation: _liftCtrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -_liftCtrl.value),
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) => _liftCtrl.forward(),
        onTapCancel: () => _liftCtrl.reverse(),
        onTap: () {
          _liftCtrl.reverse();
          widget.onPlay?.call();
        },
        child: Draggable<CardEntity>(
          data: widget.card,
          onDragStarted: () => _liftCtrl.forward(),
          onDragEnd: (_) => _liftCtrl.reverse(),
          onDraggableCanceled: (_, __) => _liftCtrl.reverse(),
          feedback: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.15,
              child: CardWidget(
                card: widget.card,
                isSelected: true,
                width: _cardW,
                height: _cardH,
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: CardWidget(card: widget.card, width: _cardW, height: _cardH),
          ),
          child: CardWidget(
            card: widget.card,
            isPlayable: true,
            width: _cardW,
            height: _cardH,
          ),
        ),
      ),
    );
  }
}

// ── Trick win overlay (arc fly + sparkles) ─────────────────────────────────────
class _TrickWinOverlay extends StatelessWidget {
  final TrickResultData trick;
  final int mySeat;
  final Animation<double> animation;

  const _TrickWinOverlay({
    required this.trick,
    required this.mySeat,
    required this.animation,
  });

  static const _angles  = [-0.15, 0.08, -0.05, 0.12];
  static const _offsets = [
    Offset(-18, -10), Offset(10, -14), Offset(-6, 12), Offset(16, 8),
  ];

  @override
  Widget build(BuildContext context) {
    final size    = MediaQuery.of(context).size;
    final relSeat = (trick.winnerSeat - mySeat + 4) % 4;
    // 0=me(bottom) 1=right 2=top 3=left
    final endOffset = [
      Offset(0,               size.height * 0.46),
      Offset(size.width * 0.46,  0),
      Offset(0,              -size.height * 0.46),
      Offset(-size.width * 0.46, 0),
    ][relSeat];
    final isMyWin = trick.winnerSeat == mySeat;

    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;

        // 0–0.28: hold; 0.28–1.0: fly with parabolic arc
        final flyT   = t < 0.28
            ? 0.0
            : Curves.easeIn.transform((t - 0.28) / 0.72);
        final arcH   = -80.0 * 4 * flyT * (1 - flyT); // parabola peak at flyT=0.5
        final dx     = endOffset.dx * flyT;
        final dy     = endOffset.dy * flyT + arcH;
        final scale  = 1.0 - 0.55 * flyT;
        final cardOp = flyT < 0.82 ? 1.0 : 1.0 - (flyT - 0.82) / 0.18;

        // banner: fade-in 0–0.12, hold 0.12–0.24, fade-out 0.24–0.35
        final bannerOp = t < 0.12
            ? t / 0.12
            : t < 0.24
                ? 1.0
                : t < 0.35
                    ? 1.0 - (t - 0.24) / 0.11
                    : 0.0;

        // sparkle: 0.10–0.55
        final sparkleOp = (t >= 0.10 && t <= 0.55)
            ? (t < 0.20
                ? (t - 0.10) / 0.10
                : t > 0.45
                    ? 1.0 - (t - 0.45) / 0.10
                    : 1.0)
            : 0.0;

        return Stack(
          children: [
            // Sparkles around center
            if (sparkleOp > 0.01)
              Center(
                child: Opacity(
                  opacity: sparkleOp.clamp(0.0, 1.0),
                  child: SizedBox(
                    width: 220,
                    height: 200,
                    child: CustomPaint(
                      painter: _SparklePainter(t),
                    ),
                  ),
                ),
              ),

            // Winner banner
            if (bannerOp > 0.01)
              Positioned(
                top: size.height * 0.30,
                left: 0, right: 0,
                child: Center(
                  child: Opacity(
                    opacity: bannerOp.clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMyWin
                            ? AppColors.primary
                            : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isMyWin ? AppColors.primary : AppColors.accent)
                                .withValues(alpha: 0.55),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        isMyWin
                            ? '🏆 You win the trick!'
                            : '✨ Seat ${trick.winnerSeat + 1} wins',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Cards flying to winner with arc
            if (cardOp > 0.01)
              Center(
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: cardOp.clamp(0.0, 1.0),
                      child: SizedBox(
                        width: 130, height: 120,
                        child: Stack(
                          alignment: Alignment.center,
                          children: List.generate(
                            trick.trickCards.length.clamp(0, 4),
                            (i) => Transform.translate(
                              offset:
                                  i < _offsets.length ? _offsets[i] : Offset.zero,
                              child: Transform.rotate(
                                angle: i < _angles.length ? _angles[i] : 0,
                                child: CardWidget(
                                  card: trick.trickCards[i].card,
                                  width: 60, height: 86,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Sparkle painter ────────────────────────────────────────────────────────────
class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rng  = math.Random(42);
    final cx   = size.width / 2;
    final cy   = size.height / 2;
    final fill = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 18; i++) {
      final angle   = (i / 18) * math.pi * 2 + t * math.pi * 1.5;
      final radius  = 48.0 + rng.nextDouble() * 38.0;
      final x       = cx + math.cos(angle) * radius;
      final y       = cy + math.sin(angle) * radius;
      final dotSize = 2.0 + rng.nextDouble() * 3.0;
      final hue     = (i * 20.0 + t * 200) % 360;
      fill.color = HSVColor.fromAHSV(0.9, hue, 0.85, 1.0).toColor();

      // Star shape
      _drawStar(canvas, Offset(x, y), dotSize * 1.6, fill);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final a  = (i * 2 * math.pi / 5) - math.pi / 2;
      final x  = center.dx + r * math.cos(a);
      final y  = center.dy + r * math.sin(a);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      final ai = a + math.pi / 5;
      path.lineTo(
        center.dx + r * 0.4 * math.cos(ai),
        center.dy + r * 0.4 * math.sin(ai),
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

// ── Score badge ────────────────────────────────────────────────────────────────
class _ScoreBadge extends StatefulWidget {
  final int tricks;
  final int? bid;
  final bool isTurn;
  const _ScoreBadge(this.tricks, {this.bid, this.isTurn = false});

  @override
  State<_ScoreBadge> createState() => _ScoreBadgeState();
}

class _ScoreBadgeState extends State<_ScoreBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTurn = widget.isTurn;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final p = isTurn ? _pulse.value : 0.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: isTurn
                ? AppColors.primary.withValues(alpha: 0.85)
                : Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isTurn
                  ? Color.lerp(AppColors.primary, AppColors.accent, p * 0.6)!
                  : Colors.white24,
              width: isTurn ? 1.5 : 0.8,
            ),
            boxShadow: isTurn
                ? [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3 + p * 0.45),
                    blurRadius: 6 + p * 12,
                    spreadRadius: p * 1.5)]
                : null,
          ),
          child: Text(
            widget.bid != null ? '${widget.tricks}/${widget.bid}' : '${widget.tricks}',
            style: TextStyle(
              color: isTurn ? Colors.white : const Color(0xFFCCFF90),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }
}

// ── Card fan (bot hands) ───────────────────────────────────────────────────────
class _CardFan extends StatelessWidget {
  final int count;
  final double baseRotation;
  const _CardFan(this.count, {this.baseRotation = 0});

  @override
  Widget build(BuildContext context) {
    final n      = count.clamp(1, 13);
    const cw     = 28.0;
    const ch     = 42.0;
    final spread = (math.pi * 0.50) / n.clamp(1, 13).toDouble();
    final total  = spread * (n - 1);

    return Transform.rotate(
      angle: baseRotation,
      child: SizedBox(
        width: cw + 60,
        height: ch + 28,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: List.generate(n, (i) {
            final angle = -total / 2 + i * spread;
            return Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomCenter,
              child: const _CardBack(),
            );
          }),
        ),
      ),
    );
  }
}

// ── Card back ──────────────────────────────────────────────────────────────────
class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 42,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.white, width: 1.0),
      boxShadow: const [
        BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(1, 2))
      ],
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD32F2F), Color(0xFF9C0000)],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Colors.white24),
        ),
        child: CustomPaint(painter: _BackPatternPainter()),
      ),
    ),
  );
}

class _BackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1
      ..style       = PaintingStyle.stroke;
    const gap = 5.0;
    for (double i = -size.height; i < size.width + size.height; i += gap) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
      canvas.drawLine(Offset(i + size.height, 0), Offset(i, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}

// ── Wood background ────────────────────────────────────────────────────────────
// ── Premium animated casino-felt table ───────────────────────────────────────
// A cached emerald-felt base (gradient + fabric grain + gold medallion + suit
// watermark + vignette) with a lightweight drifting "sheen" highlight on top.
class _WoodBackground extends StatefulWidget {
  const _WoodBackground();
  @override
  State<_WoodBackground> createState() => _WoodBackgroundState();
}

class _WoodBackgroundState extends State<_WoodBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 16))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Heavy, static felt — painted once and cached.
        const RepaintBoundary(
          child: SizedBox.expand(child: CustomPaint(painter: _FeltBasePainter())),
        ),
        // Cheap animated sheen — one radial gradient per frame.
        SizedBox.expand(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(painter: _FeltSheenPainter(_ctrl.value)),
          ),
        ),
      ],
    );
  }
}

class _FeltBasePainter extends CustomPainter {
  const _FeltBasePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect   = Offset.zero & size;
    final center = Offset(size.width / 2, size.height * 0.46);

    // 1) Emerald felt with a soft spotlight in the middle of the table.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.06),
          radius: 1.05,
          colors: [Color(0xFF1C7A50), Color(0xFF0E5235), Color(0xFF05180F)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // 2) Fine fabric grain for that woven-felt texture.
    final rng = math.Random(7);
    final grain = Paint();
    for (int i = 0; i < 900; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final light = rng.nextBool();
      grain.color = (light ? Colors.white : Colors.black)
          .withValues(alpha: 0.015 + rng.nextDouble() * 0.03);
      canvas.drawCircle(Offset(dx, dy), 0.6 + rng.nextDouble() * 0.8, grain);
    }

    // 3) Centre medallion — concentric gold rings framing the play area.
    final short = size.shortestSide;
    for (final r in [short * 0.30, short * 0.30 + 5, short * 0.40]) {
      canvas.drawCircle(
        center, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r == short * 0.40 ? 1.0 : 1.6
          ..color = const Color(0xFFFFD600).withValues(alpha: 0.10),
      );
    }

    // 4) Faint spade watermark inside the medallion.
    final tp = TextPainter(
      text: TextSpan(
        text: '♠',
        style: TextStyle(
          fontSize: short * 0.34,
          color: const Color(0xFFFFD600).withValues(alpha: 0.05),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    // 5) Vignette for depth.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.06),
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
          stops: const [0.6, 1.0],
        ).createShader(rect),
    );

    // 6) Thin inset gold frame — the premium border.
    final inset = RRect.fromRectAndRadius(
      rect.deflate(6), const Radius.circular(14),
    );
    canvas.drawRRect(
      inset,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFFFD600).withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _FeltSheenPainter extends CustomPainter {
  final double t; // 0..1 loop
  _FeltSheenPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect  = Offset.zero & size;
    final angle = t * 2 * math.pi;
    // Soft highlight drifting slowly in a gentle ellipse over the felt.
    final cx = size.width * (0.5 + 0.30 * math.cos(angle));
    final cy = size.height * (0.42 + 0.20 * math.sin(angle));
    final glow = Rect.fromCircle(
      center: Offset(cx, cy), radius: size.shortestSide * 0.65);

    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF3FE89A).withValues(alpha: 0.085),
            Colors.transparent,
          ],
        ).createShader(glow),
    );
  }

  @override
  bool shouldRepaint(_FeltSheenPainter old) => old.t != t;
}

// ── Room-chat modal sheet content (WhatsApp style) ───────────────────────────
class _ChatSheetContent extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollCtl;
  final TextEditingController inputCtl;
  final String? myUsername;
  final void Function(String text) onSend;

  const _ChatSheetContent({
    required this.messages,
    required this.scrollCtl,
    required this.inputCtl,
    required this.myUsername,
    required this.onSend,
  });

  void _send() {
    final text = inputCtl.text.trim();
    if (text.isEmpty) return;
    onSend(text);
    inputCtl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF07101C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              const Icon(Icons.chat_bubble_rounded, color: AppColors.primary, size: 14),
              const SizedBox(width: 8),
              const Expanded(child: Text('Room Chat',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
              ),
            ]),
          ),
          const Divider(height: 1, color: Colors.white12),
          // messages
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Say something!',
                    style: TextStyle(color: Colors.white38, fontSize: 13)))
                : ListView.builder(
                    controller: scrollCtl,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final uname = m['username'] as String? ?? 'Player';
                      final text  = m['message']  as String? ?? '';
                      final isMe  = uname == myUsername;
                      return _ChatBubble(username: uname, text: text, isMe: isMe);
                    },
                  ),
          ),
          // input — bottom padding absorbs keyboard so field stays visible
          Builder(builder: (bCtx) {
            final keyboardH = MediaQuery.viewInsetsOf(bCtx).bottom;
            return Container(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + keyboardH),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
                color: Color(0xFF07101C),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: inputCtl,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Message the room…',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0D1A2A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String username;
  final String text;
  final bool isMe;
  const _ChatBubble({required this.username, required this.text, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.accent.withValues(alpha: 0.2),
              child: Text(username[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.accentLight, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 2),
                    child: Text(username,
                        style: const TextStyle(color: AppColors.accentLight, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : const Color(0xFF0D1827),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: isMe ? null : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(text,
                      style: TextStyle(color: isMe ? Colors.white : Colors.white70, fontSize: 13)),
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

// ── Floating chat message (card-click send animation) ────────────────────────
class _FloatingChatMsg extends StatefulWidget {
  final String text;
  final int relSeat; // 1=right, 2=top, 3=left
  const _FloatingChatMsg({super.key, required this.text, required this.relSeat});
  @override
  State<_FloatingChatMsg> createState() => _FloatingChatMsgState();
}

class _FloatingChatMsgState extends State<_FloatingChatMsg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _fade  = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.55, 1.0)));
    _slide = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final endDx = widget.relSeat == 1
        ?  size.width * 0.35
        : widget.relSeat == 3
            ? -size.width * 0.35
            : 0.0;
    final endDy = widget.relSeat == 2 ? -size.height * 0.30 : -size.height * 0.14;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Positioned(
        left: size.width / 2 - 80 + endDx * _slide.value,
        top:  size.height / 2 - 22 + endDy * _slide.value,
        width: 160,
        child: Opacity(opacity: _fade.value, child: child!),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 12)],
        ),
        child: Text(
          widget.text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Floating emoji reaction ───────────────────────────────────────────────────
class _FloatingEmoji extends StatefulWidget {
  final String emoji;
  const _FloatingEmoji({super.key, required this.emoji});
  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _rise;
  final double _x = 0.15 + math.Random().nextDouble() * 0.55;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fade = Tween<double>(begin: 1, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0)));
    _rise = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Positioned(
        left: MediaQuery.of(context).size.width * _x,
        bottom: 120 + _rise.value * 180,
        child: Opacity(opacity: _fade.value, child: child!),
      ),
      child: Text(widget.emoji, style: const TextStyle(fontSize: 30)),
    );
  }
}

// ── DM toast bubble (fades after 3 s) ────────────────────────────────────────
// ── Per-seat mail button with pulsing unread badge ───────────────────────────
class _MailButton extends StatefulWidget {
  final int unread;
  final VoidCallback onTap;
  final double width, height;
  const _MailButton({
    required this.unread,
    required this.onTap,
    this.width = 24,
    this.height = 24,
  });

  @override
  State<_MailButton> createState() => _MailButtonState();
}

class _MailButtonState extends State<_MailButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.unread > 0;
    final base = has ? AppColors.accent : AppColors.primary;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          return Stack(clipBehavior: Clip.none, children: [
            Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: base.withValues(alpha: has ? 0.22 : 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: base.withValues(alpha: has ? 0.6 : 0.4)),
                boxShadow: has
                    ? [BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.3 + _pulse.value * 0.5),
                        blurRadius: 8 + _pulse.value * 6)]
                    : null,
              ),
              child: Icon(
                has ? Icons.mark_email_unread_rounded : Icons.mail_outline_rounded,
                color: base, size: 13,
              ),
            ),
            if (has)
              Positioned(
                right: -5, top: -5,
                child: Transform.scale(
                  scale: 0.9 + _pulse.value * 0.15,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0A1525), width: 1.5),
                    ),
                    child: Text(
                      widget.unread > 9 ? '9+' : '${widget.unread}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 8,
                          fontWeight: FontWeight.bold, height: 1),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _DmToastBubble extends StatefulWidget {
  final Map<String, dynamic> toast;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _DmToastBubble({required this.toast, required this.onTap, required this.onDismiss});

  @override
  State<_DmToastBubble> createState() => _DmToastBubbleState();
}

class _DmToastBubbleState extends State<_DmToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280))
      ..forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.toast['sender_name'] as String? ?? 'Player';
    final text = widget.toast['text'] as String? ?? '';
    final curve = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: _enter,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(curve),
        child: _bubble(name, text),
      ),
    );
  }

  Widget _bubble(String name, String text) {
    final onTap = widget.onTap;
    final onDismiss = widget.onDismiss;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xDD0D1827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8)],
        ),
        child: Row(children: [
          const Icon(Icons.mail_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                TextSpan(text: '$name: ',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                TextSpan(text: text,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded, color: Colors.white38, size: 14),
          ),
        ]),
      ),
    );
  }
}

// ── Inline quick-chat bar (appears above keyboard) ───────────────────────────
class _InlineChatBar extends StatelessWidget {
  final PlayerInfo player;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final List<Map<String, dynamic>> history;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const _InlineChatBar({
    required this.player,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.history,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: avatar + name + "private" tag ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
            child: Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: Text(
                  player.username.isNotEmpty ? player.username[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(player.username,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Row(children: [
                      const Icon(Icons.lock_rounded, color: Colors.white38, size: 9),
                      const SizedBox(width: 3),
                      Text('Private · only ${player.username} sees this',
                          style: const TextStyle(color: Colors.white38, fontSize: 9)),
                    ]),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF1E2C40)),
          // ── History ──
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: history.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('No messages yet. Say hi 👋',
                        style: TextStyle(color: Colors.white30, fontSize: 12)),
                  )
                : ListView.builder(
                    controller: scrollController,
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    itemCount: history.length,
                    itemBuilder: (_, i) {
                      final m = history[i];
                      final mine = m['fromMe'] == true;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
                          decoration: BoxDecoration(
                            color: mine
                                ? AppColors.primary.withValues(alpha: 0.85)
                                : const Color(0xFF1A2940),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(mine ? 12 : 3),
                              bottomRight: Radius.circular(mine ? 3 : 12),
                            ),
                          ),
                          child: Text(
                            m['text'] as String? ?? '',
                            style: TextStyle(
                              color: mine ? Colors.white : Colors.white.withValues(alpha: 0.9),
                              fontSize: 12.5, height: 1.3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // ── Input row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Message ${player.username}…',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    filled: true,
                    fillColor: const Color(0xFF0A1525),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  width: 34, height: 34,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 15),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Player profile dialog ─────────────────────────────────────────────────────
class _PlayerProfileDialog extends StatefulWidget {
  final PlayerInfo player;
  const _PlayerProfileDialog({required this.player});

  @override
  State<_PlayerProfileDialog> createState() => _PlayerProfileDialogState();
}

class _PlayerProfileDialogState extends State<_PlayerProfileDialog> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _friendRequested = false;
  bool _sendingRequest = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await SocialRepository().getPublicProfile(widget.player.userId!);
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    if (_sendingRequest) return;
    setState(() => _sendingRequest = true);
    try {
      await SocialRepository().sendFriendRequest(widget.player.userId!);
      if (mounted) setState(() { _friendRequested = true; _sendingRequest = false; });
    } catch (_) {
      if (mounted) setState(() => _sendingRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level  = (_profile?['level']          as num?)?.toInt() ?? 1;
    final xp     = (_profile?['xp']             as num?)?.toInt() ?? 0;
    final played = (_profile?['matches_played']  as num?)?.toInt() ?? 0;
    final won    = (_profile?['matches_won']     as num?)?.toInt() ?? 0;
    final winPct = played > 0 ? '${((won / played) * 100).toStringAsFixed(0)}%' : '--';
    final avatarUrl = _profile?['avatar_url'] as String?;

    return Dialog(
      backgroundColor: const Color(0xFF0D1827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
              ),
            ),
            const SizedBox(height: 4),
            // Avatar + level badge
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                UserAvatar(
                  username: widget.player.username,
                  avatarUrl: avatarUrl,
                  size: 64,
                  solidColor: AppColors.primary.withValues(alpha: 0.2),
                  textColor: AppColors.primary,
                  fontSize: 24,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$level',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(widget.player.username,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 2),
            Text('Level $level',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 14),
            if (_loading)
              const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
              )
            else ...[
              // Stats row
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _StatItem(label: 'Games', value: '$played'),
                _StatItem(label: 'Won',   value: '$won'),
                _StatItem(label: 'Win %', value: winPct),
              ]),
              const SizedBox(height: 12),
              // XP bar
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('XP', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  Text('$xp / ${level * 500}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (xp / (level * 500)).clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFF1A2840),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 6,
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            // Friend request button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _friendRequested
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: (_friendRequested || _sendingRequest) ? null : _sendFriendRequest,
                icon: _sendingRequest
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(
                        _friendRequested ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
                        size: 16,
                        color: _friendRequested ? AppColors.accent : Colors.white),
                label: Text(
                  _friendRequested ? 'Request Sent' : 'Add Friend',
                  style: TextStyle(
                    color: _friendRequested ? AppColors.accent : Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ],
  );
}

// ── Round result row ──────────────────────────────────────────────────────────
class _RoundRow extends StatelessWidget {
  final String name;
  final dynamic bid;
  final dynamic won;
  final double score;
  final bool isPos;
  const _RoundRow({
    required this.name,
    required this.bid,
    required this.won,
    required this.score,
    required this.isPos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text('$bid', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          SizedBox(
            width: 36,
            child: Text('$won', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          SizedBox(
            width: 44,
            child: Text(
              isPos ? '+${score.toStringAsFixed(0)}' : score.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isPos ? AppColors.primaryLight : AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
