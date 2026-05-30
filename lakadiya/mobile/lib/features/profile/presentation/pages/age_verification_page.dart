import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Shown on first launch if the user has no date of birth set.
/// Blocks navigation until DOB is confirmed and the user is 18+.
class AgeVerificationPage extends StatefulWidget {
  const AgeVerificationPage({super.key});

  @override
  State<AgeVerificationPage> createState() => _AgeVerificationPageState();
}

class _AgeVerificationPageState extends State<AgeVerificationPage> {
  DateTime? _dob;
  bool _saving = false;
  String? _error;

  int get _age {
    if (_dob == null) return 0;
    final now = DateTime.now();
    int age = now.year - _dob!.year;
    if (now.month < _dob!.month ||
        (now.month == _dob!.month && now.day < _dob!.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1924),
      lastDate: DateTime.now().subtract(const Duration(days: 1)),
      helpText: 'Select your date of birth',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: Color(0xFF0E1A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() { _dob = picked; _error = null; });
  }

  Future<void> _confirm() async {
    if (_dob == null) { setState(() => _error = 'Please select your date of birth'); return; }
    if (_age < 18) {
      setState(() => _error = 'You must be 18 or older to use Lakadiya.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService().patch('/users/me', data: {
        'date_of_birth': _dob!.toIso8601String().split('T').first,
      });
      if (mounted) context.go('/lobby');
    } catch (e) {
      setState(() { _saving = false; _error = 'Failed to save. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dob == null
        ? 'Select Date of Birth'
        : '${_dob!.day.toString().padLeft(2, '0')} / ${_dob!.month.toString().padLeft(2, '0')} / ${_dob!.year}';

    return Scaffold(
      backgroundColor: const Color(0xFF060C1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Icon
              Center(
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: const Center(child: Text('🔞', style: TextStyle(fontSize: 36))),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Age Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                'Lakadiya is a real-money card game platform restricted to players 18 years or older. Please confirm your date of birth to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 36),

              // DOB picker
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF0E1A2E),
                    border: Border.all(
                      color: _dob != null
                          ? (_age >= 18 ? AppColors.primary : AppColors.danger)
                          : AppColors.darkBorder,
                      width: 1.5,
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        color: _dob == null ? AppColors.textMuted : AppColors.primary, size: 20),
                    const SizedBox(width: 14),
                    Text(dateLabel,
                        style: TextStyle(
                          color: _dob == null ? AppColors.textMuted : Colors.white,
                          fontSize: 16,
                          fontWeight: _dob != null ? FontWeight.bold : FontWeight.normal,
                        )),
                    const Spacer(),
                    if (_dob != null)
                      Text('Age: $_age',
                          style: TextStyle(
                            color: _age >= 18 ? AppColors.primary : AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          )),
                  ]),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                  ]),
                ),
              ],

              const SizedBox(height: 28),

              // Confirm button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: (_saving || (_dob != null && _age < 18)) ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.textMuted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Confirm & Continue',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),

              // Responsible gaming note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF0E1A2E),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: const Text(
                  'This platform involves real money. Please play responsibly. We support responsible gaming — set limits anytime from Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
