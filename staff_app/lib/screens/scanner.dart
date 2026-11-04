import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../normalize.dart';

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
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_hint != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Card(
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_hint!, textAlign: TextAlign.center)),
              ),
            ),
        ],
      ),
    );
  }
}
