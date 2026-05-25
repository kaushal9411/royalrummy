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
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A2035),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Game Over! 🎉',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🏆 ${gr.winnerName}',
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...gr.finalScores.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Seat ${e.key}',
                        style: const TextStyle(color: AppColors.textSecondary)),
                    Text(
                      e.value >= 0
                          ? '+${e.value.toStringAsFixed(1)}'
                          : e.value.toStringAsFixed(1),
                      style: TextStyle(
                        color: e.value >= 0
                            ? AppColors.primaryLight
                            : AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<GameBloc>().add(GameLeave());
                context.go('/lobby');
              },
              child: const Text('Back to Lobby'),
            ),
          ],
        ),
      );
    });
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
