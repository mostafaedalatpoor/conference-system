import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

import 'android/nv_admin.dart';
import 'android/nv_theme.dart';
import 'registration/reg_home.dart';
import 'registration/reg_list.dart';
import 'screens/cards.dart';
import 'screens/config.dart';
import 'screens/connect.dart';
import 'screens/import.dart';
import 'screens/people.dart';
import 'screens/people_desk.dart';
import 'screens/people_limited.dart';
import 'screens/report.dart';
import 'screens/staff.dart';
import 'brand.dart';
import 'normalize.dart';
import 'state.dart';
import 'theme/firouzeh.dart';
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
  /// برای آزمون و پیش‌نمایش؛ پیش‌فرض بر اساس سکو.
  final bool? android;
  const AdminApp({super.key, this.android});

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    if (android ?? Platform.isAndroid) {
      // اندروید: پوسته‌ی چهار تب طبق بوم‌های «مدیریت اندروید».
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
        theme: nvTheme(Brightness.light),
        darkTheme: nvTheme(Brightness.dark),
        builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
        home: const NvAdminRoot(),
      );
    }
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
      theme: firouzehTheme(Brightness.light, desktop: desktop),
      darkTheme: firouzehTheme(Brightness.dark, desktop: desktop),
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
      if (s.event == null)
        return (s.apiKey.isEmpty ? 'هنوز وصل نشده' : 'رویداد را انتخاب کنید', false, s.apiKey.isNotEmpty);
      return ('${s.event!.code}${s.event!.locked ? '، آدرس قفل' : ''}', true, false);
    case 1:
      if (s.types.isEmpty) return ('نوع ثبت‌نامی تعریف نشده', false, true);
      return ('${faDigits(s.types.length)} نوع، ${faDigits(s.meals.length)} وعده', true, false);
    case 2:
      final active = s.staff.where((x) => x.active).toList();
      if (active.isEmpty) return ('نیرویی تعریف نشده', false, true);
      final noPin = active.where((x) => !x.hasPin && x.newPin.isEmpty).length;
      if (noPin > 0) return ('${faDigits(active.length)} نیرو، ${faDigits(noPin)} بدون PIN', false, true);
      return ('${faDigits(active.length)} نیرو', true, false);
    case 3:
      if (s.people.isEmpty) return ('هنوز کسی وارد نشده', false, false);
      return ('${faDigits(s.people.values.where((p) => p.isActive).length)} نفر', true, false);
    case 4:
      final free = s.reserveCards.where((r) => !r.used).length;
      if (s.event?.locked == true) return ('PDF ساخته شد، ${faDigits(free)} رزرو آزاد', true, false);
      return (s.reserveCards.isEmpty ? 'کارت رزرو ساخته نشده' : '${faDigits(free)} کارت رزرو آزاد', false, false);
    case 6:
      return (
        '${faDigits(s.people.values.where((p) => p.isActive).length)} نفر · جستجو، ویرایش، کار گروهی',
        false,
        false
      );
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
          padding: const EdgeInsets.fromLTRB(FirouzehSize.space4, FirouzehSize.space3, FirouzehSize.space4, 0),
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
  int _i = 5; // «امروز» اول، طبق بوم.

  void _go(AdminState s, int v) {
    if (s.event == null && v != 0) return;
    if (v == 4 && !s.settings.usesCards) return;
    // دسترسی محدود: فقط اتصال، امروز و افراد.
    if (s.limited && !const [0, 5, 6].contains(v)) return;
    if ((v == 7 || v == 8 || v == 9) && s.limited) return;
    setState(() => _i = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final needsEvent = s.event == null;
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    final steps = adminSteps(s);
    var i = needsEvent ? 0 : _i;
    if (i == 4 && !s.settings.usesCards) i = 5;
    if (s.limited && !needsEvent && !const [0, 5, 6].contains(i)) i = 5;
    final page = switch (i) {
      5 => const ReportScreen(title: 'امروز', autoRefresh: true),
      6 => s.limited ? const LimitedPeopleScreen() : const PeopleDeskScreen(),
      2 => const StaffScreen(showDevices: true),
      7 => const ReportScreen(title: 'گزارش‌ها'),
      // ثبت‌نام آنلاین در Navigator خودش تا نوار کناری با رفتن به ویزارد و جزئیات بماند.
      8 => _DeskNav(key: const ValueKey('reg-list'), child: const RegListPage(filter: 'attention')),
      9 => _DeskNav(key: const ValueKey('reg-home'), child: const RegHomePage()),
      _ => steps.firstWhere((e) => e.$1 == i).$4,
    };

    // ترتیب و نام‌ها طبق بوم «نوار کناری» مدیریت ویندوز.
    final nav = <(int, IconData, String)>[
      (5, Icons.insights_rounded, 'امروز'),
      (6, Icons.groups_rounded, 'افراد'),
      if (!s.limited) ...[
        (8, Icons.pending_actions_rounded, 'تأیید ثبت‌نام'),
        (2, Icons.smartphone_rounded, 'گوشی‌ها و کارکنان'),
        (1, Icons.tune_rounded, 'تنظیم رویداد'),
        (3, Icons.upload_file_rounded, 'ورود اکسل'),
        if (s.settings.usesCards) (4, Icons.badge_rounded, 'کارت‌ها'),
        (9, Icons.how_to_reg_rounded, 'ثبت‌نام آنلاین'),
        (7, Icons.download_rounded, 'گزارش‌ها'),
      ],
    ];

    Widget item(int k, IconData icon, String title) {
      final (line, _, attention) = switch (k) {
        7 => ('خروجی اکسل، CSV و PDF', false, false),
        8 => (s.regWaiting > 0 ? '${faDigits(s.regWaiting)} منتظر تصمیم' : 'ثبت‌نام‌های منتظر تأیید یا بررسی پرداخت', false, false),
        9 => ('صفحه، پرداخت، پیام‌ها و گزارش مالی', false, false),
        _ => stepStatus(s, k),
      };
      return _NavItem(
        icon: icon,
        title: title,
        tooltip: line,
        current: k == i,
        badge: k == 8 && s.regWaiting > 0 ? faDigits(s.regWaiting) : null,
        attention: attention && k != i,
        onTap: needsEvent && k != 0 ? null : () => _go(s, k),
      );
    }

    return CallbackShortcuts(
      bindings: {
        // Ctrl+1 تا Ctrl+7 به ترتیب نوار کناری.
        for (var n = 0; n < nav.length && n < 9; n++)
          SingleActivator(LogicalKeyboardKey(0x00000000031 + n), control: true): () => _go(s, nav[n].$1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              // SideNav: ۲۶۴px سمت راست (ابتدای RTL)، ردیف ۴۶px، فعال پر از brand.
              Container(
                width: FirouzehSize.sideNav,
                decoration: BoxDecoration(
                  color: x.surface,
                  border: BorderDirectional(end: BorderSide(color: x.line)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: FirouzehSize.space3, vertical: FirouzehSize.space4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: x.action, borderRadius: BorderRadius.circular(FirouzehSize.radiusSm)),
                        child: Icon(Icons.event_available_rounded, color: x.onAction, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(productName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('مدیریت', style: theme.textTheme.labelSmall?.copyWith(color: x.inkMuted)),
                      ]),
                    ]),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _go(s, 0),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: i == 0 ? x.stampSoft : x.sunken,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(needsEvent ? 'اتصال و رویداد' : 'رویداد فعال', style: theme.textTheme.labelSmall?.copyWith(color: x.inkMuted)),
                        Text(s.event?.name ?? 'رویدادی انتخاب نشده',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, height: 20 / 14)),
                        if (s.event != null)
                          Text('${s.event!.code}${s.event!.archived ? ' · بایگانی' : ''} · تغییر رویداد',
                              style: theme.textTheme.labelSmall?.copyWith(color: x.stamp)),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: ListView(padding: EdgeInsets.zero, children: [
                      for (final n in nav) item(n.$1, n.$2, n.$3),
                    ]),
                  ),
                  // وضعیت همگام‌سازی و «درباره».
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: s.messageIsError ? x.waitSoft : x.goSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Icon(s.messageIsError ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                          size: 18, color: s.messageIsError ? x.wait : x.go),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.busy ? 'در حال به‌روزرسانی…' : (s.messageIsError ? 'به سرور نرسیدیم' : 'متصل به سرور'),
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: s.messageIsError ? x.wait : x.go, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => showAboutRoydadyar(context),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        Icon(Icons.info_outline_rounded, size: 22, color: x.inkMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('$productName ${faDigits(appVersion.split('.').take(2).join('٫'))}، $makerShort',
                              style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: Column(
                  children: [
                    const MessageBar(),
                    if (s.limited && !needsEvent) const LimitedBanner(),
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
    if (s.limited) {
      // دسترسی محدود (۱۸-States حالت ۱۵): فقط «امروز» و «افراد».
      final i = _i > 1 ? 0 : _i;
      return Scaffold(
        appBar: AppBar(
          title: Text(i == 0 ? s.event!.name : 'افراد', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'اتصال و رویداد',
              icon: const Icon(Icons.link_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('اتصال و رویداد')),
                  body: const Column(children: [MessageBar(), Expanded(child: ConnectScreen())]),
                ),
              )),
            ),
          ],
        ),
        body: Column(children: [
          const MessageBar(),
          const LimitedBanner(),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(i),
              child: i == 0 ? const ReportScreen(autoRefresh: true, title: 'امروز') : const LimitedPeopleScreen(),
            ),
          ),
        ]),
        bottomNavigationBar: FloatingNav(
          child: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => _i = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'امروز'),
              NavigationDestination(icon: Icon(Icons.people_alt_rounded), label: 'افراد'),
            ],
          ),
        ),
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
      bottomNavigationBar: FloatingNav(
        child: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'امروز'),
            NavigationDestination(icon: Icon(Icons.people_alt_rounded), label: 'افراد'),
            NavigationDestination(icon: Icon(Icons.badge_rounded), label: 'نیروها'),
            NavigationDestination(icon: Icon(Icons.checklist_rounded), label: 'آماده‌سازی'),
          ],
        ),
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
    return ListView(padding: const EdgeInsets.all(FirouzehSize.space4), children: [
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
  LocalAuthPlatform get _auth => LocalAuthPlatform.instance;
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
        authMessages: const [],
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
              padding: const EdgeInsets.all(FirouzehSize.space5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/brand/logo.png', width: 72, height: 72),
                const SizedBox(height: FirouzehSize.space3),
                Text(appName, style: theme.textTheme.titleLarge),
                const SizedBox(height: FirouzehSize.space5),
                FilledButton.icon(
                  style: firouzehWideStyle(context),
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('باز کردن با اثر انگشت یا رمز گوشی'),
                ),
                const SizedBox(height: FirouzehSize.space6),
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
              padding: const EdgeInsets.all(FirouzehSize.space3),
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

/// Navigator جدا برای یک بخش دسکتاپ، تا صفحه‌های داخلی زیر همان نوار کناری باز شوند.
class _DeskNav extends StatelessWidget {
  final Widget child;
  const _DeskNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child));
}

/// ردیف نوار کناری ویندوز (بوم «نوار کناری»): ۴۶px، گوشه‌ی ۱۴، فعال پر از brand.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String tooltip;
  final bool current;
  final bool attention;
  final String? badge;
  final VoidCallback? onTap;
  const _NavItem({
    this.badge,
    required this.icon,
    required this.title,
    required this.tooltip,
    required this.current,
    required this.attention,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    final fg = current ? x.onAction : x.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: current ? x.action : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Opacity(
              opacity: onTap == null ? .45 : 1,
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Icon(icon, size: 22, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: fg, fontWeight: current ? FontWeight.w800 : FontWeight.w600)),
                    ),
                    if (badge != null)
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: x.waitSoft, borderRadius: BorderRadius.circular(11)),
                        child: Text(badge!, style: theme.textTheme.labelMedium?.copyWith(color: x.wait, fontWeight: FontWeight.w800)),
                      )
                    else if (attention)
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: x.waitSoft, borderRadius: BorderRadius.circular(11)),
                        child: Text('!', style: theme.textTheme.labelMedium?.copyWith(color: x.wait, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    final current = state == StepState.current;
    final disabled = state == StepState.disabled;
    final (badgeBg, badgeFg) = switch (state) {
      StepState.current => (x.onAction, x.action),
      StepState.done => (x.goSoft, x.go),
      StepState.attention => (x.waitSoft, x.wait),
      _ => (x.sunken, x.inkMuted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current ? x.action : Colors.transparent,
        borderRadius: BorderRadius.circular(FirouzehSize.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(FirouzehSize.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FirouzehSize.space2, vertical: FirouzehSize.space2),
            child: Opacity(
              opacity: disabled ? .5 : 1,
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(FirouzehSize.radiusPill)),
                  child: number == null
                      ? Icon(Icons.insights_rounded, size: 16, color: badgeFg)
                      : state == StepState.done
                          ? Icon(Icons.check_rounded, size: 16, color: badgeFg)
                          : Text(faDigits(number!),
                              style: theme.textTheme.labelLarge?.copyWith(color: badgeFg, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: FirouzehSize.space3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                            color: current ? x.onAction : x.ink)),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: current
                                ? x.onAction.withValues(alpha: .85)
                                : (state == StepState.attention ? x.wait : x.inkMuted))),
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
            padding: const EdgeInsets.fromLTRB(
                FirouzehSize.space5, FirouzehSize.space5, FirouzehSize.space5, FirouzehSize.space7),
            children: [
              // روی گوشی عنوان در نوار بالاست و تکرار نمی‌شود.
              if (title != null && MediaQuery.sizeOf(context).width >= 1024)
                Padding(
                  padding: const EdgeInsets.only(bottom: FirouzehSize.space4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (StateScope.of(context).event != null)
                      Text(StateScope.of(context).event!.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: FirouzehColors.of(context).inkMuted)),
                    Text(title!,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontSize: 28, height: 38 / 28, fontWeight: FontWeight.w800)),
                  ]),
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
        padding: const EdgeInsets.only(top: FirouzehSize.space5, bottom: FirouzehSize.space2),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// متن راهنمای کم‌رنگ زیر سرفصل‌ها.
class Hint extends StatelessWidget {
  final String text;
  const Hint(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FirouzehColors.of(context).inkMuted));
}
