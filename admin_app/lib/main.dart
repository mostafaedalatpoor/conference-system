import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/cards.dart';
import 'screens/config.dart';
import 'screens/connect.dart';
import 'screens/import.dart';
import 'screens/report.dart';
import 'screens/staff.dart';
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

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'رویداد یار — مدیریت',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: daftarTheme(Brightness.light, desktop: true),
      darkTheme: daftarTheme(Brightness.dark, desktop: true),
      home: const Shell(),
    );
  }
}

/// یک مرحله‌ی آماده‌سازی رویداد در ناوبری کناری.
enum StepState { idle, current, done, attention, disabled }

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _pages = <(String, Widget)>[
    ('اتصال و رویداد', ConnectScreen()),
    ('پیکربندی', ConfigScreen()),
    ('نیروها', StaffScreen()),
    ('شرکت‌کننده‌ها', ImportScreen()),
    ('کارت‌ها', CardsScreen()),
    ('گزارش زنده', ReportScreen()),
  ];

  /// خط وضعیت واقعی هر مرحله، تا مدیر بدون باز کردن هر بخش بداند آماده است یا نه.
  (String, bool, bool) _status(AdminState s, int k) {
    // (متن، انجام‌شده، نیازمند توجه)
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

  void _go(AdminState s, int v) {
    if (s.event == null && v != 0) return;
    setState(() => _i = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final needsEvent = s.event == null;
    final x = DaftarColors.of(context);
    final i = needsEvent ? 0 : _i;

    return CallbackShortcuts(
      bindings: {
        for (var k = 0; k < _pages.length; k++)
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
                child: ListView(
                  padding: const EdgeInsets.all(DaftarSize.space3),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(DaftarSize.space2, DaftarSize.space2, DaftarSize.space2, 0),
                      child: Row(children: [
                        Image.asset('assets/brand/logo.png', width: 32, height: 32, semanticLabel: 'لوگوی رویداد یار'),
                        const SizedBox(width: DaftarSize.space2),
                        Text('رویداد یار', style: Theme.of(context).textTheme.titleMedium),
                      ]),
                    ),
                    Divider(color: x.line, height: DaftarSize.space5),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(DaftarSize.space2, 0, DaftarSize.space2, DaftarSize.space4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.event?.name ?? 'رویدادی انتخاب نشده',
                            style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (s.event != null)
                          Text(s.event!.code,
                              textDirection: TextDirection.ltr,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                      ]),
                    ),
                    for (var k = 0; k < _pages.length; k++) ...[
                      if (k == _pages.length - 1) ...[
                        const SizedBox(height: DaftarSize.space2),
                        Divider(color: x.line),
                        const SizedBox(height: DaftarSize.space2),
                      ],
                      Builder(builder: (context) {
                        final (line, done, attention) = _status(s, k);
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
                          number: k == _pages.length - 1 ? null : k + 1,
                          title: _pages[k].$1,
                          line: line,
                          state: st,
                          onTap: st == StepState.disabled ? null : () => _go(s, k),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(height: 3, child: s.busy ? const LinearProgressIndicator() : null),
                    if (s.message != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(DaftarSize.space5, DaftarSize.space3, DaftarSize.space5, 0),
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
                    Expanded(child: _pages[i].$2),
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
              if (title != null)
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
