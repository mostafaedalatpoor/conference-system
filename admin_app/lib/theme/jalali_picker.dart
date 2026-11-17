// انتخاب‌گر تاریخ شمسی (طراحی «۰۳ · ساخت رویداد»). فقط نمایش و انتخاب شمسی است؛
// مقدار ورودی و خروجی همه‌ی این قطعه‌ها ISO میلادی (YYYY-MM-DD) است و همان به سرور می‌رود.
import 'package:flutter/material.dart';

import '../jalali.dart';
import '../normalize.dart';
import 'firouzeh.dart';

bool _sameDay(DateTime? a, DateTime? b) =>
    a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

DateTime? _day(DateTime? d) => d == null ? null : DateTime.utc(d.year, d.month, d.day);

/// تقویم ماهانه‌ی شمسی: سرماه با پیکان ماه قبل و بعد، سرستون شنبه تا جمعه، روزها با ارقام فارسی.
/// روز انتخاب‌شده پر با رنگ برند است و بازه (روزهای رویداد) کم‌رنگ. [onPick] روز میلادی (UTC، ساعت صفر) می‌گیرد.
class JalaliMonthGrid extends StatefulWidget {
  final DateTime? selected;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  /// ماه نخست؛ پیش‌فرض ماه [selected]، بعد [rangeStart]، بعد امروز.
  final DateTime? initialMonth;
  final ValueChanged<DateTime> onPick;

  const JalaliMonthGrid({
    super.key,
    this.selected,
    this.rangeStart,
    this.rangeEnd,
    this.initialMonth,
    required this.onPick,
  });

  @override
  State<JalaliMonthGrid> createState() => _JalaliMonthGridState();
}

