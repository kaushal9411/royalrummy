import 'card_entity.dart';

class PlayerInfo {
  final int seat;
  final String? userId;
  final String username;
  final String? avatar;
  final bool isBot;
  final String? botLevel;

  const PlayerInfo({
    required this.seat,
    this.userId,
    required this.username,
    this.avatar,
    required this.isBot,
    this.botLevel,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> json) => PlayerInfo(
        seat:     (json['seat'] as num).toInt(),
        userId:   json['user_id'] as String?,
        username: json['username'] as String? ?? 'Unknown',
        avatar:   json['avatar'] as String?,
        isBot:    json['is_bot'] as bool? ?? false,
        botLevel: json['bot_level'] as String?,
      );
}

class TrickPlay {
  final int seat;
  final CardEntity card;
  const TrickPlay({required this.seat, required this.card});

  factory TrickPlay.fromJson(Map<String, dynamic> json) => TrickPlay(
        seat: (json['seat'] as num).toInt(),
        card: CardEntity.fromJson(json['card'] as Map<String, dynamic>),
      );
}

class GameStateEntity {
  final String roomId;
  final String? matchId;
  final int round;
  final String phase; // waiting | bidding | playing | round_end | game_end
  final int dealer;
  final Map<int, int> bids;        // seat → bid
  final Map<int, int> tricksWon;   // seat → count
  final Map<int, double> scores;   // seat → total score
  final int? currentTurn;
  final String? ledSuit;
  final List<TrickPlay> currentTrick;
  final List<PlayerInfo> players;
  final List<CardEntity> hand;
  final int mySeat;

  const GameStateEntity({
    required this.roomId,
    this.matchId,
    required this.round,
    required this.phase,
    required this.dealer,
    required this.bids,
    required this.tricksWon,
    required this.scores,
    this.currentTurn,
    this.ledSuit,
    required this.currentTrick,
    required this.players,
    required this.hand,
    required this.mySeat,
  });

  bool get isMyTurn => currentTurn == mySeat;
  bool get isBidding => phase == 'bidding';
  bool get isPlaying => phase == 'playing';

  factory GameStateEntity.fromJson(Map<String, dynamic> json, int mySeat) {
    final bidsRaw = (json['bids'] as Map<String, dynamic>?) ?? {};
    final tricksRaw = (json['tricksWon'] as Map<String, dynamic>?) ?? {};
    final scoresRaw = (json['scores'] as Map<String, dynamic>?) ?? {};

    return GameStateEntity(
      roomId:       json['roomId'] as String,
      matchId:      json['matchId'] as String?,
      round:        (json['round'] as num?)?.toInt() ?? 0,
      phase:        json['phase'] as String? ?? 'waiting',
      dealer:       (json['dealer'] as num?)?.toInt() ?? 0,
      bids:         bidsRaw.map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
      tricksWon:    tricksRaw.map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
      scores:       scoresRaw.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())),
      currentTurn:  (json['currentTurn'] as num?)?.toInt(),
      ledSuit:      json['ledSuit'] as String?,
      currentTrick: (json['currentTrick'] as List<dynamic>? ?? [])
          .map((e) => TrickPlay.fromJson(e as Map<String, dynamic>))
          .toList(),
      players: (json['players'] as List<dynamic>? ?? [])
          .map((e) => PlayerInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      hand: (json['hand'] as List<dynamic>? ?? [])
          .map((e) => CardEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      mySeat: mySeat,
    );
  }

  GameStateEntity copyWith({
    int? round, String? phase, int? dealer,
    Map<int, int>? bids, Map<int, int>? tricksWon, Map<int, double>? scores,
    int? currentTurn, String? ledSuit,
    List<TrickPlay>? currentTrick, List<CardEntity>? hand,
  }) => GameStateEntity(
    roomId: roomId, matchId: matchId, mySeat: mySeat,
    players: players,
    round:        round        ?? this.round,
    phase:        phase        ?? this.phase,
    dealer:       dealer       ?? this.dealer,
    bids:         bids         ?? this.bids,
    tricksWon:    tricksWon    ?? this.tricksWon,
    scores:       scores       ?? this.scores,
    currentTurn:  currentTurn  ?? this.currentTurn,
    ledSuit:      ledSuit      ?? this.ledSuit,
    currentTrick: currentTrick ?? this.currentTrick,
    hand:         hand         ?? this.hand,
  );
}
