import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class DataSafetyPage extends StatelessWidget {
  const DataSafetyPage({super.key});

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
        title: const Text('Data & Privacy',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _header(),
          const SizedBox(height: 24),
          _section('Data We Collect', [
            _DataRow(Icons.phone_android_rounded,   AppColors.primary,  'Phone Number',      'Required for login and OTP verification'),
            _DataRow(Icons.person_rounded,           AppColors.accent,   'Username & Email',  'Optional profile information'),
            _DataRow(Icons.cake_rounded,             AppColors.trump,    'Date of Birth',     'Required for 18+ age verification'),
            _DataRow(Icons.credit_card_rounded,      AppColors.primary,  'PAN Card & Selfie', 'Required for KYC before first withdrawal'),
            _DataRow(Icons.account_balance_wallet_rounded, AppColors.accent, 'Transaction History', 'Wallet top-ups, withdrawals, game bets'),
            _DataRow(Icons.notifications_rounded,   AppColors.primary,  'Device Token (FCM)', 'For push notifications (OTP, game alerts, wallet)'),
            _DataRow(Icons.sports_esports_rounded,  AppColors.accent,   'Game Statistics',   'Match history, scores, XP, win rate'),
            _DataRow(Icons.language_rounded,        AppColors.textMuted,'IP Address',        'Collected automatically with each API request'),
          ]),
          const SizedBox(height: 20),
          _section('How We Use It', [
            _BulletRow('Authenticate your account and deliver OTPs securely'),
            _BulletRow('Process payments and withdrawals via Razorpay'),
            _BulletRow('Verify your age (18+) and identity (KYC)'),
            _BulletRow('Detect fraud and prevent money laundering (PMLA compliance)'),
            _BulletRow('Improve app stability via Firebase Crashlytics (anonymous crash data only)'),
            _BulletRow('Send transactional push notifications'),
          ]),
          const SizedBox(height: 20),
          _section('Third-Party Services', [
            _DataRow(Icons.payment_rounded,         AppColors.primary,  'Razorpay',          'Handles payment processing. Your card/UPI details go directly to Razorpay.'),
            _DataRow(Icons.notifications_active_rounded, AppColors.accent, 'Google Firebase', 'Push notifications (FCM) and crash reporting (Crashlytics)'),
          ]),
          const SizedBox(height: 20),
          _section('Your Rights', [
            _BulletRow('Request a copy of your personal data — email privacy@lakadiya.in'),
            _BulletRow('Delete your account and non-legally-required data — contact support'),
            _BulletRow('Opt out of promotional notifications in Notification Settings'),
            _BulletRow('Financial transaction records are retained for 7 years as required by Indian law'),
          ]),
          const SizedBox(height: 20),
          _section('Security', [
            _BulletRow('All API communication is encrypted via TLS/HTTPS'),
            _BulletRow('Sensitive keys stored AES-256 encrypted in our database'),
            _BulletRow('Passwords are never stored — we use OTP-only login'),
            _BulletRow('Payment keys handled exclusively server-side'),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.darkCard,
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Text(
              'For questions about your data, contact us at privacy@lakadiya.in',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(colors: [
        AppColors.primary.withValues(alpha: 0.12), AppColors.primary.withValues(alpha: 0.04),
      ]),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
    ),
    child: const Row(children: [
      Text('🔒', style: TextStyle(fontSize: 32)),
      SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your Data is Protected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        SizedBox(height: 4),
        Text('We collect only what is necessary and protect it with industry-standard encryption.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
      ])),
    ]),
  );

  Widget _section(String title, List<Widget> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0E1A2E),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(children: items),
      ),
    ],
  );
}

class _DataRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _DataRow(this.icon, this.color, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
      ])),
    ]),
  );
}

class _BulletRow extends StatelessWidget {
  final String text;
  const _BulletRow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(top: 5),
        child: CircleAvatar(radius: 3, backgroundColor: AppColors.primary),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4))),
    ]),
  );
}
