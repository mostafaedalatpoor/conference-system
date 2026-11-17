import 'package:conference_admin/jalali.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('میلادی به شمسی و برعکس', () {
    // نوروزهای رسمی؛ ۱۴۰۳ کبیسه است و ۱۴۰۴ تا ۱۴۰۷ نیستند.
    const nowruz = {
      1399: '2020-03-20',
      1400: '2021-03-21',
      1401: '2022-03-21',
      1402: '2023-03-21',
      1403: '2024-03-20',
      1404: '2025-03-21',
      1405: '2026-03-21',
      1406: '2027-03-21',
      1407: '2028-03-20',
    };
    for (final e in nowruz.entries) {
      test('۱ فروردین ${e.key} = ${e.value}', () {
        expect(isoDate(JalaliDate(e.key, 1, 1).toGregorian()), e.value);
        expect(JalaliDate.fromGregorian(parseIsoDate(e.value)!), JalaliDate(e.key, 1, 1));
      });
    }

    test('نمونه‌ی طراحی: ۲۰ آبان ۱۴۰۵ = 2026-11-11، چهارشنبه', () {
      final j = JalaliDate.fromGregorian(DateTime.utc(2026, 11, 11));
      expect(j, const JalaliDate(1405, 8, 20));
      expect(j.weekdayIndex, 4);
      expect(jalaliWeekdayInitials[j.weekdayIndex], 'چ');
    });

    test('کبیسه‌ها', () {
      expect(isJalaliLeapYear(1399), isTrue);
      expect(isJalaliLeapYear(1403), isTrue);
      expect(isJalaliLeapYear(1404), isFalse);
      expect(isJalaliLeapYear(1405), isFalse);
      expect(isJalaliLeapYear(1408), isTrue);
      expect(jalaliMonthLength(1403, 12), 30);
      expect(jalaliMonthLength(1404, 12), 29);
      expect(isoDate(const JalaliDate(1403, 12, 30).toGregorian()), '2025-03-20');
      expect(isoDate(const JalaliDate(1404, 12, 29).toGregorian()), '2026-03-20');
    });

    test('مرز ماه‌ها: ۳۱ شهریور، ۱ مهر، ۳۰ بهمن', () {
      expect(isoDate(const JalaliDate(1405, 6, 31).toGregorian()), '2026-09-22');
      expect(isoDate(const JalaliDate(1405, 7, 1).toGregorian()), '2026-09-23');
      expect(isoDate(const JalaliDate(1405, 11, 30).toGregorian()), '2027-02-19');
    });

    test('رفت و برگشت هر روز از ۱۳۰۰ تا ۱۵۰۰، پشت‌سرهم و بدون جاافتادگی', () {
      var g = const JalaliDate(1300, 1, 1).toGregorian();
      for (var y = 1300; y <= 1500; y++) {
        for (var m = 1; m <= 12; m++) {
          for (var d = 1; d <= jalaliMonthLength(y, m); d++) {
            final j = JalaliDate(y, m, d);
            expect(j.toGregorian(), g, reason: '$j');
            expect(JalaliDate.fromGregorian(g), j, reason: isoDate(g));
            expect(j.weekdayIndex, (g.weekday + 1) % 7);
            g = g.add(const Duration(days: 1));
          }
        }
      }
    });

    test('ساعت و منطقه‌ی زمانی روی روز اثر ندارد', () {
      expect(JalaliDate.fromGregorian(DateTime(2026, 11, 11, 23, 59)), const JalaliDate(1405, 8, 20));
      expect(JalaliDate.fromGregorian(DateTime.utc(2026, 11, 11, 0, 1)), const JalaliDate(1405, 8, 20));
    });
  });

  group('ذخیره همیشه ISO میلادی', () {
    test('parseIsoDate فقط میلادی معتبر را می‌پذیرد', () {
      expect(parseIsoDate('2026-11-11'), DateTime.utc(2026, 11, 11));
      expect(parseIsoDate(' 2026-11-11 '), DateTime.utc(2026, 11, 11));
      expect(parseIsoDate('2026-02-30'), isNull);
      expect(parseIsoDate('1405-08-20'), isNull, reason: 'سال شمسی در قالب میلادی');
      expect(parseIsoDate('2026/11/11'), isNull);
      expect(parseIsoDate(''), isNull);
      expect(parseIsoDate(null), isNull);
    });

    test('parseDateInput شمسی و میلادی را به ISO میلادی می‌برد', () {
      expect(parseDateInput('2026-11-11'), '2026-11-11');
      expect(parseDateInput('2026/11/11'), '2026-11-11');
      expect(parseDateInput('2026-11-11T00:00:00.000'), '2026-11-11');
      expect(parseDateInput('2026-11-11 00:00:00.000'), '2026-11-11');
      expect(parseDateInput('1405/08/20'), '2026-11-11');
      expect(parseDateInput('1405-8-20'), '2026-11-11');
      expect(parseDateInput('۱۴۰۵/۸/۲۰'), '2026-11-11');
      expect(parseDateInput('١٤٠٥/٠٨/٢٠'), '2026-11-11');
      expect(parseDateInput('1403/12/30'), '2025-03-20');
    });

    test('parseDateInput تاریخ ناموجود یا ناخوانا را رد می‌کند', () {
      expect(parseDateInput('1405/12/30'), isNull, reason: '۱۴۰۵ کبیسه نیست');
      expect(parseDateInput('1405/13/01'), isNull);
      expect(parseDateInput('1405/07/31'), isNull, reason: 'مهر ۳۰ روزه است');
      expect(parseDateInput('2026-02-29'), isNull);
      expect(parseDateInput('1800-01-01'), isNull);
      expect(parseDateInput('20 آبان'), isNull);
      expect(parseDateInput(''), isNull);
      expect(parseDateInput(null), isNull);
    });

    test('isoDate صفر جلو می‌گذارد', () {
      expect(isoDate(DateTime.utc(2027, 1, 5)), '2027-01-05');
    });
  });

  group('نمایش شمسی', () {
    test('برچسب با ارقام فارسی', () {
      expect(jalaliLabel('2026-11-11'), '۲۰ آبان ۱۴۰۵');
      expect(jalaliLabel('2026-11-11', weekday: true), 'چهارشنبه ۲۰ آبان ۱۴۰۵');
      expect(jalaliLabel('2026-12-05'), '۱۴ آذر ۱۴۰۵');
    });

    test('مقدار خالی یا نامعتبر برچسب ندارد', () {
      expect(jalaliLabel(''), isNull);
      expect(jalaliLabel('1405-08-20'), isNull);
      expect(jalaliLabel('nonsense'), isNull);
    });
  });
}
