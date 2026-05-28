import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/services/socket_service.dart';
import '../../domain/entities/card_entity.dart';
import '../../domain/entities/game_state_entity.dart';

// ─── Events ───────────────────────────────────────────────────────────────────

abstract class GameEvent extends Equatable {
  @override List<Object?> get props => [];
}

class GameJoinRoom extends GameEvent {
  final String roomId;
  final int mySeat;
  GameJoinRoom(this.roomId, this.mySeat);
  @override List<Object?> get props => [roomId, mySeat];
}

class GameStartGame extends GameEvent {
  final String roomId;
  GameStartGame(this.roomId);
  @override List<Object?> get props => [roomId];
}

class GameStarted extends GameEvent {
  final Map<String, dynamic> data;
  GameStarted(this.data);
}

class GameDealtCards extends GameEvent {
  final List<CardEntity> hand;
  final int seat;
  GameDealtCards(this.hand, this.seat);
}

class GameBiddingStarted extends GameEvent {
  final Map<String, dynamic> data;
  GameBiddingStarted(this.data);
}

class GameBidPlaced extends GameEvent {
  final int seat;
  final int bid;
  GameBidPlaced(this.seat, this.bid);
}

class GameCardPlayed extends GameEvent {
  final int seat;
  final CardEntity card;
  GameCardPlayed(this.seat, this.card);
}

class GameTrickResult extends GameEvent {
  final Map<String, dynamic> data;
  GameTrickResult(this.data);
}

class GameRoundResult extends GameEvent {
  final Map<String, dynamic> data;
  GameRoundResult(this.data);
}

class GameResult extends GameEvent {
  final Map<String, dynamic> data;
  GameResult(this.data);
}

class GameStateUpdated extends GameEvent {
  final Map<String, dynamic> data;
  GameStateUpdated(this.data);
}

class GameStateSynced extends GameEvent {
  final Map<String, dynamic> data;
  GameStateSynced(this.data);
}

class GamePlaceBid extends GameEvent {
  final int bid;
  GamePlaceBid(this.bid);
}

class GamePlayCard extends GameEvent {
  final CardEntity card;
  GamePlayCard(this.card);
}

class GameNextRound extends GameEvent {}

class GameErrorReceived extends GameEvent {
  final String message;
  GameErrorReceived(this.message);
}

class GameChatReceived extends GameEvent {
  final String userId, username, message;
  GameChatReceived(this.userId, this.username, this.message);
}

class GameEmojiReceived extends GameEvent {
  final String userId, emoji;
  GameEmojiReceived(this.userId, this.emoji);
}

class GameLeave extends GameEvent {}

// ─── States ───────────────────────────────────────────────────────────────────

abstract class GameState extends Equatable {
  @override List<Object?> get props => [];
}

class GameInitial extends GameState {}

class GameConnecting extends GameState {}

class GameWaiting extends GameState {
  final String roomId;
  GameWaiting(this.roomId);
  @override List<Object?> get props => [roomId];
}

class GameInProgress extends GameState {
  final GameStateEntity state;
  final List<ChatMessage> chatMessages;
  final TrickResultData? lastTrickResult;
  final RoundResultData? lastRoundResult;
  final GameResultData? gameResult;
  final String? errorMessage;

  GameInProgress({
    required this.state,
    this.chatMessages = const [],
    this.lastTrickResult,
    this.lastRoundResult,
    this.gameResult,
    this.errorMessage,
  });

  GameInProgress copyWithState(GameStateEntity s) => GameInProgress(
    state: s, chatMessages: chatMessages,
    lastTrickResult: lastTrickResult,
    lastRoundResult: lastRoundResult,
    gameResult: gameResult,
  );

  @override List<Object?> get props => [state, chatMessages, lastTrickResult, lastRoundResult, gameResult, errorMessage];
}

class GameErrorState extends GameState {
  final String message;
  GameErrorState(this.message);
  @override List<Object?> get props => [message];
}

// ─── Helper data classes ──────────────────────────────────────────────────────

class ChatMessage {
  final String userId, username, message;
  final int timestamp;
  ChatMessage(this.userId, this.username, this.message, this.timestamp);
}

class TrickResultData {
  final int winnerSeat;
  final String ledSuit;
  final Map<int, int> tricksWon;
  final List<TrickPlay> trickCards;
  TrickResultData(this.winnerSeat, this.ledSuit, this.tricksWon, this.trickCards);
}

class RoundResultData {
  final int round;
  final List<dynamic> roundScores;
  final Map<int, double> totalScores;
  RoundResultData(this.round, this.roundScores, this.totalScores);
}

class PlayerReward {
  final int xpEarned;
  final int newXp;
  final int oldLevel;
  final int newLevel;
  final int coinsEarned;
  final bool leveledUp;

