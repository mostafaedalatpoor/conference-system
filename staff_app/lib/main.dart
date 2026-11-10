import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'android/android_app.dart';
import 'android/nv_theme.dart';
import 'brand.dart';
import 'store.dart';

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

/// اندروید: پوسته‌ی گوشی؛ ویندوز: پوسته‌ی دو ستونه با کلیدهای میان‌بر. هر دو با ظاهر تازه.
bool get useAndroidDesign => !kIsWeb && Platform.isAndroid;

class StaffApp extends StatelessWidget {
  /// برای تست و پیش‌نمایش؛ پیش‌فرض بر اساس سکو.
  final bool? android;
  const StaffApp({super.key, this.android});

  @override
  Widget build(BuildContext context) {
    final isAndroid = android ?? useAndroidDesign;
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
      // بزرگ‌نمایی متن سیستم تا ۱٫۳ برابر؛ بالاتر از آن چیدمان صفحه‌ی اسکن و شیت می‌شکند.
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: NvRoot(desk: !isAndroid),
    );
  }
}
