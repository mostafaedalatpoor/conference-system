import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';

import 'screens/cards.dart';
import 'screens/config.dart';
import 'screens/connect.dart';
import 'screens/import.dart';
import 'screens/people.dart';
import 'screens/report.dart';
import 'screens/staff.dart';
import 'brand.dart';
import 'normalize.dart';
import 'state.dart';
import 'theme/daftar.dart';
import 'theme/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AdminState();
  state.load();
  runApp(StateScope(state: state, child: const AdminApp()));
}

class StateScope extends InheritedNotifier<AdminState> {
  const StateScope({super.key, required AdminState state, required super.child}) : super(notifier: state);

  static AdminState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StateScope>()!.notifier!;
  static AdminState read(BuildContext context) => context.getInheritedWidgetOfExactType<StateScope>()!.notifier!;
}

/// تم دسکتاپ (کنترل ۳۶px، گوشه‌ی ۴px) فقط برای اپ مدیریت روی ویندوز؛ روی گوشی تم موبایل.
bool get isDesktopPlatform => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: daftarTheme(Brightness.light, desktop: desktop),
      darkTheme: daftarTheme(Brightness.dark, desktop: desktop),
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: const AppLock(child: Shell()),
    );
  }
}

/// یک مرحله‌ی آماده‌سازی رویداد در ناوبری کناری.
enum StepState { idle, current, done, attention, disabled }

/// مراحل آماده‌سازی؛ «کارت‌ها» در رویداد «بدون کارت» پنهان است.
List<(int, String, IconData, Widget)> adminSteps(AdminState s) => [
      (0, 'اتصال و رویداد', Icons.link_rounded, const ConnectScreen()),
      (1, 'پیکربندی', Icons.tune_rounded, const ConfigScreen()),
      (2, 'نیروها', Icons.badge_rounded, const StaffScreen()),
      (3, 'شرکت‌کننده‌ها', Icons.upload_file_rounded, const ImportScreen()),
      if (s.settings.usesCards) (4, 'کارت‌ها', Icons.style_rounded, const CardsScreen()),
    ];

/// خط وضعیت واقعی هر مرحله، تا مدیر بدون باز کردن هر بخش بداند آماده است یا نه.
/// (متن، انجام‌شده، نیازمند توجه)
(String, bool, bool) stepStatus(AdminState s, int k) {
  switch (k) {
    case 0:
      if (s.event == null) return (s.apiKey.isEmpty ? 'هنوز وصل نشده' : 'رویداد را انتخاب کنید', false, s.apiKey.isNotEmpty);
      return ('${s.event!.code}${s.event!.locked ? '، آدرس قفل' : ''}', true, false);
    case 1:
      if (s.types.isEmpty) return ('نوع ثبت‌نامی تعریف نشده', false, true);
      return ('${faDigits(s.types.length)} نوع، ${faDigits(s.meals.length)} وعده', true, false);
    case 2:
      if (s.staff.isEmpty) return ('نیرویی تعریف نشده', false, true);
      final noPin = s.staff.where((x) => !x.hasPin && x.newPin.isEmpty).length;
      if (noPin > 0) return ('${faDigits(s.staff.length)} نیرو، ${faDigits(noPin)} بدون PIN', false, true);
      return ('${faDigits(s.staff.length)} نیرو', true, false);
    case 3:
      if (s.people.isEmpty) return ('هنوز کسی وارد نشده', false, false);
      return ('${faDigits(s.people.length)} نفر', true, false);
    case 4:
      final free = s.reserveCards.where((r) => !r.used).length;
      if (s.event?.locked == true) return ('PDF ساخته شد، ${faDigits(free)} رزرو آزاد', true, false);
      return (s.reserveCards.isEmpty ? 'کارت رزرو ساخته نشده' : '${faDigits(free)} کارت رزرو آزاد', false, false);
    default:
      return ('شمارش زنده‌ی روز اجرا', false, false);
  }
}

/// پیام آخرین کار (خطا یا موفقیت) بالای صفحه.
class MessageBar extends StatelessWidget {
  const MessageBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 3, child: s.busy ? const LinearProgressIndicator() : null),
      if (s.message != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(DaftarSize.space4, DaftarSize.space3, DaftarSize.space4, 0),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Notice(
                tone: s.messageIsError ? NoticeTone.stop : NoticeTone.go,
                text: s.message!,
                action: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () {
                      s.message = null;
                      s.notify();
                    },
                    child: const Text('بستن'),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

void showAboutRoydadyar(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: const SizedBox(
          width: 420,
          child: AboutCard(
            appName: appName,
            appNameLatin: appNameLatin,
            version: appVersion,
            maker: makerFull,
            website: makerWebsite,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('بستن'))],
      ),
    );

/// زیر ۱۰۲۴px (گوشی، پنجره‌ی باریک): چهار تب پایین؛ بالاتر: SideNav مرحله‌ای.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1024 ? const DeskShell() : const MobileShell();
}

