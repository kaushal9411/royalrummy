import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

String _fullAvatarUrl(String url) =>
    url.startsWith('http') ? url : '${AppConstants.baseUrl}$url';

/// Opens a fullscreen, pinch-zoomable view of a user's profile picture.
/// Falls back to a large initial when there's no photo. Tap anywhere to close.
void showAvatarViewer(
  BuildContext context, {
  String? avatarUrl,
  required String username,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'avatar',
    barrierColor: Colors.black.withValues(alpha: 0.9),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) =>
        _AvatarViewer(avatarUrl: avatarUrl, username: username),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AvatarViewer extends StatelessWidget {
  final String? avatarUrl;
  final String username;
  const _AvatarViewer({this.avatarUrl, required this.username});

  @override
  Widget build(BuildContext context) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    final side = MediaQuery.of(context).size.width.clamp(0.0, 460.0) * 0.82;

    Widget fallback() => Container(
          color: AppColors.primary.withValues(alpha: 0.2),
          child: Center(
            child: Text(initial,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: side * 0.4,
                    fontWeight: FontWeight.bold)),
          ),
        );

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        blurRadius: 40),
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 24),
                  ],
                ),
                child: ClipOval(
                  child: hasUrl
                      ? InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: CachedNetworkImage(
                            imageUrl: _fullAvatarUrl(avatarUrl!),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => fallback(),
                            errorWidget: (_, __, ___) => fallback(),
                          ),
                        )
                      : fallback(),
                ),
              ),
            ),
            // Name
            Positioned(
              left: 0, right: 0, bottom: 70,
              child: Center(
                child: Text(username,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
              ),
            ),
            // Close
            Positioned(
              top: 44, right: 22,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
