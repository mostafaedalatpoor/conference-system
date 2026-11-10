// اپ مدیریت روی اندروید با ظاهر تازه: قفل، اتصال در سه قدم، و پوسته‌ی چهار تب
// (امروز، افراد، گوشی‌ها، رویداد). ویندوز همان «دفتر» را دارد.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

import '../brand.dart';
import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import 'event_tab.dart';
import 'jalali.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'people_tab.dart';
import 'phones_tab.dart';
import 'today_tab.dart';

/// ریشه: قفل → اتصال (اگر رویدادی انتخاب نشده) → پوسته.
class NvAdminRoot extends StatelessWidget {
  const NvAdminRoot({super.key});

  @override
  Widget build(BuildContext context) => const NvAppLock(child: _AfterLock());
}

class _AfterLock extends StatelessWidget {
  const _AfterLock();

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    if (s.event == null) return const NvConnectFlow();
    return const NvAdminShell();
  }
}

// ---------------------------------------------------------------- قفل

/// قفل با اثر انگشت یا رمز گوشی، هنگام باز شدن و بعد از ۵ دقیقه در پس‌زمینه.
/// کلید مدیریت روی گوشی ذخیره است؛ گوشی گم‌شده نباید یعنی دسترسی کامل مدیریت.
class NvAppLock extends StatefulWidget {
  final Widget child;
  const NvAppLock({super.key, required this.child});

  @override
  State<NvAppLock> createState() => _NvAppLockState();
}

class _NvAppLockState extends State<NvAppLock> with WidgetsBindingObserver {
  LocalAuthPlatform get _auth => LocalAuthPlatform.instance;
  bool _locked = !_isTest && (Platform.isAndroid || Platform.isIOS);
  bool _busy = false;
  bool _unsupported = false;
  bool _warnClosed = false;
  DateTime? _pausedAt;

  static bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock(biometricOnly: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null && !_busy) {
      if (DateTime.now().difference(_pausedAt!).inMinutes >= 5) {
        setState(() => _locked = true);
        _unlock(biometricOnly: true);
      }
      _pausedAt = null;
    }
  }

  Future<void> _unlock({bool biometricOnly = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _auth.isDeviceSupported()) {
        // گوشی قفل صفحه ندارد: اپ باز می‌شود ولی هشدار می‌دهد.
        setState(() {
          _unsupported = true;
          _locked = false;
        });
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'برای باز کردن $appName، هویت خود را تأیید کنید.',
        authMessages: const [],
        options: AuthenticationOptions(biometricOnly: biometricOnly, stickyAuth: true),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // اثر انگشت ثبت نشده یا خطای سیستم: با رمز گوشی امتحان می‌شود؛ اگر باز هم نشد، باز می‌ماند با هشدار.
      if (biometricOnly && mounted) {
        setState(() => _busy = false);
        return _unlock();
      }
      if (mounted) {
        setState(() {
          _unsupported = true;
          _locked = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    final warn = _unsupported && !_warnClosed
        ? NvBanner(
            tone: NvTone.wait,
            icon: Icons.warning_rounded,
            title: 'قفل صفحه‌ی گوشی روشن نیست',
            text: 'این اپ اطلاعات شرکت‌کننده‌ها را دارد. در تنظیمات گوشی اثر انگشت یا رمز بگذارید.',
            action: TextButton(onPressed: () => setState(() => _warnClosed = true), child: const Text('فهمیدم')),
          )
        : null;
    if (!_locked) {
      if (warn == null) return widget.child;
      return Column(children: [
        Material(
          color: c.bg,
          child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: warn)),
        ),
        Expanded(child: widget.child),
      ]);
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(28), boxShadow: Nv.raised(c)),
              child: const Icon(Icons.event_available_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 22),
            Text(appName, style: nvText(context, 26, w: FontWeight.w800)),
            if (s.event != null) ...[
              const SizedBox(height: 6),
              Text(s.event!.name, textAlign: TextAlign.center, style: nvText(context, 14, color: c.muted)),
            ],
            const SizedBox(height: 22),
            NvButton(label: 'باز کردن با اثر انگشت', icon: Icons.fingerprint_rounded, busy: _busy, onPressed: _busy ? null : () => _unlock(biometricOnly: true)),
            const SizedBox(height: 6),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => _unlock(),
              child: Text('با رمز گوشی باز کن', style: nvText(context, 14, w: FontWeight.w700, color: c.brandText)),
            ),
            const Spacer(),
            Text('$makerFull · نسخه‌ی ${faDigits(appVersion)}', style: nvText(context, 11, color: c.muted)),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- اتصال

/// سربرگ صفحه‌های اتصال: برگشت، عنوان و نوار «قدم n از ۳».
class _StepHeader extends StatelessWidget {
  final String title;
  final int step;
  final VoidCallback? onBack;
  const _StepHeader({required this.title, required this.step, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvHeader(
      radius: 28,
      bottom: 52,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (onBack != null) ...[NvRoundIcon(icon: Icons.arrow_forward_rounded, label: 'بازگشت', onTap: onBack), const SizedBox(width: 10)],
          Text(title, style: nvText(context, 20, w: FontWeight.w800, color: c.onBrand)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 1; i <= 3; i++) ...[
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i <= step ? Colors.white : Colors.white.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text('قدم ${faDigits(step)} از ۳', style: nvText(context, 12, w: FontWeight.w700, color: c.onBrand)),
        ]),
      ]),
    );
  }
}

