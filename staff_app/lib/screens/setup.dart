import 'package:flutter/material.dart';

import '../main.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _server = TextEditingController(text: 'https://newvisionteam.ir');
  final _event = TextEditingController();
  final _pin = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = StoreScope.read(context);
    if (s.server != null && _server.text == 'https://newvisionteam.ir') _server.text = s.server!;
    if (s.eventCode != null && _event.text.isEmpty) _event.text = s.eventCode!;
    if (_label.text.isEmpty) _label.text = s.deviceLabel;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var server = _server.text.trim();
      if (!server.startsWith('http')) server = 'https://$server';
      await StoreScope.read(context).login(
        server: server,
        eventCode: _event.text,
        pin: _pin.text,
        label: _label.text,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ورود نیروی اجرایی')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (store.needsLogin)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'دسترسی این گوشی باطل شده یا منقضی است. دوباره وارد شوید.'
                    '${store.pending.isNotEmpty ? '\n${store.pending.length} کار ارسال‌نشده روی گوشی مانده و بعد از ورود ارسال می‌شود.' : ''}',
                  ),
                ),
              ),
            TextField(
              controller: _server,
              decoration: const InputDecoration(labelText: 'آدرس سایت'),
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _event,
              decoration: const InputDecoration(labelText: 'کد رویداد'),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              decoration: const InputDecoration(labelText: 'PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'نام این گوشی (مثلاً میز پذیرش ۱)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ورود و دریافت لیست', style: TextStyle(fontSize: 16)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            const Text(
              'بعد از ورود، کل لیست روی گوشی ذخیره می‌شود و اپ بدون اینترنت هم کار می‌کند.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