class _JalaliMonthGridState extends State<JalaliMonthGrid> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final j = JalaliDate.fromGregorian(widget.initialMonth ?? widget.selected ?? widget.rangeStart ?? DateTime.now());
    _year = j.year;
    _month = j.month;
  }

  void _shift(int delta) => setState(() {
        final m = _year * 12 + _month - 1 + delta;
        _year = m ~/ 12;
        _month = m % 12 + 1;
      });

  @override
  Widget build(BuildContext context) {
    final x = FirouzehColors.of(context);
    final text = Theme.of(context).textTheme;
    final first = JalaliDate(_year, _month, 1);
    final firstG = first.toGregorian();
    final lead = first.weekdayIndex;
    final len = jalaliMonthLength(_year, _month);
    final start = _day(widget.rangeStart);
    final end = _day(widget.rangeEnd) ?? start;
    final rangeFill = Color.alphaBlend(x.stamp.withValues(alpha: .25), x.sunken);
    final radius = BorderRadius.circular(FirouzehSize.radiusSm);

    Widget cell(int i) {
      if (i < lead || i >= lead + len) return const SizedBox(height: 36);
      final d = i - lead + 1;
      final g = firstG.add(Duration(days: d - 1));
      final picked = _sameDay(g, widget.selected);
      final inRange = start != null && end != null && !g.isBefore(start) && !g.isAfter(end);
      final friday = i % 7 == 6;
      return Semantics(
        button: true,
        selected: picked,
        excludeSemantics: true,
        label: JalaliDate(_year, _month, d).format(weekday: true),
        child: Material(
          color: picked
              ? x.stamp
              : inRange
                  ? rangeFill
                  : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => widget.onPick(g),
            child: SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  faDigits(d),
                  style: text.bodyMedium?.copyWith(
                    color: picked
                        ? x.onStamp
                        : friday
                            ? x.inkMuted
                            : x.ink,
                    fontWeight: picked || inRange ? FontWeight.w800 : FontWeight.w400,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final weeks = (lead + len + 6) ~/ 7;
    return Container(
      padding: const EdgeInsets.fromLTRB(FirouzehSize.space2, FirouzehSize.space1, FirouzehSize.space2, FirouzehSize.space2),
      decoration: BoxDecoration(color: x.sunken, borderRadius: BorderRadius.circular(FirouzehSize.radiusMd)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          // در راست‌به‌چپ این دو آیکن قرینه می‌شوند: «ماه قبل» سمت راست با پیکان رو به راست.
          IconButton(
            tooltip: 'ماه قبل',
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${jalaliMonths[_month - 1]} ${faDigits(_year)}',
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'ماه بعد',
            onPressed: () => _shift(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        const SizedBox(height: FirouzehSize.space1),
        ExcludeSemantics(
          child: Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  jalaliWeekdayInitials[i],
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(
                    color: i == 6 ? x.stop : x.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: FirouzehSize.space1),
        for (var w = 0; w < weeks; w++)
          Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(child: Padding(padding: const EdgeInsets.all(1), child: cell(w * 7 + c))),
          ]),
      ]),
    );
  }
}

/// تقویم شمسی در پنجره؛ با لمس یک روز بسته می‌شود و ISO میلادی آن را برمی‌گرداند (انصراف: null).
Future<String?> showJalaliDatePicker(
  BuildContext context, {
  String value = '',
  DateTime? rangeStart,
  DateTime? rangeEnd,
  String title = 'انتخاب تاریخ',
}) {
  final selected = parseIsoDate(value);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      // پنجره‌ی کوتاه ویندوز: تقویم فشرده نشود، پیمایش شود.
      scrollable: true,
      title: Text(title),
      content: SizedBox(
        width: 340,
        child: JalaliMonthGrid(
          selected: selected,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          initialMonth: selected ?? rangeStart,
          onPick: (g) => Navigator.pop(c, isoDate(g)),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('انصراف'))],
    ),
  );
}

/// فیلد تاریخ شمسی: کادر با «۲۰ آبان ۱۴۰۵» و آیکن تقویم؛ با لمس، تقویم شمسی باز می‌شود.
/// [value] و خروجی [onChanged] ISO میلادی است، یا '' برای خالی. مقدار نامعتبر قدیمی
/// (مثل 1405-08-20 که شمسی تایپ شده بود) با خطا نشان داده می‌شود تا دوباره انتخاب شود.
class JalaliDateField extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  final String? label;

  /// متن جای مقدار خالی (مثل «همه‌ی روزها» برای وعده).
  final String? emptyText;
  final bool clearable;

  /// حلقه‌ی رنگ برند، برای فیلدی که تقویمش زیر آن باز است.
  final bool active;
  final bool dense;

  /// روزهایی که در تقویم کم‌رنگ دیده می‌شوند (روزهای رویداد).
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final String? dialogTitle;

  /// اگر داده شود، به‌جای پنجره‌ی تقویم همین صدا زده می‌شود (تقویم درون‌خطی).
  final VoidCallback? onTap;

  const JalaliDateField({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.emptyText,
    this.clearable = false,
    this.active = false,
    this.dense = false,
    this.rangeStart,
    this.rangeEnd,
    this.dialogTitle,
    this.onTap,
  }) : assert(onChanged != null || onTap != null);

  Future<void> _open(BuildContext context) async {
    if (onTap != null) return onTap!();
    final v = await showJalaliDatePicker(
      context,
      value: value,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      title: dialogTitle ?? label ?? 'انتخاب تاریخ',
    );
    if (v != null) onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    final empty = value.trim().isEmpty;
    final shown = jalaliLabel(value);
    final invalid = !empty && shown == null;
    final border = theme.inputDecorationTheme.border;
    final radius = border is OutlineInputBorder ? border.borderRadius : BorderRadius.circular(FirouzehSize.radiusSm);
    final canClear = clearable && !empty && onChanged != null;

    return Semantics(
      button: true,
      label: [label, shown ?? (empty ? emptyText : value)].whereType<String>().join(': '),
      // دکمه‌ی «پاک کردن» باید برای صفحه‌خوان بماند.
      excludeSemantics: !canClear,
      child: InkWell(
        borderRadius: radius,
        onTap: () => _open(context),
        child: InputDecorator(
          isFocused: active,
          isEmpty: empty && emptyText == null,
          decoration: InputDecoration(
            labelText: label,
            isDense: dense,
            errorText: invalid ? (dense ? 'نامعتبر' : 'تاریخ نامعتبر؛ دوباره انتخاب کنید') : null,
            suffixIcon: canClear
                ? IconButton(
                    tooltip: 'پاک کردن',
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => onChanged!(''),
                  )
                : Icon(Icons.calendar_month_rounded, size: 20, color: active ? x.stamp : x.inkMuted),
            suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
          ),
          child: Text(
            shown ?? (empty ? emptyText ?? '' : value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
              color: empty ? x.inkMuted : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// شروع و پایان رویداد با یک تقویم درون‌خطی زیر دو فیلد. فیلد فعال حلقه‌ی رنگ برند دارد،
/// روزِ فیلد فعال پر و بازه تا پایان کم‌رنگ است. پایان هیچ‌وقت پیش از شروع نمی‌افتد.
class JalaliRangePicker extends StatefulWidget {
  final String start;
  final String end;
  final void Function(String start, String end) onChanged;
  final String startLabel;
  final String endLabel;

  const JalaliRangePicker({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
    this.startLabel = 'شروع',
    this.endLabel = 'پایان',
  });

  @override
  State<JalaliRangePicker> createState() => _JalaliRangePickerState();
}

class _JalaliRangePickerState extends State<JalaliRangePicker> {
  /// فیلدی که تقویمش باز است: ۰ شروع، ۱ پایان، null بسته.
  int? _active;

  @override
  void initState() {
    super.initState();
    if (parseIsoDate(widget.start) == null) _active = 0;
  }

  void _toggle(int which) => setState(() => _active = _active == which ? null : which);

  void _pick(DateTime g) {
    final iso = isoDate(g);
    final s = parseIsoDate(widget.start);
    final e = parseIsoDate(widget.end);
    if (_active == 0 || s == null || g.isBefore(s)) {
      // شروع تازه؛ پایانِ خالی یا پیش از آن به همان روز می‌آید.
      widget.onChanged(iso, e == null || e.isBefore(g) ? iso : widget.end);
      setState(() => _active = 1);
    } else {
      widget.onChanged(widget.start, iso);
      setState(() => _active = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = parseIsoDate(widget.start);
    final e = parseIsoDate(widget.end);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: JalaliDateField(
            label: widget.startLabel,
            value: widget.start,
            active: _active == 0,
            onTap: () => _toggle(0),
          ),
        ),
        const SizedBox(width: FirouzehSize.space3),
        Expanded(
          child: JalaliDateField(
            label: widget.endLabel,
            value: widget.end,
            active: _active == 1,
            onTap: () => _toggle(1),
          ),
        ),
      ]),
      if (_active != null) ...[
        const SizedBox(height: FirouzehSize.space2),
        JalaliMonthGrid(
          key: ValueKey(_active),
          selected: _active == 1 ? e : s,
          rangeStart: s,
          rangeEnd: e,
          initialMonth: _active == 1 ? e ?? s : s,
          onPick: _pick,
        ),
      ],
    ]);
  }
}
