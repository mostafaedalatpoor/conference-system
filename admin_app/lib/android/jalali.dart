// تاریخ شمسی: تبدیل میلادی ↔ شمسی و تقویم ماهانه‌ی انتخاب بازه (شروع و پایان رویداد).
import 'package:flutter/material.dart';

import '../normalize.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';

const jalaliMonths = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];

/// (سال، ماه، روز) شمسی از تاریخ میلادی.
(int, int, int) toJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + (365 * gy) + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) + ((gy2 + 399) ~/ 400) + gd + gdm[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final int jm, jd;
  if (days < 186) {
    jm = 1 + days ~/ 31;
    jd = 1 + (days % 31);
  } else {
    jm = 7 + (days - 186) ~/ 30;
    jd = 1 + ((days - 186) % 30);
  }
  return (jy, jm, jd);
}

/// تاریخ میلادی از شمسی.
DateTime fromJalali(int jy, int jm, int jd) {
  jy += 1595;
  var days = -355668 + (365 * jy) + ((jy ~/ 33) * 8) + (((jy % 33) + 3) ~/ 4) + jd + (jm < 7 ? (jm - 1) * 31 : ((jm - 7) * 30) + 186);
  var gy = 400 * (days ~/ 146097);
  days %= 146097;
  if (days > 36524) {
    gy += 100 * (--days ~/ 36524);
    days %= 36524;
    if (days >= 365) days++;
  }
  gy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    gy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  var gd = days + 1;
  final leap = (gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0);
  final sal = [0, 31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var gm = 0;
  for (gm = 1; gm <= 12 && gd > sal[gm]; gm++) {
    gd -= sal[gm];
  }
  return DateTime(gy, gm, gd);
}

int jalaliMonthLength(int jy, int jm) {
  if (jm <= 6) return 31;
  if (jm <= 11) return 30;
  // اسفند: ۳۰ روز در سال کبیسه (اگر ۱ فروردین سال بعد ۳۰ اسفند را لازم دارد).
  final next = fromJalali(jy + 1, 1, 1);
  final last = fromJalali(jy, 12, 1);
  return next.difference(last).inDays;
}

/// «۲۰ آبان ۱۴۰۵» از «2026-11-11»؛ اگر خوانده نشد، خود متن.
String jalaliLabel(String iso, {bool year = true}) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final (y, m, dd) = toJalali(d.year, d.month, d.day);
  return faDigits('$dd ${jalaliMonths[m - 1]}${year ? ' $y' : ''}');
}

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// تقویم ماهانه‌ی شمسی برای انتخاب یک روز یا بازه. لمس اول = شروع، لمس دوم = پایان.
class JalaliRangeCalendar extends StatefulWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime? start, DateTime? end) onChanged;
  final bool range;
  const JalaliRangeCalendar({super.key, this.start, this.end, required this.onChanged, this.range = true});

  @override
  State<JalaliRangeCalendar> createState() => _JalaliRangeCalendarState();
}

class _JalaliRangeCalendarState extends State<JalaliRangeCalendar> {
  late int _y, _m;

  @override
  void initState() {
    super.initState();
    final base = widget.start ?? DateTime.now();
    final (y, m, _) = toJalali(base.year, base.month, base.day);
    _y = y;
    _m = m;
  }

  void _move(int d) => setState(() {
        _m += d;
        if (_m < 1) {
          _m = 12;
          _y--;
        } else if (_m > 12) {
          _m = 1;
          _y++;
        }
      });

  void _tap(DateTime day) {
    final s = widget.start, e = widget.end;
    if (!widget.range) return widget.onChanged(day, null);
    if (s == null || e != null || day.isBefore(s)) {
      widget.onChanged(day, null);
    } else {
      widget.onChanged(s, day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final first = fromJalali(_y, _m, 1);
    // شنبه ستون اول: weekday دارت ۶ = شنبه.
    final lead = (first.weekday + 1) % 7;
    final len = jalaliMonthLength(_y, _m);
    final today = DateTime.now();
    bool same(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;
    final s = widget.start, e = widget.end;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(tooltip: 'ماه قبل', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_right_rounded)),
          Expanded(child: Text(faDigits('${jalaliMonths[_m - 1]} $_y'), textAlign: TextAlign.center, style: nvText(context, 15, w: FontWeight.w800))),
          IconButton(tooltip: 'ماه بعد', onPressed: () => _move(1), icon: const Icon(Icons.chevron_left_rounded)),
        ]),
        Row(children: [
          for (final (i, d) in const ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'].indexed)
            Expanded(child: Text(d, textAlign: TextAlign.center, style: nvText(context, 11, w: FontWeight.w700, color: i == 6 ? c.stop : c.muted))),
        ]),
        const SizedBox(height: 4),
        for (var row = 0; row * 7 < lead + len; row++)
          Row(children: [
            for (var col = 0; col < 7; col++)
              Expanded(
                child: Builder(builder: (context) {
                  final n = row * 7 + col - lead + 1;
                  if (n < 1 || n > len) return const SizedBox(height: 40);
                  final day = fromJalali(_y, _m, n);
                  final isStart = same(s, day), isEnd = same(e, day);
                  final inside = s != null && e != null && day.isAfter(s) && day.isBefore(e);
                  final on = isStart || isEnd;
                  return Padding(
                    padding: const EdgeInsets.all(1),
                    child: Material(
                      color: on ? c.brand : (inside ? c.brand.withValues(alpha: .22) : Colors.transparent),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _tap(day),
                        child: SizedBox(
                          height: 38,
                          child: Center(
                            child: Text(
                              faDigits(n),
                              style: nvText(
                                context,
                                14,
                                w: on || inside || same(today, day) ? FontWeight.w800 : FontWeight.w500,
                                color: on ? c.onBrand : (col == 6 ? c.stop : (same(today, day) ? c.brandText : c.ink)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
          ]),
      ]),
    );
  }
}

/// خانه‌ی تاریخ (شروع یا پایان) که با لمس، تقویم را روی خودش متمرکز می‌کند.
class JalaliDateBox extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool active;
  final VoidCallback onTap;
  const JalaliDateBox({super.key, required this.label, required this.date, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: nvText(context, 14, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Material(
        color: c.field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nv.r16),
          side: active ? BorderSide(color: c.brand, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Nv.r16),
          onTap: onTap,
          child: SizedBox(
            height: Nv.field,
            child: Row(children: [
              const SizedBox(width: 12),
              Icon(Icons.calendar_month_rounded, size: 20, color: active ? c.brandText : c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(date == null ? 'انتخاب کنید' : jalaliLabel(isoDate(date!)),
                    style: nvText(context, 14, w: FontWeight.w600, color: date == null ? c.muted : c.ink)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
