import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _kyc;
  Map<String, dynamic>? _rg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().get('/users/me'),
        ApiService().get('/kyc/status').catchError((_) => throw 'kyc'),
        ApiService().get('/responsible-gaming/settings').catchError((_) => throw 'rg'),
      ]);
      if (mounted) {
        setState(() {
          _profile = Map<String, dynamic>.from(results[0].data as Map);
          try {
            _kyc = Map<String, dynamic>.from(results[1].data as Map);
          } catch (_) {}
          try {
            _rg = Map<String, dynamic>.from(results[2].data as Map);
          } catch (_) {}
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Computed helpers ──────────────────────────────────────────────────────

  int? get _age {
    final dob = _profile?['date_of_birth'] as String?;
    if (dob == null) return null;
    try {
      final birth = DateTime.parse(dob);
      final now   = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) age--;
      return age;
    } catch (_) { return null; }
  }

  bool get _isMinor => _profile?['is_minor'] == true || (_age != null && _age! < 18);
  bool get _ageSet   => _profile?['date_of_birth'] != null;
  String get _kycStatus {
    final s = _kyc?['status'] as String?;
    if (s == null || s == 'not_submitted') return 'not_submitted';
    return s;
  }

  bool get _selfExcluded => _rg?['self_excluded'] == true;
  bool get _hasLimits =>
      _rg?['daily_limit'] != null ||
      _rg?['weekly_limit'] != null ||
      _rg?['monthly_limit'] != null;

  bool get _notifGame   => StorageService.getBool('notif_game',   defaultValue: true);
  bool get _notifWallet => StorageService.getBool('notif_wallet', defaultValue: true);
  bool get _notifPromo  => StorageService.getBool('notif_promo',  defaultValue: true);

  // ── Build ─────────────────────────────────────────────────────────────────

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
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.darkCard,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Minor warning ──────────────────────────────────────
                  if (_isMinor) ...[
                    _minorWarningBanner(),
                    const SizedBox(height: 16),
                  ],

                  // ── Account & Compliance ───────────────────────────────
                  _sectionLabel('Account & Compliance'),
                  _tile(
                    icon: Icons.cake_rounded,
                    color: AppColors.trump,
                    title: 'Age Verification',
                    subtitle: _ageSet
                        ? (_isMinor ? 'Under 18 — Gambling restricted' : 'Verified — $_age years old')
                        : 'Not completed — tap to verify',
                    badge: _ageSet
                        ? (_isMinor ? _badge('Under 18', AppColors.danger) : _badge('✓ Verified', AppColors.primary))
                        : _badge('Required', AppColors.trump),
                    onTap: () => context.push('/age-verification').then((_) => _load()),
                  ),
                  _tile(
                    icon: Icons.verified_user_rounded,
                    color: AppColors.primary,
                    title: 'KYC Verification',
                    subtitle: _kycSubtitle(),
                    badge: _kycBadge(),
                    onTap: () => context.push('/kyc').then((_) => _load()),
                  ),

                  const SizedBox(height: 20),

                  // ── Responsible Gaming ─────────────────────────────────
                  _sectionLabel('Responsible Gaming'),
                  _tile(
                    icon: Icons.bar_chart_rounded,
                    color: AppColors.accent,
                    title: 'Spending Limits & Self-Exclusion',
                    subtitle: _selfExcluded
                        ? 'Self-excluded — tap to manage'
                        : _hasLimits
                            ? 'Limits active — tap to edit'
                            : 'No limits set — tap to configure',
                    badge: _selfExcluded
                        ? _badge('Excluded', AppColors.danger)
                        : _hasLimits
                            ? _badge('Limits On', AppColors.primary)
                            : null,
                    onTap: () => context.push('/responsible-gaming').then((_) => _load()),
                  ),

                  const SizedBox(height: 20),

                  // ── Notifications ──────────────────────────────────────
                  _sectionLabel('Notifications'),
                  _tile(
                    icon: Icons.notifications_rounded,
                    color: const Color(0xFFFFD700),
                    title: 'Notification Preferences',
                    subtitle: _notifPrefsSubtitle(),
                    onTap: () => context.push('/notification-settings').then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 20),

                  // ── Privacy & Legal ────────────────────────────────────
                  _sectionLabel('Privacy & Legal'),
                  _tile(
                    icon: Icons.privacy_tip_rounded,
                    color: AppColors.primary,
                    title: 'Privacy Policy',
                    subtitle: 'How we collect and protect your data',
                    onTap: () => context.push('/privacy-policy'),
                  ),
                  _tile(
                    icon: Icons.gavel_rounded,
                    color: AppColors.accent,
                    title: 'Terms of Service',
                    subtitle: '18+ real-money gaming rules and conditions',
                    onTap: () => context.push('/terms'),
                  ),
                  _tile(
                    icon: Icons.security_rounded,
                    color: AppColors.primary,
                    title: 'Data & Privacy',
                    subtitle: 'What data we collect and your rights',
                    onTap: () => context.push('/data-safety'),
                  ),

                  const SizedBox(height: 24),

                  // ── 18+ badge ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.danger.withValues(alpha: 0.08),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: const Row(children: [
                      Text('🔞', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('18+ Platform',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 3),
                        Text('Lakadiya is strictly for adults 18 years and older. Play responsibly.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _minorWarningBanner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: AppColors.danger.withValues(alpha: 0.12),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.5), width: 1.5),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('⚠️', style: TextStyle(fontSize: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Real-Money Gaming Restricted',
            style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          'Your age (${_age ?? '?'}y) is below 18. Real-money game rooms and wallet transactions are blocked until you turn 18.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
        ),
      ])),
    ]),
  );

  String _kycSubtitle() {
    switch (_kycStatus) {
      case 'approved':     return 'Verified — withdrawals enabled';
      case 'pending':      return 'Under review — usually 24–48 hours';
      case 'rejected':     return 'Rejected — ${_kyc?['admin_remark'] ?? 'tap to resubmit'}';
      case 'not_submitted': return 'Not submitted — required before first withdrawal';
      default:             return 'Tap to check status';
    }
  }

  Widget _kycBadge() {
    switch (_kycStatus) {
      case 'approved':      return _badge('✓ Verified', AppColors.primary);
      case 'pending':       return _badge('⏳ Pending', AppColors.trump);
      case 'rejected':      return _badge('✕ Rejected', AppColors.danger);
      case 'not_submitted': return _badge('Required', AppColors.textMuted);
      default:              return const SizedBox.shrink();
    }
  }

  String _notifPrefsSubtitle() {
    final offCount = [!_notifGame, !_notifWallet, !_notifPromo].where((v) => v).length;
    if (offCount == 0) return 'All notifications on';
    return '$offCount channel${offCount > 1 ? 's' : ''} disabled';
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label,
        style: const TextStyle(
            color: AppColors.textMuted, fontSize: 11,
            fontWeight: FontWeight.w600, letterSpacing: 0.8)),
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? badge,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
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
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ])),
            if (badge != null) ...[
              const SizedBox(width: 8),
              badge,
            ],
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 13),
          ]),
        ),
      );
}