  const PlayerReward({
    required this.xpEarned,
    required this.newXp,
    required this.oldLevel,
    required this.newLevel,
    required this.coinsEarned,
    required this.leveledUp,
  });

  factory PlayerReward.fromJson(Map<String, dynamic> j) => PlayerReward(
    xpEarned:    (j['xpEarned']    as num?)?.toInt() ?? 0,
    newXp:       (j['newXp']       as num?)?.toInt() ?? 0,
    oldLevel:    (j['oldLevel']    as num?)?.toInt() ?? 1,
    newLevel:    (j['newLevel']    as num?)?.toInt() ?? 1,
    coinsEarned: (j['coinsEarned'] as num?)?.toInt() ?? 0,
    leveledUp:   j['leveledUp']    as bool? ?? false,
  );
}

class GameResultData {
  final int winnerSeat;
  final String winnerName;
  final Map<int, double> finalScores;
  final double betAmount;
  final double totalPot;
  final String? winnerUserId;
  final PlayerReward? myReward;

  GameResultData(
    this.winnerSeat,
    this.winnerName,
    this.finalScores, {
    this.betAmount   = 0,
    this.totalPot    = 0,
    this.winnerUserId,
    this.myReward,
  });

  bool get hasBet => betAmount > 0;
}

// ─── BLoC ─────────────────────────────────────────────────────────────────────

class GameBloc extends Bloc<GameEvent, GameState> {
  final SocketService _socket;
  String? _roomId;
  int _mySeat = 0;
  int get mySeat => _mySeat;
  bool _listenersRegistered = false;
  List<Map<String, dynamic>> _pendingPlayers = [];
  List<CardEntity> _pendingHand = [];

  GameBloc({SocketService? socket})
      : _socket = socket ?? SocketService(),
        super(GameInitial()) {
    on<GameJoinRoom>(_onJoin);
    on<GameStartGame>(_onStartGame);
    on<GameStarted>(_onStarted);
    on<GameDealtCards>(_onDealt);
    on<GameBiddingStarted>(_onBidding);
    on<GameBidPlaced>(_onBidPlaced);
    on<GameCardPlayed>(_onCardPlayed);
    on<GameTrickResult>(_onTrickResult);
    on<GameRoundResult>(_onRoundResult);
    on<GameResult>(_onGameResult);
    on<GameStateUpdated>(_onStateUpdate);
    on<GameStateSynced>(_onStateSync);
    on<GamePlaceBid>(_onPlaceBid);
    on<GamePlayCard>(_onPlayCard);
    on<GameNextRound>(_onNextRound);
    on<GameErrorReceived>(_onError);
    on<GameChatReceived>(_onChat);
    on<GameEmojiReceived>(_onEmoji);
    on<GameLeave>(_onLeave);
  }

  void _registerSocketListeners() {
    _socket.on('game_started',     (d) => add(GameStarted(Map<String, dynamic>.from(d as Map))));
    _socket.on('deal_cards',       (d) {
      final data = Map<String, dynamic>.from(d as Map);
      final cards = (data['hand'] as List).map((c) =>
          CardEntity.fromJson(Map<String, dynamic>.from(c as Map))).toList();
      add(GameDealtCards(cards, (data['seat'] as num).toInt()));
    });
    _socket.on('bidding_started',  (d) => add(GameBiddingStarted(Map<String, dynamic>.from(d as Map))));
    _socket.on('bid_placed',       (d) {
      final data = Map<String, dynamic>.from(d as Map);
      add(GameBidPlaced((data['seat'] as num).toInt(), (data['bid'] as num).toInt()));
    });
    _socket.on('card_played',      (d) {
      final data = Map<String, dynamic>.from(d as Map);
      add(GameCardPlayed(
        (data['seat'] as num).toInt(),
        CardEntity.fromJson(Map<String, dynamic>.from(data['card'] as Map)),
      ));
    });
    _socket.on('trick_result',     (d) => add(GameTrickResult(Map<String, dynamic>.from(d as Map))));
    _socket.on('round_result',     (d) => add(GameRoundResult(Map<String, dynamic>.from(d as Map))));
    _socket.on('game_result',      (d) => add(GameResult(Map<String, dynamic>.from(d as Map))));
    _socket.on('game_state_update',(d) => add(GameStateUpdated(Map<String, dynamic>.from(d as Map))));
    _socket.on('game_state_sync',  (d) => add(GameStateSynced(Map<String, dynamic>.from(d as Map))));
    _socket.on('error',            (d) => add(GameErrorReceived((d as Map)['message'] as String)));
    _socket.on('chat_message',     (d) {
      final data = Map<String, dynamic>.from(d as Map);
      add(GameChatReceived(data['userId'] as String, data['username'] as String, data['message'] as String));
    });
    _socket.on('emoji_reaction',   (d) {
      final data = Map<String, dynamic>.from(d as Map);
      add(GameEmojiReceived(data['userId'] as String, data['emoji'] as String));
    });
  }

