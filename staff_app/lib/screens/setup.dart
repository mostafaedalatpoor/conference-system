import 'package:flutter/material.dart';

import '../errors.dart';
import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

const _defaultServer = 'https://newvisionteam.ir';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _server = TextEditingController(text: _defaultServer);
  final _event = TextEditingController();
  final _pin = TextEditingController();
  final _label = TextEditingController();
  final _pinFocus = FocusNode();
  final _labelFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _event, _pin, _label]) {
      c.dispose();
    }
    _pinFocus.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = StoreScope.read(context);
    if (s.server != null && _server.text == _defaultServer) _server.text = s.server!;
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
      if (mounted) setState(() => _error = friendlyError(e, login: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    const gap = SizedBox(height: DaftarSize.space4);
    const suggestions = ['پذیرش ۱', 'پذیرش ۲', 'پذیرایی ۱', 'پذیرایی ۲'];

    return Scaffold(
      appBar: AppBar(title: const Text('ورود نیروی اجرایی')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DaftarSize.space4),
          children: [
            if (store.needsLogin) ...[
              Notice(
                tone: NoticeTone.stop,
                title: 'دسترسی این گوشی باطل شده',
                text: 'دوباره وارد شوید.'
                    '${store.pending.isNotEmpty ? ' ${faDigits(store.pending.length)} کار ارسال‌نشده روی گوشی مانده و بعد از ورود ارسال می‌شود.' : ''}',
              ),
              gap,
            ],
            DaftarField(
              label: 'کد رویداد',
              child: TextField(
                controller: _event,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _pinFocus.requestFocus(),
              ),
            ),
            gap,
            DaftarField(
              label: 'PIN',
              helper: 'PIN را از مدیر رویداد بگیرید.',
              child: TextField(
                controller: _pin,
                focusNode: _pinFocus,
                keyboardType: TextInputType.number,
                obscureText: true,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _labelFocus.requestFocus(),
              ),
            ),
            gap,
            DaftarField(
              label: 'نام این گوشی',
              child: TextField(
                controller: _label,
                focusNode: _labelFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
            ),
            const SizedBox(height: DaftarSize.space2),
            Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
              for (final s in suggestions)
                ChoiceChip(
                  label: Text(s),
                  selected: _label.text == s,
                  onSelected: (_) => setState(() => _label.text = s),
                ),
            ]),
            const SizedBox(height: DaftarSize.space2),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: DaftarSize.space3),
                title: Text('تنظیمات پیشرفته', style: theme.textTheme.labelLarge?.copyWith(color: x.inkMuted)),
                initiallyExpanded: _server.text != _defaultServer,
                children: [
                  DaftarField(
                    label: 'آدرس سایت',
                    child: TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              Notice(tone: NoticeTone.stop, text: _error!),
              gap,
            ],
            FilledButton(
              style: daftarWideStyle(context, xl: true),
              onPressed: _busy ? null : _submit,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_busy) ...[
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: x.inkMuted),
                  ),
                  const SizedBox(width: DaftarSize.space3),
                ],
                Text(_busy ? 'در حال دریافت لیست…' : 'ورود و دریافت لیست'),
              ]),
            ),
            gap,
            const Notice(
              tone: NoticeTone.info,
              text: 'بعد از ورود، کل لیست روی گوشی ذخیره می‌شود و اپ بدون اینترنت هم کار می‌کند.',
            ),
          ],
        ),
      ),
    );
  }
}