class DeskShell extends StatefulWidget {
  const DeskShell({super.key});

  @override
  State<DeskShell> createState() => _DeskShellState();
}

class _DeskShellState extends State<DeskShell> {
  int _i = 0;

  void _go(AdminState s, int v) {
    if (s.event == null && v != 0) return;
    if (v == 4 && !s.settings.usesCards) return;
    setState(() => _i = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final needsEvent = s.event == null;
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final steps = adminSteps(s);
    var i = needsEvent ? 0 : _i;
    if (i == 4 && !s.settings.usesCards) i = 0;
    final page = i == 5 ? const ReportScreen() : steps.firstWhere((e) => e.$1 == i).$4;

    Widget item(int k, String title, {int? number}) {
      final (line, done, attention) = stepStatus(s, k);
      final StepState st = needsEvent && k != 0
          ? StepState.disabled
          : k == i
              ? StepState.current
              : attention
                  ? StepState.attention
                  : done
                      ? StepState.done
                      : StepState.idle;
      return _StepItem(
        number: number,
        title: title,
        line: line,
        state: st,
        onTap: st == StepState.disabled ? null : () => _go(s, k),
      );
    }

    return CallbackShortcuts(
      bindings: {
        for (var k = 0; k < 6; k++)
          SingleActivator(LogicalKeyboardKey(0x00000000031 + k), control: true): () => _go(s, k),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              // SideNav: فهرست مراحل، ۲۶۰px سمت راست (ابتدای RTL).
              Container(
                width: 260,
                decoration: BoxDecoration(
                  color: x.surface,
                  border: BorderDirectional(end: BorderSide(color: x.line)),
                ),
                child: Column(children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(DaftarSize.space3),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(DaftarSize.space2, DaftarSize.space2, DaftarSize.space2, 0),
                          child: Row(children: [
                            Image.asset('assets/brand/logo.png', width: 32, height: 32, semanticLabel: 'لوگوی رویدادیار'),
                            const SizedBox(width: DaftarSize.space2),
                            Text(appName, style: theme.textTheme.titleMedium),
                          ]),
                        ),
                        Divider(color: x.line, height: DaftarSize.space5),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(DaftarSize.space2, 0, DaftarSize.space2, DaftarSize.space4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.event?.name ?? 'رویدادی انتخاب نشده',
                                style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (s.event != null)
                              Text(s.event!.code,
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                          ]),
                        ),
                        for (var n = 0; n < steps.length; n++) item(steps[n].$1, steps[n].$2, number: n + 1),
                        const SizedBox(height: DaftarSize.space2),
                        Divider(color: x.line),
                        const SizedBox(height: DaftarSize.space2),
                        item(5, 'گزارش زنده'),
                      ],
                    ),
                  ),
                  // MakerCredit: پایین ناوبری، کوچک‌ترین متن.
                  InkWell(
                    onTap: () => showAboutRoydadyar(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DaftarSize.space4),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: x.line))),
                      child: Text('$productName ${faDigits(appVersion.split('.').take(2).join('٫'))}، $makerShort',
                          style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: Column(
                  children: [
                    const MessageBar(),
                    Expanded(child: page),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// اپ مدیریت روی موبایل: امروز، افراد، نیروها، آماده‌سازی (ScreenAdminMobile).
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    if (s.event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(appName)),
        body: const Column(children: [MessageBar(), Expanded(child: ConnectScreen())]),
      );
    }
    const titles = ['امروز', 'افراد', 'نیروها', 'آماده‌سازی'];
    final pages = <Widget>[
      const ReportScreen(autoRefresh: true, title: 'امروز'),
      const PeopleScreen(),
      const StaffScreen(showDevices: true),
      const PrepScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_i == 0 ? s.event!.name : titles[_i], overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [const MessageBar(), Expanded(child: KeyedSubtree(key: ValueKey(_i), child: pages[_i]))]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'امروز'),
          NavigationDestination(icon: Icon(Icons.people_alt_rounded), label: 'افراد'),
          NavigationDestination(icon: Icon(Icons.badge_rounded), label: 'نیروها'),
          NavigationDestination(icon: Icon(Icons.checklist_rounded), label: 'آماده‌سازی'),
        ],
      ),
    );
  }
}

