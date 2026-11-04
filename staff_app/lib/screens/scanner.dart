import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

/// صفحه‌ی تمام‌صفحه‌ی اسکن؛ با اولین QR معتبر، توکن کارت را برمی‌گرداند.
class ScannerPage extends StatefulWidget {
  final String title;
  const ScannerPage({super.key, this.title = 'اسکن کارت'});

  static Future<String?> scan(BuildContext context, {String title = 'اسکن کارت'}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ScannerPage(title: title)));

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final token = tokenFromScan(raw);
      if (token != null) {
        _done = true;
        Navigator.of(context).pop(token);
        return;
      }
      setState(() => _hint = 'این QR مال کارت کنفرانس نیست.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'چراغ‌قوه',
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      backgroundColor: DaftarColors.of(context).camera,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_hint != null)
            Positioned(
              left: DaftarSize.space4,
              right: DaftarSize.space4,
              bottom: DaftarSize.space6,
              child: Notice(tone: NoticeTone.wait, text: _hint!),
            ),
        ],
      ),
    );
  }
}