  void _onJoin(GameJoinRoom event, Emitter<GameState> emit) {
    _roomId = event.roomId;
    if (event.mySeat != 0) _mySeat = event.mySeat;
    if (!_listenersRegistered) {
      _listenersRegistered = true;
      _registerSocketListeners();
    }
    // Reconnect if the socket was disconnected from a previous game's leave.
    if (!_socket.isConnected) _socket.connect();
    _socket.joinRoom(event.roomId);
    // Don't revert to waiting if the game is already in progress.
    // game_page calls GameJoinRoom in initState which can arrive after
    // bidding_started has already emitted GameInProgress.
    if (state is! GameInProgress) {
      emit(GameWaiting(event.roomId));
    }
  }

  void _onStartGame(GameStartGame event, Emitter<GameState> emit) {
    _socket.startGame(event.roomId);
  }

  void _onStarted(GameStarted event, Emitter<GameState> emit) {
    // Store players list sent with game_started for use in _onBidding
    final raw = event.data['players'];
    if (raw is List) {
      _pendingPlayers = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }

  void _onDealt(GameDealtCards event, Emitter<GameState> emit) {
    // Always update mySeat from the actual seat the server assigned us
    _mySeat = event.seat;
    _pendingHand = event.hand;
    if (state is GameInProgress) {
      final current = (state as GameInProgress).state;
      emit((state as GameInProgress).copyWithState(current.copyWith(hand: event.hand)));
    }
  }

  void _onBidding(GameBiddingStarted event, Emitter<GameState> emit) {
    final prevScores = state is GameInProgress
        ? _rawScores((state as GameInProgress).state.scores)
        : <String, dynamic>{};
    final gs = GameStateEntity.fromJson({
      'roomId':       _roomId,
      'round':        event.data['round'],
      'phase':        'bidding',
      'dealer':       event.data['dealer'],
      'bids':         {},
      'tricksWon':    {},
      'scores':       prevScores,
      'currentTurn':  event.data['currentTurn'],
      'ledSuit':      null,
      'currentTrick': [],
      'players':      _pendingPlayers,
      'hand':         _rawHand(_pendingHand),
    }, _mySeat);
    emit(GameInProgress(state: gs));
  }

  void _onBidPlaced(GameBidPlaced event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final s = (state as GameInProgress).state;
    final newBids = Map<int, int>.from(s.bids)..[event.seat] = event.bid;
    emit((state as GameInProgress).copyWithState(s.copyWith(bids: newBids)));
  }

  void _onCardPlayed(GameCardPlayed event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final s = (state as GameInProgress).state;
    final newHand = event.seat == _mySeat
        ? s.hand.where((c) => c != event.card).toList()
        : s.hand;
    final newTrick = [...s.currentTrick, TrickPlay(seat: event.seat, card: event.card)];
    emit((state as GameInProgress).copyWithState(s.copyWith(hand: newHand, currentTrick: newTrick)));
  }

  void _onTrickResult(GameTrickResult event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final d = event.data;
    final rawTricks = Map<String, dynamic>.from((d['tricksWon'] as Map?) ?? {});
    final tricks = rawTricks.map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
    final s = (state as GameInProgress).state;
    final tr = TrickResultData(
      (d['winnerSeat'] as num).toInt(),
      d['ledSuit'] as String? ?? '',
      tricks,
      List<TrickPlay>.from(s.currentTrick), // capture before clearing
    );
    emit(GameInProgress(
      state: s.copyWith(tricksWon: tricks, currentTrick: []),
      chatMessages: (state as GameInProgress).chatMessages,
      lastTrickResult: tr,
    ));
  }

  void _onRoundResult(GameRoundResult event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final d = event.data;
    final rawScores = (d['totalScores'] as Map<String, dynamic>?) ?? {};
    final scores = rawScores.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
    final rr = RoundResultData(
      (d['round'] as num).toInt(),
      d['roundScores'] as List<dynamic>? ?? [],
      scores,
    );
    final s = (state as GameInProgress).state;
    emit(GameInProgress(
      state: s.copyWith(scores: scores, phase: 'round_end'),
      chatMessages: (state as GameInProgress).chatMessages,
      lastRoundResult: rr,
    ));
  }

  void _onGameResult(GameResult event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final d = event.data;
    final rawScores = (d['finalScores'] as Map<String, dynamic>?) ?? {};
    final scores = rawScores.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));