/// کارت سفید شناور روی سربرگ.
class _FloatCard extends StatelessWidget {
  final List<Widget> children;
  const _FloatCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Transform.translate(
      offset: const Offset(0, -26),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r24), boxShadow: Nv.raised(c)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

class NvConnectFlow extends StatefulWidget {
  const NvConnectFlow({super.key});

  @override
  State<NvConnectFlow> createState() => _NvConnectFlowState();
}

class _NvConnectFlowState extends State<NvConnectFlow> {
  final _site = TextEditingController();
  final _key = TextEditingController();
  int _step = 1;
  bool _busy = false;
  bool _showKey = false;
  String? _siteError, _keyError;
  bool _newEvent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = StateScope.read(context);
    if (_site.text.isEmpty) _site.text = s.server.replaceFirst(RegExp(r'^https?://'), '');
    if (_key.text.isEmpty) _key.text = s.apiKey;
    // کلید از قبل هست ولی رویدادی انتخاب نشده: مستقیم قدم سوم.
    if (s.apiKey.isNotEmpty && s.events.isNotEmpty && _step == 1) _step = 3;
  }

  @override
  void dispose() {
    _site.dispose();
    _key.dispose();
    super.dispose();
  }

  String get _server {
    final t = latinDigits(_site.text.trim()).replaceAll(RegExp(r'/+$'), '');
    return t.startsWith('http') ? t : 'https://$t';
  }

