import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/card_entity.dart';
import '../../domain/entities/game_state_entity.dart';
import '../bloc/game_bloc.dart';
import '../widgets/card_widget.dart';
import '../widgets/bid_dialog.dart';

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
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _trickAnimCtrl.dispose();
    _Sfx.cleanup();
    super.dispose();
  }

  void _showBidDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BidDialog(
        onBid: (bid) => context.read<GameBloc>().add(GamePlaceBid(bid)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<GameBloc>().add(GameLeave());
      },
      child: Scaffold(
        body: BlocConsumer<GameBloc, GameState>(
          listener: (ctx, state) {
            if (state is GameInProgress) {
              if (state.state.isBidding &&
                  state.state.isMyTurn &&
                  !state.state.bids.containsKey(state.state.mySeat)) {
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
                _showRoundResult(ctx, state.lastRoundResult!);
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
            if (state is GameInProgress) return _buildGame(ctx, state);
            return _buildLoader();
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
              _buildTopRow(gs, topP, topSeat, gs.bids[topSeat],
                  gs.tricksWon[topSeat] ?? 0, botCards),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSideBot(leftP, leftSeat, gs.bids[leftSeat],
                        gs.tricksWon[leftSeat] ?? 0, botCards,
                        isLeft: true, isTurn: gs.currentTurn == leftSeat),
                    Expanded(
                      child: _buildTrickArea(gs, gs.isMyTurn && gs.isPlaying),
                    ),
                    _buildSideBot(rightP, rightSeat, gs.bids[rightSeat],
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
      ],
    );
  }

  // ── Top row ────────────────────────────────────────────────────────────────
  Widget _buildTopRow(GameStateEntity gs, PlayerInfo? player, int seat,
      int? bid, int tricks, int cardCount) {
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: GestureDetector(
              onTap: () {
                context.read<GameBloc>().add(GameLeave());
                context.go('/lobby');
              },
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CardFan(cardCount, baseRotation: math.pi),
                const SizedBox(width: 10),
                if (player != null) ...[
                  Text(player.username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  const SizedBox(width: 6),
                  _ScoreBadge(tricks, bid: bid, isTurn: gs.currentTurn == seat),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('♠', style: TextStyle(color: Colors.white, fontSize: 14)),
                  Text('T', style: TextStyle(color: Colors.white60, fontSize: 8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Side bot ────────────────────────────────────────────────────────────────
  Widget _buildSideBot(PlayerInfo? player, int seat, int? bid, int tricks,
      int cardCount, {required bool isLeft, required bool isTurn}) {
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CardFan(cardCount, baseRotation: isLeft ? -math.pi / 2 : math.pi / 2),
          const SizedBox(height: 4),
          if (player != null) ...[
            Text(player.username,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            _ScoreBadge(tricks, bid: bid, isTurn: isTurn),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Tap or drag to play',
                            style: TextStyle(
                                color: AppColors.primaryLight,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
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
  void _showRoundResult(BuildContext context, RoundResultData rr) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A2035),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Round ${rr.round} Result',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: rr.roundScores.map((s) {
              final seat  = (s['seat'] as num).toInt();
              final bid   = s['bid'];
              final won   = s['won'];
              final score = (s['score'] as num).toDouble();
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Seat $seat  B:$bid  W:$won',
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13)),
                    Text(
                      score >= 0
                          ? '+${score.toStringAsFixed(1)}'
                          : score.toStringAsFixed(1),
                      style: TextStyle(
                        color: score >= 0
                            ? AppColors.primaryLight
                            : AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<GameBloc>().add(GameNextRound());
              },
              child: const Text('Next Round',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
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
class _ScoreBadge extends StatelessWidget {
  final int tricks;
  final int? bid;
  final bool isTurn;
  const _ScoreBadge(this.tricks, {this.bid, this.isTurn = false});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: isTurn
          ? AppColors.primary.withValues(alpha: 0.85)
          : Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isTurn ? AppColors.primary : Colors.white24,
        width: isTurn ? 1.5 : 0.8,
      ),
      boxShadow: isTurn
          ? [BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8)]
          : null,
    ),
    child: Text(
      bid != null ? '$tricks/$bid' : '$tricks',
      style: TextStyle(
        color: isTurn ? Colors.white : const Color(0xFFCCFF90),
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );
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
class _WoodBackground extends StatelessWidget {
  const _WoodBackground();
  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: CustomPaint(painter: _WoodPainter()));
}

class _WoodPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB8855A), Color(0xFF9C6B3E), Color(0xFFA87848)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    final rng  = math.Random(42);
    final dark = Paint()..style = PaintingStyle.stroke;

    for (int i = 0; i < 70; i++) {
      final y   = rng.nextDouble() * size.height;
      final op  = 0.04 + rng.nextDouble() * 0.12;
      final isDk = rng.nextBool();
      dark
        ..color       = (isDk ? Colors.black : Colors.white).withValues(alpha: op)
        ..strokeWidth = 0.4 + rng.nextDouble() * 2.0;

      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 18) {
        path.lineTo(x, y + (rng.nextDouble() - 0.5) * 5);
      }
      canvas.drawPath(path, dark);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.25)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
