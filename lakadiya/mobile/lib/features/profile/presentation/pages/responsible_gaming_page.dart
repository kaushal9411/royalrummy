import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class ResponsibleGamingPage extends StatefulWidget {
  const ResponsibleGamingPage({super.key});
  @override
  State<ResponsibleGamingPage> createState() => _ResponsibleGamingPageState();
}

class _ResponsibleGamingPageState extends State<ResponsibleGamingPage> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _settings;

  final _dailyCtl   = TextEditingController();
  final _weeklyCtl  = TextEditingController();
  final _monthlyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dailyCtl.dispose();
    _weeklyCtl.dispose();
    _monthlyCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get('/responsible-gaming/settings');
      if (mounted) {
        final d = Map<String, dynamic>.from(res.data as Map);
        _dailyCtl.text   = d['daily_limit']?.toString()   ?? '';
        _weeklyCtl.text  = d['weekly_limit']?.toString()  ?? '';
        _monthlyCtl.text = d['monthly_limit']?.toString() ?? '';
        setState(() { _settings = d; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().put('/responsible-gaming/settings', data: {
        'daily_limit':   _dailyCtl.text.isEmpty   ? null : double.tryParse(_dailyCtl.text),
        'weekly_limit':  _weeklyCtl.text.isEmpty  ? null : double.tryParse(_weeklyCtl.text),
        'monthly_limit': _monthlyCtl.text.isEmpty ? null : double.tryParse(_monthlyCtl.text),
      });
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spending limits saved'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selfExclude(int days) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Self-Exclusion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'You will be locked out of all real-money games for $days day${days > 1 ? 's' : ''}. This cannot be undone before the period ends. Continue?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Self-Exclude', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().post('/responsible-gaming/self-exclude', data: {'days': days});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Self-excluded for $days days'), backgroundColor: AppColors.danger),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isExcluded = _settings?['self_excluded'] == true;
    final exclusionUntil = _settings?['exclusion_until'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFF060C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07101C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Responsible Gaming',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Banner
                  _infoBanner(),
                  const SizedBox(height: 24),

                  // Self-exclusion status
                  if (isExcluded) ...[
                    _excludedBanner(exclusionUntil),
                    const SizedBox(height: 20),
                  ],

                  // Spending limits
                  _sectionTitle('Spending Limits', Icons.bar_chart_rounded),
                  const SizedBox(height: 6),
                  const Text('Set the maximum amount you can bet per period. Leave blank to remove the limit.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 16),
                  _limitField('Daily Limit (₹)', _dailyCtl),
                  const SizedBox(height: 12),
                  _limitField('Weekly Limit (₹)', _weeklyCtl),
                  const SizedBox(height: 12),
                  _limitField('Monthly Limit (₹)', _monthlyCtl),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Limits', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Self-exclusion
                  if (!isExcluded) ...[
                    _sectionTitle('Self-Exclusion', Icons.block_rounded),
                    const SizedBox(height: 6),
                    const Text('Temporarily lock yourself out of all real-money game rooms.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(children: [
                      _excludeBtn('1 Day', 1),
                      const SizedBox(width: 10),
                      _excludeBtn('7 Days', 7),
                      const SizedBox(width: 10),
                      _excludeBtn('30 Days', 30),
                    ]),
                    const SizedBox(height: 10),
                    _excludeBtn('180 Days', 180, full: true),
                  ],

                  const SizedBox(height: 32),

                  // Help resource
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF0E1A2E),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Need Help?',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      const Text(
                        'If gambling is affecting your life, reach out for support:',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      const Text('iCare Helpline: 1800-599-0019',
                          style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoBanner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(colors: [
        AppColors.primary.withValues(alpha: 0.12), AppColors.primary.withValues(alpha: 0.04),
      ]),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      const Text('🛡️', style: TextStyle(fontSize: 28)),
      const SizedBox(width: 14),
      const Expanded(child: Text(
        'We support responsible gaming. Use these tools to keep your gaming fun and within your means.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
      )),
    ]),
  );

  Widget _excludedBanner(String? until) {
    String label = 'You are currently self-excluded from real-money games.';
    if (until != null) {
      try {
        final dt = DateTime.parse(until).toLocal();
        label += '\nActive until: ${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.danger.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.block_rounded, color: AppColors.danger, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.5))),
      ]),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: AppColors.primary, size: 15),
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
  ]);

  Widget _limitField(String label, TextEditingController ctl) => TextField(
    controller: ctl,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: const TextStyle(color: Colors.white, fontSize: 16),
    decoration: InputDecoration(
      labelText: label,
      prefixText: '₹  ',
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: const Color(0xFF0E1A2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
  );

  Widget _excludeBtn(String label, int days, {bool full = false}) {
    final btn = OutlinedButton(
      onPressed: () => _selfExclude(days),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: const BorderSide(color: AppColors.danger),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
    return full ? SizedBox(width: double.infinity, height: 44, child: btn) : Expanded(child: btn);
  }
}
