import '../../../../core/constants/app_constants.dart';

class CardEntity {
  final String suit;
  final String rank;
  final bool hidden;

  const CardEntity({
    required this.suit,
    required this.rank,
    this.hidden = false,
  });

  factory CardEntity.fromJson(Map<String, dynamic> json) {
    if (json['hidden'] == true) {
      return const CardEntity(suit: '', rank: '', hidden: true);
    }
    return CardEntity(
      suit: json['suit'] as String,
      rank: json['rank'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'suit': suit, 'rank': rank};

  bool get isTrump => suit == AppConstants.trumpSuit;

  bool get isRed => suit == 'hearts' || suit == 'diamonds';

  String get symbol => AppConstants.suitSymbols[suit] ?? '';

  String get displayRank => rank;

  @override
  bool operator ==(Object other) =>
      other is CardEntity && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;

  @override
  String toString() => '$rank$symbol';
}