  Future<void> _checkSite() async {
    if (_site.text.trim().isEmpty) return setState(() => _siteError = 'آدرس سایت را بنویسید.');
    setState(() {
      _busy = true;
      _siteError = null;
    });
    try {
      final r = await http.get(Uri.parse('$_server/wp-json/conf/v1/admin/ping')).timeout(const Duration(seconds: 20));
      // بدون کلید ۴۰۱ برمی‌گردد؛ یعنی افزونه روی سایت هست.
      if (r.statusCode == 401 || r.statusCode == 200) {
        setState(() => _step = 2);
      } else {
        setState(() => _siteError = 'رویدادیار روی این سایت پیدا نشد (کد ${faDigits(r.statusCode)}). افزونه نصب و فعال است؟');
      }
    } catch (_) {
      setState(() => _siteError = 'به این سایت نرسیدیم. آدرس یا اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final s = StateScope.read(context);
    if (_key.text.trim().isEmpty) return setState(() => _keyError = 'کلید مدیریت را بنویسید.');
    setState(() {
      _busy = true;
      _keyError = null;
    });
    await s.connect(_server, _key.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (s.messageIsError) {
      setState(() => _keyError = s.message?.contains('کلید') == true ? 'کلید درست نیست. از پیشخوان وردپرس دوباره کپی کنید.' : s.message);
      s.message = null;
      s.notify();
      return;
    }
    s.message = null;
    setState(() => _step = 3);
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    if (_step == 3 && _newEvent) return _NewEvent(onBack: () => setState(() => _newEvent = false));

    final Widget card;
    final Widget bottom;
    if (_step == 1) {
      card = _FloatCard(children: [
        NvField(
          label: 'آدرس سایت',
          error: _siteError,
          helper: 'همان سایتی که افزونه‌ی رویدادیار روی آن نصب است.',
          child: TextField(
            controller: _site,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(hintText: 'example.ir'),
            onSubmitted: (_) => _checkSite(),
          ),
        ),
      ]);
      bottom = NvButton(label: 'ادامه', busy: _busy, onPressed: _busy ? null : _checkSite);
    } else if (_step == 2) {
      card = _FloatCard(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: c.goSoft, borderRadius: BorderRadius.circular(Nv.r14)),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, size: 20, color: c.go),
            const SizedBox(width: 8),
            const Text('سایت پیدا شد: '),
            Flexible(child: Text(Uri.parse(_server).host, textDirection: TextDirection.ltr, style: nvText(context, 14, w: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 14),
        NvField(
          label: 'کلید مدیریت',
          error: _keyError,
          child: TextField(
            controller: _key,
            obscureText: !_showKey,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                tooltip: _showKey ? 'پنهان کن' : 'نشان بده',
                icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onSubmitted: (_) => _connect(),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('کلید را از کجا بگیرم؟', style: nvText(context, 14, w: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final l in const ['۱. وارد پیشخوان وردپرس سایت شوید.', '۲. منوی «رویدادیار» ← «تنظیمات».', '۳. «ساخت کلید» را بزنید و کپی کنید.'])
              Text(l, style: nvText(context, 13, height: 1.7)),
            Text('کلید فقط یک بار نشان داده می‌شود؛ اگر گم شد، کلید تازه بسازید.', style: nvText(context, 13, color: c.muted, height: 1.7)),
          ]),
        ),
      ]);
      bottom = NvButton(label: 'اتصال', busy: _busy, onPressed: _busy ? null : _connect);
    } else {
      card = _FloatCard(children: [
        Text('کدام رویداد؟', style: nvText(context, 16, w: FontWeight.w800)),
        const SizedBox(height: 10),
        if (s.events.isEmpty) Text('هنوز رویدادی روی این سایت نیست.', style: nvText(context, 14, color: c.muted)),
        for (final e in s.events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: c.field,
              borderRadius: BorderRadius.circular(Nv.r16),
              child: InkWell(
                borderRadius: BorderRadius.circular(Nv.r16),
                onTap: s.busy ? null : () => s.selectEvent(e.code),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.event_rounded, color: c.brandText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.name, style: nvText(context, 15, w: FontWeight.w700)),
                        Text([e.code, if (e.startDate != null) jalaliLabel(e.startDate!)].join(' · '), style: nvText(context, 12, color: c.muted)),
                      ]),
                    ),
                    Icon(Icons.chevron_left_rounded, color: c.muted),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        NvSoftButton(label: 'رویداد تازه', icon: Icons.add_rounded, onPressed: () => setState(() => _newEvent = true)),
      ]);
      bottom = const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        _StepHeader(
          title: _step == 1 ? 'اتصال به سایت' : (_step == 2 ? 'کلید مدیریت' : 'انتخاب رویداد'),
          step: _step,
          onBack: _step == 1 ? null : () => setState(() => _step--),
        ),
        Expanded(child: ListView(padding: EdgeInsets.zero, children: [card])),
        if (s.busy && _step == 3) const LinearProgressIndicator(),
        Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom), child: bottom),
      ]),
    );
  }
}

class _NewEvent extends StatefulWidget {
  final VoidCallback onBack;
  const _NewEvent({required this.onBack});

  @override
  State<_NewEvent> createState() => _NewEventState();
}

class _NewEventState extends State<_NewEvent> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  DateTime? _start, _end;
  bool _editCode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final (jy, _, _) = toJalali(now.year, now.month, now.day);
    _code.text = 'conf$jy';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = StateScope.read(context);
    final code = latinDigits(_code.text.trim()).toLowerCase();
    if (_name.text.trim().isEmpty) return setState(() => _error = 'نام رویداد را بنویسید.');
    if (_start == null) return setState(() => _error = 'روز شروع را در تقویم بزنید.');
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,40}$').hasMatch(code)) {
      return setState(() => _error = 'کد رویداد فقط حروف کوچک انگلیسی، رقم و خط تیره.');
    }
    if (s.events.any((e) => e.code == code)) return setState(() => _error = 'رویدادی با این کد هست؛ کد دیگری بنویسید.');
    setState(() => _error = null);
    await s.saveEvent(code: code, name: _name.text.trim(), startDate: isoDate(_start!), endDate: isoDate(_end ?? _start!), baseUrl: '');
    if (mounted && s.messageIsError) setState(() => _error = s.message);
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        _StepHeader(title: 'رویداد تازه', step: 3, onBack: widget.onBack),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            _FloatCard(children: [
              NvField(label: 'نام رویداد', child: TextField(controller: _name, decoration: const InputDecoration(hintText: 'مثلاً همایش ملی انرژی ۱۴۰۵'))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: JalaliDateBox(label: 'شروع', date: _start, active: _start == null || _end != null, onTap: () => setState(() => _end = null))),
                const SizedBox(width: 10),
                Expanded(child: JalaliDateBox(label: 'پایان', date: _end, active: _start != null && _end == null, onTap: () {})),
              ]),
              const SizedBox(height: 10),
              JalaliRangeCalendar(start: _start, end: _end, onChanged: (a, b) => setState(() {
                    _start = a;
                    _end = b;
                  })),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text('کد رویداد', style: nvText(context, 14, w: FontWeight.w700))),
                Text('خودکار؛ قابل ویرایش', style: nvText(context, 12, color: c.muted)),
              ]),
              const SizedBox(height: 6),
              TextField(
                controller: _code,
                readOnly: !_editCode,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: nvText(context, 15, w: FontWeight.w700),
                decoration: InputDecoration(
                  helperText: 'نیروها با این کد وارد می‌شوند.',
                  suffixIcon: IconButton(tooltip: 'ویرایش کد', icon: const Icon(Icons.edit_rounded), onPressed: () => setState(() => _editCode = true)),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 10), NvBanner(tone: NvTone.stop, text: _error!)],
            ]),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
          child: NvButton(label: 'ساخت رویداد', busy: s.busy, onPressed: s.busy ? null : _save),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- پوسته

