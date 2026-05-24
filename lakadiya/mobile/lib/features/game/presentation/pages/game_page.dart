import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/card_entity.dart';
import '../../domain/entities/game_state_entity.dart';
import '../bloc/game_bloc.dart';
import '../widgets/card_widget.dart';
import '../widgets/player_seat_widget.dart';
import '../widgets/bid_dialog.dart';

class GamePage extends StatefulWidget {
  final String roomId;
  const GamePage({super.key, required this.roomId});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  CardEntity? _selectedCard;

  @override
  void initState() {
    super.initState();
    // Reconnect in case of refresh
    context.read<GameBloc>().add(GameJoinRoom(widget.roomId, 0));
  }

  void _onCardTap(CardEntity card, GameInProgress state) {
    if (!state.state.isMyTurn || !state.state.isPlaying) return;
    setState(() => _selectedCard = _selectedCard == card ? null : card);
  }

  void _playSelected(GameInProgress state) {
    if (_selectedCard == null) return;
    context.read<GameBloc>().add(GamePlayCard(_selectedCard!));
    setState(() => _selectedCard = null);
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
        backgroundColor: const Color(0xFF0A3A1A),
        body: BlocConsumer<GameBloc, GameState>(
          listener: (ctx, state) {
            if (state is GameInProgress) {
              // Auto-prompt bid when it's my turn
              if (state.state.isBidding &&
                  state.state.isMyTurn &&
                  !state.state.bids.containsKey(state.state.mySeat)) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _showBidDialog());
              }
              // Show round result
              if (state.lastRoundResult != null && state.state.phase == 'round_end') {
                _showRoundResult(ctx, state.lastRoundResult!);
              }
              // Show game result
              if (state.gameResult != null && state.state.phase == 'game_end') {
                _showGameResult(ctx, state.gameResult!);
              }
            }
            if (state is GameErrorState) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: AppColors.danger),
              );
            }
          },
          builder: (ctx, state) {
            if (state is GameWaiting || state is GameInitial || state is GameConnecting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (state is GameInProgress) return _buildGame(ctx, state);
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Widget _buildGame(BuildContext context, GameInProgress state) {
    final gs = state.state;
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(gs),
          Expanded(
            child: Stack(
              children: [
                _buildTable(gs),
                _buildPlayers(gs),
              ],
            ),
          ),
          _buildMyHand(context, state),
        ],
      ),
    );
  }

  Widget _buildTopBar(GameStateEntity gs) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: Colors.black26,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.read<GameBloc>().add(GameLeave());
            context.go('/lobby');
          },
        ),
        Column(
          children: [
            Text('Round ${gs.round} / 5',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.trump.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('♠ Trump', style: TextStyle(color: AppColors.trumpLight, fontSize: 11)),
            ),
          ],
        ),
        Text(_phaseLabel(gs.phase),
            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _buildTable(GameStateEntity gs) => Center(
    child: Container(
      width: 180, height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF0D5C2A),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF1A8C40), width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (gs.currentTrick.isNotEmpty) ...[
            Wrap(
              spacing: 4,
              children: gs.currentTrick.map((tp) =>
                CardWidget(card: tp.card, width: 36, height: 52)
              ).toList(),
            ),
          ] else ...[
            Text(
              gs.ledSuit != null
                  ? 'Led: ${gs.ledSuit}'
                  : gs.isBidding ? 'Bidding…' : 'Lead a card',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildPlayers(GameStateEntity gs) {
    // Position 4 players around the table: top, right, bottom (me), left
    final positions = [
      // seat 0 = top
      const Alignment(0, -0.95),
      // seat 1 = right
      const Alignment(0.95, 0),
      // seat 2 = bottom (usually me)
      const Alignment(0, 0.95),
      // seat 3 = left
      const Alignment(-0.95, 0),
    ];

    return Stack(
      children: List.generate(gs.players.length, (i) {
        final player = gs.players[i];
        final seat   = player.seat;
        final align  = positions[seat % 4];
        return Align(
          alignment: align,
          child: PlayerSeatWidget(
            player:        player,
            bid:           gs.bids[seat],
            tricksWon:     gs.tricksWon[seat] ?? 0,
            score:         gs.scores[seat] ?? 0,
            isCurrentTurn: gs.currentTurn == seat,
            isDealer:      gs.dealer == seat,
          ),
        );
      }),
    );
  }

  Widget _buildMyHand(BuildContext context, GameInProgress state) {
    final gs   = state.state;
    final hand = gs.hand;
    if (hand.isEmpty) return const SizedBox(height: 90);

    final canPlay = gs.isMyTurn && gs.isPlaying;

    return Container(
      height: 110,
      color: Colors.black26,
      child: Column(
        children: [
          if (canPlay && _selectedCard != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ElevatedButton.icon(
                onPressed: () => _playSelected(state),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text('Play ${_selectedCard}'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: hand.length,
              itemBuilder: (_, i) {
                final card = hand[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CardWidget(
                    card:       card,
                    isPlayable: canPlay,
                    isSelected: _selectedCard == card,
                    onTap:      canPlay ? () => _onCardTap(card, state) : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(String phase) => switch (phase) {
    'bidding'   => 'Bidding',
    'playing'   => 'Playing',
    'round_end' => 'Round Over',
    'game_end'  => 'Game Over',
    _           => 'Waiting',
  };

  void _showRoundResult(BuildContext context, RoundResultData rr) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: Text('Round ${rr.round} Result',
              style: const TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: rr.roundScores.map((s) {
              final seat  = (s['seat'] as num).toInt();
              final bid   = s['bid'];
              final won   = s['won'];
              final score = (s['score'] as num).toDouble();
              return ListTile(
                title: Text('Seat $seat: Bid $bid, Won $won',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                trailing: Text(
                  score >= 0 ? '+${score.toStringAsFixed(1)}' : score.toStringAsFixed(1),
                  style: TextStyle(
                    color: score >= 0 ? AppColors.primaryLight : AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
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
              child: const Text('Next Round'),
            ),
          ],
        ),
      );
    });
  }

  void _showGameResult(BuildContext context, GameResultData gr) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: const Text('Game Over! 🎉',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.accent)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Winner: ${gr.winnerName}',
                  style: const TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 18, fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 16),
              ...gr.finalScores.entries.map((e) => ListTile(
                dense: true,
                title: Text('Seat ${e.key}',
                    style: const TextStyle(color: AppColors.textPrimary)),
                trailing: Text(
                  e.value >= 0 ? '+${e.value.toStringAsFixed(1)}' : e.value.toStringAsFixed(1),
                  style: TextStyle(
                    color: e.value >= 0 ? AppColors.primaryLight : AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
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
