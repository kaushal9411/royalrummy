import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/card_entity.dart';
import '../../domain/entities/game_state_entity.dart';
import '../bloc/game_bloc.dart';
import '../widgets/card_widget.dart';
import '../widgets/bid_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _trickAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
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
    _trickAnimCtrl.dispose();
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
              // Trick win animation
              if (state.lastTrickResult != null &&
                  !identical(state.lastTrickResult, _lastTriggered) &&
                  state.lastTrickResult!.trickCards.isNotEmpty) {
                _lastTriggered = state.lastTrickResult;
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
  Widget _buildLoader() => Stack(
    children: [
      const _WoodBackground(),
      const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    ],
  );

  // ── Main game layout ───────────────────────────────────────────────────────
  Widget _buildGame(BuildContext context, GameInProgress gip) {
    final gs       = gip.state;
    final mySeat   = gs.mySeat;
    final topSeat  = (mySeat + 2) % 4;
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
        // ── Wood table ──
        const _WoodBackground(),

        // ── Layout ──
        SafeArea(
          child: Column(

            children: [
              // Top: [X]  [Bot-top + fan]  [♠ trump]
              _buildTopRow(gs, topP, topSeat, gs.bids[topSeat],
                  gs.tricksWon[topSeat] ?? 0, botCards),

              // Middle: Bot-left | Trick area | Bot-right
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

              // Player hand row
              _buildPlayerHand(context, gip, myP, mySeat),
            ],
          ),
        ),

        // ── Trick win animation overlay ──
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
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exit button
          Padding(
            padding: const EdgeInsets.all(8),
            child: GestureDetector(
              onTap: () {
                context.read<GameBloc>().add(GameLeave());
                context.go('/lobby');
              },
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),

          // Top bot
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                // Info row: name + score
                if (player != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(player.username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                      const SizedBox(width: 6),
                      _ScoreBadge(tricks, bid: bid, isTurn: gs.currentTurn == seat),
                    ],
                  ),
                const SizedBox(height: 6),
                // Card fan pointing down
                _CardFan(cardCount, baseRotation: math.pi),
              ],
            ),
          ),

          // Trump indicator
          Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('♠', style: TextStyle(color: Colors.white, fontSize: 16)),
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
      width: 85,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Card fan rotated 90°
          _CardFan(cardCount, baseRotation: isLeft ? -math.pi / 2 : math.pi / 2),
          const SizedBox(height: 8),
          // Name + score
          if (player != null) ...[
            Text(player.username,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
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
                    color: AppColors.primary.withValues(alpha: 0.7),
                    width: 2,
                  )
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
                      gs.isBidding ? 'Bidding…' : (canPlay ? 'Drop card here' : 'Lead a card'),
                      style: TextStyle(
                        color: hovering ? AppColors.primaryLight : Colors.white54,
                        fontSize: 14,
                        fontWeight: hovering ? FontWeight.bold : FontWeight.normal,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                      ),
                    ),
                    if (canPlay && !gs.isBidding) ...[
                      const SizedBox(height: 6),
                      Icon(
                        Icons.arrow_downward_rounded,
                        color: hovering
                            ? AppColors.primary
                            : Colors.white24,
                        size: 20,
                      ),
                    ],
                  ],
                )
              else
                Stack(
                  alignment: Alignment.center,
                  children: List.generate(trick.length, (i) {
                    final angles  = [-0.15, 0.08, -0.05, 0.12];
                    final offsets = [
                      const Offset(-18, -10),
                      const Offset(10, -14),
                      const Offset(-6, 12),
                      const Offset(16, 8),
                    ];
                    return Transform.translate(
                      offset: i < offsets.length ? offsets[i] : Offset.zero,
                      child: Transform.rotate(
                        angle: i < angles.length ? angles[i] : 0,
                        child: CardWidget(card: trick[i].card, width: 60, height: 86),
                      ),
                    );
                  }),
                ),

              // Phase label
              if (gs.isBidding)
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Bidding',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Player hand ────────────────────────────────────────────────────────────
  Widget _buildPlayerHand(BuildContext context, GameInProgress gip,
      PlayerInfo? myPlayer, int mySeat) {
    final gs       = gip.state;
    final hand     = gs.hand;
    final canPlay  = gs.isMyTurn && gs.isPlaying;
    final myBid    = gs.bids[mySeat];
    final myTricks = gs.tricksWon[mySeat] ?? 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120, maxHeight: 160),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          border: const Border(top: BorderSide(color: Colors.black26, width: 1)),
        ),
      child: Column(
        children: [
          // Info bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  myPlayer?.username ?? 'You',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Row(
                  children: [
                    if (myBid != null)
                      _ScoreBadge(myTricks, bid: myBid, isTurn: gs.isMyTurn),
                    if (canPlay) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Drag to play',
                            style: TextStyle(
                                color: AppColors.primaryLight,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Cards — draggable when it's player's turn
          Expanded(
            child: hand.isEmpty
                ? const Center(
                    child: Text('No cards', style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    itemCount: hand.length,
                    itemBuilder: (_, i) {
                      final card = hand[i];
                      if (!canPlay) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: CardWidget(card: card, width: 68, height: 98),
                        );
                      }
                      return Draggable<CardEntity>(
                        data: card,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Transform.scale(
                            scale: 1.12,
                            child: CardWidget(
                              card: card,
                              isSelected: true,
                              width: 68,
                              height: 98,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: CardWidget(card: card, width: 68, height: 98),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: CardWidget(
                            card: card,
                            isPlayable: true,
                            width: 68,
                            height: 98,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
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
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    Text(
                      score >= 0 ? '+${score.toStringAsFixed(1)}' : score.toStringAsFixed(1),
                      style: TextStyle(
                        color: score >= 0 ? AppColors.primaryLight : AppColors.danger,
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
              child: const Text('Next Round', style: TextStyle(color: AppColors.primary)),
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
              style: TextStyle(color: AppColors.accent, fontSize: 22, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🏆 ${gr.winnerName}',
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 20, fontWeight: FontWeight.bold)),
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
                        color: e.value >= 0 ? AppColors.primaryLight : AppColors.danger,
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

// ── Trick win overlay ──────────────────────────────────────────────────────
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
  static const _offsets = [Offset(-18, -10), Offset(10, -14), Offset(-6, 12), Offset(16, 8)];

  @override
  Widget build(BuildContext context) {
    final size    = MediaQuery.of(context).size;
    final relSeat = (trick.winnerSeat - mySeat + 4) % 4;
    // 0=me(bottom) 1=right 2=top 3=left
    final endOffset = [
      Offset(0,              size.height * 0.46),
      Offset(size.width * 0.46,  0),
      Offset(0,             -size.height * 0.46),
      Offset(-size.width * 0.46, 0),
    ][relSeat];
    final isMyWin = trick.winnerSeat == mySeat;

    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;
        // 0-0.35 → hold + show banner, 0.35-1.0 → fly to winner
        final flyT   = t < 0.35 ? 0.0 : Curves.easeIn.transform((t - 0.35) / 0.65);
        final cardOp = flyT < 0.82 ? 1.0 : 1.0 - (flyT - 0.82) / 0.18;
        final dx     = endOffset.dx * flyT;
        final dy     = endOffset.dy * flyT;
        final scale  = 1.0 - 0.55 * flyT;

        // banner: fade-in 0-0.15, hold 0.15-0.30, fade-out 0.30-0.45
        final bannerOp = t < 0.15 ? t / 0.15
            : t < 0.30 ? 1.0
            : t < 0.45 ? 1.0 - (t - 0.30) / 0.15
            : 0.0;

        return Stack(
          children: [
            // Winner banner
            if (bannerOp > 0.01)
              Positioned(
                top: size.height * 0.37,
                left: 0, right: 0,
                child: Center(
                  child: Opacity(
                    opacity: bannerOp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMyWin ? AppColors.primary : const Color(0xFF1A1A2E),
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
                        isMyWin ? '🏆 You win the trick!' : '✨ Seat ${trick.winnerSeat + 1} wins',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Cards flying to winner
            if (cardOp > 0.01)
              Center(
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: cardOp,
                      child: SizedBox(
                        width: 130, height: 120,
                        child: Stack(
                          alignment: Alignment.center,
                          children: List.generate(
                            trick.trickCards.length.clamp(0, 4),
                            (i) => Transform.translate(
                              offset: i < _offsets.length ? _offsets[i] : Offset.zero,
                              child: Transform.rotate(
                                angle: i < _angles.length ? _angles[i] : 0,
                                child: CardWidget(
                                  card: trick.trickCards[i].card,
                                  width: 62, height: 88,
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

// ── Score badge ────────────────────────────────────────────────────────────
class _ScoreBadge extends StatelessWidget {
  final int tricks;
  final int? bid;
  final bool isTurn;
  const _ScoreBadge(this.tricks, {this.bid, this.isTurn = false});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
          ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8)]
          : null,
    ),
    child: Text(
      bid != null ? '$tricks/$bid' : '$tricks',
      style: TextStyle(
        color: isTurn ? Colors.white : const Color(0xFFCCFF90),
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    ),
  );
}

// ── Card fan (bot hands) ───────────────────────────────────────────────────
class _CardFan extends StatelessWidget {
  final int count;
  final double baseRotation;
  const _CardFan(this.count, {this.baseRotation = 0});

  @override
  Widget build(BuildContext context) {
    final n = count.clamp(1, 13);
    const cw = 34.0;
    const ch = 50.0;
    final spread = (math.pi * 0.50) / n.clamp(1, 13).toDouble();
    final total  = spread * (n - 1);

    return Transform.rotate(
      angle: baseRotation,
      child: SizedBox(
        width: cw + 70,
        height: ch + 36,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: List.generate(n, (i) {
            final angle = -total / 2 + i * spread;
            return Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomCenter,
              child: _CardBack(width: cw, height: ch),
            );
          }),
        ),
      ),
    );
  }
}

// ── Card back ──────────────────────────────────────────────────────────────
class _CardBack extends StatelessWidget {
  final double width, height;
  const _CardBack({this.width = 34, this.height = 50});

  @override
  Widget build(BuildContext context) => Container(
    width:  width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: Colors.white, width: 1.2),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(1, 2))],
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD32F2F), Color(0xFF9C0000)],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
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
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const gap = 5.0;
    for (double i = -size.height; i < size.width + size.height; i += gap) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
      canvas.drawLine(Offset(i + size.height, 0), Offset(i, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}

// ── Wood background ────────────────────────────────────────────────────────
class _WoodBackground extends StatelessWidget {
  const _WoodBackground();

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(painter: _WoodPainter()),
  );
}

class _WoodPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Base warm wood color
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

    // Wood grain lines
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

    // Subtle vignette
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.25),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
