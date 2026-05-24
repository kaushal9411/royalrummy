import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../game/providers/game_provider.dart';
import '../../game/providers/socket_provider.dart';
import '../widgets/card_hand_widget.dart';
import '../widgets/game_table_widget.dart';
import '../widgets/player_seat_widget.dart';
import '../widgets/turn_timer_widget.dart';
import '../widgets/action_buttons_widget.dart';
import '../widgets/discard_pile_widget.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String tableId;
  const GameScreen({super.key, required this.tableId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with TickerProviderStateMixin {
  late AnimationController _dealController;
  late AnimationController _cardDrawController;

  @override
  void initState() {
    super.initState();
    _dealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cardDrawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Join the table via socket
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socketServiceProvider).joinTable(widget.tableId);
    });
  }

  @override
  void dispose() {
    _dealController.dispose();
    _cardDrawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider(widget.tableId));
    final myHand = ref.watch(myHandProvider(widget.tableId));
    final isMyTurn = ref.watch(isMyTurnProvider(widget.tableId));

    return WillPopScope(
      onWillPop: () async {
        return await _showLeaveConfirmation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A5C3A), // Casino green
        body: SafeArea(
          child: gameState.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            error: (err, stack) => Center(
              child: Text('Error: $err', style: const TextStyle(color: Colors.white)),
            ),
            data: (state) => Stack(
              children: [
                // ── Background Table ───────────────────────────────────────
                const GameTableWidget(),

                // ── Opponent Seats (top area) ──────────────────────────────
                _buildOpponentSeats(state),

                // ── Center: Closed pile + Open pile ───────────────────────
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Closed (draw) pile
                      _buildClosedPile(state, isMyTurn),
                      const SizedBox(width: 24),
                      // Open (discard) pile
                      DiscardPileWidget(
                        topCard: state.openPileTop,
                        onTap: isMyTurn && state.validActions.contains('draw_card')
                            ? () => _drawFromOpen()
                            : null,
                      ),
                    ],
                  ),
                ),

                // ── Wild Joker indicator ───────────────────────────────────
                Positioned(
                  top: 80,
                  right: 16,
                  child: _buildWildJokerCard(state.wildJoker),
                ),

                // ── Turn Timer ─────────────────────────────────────────────
                if (isMyTurn)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: TurnTimerWidget(tableId: widget.tableId),
                  ),

                // ── My Hand (bottom) ───────────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Action buttons (declare, sort, drop)
                      ActionButtonsWidget(
                        tableId: widget.tableId,
                        isMyTurn: isMyTurn,
                        validActions: state.validActions,
                        onDeclare: _onDeclare,
                        onDrop: _onDrop,
                        onSort: _onSort,
                      ),

                      // Card hand
                      CardHandWidget(
                        cards: myHand,
                        isMyTurn: isMyTurn,
                        validActions: state.validActions,
                        selectedCard: ref.watch(selectedCardProvider),
                        onCardTap: (card) => _onCardTap(card, state.validActions),
                        onCardDoubleTap: (card) => _onCardDiscard(card),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpponentSeats(GameState state) {
    final opponents = state.players
        .where((p) => p.userId != state.myUserId)
        .toList();

    return Positioned(
      top: 40,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: opponents.map((player) => PlayerSeatWidget(
          player: player,
          isCurrentTurn: state.currentTurnUserId == player.userId,
          isDisconnected: player.status == 'disconnected',
        )).toList(),
      ),
    );
  }

  Widget _buildClosedPile(GameState state, bool isMyTurn) {
    return GestureDetector(
      onTap: isMyTurn && state.validActions.contains('draw_card')
          ? () => _drawFromClosed()
          : null,
      child: Stack(
        children: List.generate(
          3,
          (i) => Positioned(
            top: i * 1.0,
            left: i * 1.0,
            child: _buildCardBack(),
          ),
        ),
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      width: 60,
      height: 86,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(2, 2)),
        ],
      ),
      child: Center(
        child: Icon(Icons.style, color: Colors.white.withOpacity(0.5), size: 24),
      ),
    );
  }

  Widget _buildWildJokerCard(String? wildJoker) {
    if (wildJoker == null) return const SizedBox();
    return Column(
      children: [
        const Text('Wild', style: TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
        Container(
          width: 36,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.yellow, width: 2),
          ),
          child: Center(
            child: Text(wildJoker, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  void _drawFromClosed() {
    ref.read(socketServiceProvider).drawCard(widget.tableId, 'closed');
    _cardDrawController.forward().then((_) => _cardDrawController.reset());
  }

  void _drawFromOpen() {
    ref.read(socketServiceProvider).drawCard(widget.tableId, 'open');
  }

  void _onCardTap(String card, List<String> validActions) {
    if (validActions.contains('discard_card')) {
      ref.read(selectedCardProvider.notifier).state = card;
    }
  }

  void _onCardDiscard(String card) {
    final validActions = ref.read(isMyTurnProvider(widget.tableId))
        ? ref.read(gameStateProvider(widget.tableId)).value?.validActions ?? []
        : [];

    if (validActions.contains('discard_card')) {
      ref.read(socketServiceProvider).discardCard(widget.tableId, card);
      ref.read(selectedCardProvider.notifier).state = null;
    }
  }

  void _onDeclare() {
    Navigator.pushNamed(
      context,
      '/game/arrange',
      arguments: {'table_id': widget.tableId},
    );
  }

  void _onDrop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drop Game?'),
        content: const Text('You will receive a penalty of 20-40 points. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Drop'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(socketServiceProvider).dropGame(widget.tableId);
    }
  }

  void _onSort() {
    ref.read(myHandProvider(widget.tableId).notifier).sortHand();
  }

  Future<bool> _showLeaveConfirmation() async {
    final gameState = ref.read(gameStateProvider(widget.tableId)).value;
    if (gameState?.status != 'in_progress') return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Game?'),
        content: const Text('Leaving will count as a drop. Your entry fee may be forfeited.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
