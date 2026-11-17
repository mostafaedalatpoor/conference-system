import 'package:conference_admin/theme/firouzeh.dart';
import 'package:conference_admin/theme/jalali_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// مثل main.dart: فارسی و راست‌به‌چپ در همه‌ی اپ، پنجره‌ها هم.
Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: firouzehTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 360, child: child))),
    );

/// نگه‌دارنده‌ی شروع و پایان، مثل صفحه‌ی اتصال و رویداد.
class _RangeHost extends StatefulWidget {
  final String start, end;
  final List<(String, String)> log;
  const _RangeHost(this.start, this.end, this.log);

  @override
  State<_RangeHost> createState() => _RangeHostState();
}

class _RangeHostState extends State<_RangeHost> {
  late String s = widget.start, e = widget.end;

  @override
  Widget build(BuildContext context) => JalaliRangePicker(
        start: s,
        end: e,
        onChanged: (a, b) => setState(() {
          s = a;
          e = b;
          widget.log.add((a, b));
        }),
      );
}

void main() {
  testWidgets('تقویم ماه آبان ۱۴۰۵؛ لمس ۲۰ همان 2026-11-11 است', (t) async {
    DateTime? picked;
    await t.pumpWidget(_wrap(JalaliMonthGrid(
      initialMonth: DateTime.utc(2026, 11, 1),
      onPick: (g) => picked = g,
    )));
    expect(find.text('آبان ۱۴۰۵'), findsOneWidget);
    for (final w in ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']) {
      expect(find.text(w), findsOneWidget);
    }
    expect(find.text('۳۰'), findsOneWidget);
    expect(find.text('۳۱'), findsNothing, reason: 'آبان ۳۰ روزه است');
    await t.tap(find.text('۲۰'));
    expect(picked, DateTime.utc(2026, 11, 11));
  });

  testWidgets('ماه بعد و قبل، با گذر از سال', (t) async {
    await t.pumpWidget(_wrap(JalaliMonthGrid(initialMonth: DateTime.utc(2026, 3, 21), onPick: (_) {})));
    expect(find.text('فروردین ۱۴۰۵'), findsOneWidget);
    await t.tap(find.byTooltip('ماه قبل'));
    await t.pump();
    expect(find.text('اسفند ۱۴۰۴'), findsOneWidget);
    expect(find.text('۳۰'), findsNothing, reason: 'اسفند ۱۴۰۴ کبیسه نیست');
    await t.tap(find.byTooltip('ماه بعد'));
    await t.tap(find.byTooltip('ماه بعد'));
    await t.pump();
    expect(find.text('اردیبهشت ۱۴۰۵'), findsOneWidget);
  });

  testWidgets('بازه: شروع و پایان ISO میلادی ذخیره می‌شوند و پایان پیش از شروع نمی‌افتد', (t) async {
    final log = <(String, String)>[];
    await t.pumpWidget(_wrap(_RangeHost('2026-11-11', '2026-11-12', log)));
    expect(find.text('۲۰ آبان ۱۴۰۵'), findsOneWidget);
    expect(find.text('۲۱ آبان ۱۴۰۵'), findsOneWidget);
    expect(find.byType(JalaliMonthGrid), findsNothing, reason: 'با تاریخ موجود تقویم بسته است');

    await t.tap(find.text('۲۰ آبان ۱۴۰۵'));
    await t.pump();
    await t.tap(find.text('۱۸'));
    await t.pump();
    expect(log.last, ('2026-11-09', '2026-11-12'));

    // بعد از شروع، تقویم برای پایان باز می‌ماند.
    await t.tap(find.text('۲۵'));
    await t.pump();
    expect(log.last, ('2026-11-09', '2026-11-16'));
    expect(find.byType(JalaliMonthGrid), findsNothing);

    // شروعِ بعد از پایان، پایان را هم جلو می‌برد.
    await t.tap(find.text('۱۸ آبان ۱۴۰۵'));
    await t.pump();
    await t.tap(find.text('۲۸'));
    await t.pump();
    expect(log.last, ('2026-11-19', '2026-11-19'));
  });

  testWidgets('فیلد تاریخ: برچسب شمسی، مقدار نامعتبر قدیمی، پاک کردن', (t) async {
    String? out;
    await t.pumpWidget(_wrap(Column(children: [
      JalaliDateField(label: 'روز', value: '2026-12-05', clearable: true, onChanged: (v) => out = v),
      JalaliDateField(label: 'روز', value: '1405-08-20', onChanged: (_) {}),
      JalaliDateField(label: 'روز', value: '', emptyText: 'همه‌ی روزها', onChanged: (_) {}),
    ])));
    expect(find.text('۱۴ آذر ۱۴۰۵'), findsOneWidget);
    expect(find.text('1405-08-20'), findsOneWidget);
    expect(find.text('تاریخ نامعتبر؛ دوباره انتخاب کنید'), findsOneWidget);
    expect(find.text('همه‌ی روزها'), findsOneWidget);
    await t.tap(find.byTooltip('پاک کردن'));
    expect(out, '');
  });

  testWidgets('پنجره‌ی تقویم ISO میلادی برمی‌گرداند', (t) async {
    String? out;
    await t.pumpWidget(_wrap(JalaliDateField(
      label: 'روز وعده',
      value: '2026-11-11',
      onChanged: (v) => out = v,
    )));
    await t.tap(find.byType(JalaliDateField));
    await t.pumpAndSettle();
    expect(find.text('آبان ۱۴۰۵'), findsOneWidget);
    await t.tap(find.text('۲۱'));
    await t.pumpAndSettle();
    expect(out, '2026-11-12');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
