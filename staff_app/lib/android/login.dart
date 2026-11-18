// ورود، دریافت لیست و «دسترسی باطل شد» (طرح ۱ تا ۳).
import 'package:flutter/material.dart';

import '../brand.dart';
import '../errors.dart';
import '../main.dart';
import '../normalize.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';

const _defaultServer = 'https://newvisionteam.ir';
const _deviceSuggestions = ['میز پذیرش ۱', 'میز پذیرش ۲', 'پذیرایی ۱', 'پذیرایی ۲'];

class NvLoginScreen extends StatefulWidget {
  /// ویندوز: «نام این رایانه».
  final bool desk;
  const NvLoginScreen({super.key, this.desk = false});

  @override
  State<NvLoginScreen> createState() => _NvLoginScreenState();
}

class _NvLoginScreenState extends State<NvLoginScreen> {
  final _server = TextEditingController(text: _defaultServer);
  final _event = TextEditingController();
  final _pin = TextEditingController();
  final _label = TextEditingController();
  final _pinFocus = FocusNode();
  final _labelFocus = FocusNode();
  bool _busy = false;
  bool _showPin = false;
  bool _advanced = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = StoreScope.read(context);
    if (s.server != null && _server.text == _defaultServer) _server.text = s.server!;
    if (s.eventCode != null && _event.text.isEmpty) _event.text = s.eventCode!;
    if (_label.text.isEmpty) _label.text = s.deviceLabel;
  }

  @override
  void dispose() {
    for (final c in [_server, _event, _pin, _label]) {
      c.dispose();
    }
    _pinFocus.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_event.text.trim().isEmpty || _pin.text.trim().isEmpty) {
      setState(() => _error = _event.text.trim().isEmpty ? 'کد رویداد را بنویسید.' : 'PIN را بنویسید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var server = _server.text.trim();
      if (!server.startsWith('http')) server = 'https://$server';
      await StoreScope.read(context).login(server: server, eventCode: _event.text, pin: _pin.text, label: _label.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, login: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return NvDownloadView(eventName: _event.text.trim(), onCancel: () => setState(() => _busy = false));
    final c = NvColors.of(context);
    final host = Uri.tryParse(_server.text)?.host ?? _server.text;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        NvHeader(
          bottom: 64,
          radius: 36,
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.event_available_rounded, size: 30, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(appName, style: nvText(context, 30, w: FontWeight.w800, color: Colors.white, height: 1.4)),
              const SizedBox(height: 4),
              Text('پذیرش و پذیرایی روز اجرا، حتی بدون اینترنت', style: nvText(context, 15, color: Colors.white.withValues(alpha: .9))),
            ]),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: NvCard(
              raised: true,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                NvField(
                  label: 'کد رویداد',
                  child: TextField(
                    controller: _event,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    style: nvText(context, 18, w: FontWeight.w600),
                    onSubmitted: (_) => _pinFocus.requestFocus(),
                  ),
                ),
                const SizedBox(height: 14),
                NvField(
                  label: 'PIN شخصی',
                  helper: 'PIN را از مدیر رویداد بگیرید.',
                  child: TextField(
                    controller: _pin,
                    focusNode: _pinFocus,
                    keyboardType: TextInputType.number,
                    obscureText: !_showPin,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: nvText(context, 18).copyWith(letterSpacing: _showPin ? 0 : 4),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _labelFocus.requestFocus(),
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        tooltip: _showPin ? 'پنهان کردن PIN' : 'نمایش PIN',
                        icon: Icon(_showPin ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: c.muted),
                        onPressed: () => setState(() => _showPin = !_showPin),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                NvField(
                  label: widget.desk ? 'نام این رایانه' : 'نام این گوشی',
                  child: TextField(
                    controller: _label,
                    focusNode: _labelFocus,
                    textInputAction: TextInputAction.done,
                    style: nvText(context, 16),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in _deviceSuggestions)
                    if (s != _label.text)
                      ActionChip(
                        label: Text(s, style: nvText(context, 12, w: FontWeight.w600)),
                        backgroundColor: c.chip,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        onPressed: () => setState(() => _label.text = s),
                      ),
                ]),
                if (_advanced) ...[
                  const SizedBox(height: 14),
                  NvField(
                    label: 'آدرس سایت',
                    child: TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  NvBanner(tone: NvTone.stop, text: _error!),
                ],
                const SizedBox(height: 16),
                NvButton(label: 'ورود و دریافت لیست', onPressed: _submit),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  Flexible(child: Text('بعد از ورود، اپ بدون اینترنت هم کار می‌کند', style: nvText(context, 13, color: c.muted))),
                ]),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
          child: Column(children: [
            TextButton.icon(
              onPressed: () => setState(() => _advanced = !_advanced),
              icon: Icon(Icons.settings_rounded, size: 16, color: c.muted),
              label: Text('آدرس سایت: $host · تنظیمات پیشرفته', style: nvText(context, 12, color: c.muted)),
            ),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'ساخته‌ی '),
                TextSpan(text: makerTeam, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                TextSpan(text: ' · نسخه‌ی ${faDigits(appVersion.split('.').take(2).join('٫'))}'),
              ]),
              textAlign: TextAlign.center,
              style: nvText(context, 12, color: c.muted),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// تمام‌صفحه‌ی برند هنگام دریافت لیست.
class NvDownloadView extends StatelessWidget {
  final String eventName;
  final VoidCallback? onCancel;
  const NvDownloadView({super.key, required this.eventName, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Scaffold(
      backgroundColor: c.brand,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Spacer(),
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), shape: BoxShape.circle),
              child: const Icon(Icons.cloud_download_rounded, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 28),
            Text('در حال دریافت لیست', style: nvText(context, 26, w: FontWeight.w800, color: Colors.white)),
            if (eventName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(eventName, textDirection: TextDirection.ltr, style: nvText(context, 16, color: Colors.white.withValues(alpha: .92))),
            ],
            const SizedBox(height: 28),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(minHeight: 10, color: Colors.white, backgroundColor: Colors.white.withValues(alpha: .22)),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(Nv.r16)),
              child: Text(
                'بعد از پایان، لیست روی همین گوشی می‌ماند و بدون اینترنت هم می‌توانید پذیرش و پذیرایی کنید. تا پایان دریافت، صفحه را باز نگه دارید.',
                style: nvText(context, 14, color: Colors.white, height: 1.6),
              ),
            ),
            const Spacer(),
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                child: Text('لغو و برگشت', style: nvText(context, 14, color: Colors.white).copyWith(decoration: TextDecoration.underline, decorationColor: Colors.white)),
              ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}

/// دسترسی گوشی باطل شده: فقط PIN دوباره؛ کارهای ارسال‌نشده نگه داشته می‌شوند.
class NvRevokedScreen extends StatefulWidget {
  const NvRevokedScreen({super.key});

  @override
  State<NvRevokedScreen> createState() => _NvRevokedScreenState();
}

class _NvRevokedScreenState extends State<NvRevokedScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = StoreScope.read(context);
    if (_pin.text.trim().isEmpty) {
      setState(() => _error = 'PIN را بنویسید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await s.login(server: s.server!, eventCode: s.eventCode ?? '', pin: _pin.text, label: s.deviceLabel);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, login: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final n = s.pending.length;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        NvHeader(
          bottom: 56,
          radius: 36,
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text('ورود دوباره', style: nvText(context, 28, w: FontWeight.w800, color: Colors.white)),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: NvCard(
              raised: true,
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const NvBanner(
                  tone: NvTone.stop,
                  icon: Icons.lock_rounded,
                  title: 'دسترسی این گوشی باطل شده است',
                  text: 'مدیر دسترسی را قطع کرده یا PIN عوض شده. با PIN خودتان دوباره وارد شوید.',
                ),
                if (n > 0) ...[
                  const SizedBox(height: 14),
                  NvBanner(
                    tone: NvTone.wait,
                    icon: Icons.cloud_upload_rounded,
                    title: '${faDigits(n)} کار ارسال‌نشده روی گوشی مانده',
                    text: 'از بین نرفته‌اند. بعد از ورود خودکار ارسال می‌شوند.',
                  ),
                ],
                const SizedBox(height: 14),
                NvField(
                  label: 'PIN شخصی',
                  error: _error,
                  child: TextField(
                    controller: _pin,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(hintText: 'PIN را بنویسید'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 14),
                NvButton(label: 'ورود', onPressed: _submit, busy: _busy),
                const SizedBox(height: 12),
                Text(
                  'مشکل از PIN نیست؟ با مدیر رویداد تماس بگیرید یا از پشتیبانی نگاه جدید ($makerWebsite) کمک بگیرید.',
                  textAlign: TextAlign.center,
                  style: nvText(context, 13, color: c.muted, height: 1.7),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text('${s.eventCode ?? ''} · ${s.deviceLabel}', textAlign: TextAlign.center, style: nvText(context, 12, color: c.muted)),
        ),
      ]),
    );
  }
}

/// رقم‌های فارسی برای نام‌ها (اگر لازم شد).
String fa(Object s) => faDigits(s);