/// تب «آماده‌سازی» موبایل: همان مراحل اپ ویندوز، و «درباره و پشتیبانی» در انتها.
class PrepScreen extends StatelessWidget {
  const PrepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final steps = adminSteps(s);
    return ListView(padding: const EdgeInsets.all(DaftarSize.space4), children: [
      for (var n = 0; n < steps.length; n++)
        Builder(builder: (context) {
          final (k, title, _, page) = steps[n];
          final (line, done, attention) = stepStatus(s, k);
          return _StepItem(
            number: n + 1,
            title: title,
            line: line,
            state: attention ? StepState.attention : (done ? StepState.done : StepState.idle),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(title)),
                body: Column(children: [const MessageBar(), Expanded(child: page)]),
              ),
            )),
          );
        }),
      const SectionTitle('درباره و پشتیبانی'),
      const AboutCard(
        appName: appName,
        appNameLatin: appNameLatin,
        version: appVersion,
        maker: makerFull,
        website: makerWebsite,
      ),
    ]);
  }
}

/// قفل اپ مدیریت روی گوشی با اثر انگشت یا رمز صفحه‌ی گوشی، هنگام باز شدن و بعد از ۵ دقیقه در پس‌زمینه.
/// کلید API مدیریت روی گوشی ذخیره است؛ گوشی گم‌شده نباید یعنی دسترسی کامل مدیریت.
class AppLock extends StatefulWidget {
  final Widget child;
  const AppLock({super.key, required this.child});

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _locked = Platform.isAndroid || Platform.isIOS;
  bool _busy = false;
  bool _unsupported = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null && !_busy) {
      if (DateTime.now().difference(_pausedAt!).inMinutes >= 5) {
        setState(() => _locked = true);
        _unlock();
      }
      _pausedAt = null;
    }
  }

  Future<void> _unlock() async {
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
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // خطای سیستم: بسته نمی‌ماند تا مدیر روز اجرا پشت در نماند، ولی هشدار می‌دهد.
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
    if (_locked) {
      final theme = Theme.of(context);
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(DaftarSize.space5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/brand/logo.png', width: 72, height: 72),
                const SizedBox(height: DaftarSize.space3),
                Text(appName, style: theme.textTheme.titleLarge),
                const SizedBox(height: DaftarSize.space5),
                FilledButton.icon(
                  style: daftarWideStyle(context),
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('باز کردن با اثر انگشت یا رمز گوشی'),
                ),
                const SizedBox(height: DaftarSize.space6),
                const MakerLine(team: makerTeam),
              ]),
            ),
          ),
        ),
      );
    }
    if (_unsupported) {
      return Column(children: [
        Material(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(DaftarSize.space3),
              child: Notice(
                tone: NoticeTone.wait,
                text: 'قفل صفحه‌ی این گوشی روشن نیست؛ هر کسی با این گوشی به مدیریت رویداد دسترسی دارد. '
                    'از تنظیمات گوشی رمز یا اثر انگشت بگذارید.',
                action: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(onPressed: () => setState(() => _unsupported = false), child: const Text('فهمیدم')),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ]);
    }
    return widget.child;
  }
}

class _StepItem extends StatelessWidget {
  final int? number;
  final String title;
  final String line;
  final StepState state;
  final VoidCallback? onTap;
  const _StepItem({required this.number, required this.title, required this.line, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final current = state == StepState.current;
    final disabled = state == StepState.disabled;
    final (badgeBg, badgeFg) = switch (state) {
      StepState.current => (x.stamp, x.onStamp),
      StepState.done => (x.goSoft, x.go),
      StepState.attention => (x.waitSoft, x.wait),
      _ => (x.sunken, x.inkMuted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current ? x.stampSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
        child: InkWell(
          borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space2, vertical: DaftarSize.space2),
            child: Opacity(
              opacity: disabled ? .5 : 1,
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(DaftarSize.radiusXs)),
                  child: number == null
                      ? Icon(Icons.insights_rounded, size: 16, color: badgeFg)
                      : state == StepState.done
                          ? Icon(Icons.check_rounded, size: 16, color: badgeFg)
                          : Text(faDigits(number!),
                              style: theme.textTheme.labelLarge?.copyWith(color: badgeFg, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: DaftarSize.space3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: current ? FontWeight.w800 : FontWeight.w600)),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: state == StepState.attention ? x.wait : x.inkMuted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// ستون استاندارد صفحه‌ها با بیشینه‌ی عرض ۱۱۰۰px.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  const PageBody({super.key, required this.children, this.title});

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(DaftarSize.space5, DaftarSize.space5, DaftarSize.space5, DaftarSize.space7),
            children: [
              // روی گوشی عنوان در نوار بالاست و تکرار نمی‌شود.
              if (title != null && MediaQuery.sizeOf(context).width >= 1024)
                Padding(
                  padding: const EdgeInsets.only(bottom: DaftarSize.space2),
                  child: Text(title!, style: Theme.of(context).textTheme.titleLarge),
                ),
              ...children,
            ],
          ),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: DaftarSize.space5, bottom: DaftarSize.space2),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// متن راهنمای کم‌رنگ زیر سرفصل‌ها.
class Hint extends StatelessWidget {
  final String text;
  const Hint(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DaftarColors.of(context).inkMuted));
}
