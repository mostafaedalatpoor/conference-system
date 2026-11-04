import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/cards.dart';
import 'screens/config.dart';
import 'screens/connect.dart';
import 'screens/import.dart';
import 'screens/report.dart';
import 'screens/staff.dart';
import 'state.dart';

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
    const seed = Color(0xFF1F5FBF);
    return MaterialApp(
      title: 'مدیریت کنفرانس',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, fontFamily: 'Vazirmatn'),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _pages = <(IconData, String, Widget)>[
    (Icons.link, 'اتصال و رویداد', ConnectScreen()),
    (Icons.tune, 'پیکربندی', ConfigScreen()),
    (Icons.badge, 'نیروها', StaffScreen()),
    (Icons.upload_file, 'شرکت‌کننده‌ها', ImportScreen()),
    (Icons.style, 'کارت‌ها', CardsScreen()),
    (Icons.insights, 'گزارش', ReportScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final needsEvent = s.event == null;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _i,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (v) {
              if (needsEvent && v != 0) return;
              setState(() => _i = v);
            },
            destinations: [
              for (var k = 0; k < _pages.length; k++)
                NavigationRailDestination(
                  icon: Icon(_pages[k].$1),
                  label: Text(_pages[k].$2),
                  disabled: needsEvent && k != 0,
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (s.busy) const LinearProgressIndicator(),
                if (s.message != null)
                  MaterialBanner(
                    backgroundColor:
                        s.messageIsError ? Theme.of(context).colorScheme.errorContainer : Colors.green.shade50,
                    content: SelectableText(s.message!),
                    actions: [
                      TextButton(
                        onPressed: () {
                          s.message = null;
                          s.notify();
                        },
                        child: const Text('بستن'),
                      ),
                    ],
                  ),
                if (s.event != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text('رویداد: ${s.event!.name} (${s.event!.code})'),
                  ),
                Expanded(child: _pages[needsEvent ? 0 : _i].$3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ستون استاندارد صفحه‌ها با عرض محدود.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(padding: const EdgeInsets.all(24), children: children),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
