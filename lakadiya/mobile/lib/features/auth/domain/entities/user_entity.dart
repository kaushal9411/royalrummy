class UserEntity {
  final String id;
  final String username;
  final String? email;
  final String? avatarUrl;
  final int coins;
  final int xp;
  final int level;
  final String provider;

  const UserEntity({
    required this.id,
    required this.username,
    this.email,
    this.avatarUrl,
    required this.coins,
    required this.xp,
    required this.level,
    required this.provider,
  });

  factory UserEntity.fromJson(Map<String, dynamic> json) => UserEntity(
        id:        json['id'] as String,
        username:  json['username'] as String,
        email:     json['email'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        coins:     (json['coins'] as num?)?.toInt() ?? 1000,
        xp:        (json['xp'] as num?)?.toInt() ?? 0,
        level:     (json['level'] as num?)?.toInt() ?? 1,
        provider:  json['provider'] as String? ?? 'local',
      );

  Map<String, dynamic> toJson() => {
        'id':         id,
        'username':   username,
        'email':      email,
        'avatar_url': avatarUrl,
        'coins':      coins,
        'xp':         xp,
        'level':      level,
        'provider':   provider,
      };
}
