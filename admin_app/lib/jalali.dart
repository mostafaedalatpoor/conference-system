// تقویم شمسی، فقط برای نمایش و انتخاب تاریخ.
// ذخیره و تبادل با سرور همیشه ISO میلادی است (YYYY-MM-DD)؛ هیچ تاریخ شمسی‌ای به سرور نمی‌رود.
// کبیسه‌ها با جدول نقطه‌های شکست (Borkowski)، همان روش jalaali-js، حساب می‌شوند.
import 'normalize.dart';

const jalaliMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', //
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// روزهای هفته از شنبه (اندیس ۰) تا جمعه (اندیس ۶).
const jalaliWeekdays = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه'];
const jalaliWeekdayInitials = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

/// بازه‌ی سال میلادی که سرور می‌پذیرد (cd_valid_date در افزونه). سال کوچک‌تر یعنی تاریخ شمسی به‌اشتباه.
const minGregorianYear = 1900;
const maxGregorianYear = 2199;

/// بازه‌ی سال شمسی که در ورودی متنی (اکسل) شناخته می‌شود.
const minJalaliInputYear = 1300;
const maxJalaliInputYear = 1500;

const _breaks = [
  -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, //
  1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
];

/// روز ۱ فروردین سال شمسی [jy] به میلادی (UTC، ساعت صفر).
DateTime _nowruz(int jy) {
  if (jy < 1 || jy >= _breaks.last) throw RangeError.range(jy, 1, _breaks.last - 1, 'jy');
  final gy = jy + 621;
  var leapJ = -14;
  var jp = _breaks.first;
  var jump = 0;
  for (var i = 1; i < _breaks.length; i++) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    leapJ += jump ~/ 33 * 8 + jump.remainder(33) ~/ 4;
    jp = jm;
  }
  final n = jy - jp;
  leapJ += n ~/ 33 * 8 + (n.remainder(33) + 3) ~/ 4;
  if (jump.remainder(33) == 4 && jump - n == 4) leapJ += 1;
  final leapG = gy ~/ 4 - (gy ~/ 100 + 1) * 3 ~/ 4 - 150;
  return DateTime.utc(gy, 3, 20 + leapJ - leapG);
}

bool isJalaliLeapYear(int jy) => _nowruz(jy + 1).difference(_nowruz(jy)).inDays == 366;

int jalaliMonthLength(int jy, int jm) => jm <= 6
    ? 31
    : jm <= 11
        ? 30
        : (isJalaliLeapYear(jy) ? 30 : 29);

class JalaliDate implements Comparable<JalaliDate> {
  final int year, month, day;
  const JalaliDate(this.year, this.month, this.day);

  /// فقط سال، ماه و روز [g] خوانده می‌شود؛ ساعت و منطقه‌ی زمانی اثری ندارد.
  factory JalaliDate.fromGregorian(DateTime g) {
    final d = DateTime.utc(g.year, g.month, g.day);
    var jy = d.year - 621;
    var start = _nowruz(jy);
    if (d.isBefore(start)) start = _nowruz(--jy);
    var k = d.difference(start).inDays;
    if (k < 186) return JalaliDate(jy, 1 + k ~/ 31, 1 + k % 31);
    k -= 186;
    return JalaliDate(jy, 7 + k ~/ 30, 1 + k % 30);
  }

  static bool isValid(int y, int m, int d) =>
      y >= 1 && y < _breaks.last && m >= 1 && m <= 12 && d >= 1 && d <= jalaliMonthLength(y, m);

  /// همان روز به میلادی (UTC، ساعت صفر).
  DateTime toGregorian() {
    final offset = month <= 7 ? (month - 1) * 31 : 186 + (month - 7) * 30;
    return _nowruz(year).add(Duration(days: offset + day - 1));
  }

  /// ۰ = شنبه … ۶ = جمعه.
  int get weekdayIndex => (toGregorian().weekday + 1) % 7;

  /// «۲۰ آبان ۱۴۰۵»
  String format({bool weekday = false}) =>
      '${weekday ? '${jalaliWeekdays[weekdayIndex]} ' : ''}${faDigits(day)} ${jalaliMonths[month - 1]} ${faDigits(year)}';

  @override
  int compareTo(JalaliDate o) => year != o.year
      ? year - o.year
      : month != o.month
          ? month - o.month
          : day - o.day;

  @override
  bool operator ==(Object o) => o is JalaliDate && o.year == year && o.month == month && o.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year/$month/$day';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// شکل ذخیره: YYYY-MM-DD میلادی.
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

final _isoRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// ISO میلادی ذخیره‌شده به DateTime (UTC، ساعت صفر). خالی، روز ناموجود (2026-02-30)
/// یا سال بیرون از بازه‌ی سرور (مثل 1405-08-20 که شمسی بوده) null می‌دهد.
DateTime? parseIsoDate(String? s) {
  final m = _isoRe.firstMatch((s ?? '').trim());
  if (m == null) return null;
  return _gregorian(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

DateTime? _gregorian(int y, int m, int d) {
  if (y < minGregorianYear || y > maxGregorianYear || m < 1 || m > 12 || d < 1) return null;
  final g = DateTime.utc(y, m, d);
  return g.month == m && g.day == d ? g : null;
}

final _inputRe = RegExp(r'^(\d{4})\s*[-/.٫]\s*(\d{1,2})\s*[-/.٫]\s*(\d{1,2})(?:[T ].*)?$');

/// تاریخ نوشته‌شده (خانه‌ی اکسل یا متن) به ISO میلادی، یا null اگر خوانا نیست.
/// شمسی (۱۴۰۵/۸/۲۰، 1405-08-20) و میلادی (2026-11-11، 2026/11/11، 2026-11-11T00:00:00) هر دو پذیرفته می‌شوند؛
/// سال ۱۳۰۰ تا ۱۵۰۰ شمسی است.
String? parseDateInput(String? raw) {
  final m = _inputRe.firstMatch(latinDigits((raw ?? '').trim()));
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (y >= minJalaliInputYear && y <= maxJalaliInputYear) {
    return JalaliDate.isValid(y, mo, d) ? isoDate(JalaliDate(y, mo, d).toGregorian()) : null;
  }
  final g = _gregorian(y, mo, d);
  return g == null ? null : isoDate(g);
}

/// ISO میلادی ذخیره‌شده به برچسب شمسی: «۲۰ آبان ۱۴۰۵» (با [weekday]: «چهارشنبه ۲۰ آبان ۱۴۰۵»).
/// خالی یا نامعتبر null می‌دهد.
String? jalaliLabel(String? iso, {bool weekday = false}) {
  final g = parseIsoDate(iso);
  return g == null ? null : JalaliDate.fromGregorian(g).format(weekday: weekday);
}
