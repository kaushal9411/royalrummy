import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_theme.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  static const _kGameKey   = 'notif_game';
  static const _kWalletKey = 'notif_wallet';
  static const _kPromoKey  = 'notif_promo';

  bool _loading = true;
  bool _saving  = false;

  bool _game   = true;
  bool _wallet = true;
  bool _promo  = true;

  @override
  void initState() {
    super.initState();
    // Show cached values immediately while we load from backend
    _game   = StorageService.getBool(_kGameKey,   defaultValue: true);
    _wallet = StorageService.getBool(_kWalletKey, defaultValue: true);
    _promo  = StorageService.getBool(_kPromoKey,  defaultValue: true);
    _loadFromBackend();
  }

  Future<void> _loadFromBackend() async {
    try {
      final res = await ApiService().get('/notifications/preferences');
      final data = Map<String, dynamic>.from(res.data as Map);
      if (mounted) {
        setState(() {
          _game   = data['game']   as bool? ?? true;
          _wallet = data['wallet'] as bool? ?? true;
          _promo  = data['promo']  as bool? ?? true;
          _loading = false;
        });
        // Keep local cache in sync
        await StorageService.setBool(_kGameKey,   _game);
        await StorageService.setBool(_kWalletKey, _wallet);
        await StorageService.setBool(_kPromoKey,  _promo);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    // Optimistic local update
    setState(() {
      if (key == _kGameKey)   _game   = value;
      if (key == _kWalletKey) _wallet = value;
      if (key == _kPromoKey)  _promo  = value;
    });
    await StorageService.setBool(key, value);

    // Sync to backend
    setState(() => _saving = true);
    try {
      await ApiService().patch('/notifications/preferences', data: {
        'game':   _game,
        'wallet': _wallet,
        'promo':  _promo,
      });
    } catch (_) {
      // Revert on failure
      if (mounted) {
        final reverted = StorageService.getBool(key, defaultValue: true);
        setState(() {
          if (key == _kGameKey)   _game   = reverted;
          if (key == _kWalletKey) _wallet = reverted;
          if (key == _kPromoKey)  _promo  = reverted;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please try again'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07101C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notification Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _infoNote(
                  'Changes sync to the server instantly. '
                  'Transactional notifications (OTP, security alerts) are required and cannot be disabled.',
                ),
                const SizedBox(height: 16),
                _tile(
                  icon: Icons.lock_rounded,
                  iconColor: AppColors.primary,
                  title: 'OTP & Security',
                  subtitle: 'One-time passwords and login alerts',
                  value: true,
                  locked: true,
                  onChanged: (_) {},
                ),
                _tile(
                  icon: Icons.sports_esports_rounded,
                  iconColor: AppColors.accent,
                  title: 'Game Room Alerts',
                  subtitle: 'New bet rooms, game invites, match results',
                  value: _game,
                  onChanged: (v) => _toggle(_kGameKey, v),
                ),
                _tile(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: AppColors.primary,
                  title: 'Wallet & Payments',
                  subtitle: 'Deposits, withdrawals, payment confirmations',
                  value: _wallet,
                  onChanged: (v) => _toggle(_kWalletKey, v),
                ),
                _tile(
                  icon: Icons.campaign_rounded,
                  iconColor: const Color(0xFFFFD700),
                  title: 'Promotions & Offers',
                  subtitle: 'Bonus offers, seasonal events, announcements',
                  value: _promo,
                  onChanged: (v) => _toggle(_kPromoKey, v),
                ),
                const SizedBox(height: 16),
                _infoNote(
                  'To fully disable push notifications, use your device\'s system notification settings for Lakadiya.',
                ),
              ],
            ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    bool locked = false,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0E1A2E),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            Text(subtitle,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ])),
          const SizedBox(width: 12),
          if (locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Required',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
            )
          else
            Switch(
              value: value,
              onChanged: _saving ? null : onChanged,
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
            ),
        ]),
      );

  Widget _infoNote(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: AppColors.darkCard,
      border: Border.all(color: AppColors.darkBorder),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5))),
    ]),
  );
}