class NvAdminShell extends StatefulWidget {
  const NvAdminShell({super.key});

  @override
  State<NvAdminShell> createState() => _NvAdminShellState();
}

class _NvAdminShellState extends State<NvAdminShell> {
  int _i = 0;

  void go(int i) => setState(() => _i = i);

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final pages = <Widget>[
      TodayTab(onGo: go),
      const PeopleTab(),
      const PhonesTab(),
      const EventTab(),
    ];
    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        extendBody: true,
        body: Column(children: [
          // پیام کوتاه آخرین کار (موفق یا خطا)؛ پیام موفق خودش می‌رود.
          Expanded(child: KeyedSubtree(key: ValueKey(_i), child: pages[_i])),
          if (s.message != null) _MessageToast(key: ValueKey(s.message), text: s.message!, error: s.messageIsError),
        ]),
        bottomNavigationBar: NvNavBar(
          index: _i,
          onTap: go,
          items: const [
            (Icons.insights_rounded, 'امروز', false),
            (Icons.groups_rounded, 'افراد', false),
            (Icons.smartphone_rounded, 'گوشی‌ها', false),
            (Icons.tune_rounded, 'رویداد', false),
          ],
        ),
      ),
    );
  }
}

/// پیام پایین صفحه: موفق ۴ ثانیه بعد می‌رود؛ خطا تا «بستن» می‌ماند.
class _MessageToast extends StatefulWidget {
  final String text;
  final bool error;
  const _MessageToast({super.key, required this.text, required this.error});

  @override
  State<_MessageToast> createState() => _MessageToastState();
}

class _MessageToastState extends State<_MessageToast> {
  @override
  void initState() {
    super.initState();
    if (!widget.error) {
      Future.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        final s = StateScope.read(context);
        if (s.message == widget.text) {
          s.message = null;
          s.notify();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      child: Material(
        color: widget.error ? c.stop : c.ink,
        borderRadius: BorderRadius.circular(Nv.r14),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 6),
          child: Row(children: [
            Expanded(child: Text(widget.text, style: nvText(context, 14, color: c.bg))),
            TextButton(
              onPressed: () {
                final s = StateScope.read(context);
                s.message = null;
                s.notify();
              },
              child: Text('بستن', style: nvText(context, 14, w: FontWeight.w700, color: c.bg)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// سربرگ تب‌ها: خط کوچک بالا، عنوان، و نشانگر «زنده» یا ساعت آخرین داده.
class NvTabHeader extends StatelessWidget {
  final String line;
  final String title;
  final Widget? trailing;
  final double bottom;
  const NvTabHeader({super.key, required this.line, required this.title, this.trailing, this.bottom = 56});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvHeader(
      radius: 28,
      bottom: bottom,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line, style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 19, w: FontWeight.w800, color: c.onBrand, height: 1.4)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ]),
    );
  }
}

/// قرص سفید‌نیمه‌شفاف روی سربرگ (زنده، ساعت).
class NvHeaderPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const NvHeaderPill({super.key, required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: .16),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(text, style: nvText(context, 12, w: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
      );
}

/// امروز به شمسی با روز هفته: «چهارشنبه ۲۰ آبان».
String todayLine([DateTime? now]) {
  final n = now ?? DateTime.now();
  const days = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه', 'یکشنبه'];
  return '${days[n.weekday - 1]} ${jalaliLabel(isoDate(n), year: false)} · ${faDigits(hm(n))}';
}

/// دسترسی سریع: آیا گزارش (و دستگاه‌ها) گرفته شده.
extension AdminReport on AdminState {
  List<Map<String, dynamic>> get flaggedList => [for (final f in (report?['flagged'] as List? ?? const [])) (f as Map).cast<String, dynamic>()];
  List<Map<String, dynamic>> get deviceList => [for (final d in (report?['devices'] as List? ?? const [])) (d as Map).cast<String, dynamic>()];
}
