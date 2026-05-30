import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class KycPage extends StatefulWidget {
  const KycPage({super.key});
  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  final _panCtl      = TextEditingController();
  final _nameCtl     = TextEditingController();
  File? _panDoc;
  File? _selfie;
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _panCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final res = await ApiService().get('/kyc/status');
      if (mounted) setState(() { _status = Map<String, dynamic>.from(res.data as Map); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(bool isPanDoc) async {
    try {
      final picked = await ImagePicker().pickImage(
        // PAN card: pick from gallery; selfie: must use live camera (identity verification)
        source: isPanDoc ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked == null) return;
      setState(() {
        if (isPanDoc) { _panDoc = File(picked.path); }
        else          { _selfie = File(picked.path); }
      });
    } catch (e) {
      if (mounted) {
        _snack(isPanDoc
            ? 'Cannot access gallery. Please allow photo access in device Settings.'
            : 'Cannot access camera. Please allow camera access in device Settings.');
      }
    }
  }

  Future<void> _submit() async {
    final pan  = _panCtl.text.trim().toUpperCase();
    final name = _nameCtl.text.trim();
    if (pan.length != 10) { _snack('Enter a valid 10-character PAN number'); return; }
    if (name.length < 3)  { _snack('Enter your full legal name'); return; }
    if (_panDoc == null)  { _snack('Please upload your PAN card photo'); return; }
    if (_selfie == null)  { _snack('Please take a selfie'); return; }

    setState(() => _submitting = true);
    try {
      final formData = FormData.fromMap({
        'pan_number': pan,
        'full_name':  name,
        'pan_doc':    await MultipartFile.fromFile(_panDoc!.path, filename: 'pan_doc.jpg'),
        'selfie':     await MultipartFile.fromFile(_selfie!.path, filename: 'selfie.jpg'),
      });
      await ApiService().dio.post('/kyc/submit', data: formData);
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC submitted for review'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) _snack('Submission failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
  );

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
        title: const Text('KYC Verification',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _status?['status'] == 'approved'
                  ? _buildApproved()
                  : _status?['status'] == 'pending'
                      ? _buildPending()
                      : _buildForm(),
            ),
    );
  }

  Widget _buildApproved() => Column(children: [
    const SizedBox(height: 40),
    const Center(child: Text('✅', style: TextStyle(fontSize: 64))),
    const SizedBox(height: 20),
    const Text('KYC Verified', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    const SizedBox(height: 10),
    const Text('Your identity has been verified. You can now withdraw funds without any restrictions.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
  ]);

  Widget _buildPending() => Column(children: [
    const SizedBox(height: 40),
    const Center(child: Text('⏳', style: TextStyle(fontSize: 64))),
    const SizedBox(height: 20),
    const Text('Under Review', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    const SizedBox(height: 10),
    Text(
      'Your KYC documents are being reviewed. This typically takes 24–48 hours.${_status?['admin_remark'] != null ? '\n\nRemark: ${_status!['admin_remark']}' : ''}',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
      textAlign: TextAlign.center,
    ),
  ]);

  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Info banner
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.accent.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
          SizedBox(width: 10),
          Expanded(child: Text(
            'KYC is required before your first withdrawal. Your documents are reviewed by our team within 24–48 hours.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
          )),
        ]),
      ),
      const SizedBox(height: 24),

      // PAN number
      _field('PAN Number', _panCtl, hint: 'e.g. ABCDE1234F', caps: true, maxLen: 10),
      const SizedBox(height: 14),
      _field('Full Legal Name', _nameCtl, hint: 'As on PAN card'),
      const SizedBox(height: 20),

      // PAN card upload
      _docUpload(
        label: 'PAN Card Photo',
        icon: Icons.credit_card_rounded,
        file: _panDoc,
        onTap: () => _pickImage(true),
      ),
      const SizedBox(height: 14),
      _docUpload(
        label: 'Selfie with PAN Card',
        icon: Icons.camera_alt_rounded,
        file: _selfie,
        onTap: () => _pickImage(false),
      ),
      const SizedBox(height: 28),

      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _submitting
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Submit KYC Documents',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    ],
  );

  Widget _field(String label, TextEditingController ctl, {String? hint, bool caps = false, int? maxLen}) =>
      TextField(
        controller: ctl,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
        maxLength: maxLen,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: TextStyle(color: AppColors.textMuted),
          filled: true,
          fillColor: const Color(0xFF0E1A2E),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.darkBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.darkBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        ),
      );

  Widget _docUpload({required String label, required IconData icon, required File? file, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF0E1A2E),
            border: Border.all(
              color: file != null ? AppColors.primary : AppColors.darkBorder,
              width: file != null ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (file != null ? AppColors.primary : AppColors.textMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: file != null ? AppColors.primary : AppColors.textMuted, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                file != null ? file.path.split('/').last : 'Tap to upload (JPG/PNG)',
                style: TextStyle(color: file != null ? AppColors.primary : AppColors.textMuted, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ])),
            if (file != null)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
            else
              const Icon(Icons.upload_rounded, color: AppColors.textMuted, size: 20),
          ]),
        ),
      );
}