    // Parse optional bet result
    final betRaw    = d['betResult'] as Map?;
    final betAmount = (betRaw?['betAmount']  as num?)?.toDouble() ?? 0.0;
    final totalPot  = (betRaw?['totalPot']   as num?)?.toDouble() ?? 0.0;
    final winnerUid = betRaw?['winnerUserId'] as String?;

    // Extract this player's reward by seat
    PlayerReward? myReward;
    final rewardsRaw = d['playerRewards'] as Map?;
    if (rewardsRaw != null) {
      final raw = rewardsRaw[_mySeat.toString()];
      if (raw != null) {
        myReward = PlayerReward.fromJson(Map<String, dynamic>.from(raw as Map));
      }
    }

    final gr = GameResultData(
      (d['winnerSeat'] as num).toInt(),
      d['winnerName'] as String? ?? '',
      scores,
      betAmount:    betAmount,
      totalPot:     totalPot,
      winnerUserId: winnerUid,
      myReward:     myReward,
    );
    final s = (state as GameInProgress).state;
    emit(GameInProgress(
      state: s.copyWith(phase: 'game_end', scores: scores),
      chatMessages: (state as GameInProgress).chatMessages,
      gameResult: gr,
    ));
  }

  void _onStateUpdate(GameStateUpdated event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final d = event.data;
    final s = (state as GameInProgress).state;
    final rawTricks = (d['tricksWon'] as Map<String, dynamic>?) ?? {};
    final tricks = rawTricks.isEmpty ? s.tricksWon
        : rawTricks.map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
    final rawTrick = (d['currentTrick'] as List<dynamic>?) ?? [];
    final currentTrick = rawTrick.isEmpty ? s.currentTrick
        : rawTrick.map((e) => TrickPlay.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    emit((state as GameInProgress).copyWithState(s.copyWith(
      phase:        d['phase'] as String? ?? s.phase,
      currentTurn:  (d['currentTurn'] as num?)?.toInt() ?? s.currentTurn,
      tricksWon:    tricks,
      currentTrick: currentTrick,
      ledSuit:      d['ledSuit'] as String?,
    )));
  }

  void _onStateSync(GameStateSynced event, Emitter<GameState> emit) {
    final gs = GameStateEntity.fromJson(event.data, _mySeat);
    emit(GameInProgress(state: gs));
  }

  void _onPlaceBid(GamePlaceBid event, Emitter<GameState> emit) {
    if (_roomId == null) return;
    _socket.placeBid(_roomId!, event.bid);
  }

  void _onPlayCard(GamePlayCard event, Emitter<GameState> emit) {
    if (_roomId == null) return;
    _socket.playCard(_roomId!, event.card.toJson().map((k, v) => MapEntry(k, v.toString())));
  }

  void _onNextRound(GameNextRound event, Emitter<GameState> emit) {
    if (_roomId == null) return;
    _socket.nextRound(_roomId!);
  }

  void _onError(GameErrorReceived event, Emitter<GameState> emit) {
    if (state is GameInProgress) {
      final prev = state as GameInProgress;
      emit(GameInProgress(
        state: prev.state,
        chatMessages: prev.chatMessages,
        lastTrickResult: prev.lastTrickResult,
        lastRoundResult: prev.lastRoundResult,
        gameResult: prev.gameResult,
        errorMessage: event.message,
      ));
    } else {
      emit(GameErrorState(event.message));
    }
  }

  void _onChat(GameChatReceived event, Emitter<GameState> emit) {
    if (state is! GameInProgress) return;
    final current = state as GameInProgress;
    final msgs = [...current.chatMessages,
      ChatMessage(event.userId, event.username, event.message, DateTime.now().millisecondsSinceEpoch)];
    emit(GameInProgress(
      state: current.state, chatMessages: msgs,
      lastTrickResult: current.lastTrickResult,
      lastRoundResult: current.lastRoundResult,
      gameResult: current.gameResult,
    ));
  }

  void _onEmoji(GameEmojiReceived event, Emitter<GameState> emit) {}

  void _onLeave(GameLeave event, Emitter<GameState> emit) {
    // Remove every listener so they don't stack on the next game.
    for (final e in [
      'game_started', 'deal_cards', 'bidding_started', 'bid_placed',
      'card_played', 'trick_result', 'round_result', 'game_result',
      'game_state_update', 'game_state_sync', 'error',
      'chat_message', 'emoji_reaction',
    ]) { _socket.off(e); }
    // Allow the next GameJoinRoom to re-register listeners fresh.
    _listenersRegistered = false;
    _pendingPlayers = [];
    _pendingHand    = [];
    _socket.disconnect();
    emit(GameInitial());
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _rawScores(Map<int, double> scores) =>
      scores.map((k, v) => MapEntry(k.toString(), v));

  List<Map<String, dynamic>> _rawHand(List<CardEntity> hand) =>
      hand.map((c) => c.toJson()).toList();
}
