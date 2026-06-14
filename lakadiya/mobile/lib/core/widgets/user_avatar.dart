import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';
import 'avatar_viewer.dart';

/// Reusable circular avatar that shows the uploaded photo when available,
/// falling back to the first letter of [username] on a gradient/solid background.
class UserAvatar extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final double size;

  // Background — use [gradientColors] OR [solidColor]; gradient wins if both given.
  final List<Color>? gradientColors;
  final Color? solidColor;

  final Color textColor;
  final double? fontSize;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  /// Tap the avatar to open a fullscreen, zoomable view. On by default so the
  /// behaviour is consistent everywhere; pass false where a parent already
  /// handles the avatar tap.
  final bool tapToView;

  const UserAvatar({
    super.key,
    required this.username,
    this.avatarUrl,
    this.size = 40,
    this.gradientColors,
    this.solidColor,
    this.textColor = Colors.white,
    this.fontSize,
    this.border,
    this.boxShadow,
    this.tapToView = true,
  });

  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConstants.baseUrl}$url';

  @override
  Widget build(BuildContext context) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final fSize = fontSize ?? (size * 0.38).clamp(10.0, 28.0);

    Widget fallback = Center(
      child: Text(initial,
          style: TextStyle(
              color: textColor, fontSize: fSize, fontWeight: FontWeight.bold)),
    );

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradientColors != null
            ? LinearGradient(colors: gradientColors!)
            : null,
        color: gradientColors == null
            ? (solidColor ?? AppColors.primary)
            : null,
        border: border,
        boxShadow: boxShadow,
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: _fullUrl(avatarUrl!),
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );

    if (!tapToView) return avatar;
    return GestureDetector(
      onTap: () => showAvatarViewer(context, avatarUrl: avatarUrl, username: username),
      child: avatar,
    );
  }
}
