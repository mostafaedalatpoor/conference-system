import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home.dart';
import 'screens/setup.dart';
import 'store.dart';
import 'theme/daftar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  store.load();
  runApp(StoreScope(store: store, child: const StaffApp()));
}

/// دسترسی صفحه‌ها به AppStore و بازسازی با هر تغییر.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

class StaffApp extends StatelessWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'رویداد یار',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: daftarTheme(Brightness.light),
      darkTheme: daftarTheme(Brightness.dark),
      // بزرگ‌نمایی متن سیستم تا ۱٫۳ برابر؛ بالاتر از آن چیدمان صفحه‌ی اسکن و شیت می‌شکند.
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!store.loggedIn || store.needsLogin) return const SetupScreen();
    return const HomeScreen();
  }
}
