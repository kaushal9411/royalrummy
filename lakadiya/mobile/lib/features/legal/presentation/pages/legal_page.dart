import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_theme.dart';

class LegalPage extends StatefulWidget {
  final String title;
  /// Asset path e.g. 'assets/legal/privacy_policy.html'
  final String assetPath;

  const LegalPage({super.key, required this.title, required this.assetPath});

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late final WebViewController _ctrl;
  bool _loading = true;
  bool _error   = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled) // static HTML — no JS needed
      ..setBackgroundColor(const Color(0xFF060C1A))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
        onWebResourceError: (_) { if (mounted) setState(() { _loading = false; _error = true; }); },
      ));
    _loadAsset();
  }

  Future<void> _loadAsset() async {
    try {
      final html = await rootBundle.loadString(widget.assetPath);
      await _ctrl.loadHtmlString(html, baseUrl: 'about:blank');
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
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
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: Stack(
        children: [
          if (_error)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
                const SizedBox(height: 16),
                const Text('Failed to load document',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () { setState(() { _loading = true; _error = false; }); _loadAsset(); },
                  child: const Text('Retry'),
                ),
              ]),
            )
          else
            WebViewWidget(controller: _ctrl),
          if (_loading && !_error)
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ],
      ),
    );
  }
}
