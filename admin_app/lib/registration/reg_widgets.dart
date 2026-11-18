// اجزای مشترک صفحه‌های ثبت‌نام آنلاین (بوم‌های ۱۷ و ۲۰ تا ۲۹ اندروید، ۱۱ تا ۱۸ ویندوز).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../main.dart';
import '../normalize.dart';
import 'reg_api.dart';

/// پهنای ویندوز: چیدمان چندستونه.
bool regWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 1000;

/// صفحه‌ی ثبت‌نام با سربرگ خمیده، بدنه‌ی شناور و نوار پایین اختیاری.
/// صفحه‌ها همیشه در تم «فیروزه»ی اندروید (nvTheme) کشیده می‌شوند تا روی ویندوز هم همان بوم باشند.
class RegScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;
  final List<Widget> actions;
  final int? step;
  final double overlap;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  const RegScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.bottom,
    this.actions = const [],
    this.step,
    this.overlap = 30,
    this.onRefresh,
    this.maxWidth = 760,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Theme(
      data: nvTheme(b),
      child: Builder(builder: (context) {
        final c = NvColors.of(context);
        final list = ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            NvHeader(
              radius: 28,
              bottom: overlap + 24,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      if (Navigator.of(context).canPop()) ...[
                        NvRoundIcon(icon: Icons.arrow_forward_rounded, label: 'بازگشت', onTap: () => Navigator.of(context).maybePop()),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (subtitle != null)
                            Text(subtitle!, style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
                          Text(title, style: nvText(context, 20, w: FontWeight.w800, color: c.onBrand, height: 1.4)),
                        ]),
                      ),
                      ...actions,
                    ]),
                    if (step != null) ...[
                      const SizedBox(height: 14),
                      Row(children: [
                        for (var i = 1; i <= 7; i++) ...[
                          if (i > 1) const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: i <= step! ? c.onBrand : c.onBrand.withValues(alpha: .3),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ]),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, -overlap),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap(children)),
                  ),
                ),
              ),
            ),
          ],
        );
        return Scaffold(
          backgroundColor: c.bg,
          body: Column(children: [
            const MessageBar(),
            Expanded(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
          ]),
          bottomNavigationBar: bottom == null
              ? null
              : Container(
                  decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + MediaQuery.paddingOf(context).bottom),
                  child: Align(heightFactor: 1, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: bottom)),
                ),
        );
      }),
    );
  }

  static List<Widget> _gap(List<Widget> w) => [
        for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: 12), w[i]],
      ];
}

/// کارت سفید با تیتر و راهنما.
class RegCard extends StatelessWidget {
  final String? title;
  final String? hint;
  final List<Widget> children;
  final bool raised;
  final Widget? trailing;
  const RegCard({super.key, this.title, this.hint, this.children = const [], this.raised = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvCard(
      raised: raised,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Row(children: [
            Expanded(child: Text(title!, style: nvText(context, 15, w: FontWeight.w800))),
            if (trailing != null) trailing!,
          ]),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: nvText(context, 12, color: c.muted, height: 1.6)),
        ],
        for (final w in children) ...[const SizedBox(height: 10), w],
      ]),
    );
  }
}

/// انتخاب چندگزینه‌ای فشرده (بوم: .seg).
class RegSeg<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const RegSeg({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: Semantics(
              selected: o.$1 == value,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(o.$1),
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: o.$1 == value ? BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(10)) : null,
                  child: Text(o.$2,
                      textAlign: TextAlign.center,
                      style: nvText(context, 13,
                          w: o.$1 == value ? FontWeight.w800 : FontWeight.w700, color: o.$1 == value ? c.onBrand : c.muted)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// گزینه‌ی رادیویی کارت‌مانند با توضیح (بوم: .op).
class RegOption extends StatelessWidget {
  final String title;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;
  const RegOption({super.key, required this.title, this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Nv.r16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.brandSoft : null,
            borderRadius: BorderRadius.circular(Nv.r16),
            border: Border.all(color: selected ? c.brand : c.lineSoft, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: nvText(context, 14, w: FontWeight.w800)),
                if (hint != null) Text(hint!, style: nvText(context, 12, color: c.muted, height: 1.6)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? c.brandText : c.line),
          ]),
        ),
      ),
    );
  }
}

/// سطر روشن و خاموش با تیتر و راهنما.
class RegToggle extends StatelessWidget {
  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  const RegToggle({super.key, required this.title, this.hint, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return MergeSemantics(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: nvText(context, 14, w: FontWeight.w700)),
            if (hint != null) Text(hint!, style: nvText(context, 12, color: c.muted, height: 1.6)),
          ]),
        ),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// فیلد متنی که مقدار را در یک Map می‌نویسد.
class RegText extends StatefulWidget {
  final String label;
  final Map map;
  final String keyName;
  final bool ltr;
  final bool number;
  final int lines;
  final String? hint;
  final String? helper;
  final bool optional;
  final ValueChanged<String>? onChanged;
  const RegText(this.label, this.map, this.keyName,
      {super.key, this.ltr = false, this.number = false, this.lines = 1, this.hint, this.helper, this.optional = false, this.onChanged});

  @override
  State<RegText> createState() => _RegTextState();
}

class _RegTextState extends State<RegText> {
  late final _c = TextEditingController(text: _initial());

  String _initial() {
    final v = widget.map[widget.keyName];
    if (v is List) return v.join('\n');
    if (widget.number) return faDigits('${v ?? 0}');
    return '${v ?? ''}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NvField(
        label: widget.label,
        optional: widget.optional,
        helper: widget.helper,
        child: TextField(
          controller: _c,
          minLines: widget.lines,
          maxLines: widget.lines == 1 ? 1 : widget.lines + 3,
          textDirection: widget.ltr ? TextDirection.ltr : null,
          textAlign: widget.ltr ? TextAlign.left : TextAlign.start,
          keyboardType: widget.number ? TextInputType.number : (widget.lines > 1 ? TextInputType.multiline : TextInputType.text),
          decoration: InputDecoration(hintText: widget.hint),
          onChanged: (v) {
            final old = widget.map[widget.keyName];
            if (widget.number) {
              widget.map[widget.keyName] = int.tryParse(latinDigits(v).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            } else if (old is List) {
              widget.map[widget.keyName] = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            } else {
              widget.map[widget.keyName] = v;
            }
            widget.onChanged?.call(v);
          },
        ),
      );
}

/// چیپ وضعیت ثبت‌نام با آیکن و رنگ معنایی.
class RegStatusPill extends StatelessWidget {
  final Registration r;
  const RegStatusPill(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final (Color bg, Color fg, IconData? ic, String label) = r.archived
        ? (c.field, c.muted, Icons.inventory_2_outlined, 'بایگانی‌شده')
        : switch (r.status) {
            'confirmed' => (c.goSoft, c.go, Icons.check_circle_rounded, r.statusLabel),
            'pending_approval' => (c.waitSoft, c.wait, null, r.statusLabel),
            'pending_review' => (c.waitSoft, c.wait, Icons.receipt_long_rounded, r.statusLabel),
            'rejected' => (c.stopSoft, c.stop, Icons.cancel_rounded, r.statusLabel),
            'expired' => (c.field, c.muted, Icons.timer_off_rounded, r.statusLabel),
            _ => (c.field, c.muted, Icons.schedule_rounded, r.statusLabel),
          };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ic != null) ...[Icon(ic, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: nvText(context, 12, w: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// سطر کلید و مقدار (بوم: .kv).
class RegKv extends StatelessWidget {
  final String k;
  final String v;
  final bool ltr;
  final Color? color;
  final bool big;
  const RegKv(this.k, this.v, {super.key, this.ltr = false, this.color, this.big = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 34),
      child: Row(children: [
        Expanded(child: Text(k, style: nvText(context, big ? 16 : 14, color: color ?? c.muted, w: big ? FontWeight.w800 : FontWeight.w500))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(v,
              textDirection: ltr ? TextDirection.ltr : null,
              textAlign: TextAlign.left,
              style: nvText(context, big ? 18 : 14, w: FontWeight.w800, color: color)),
        ),
      ]),
    );
  }
}

/// دکمه‌ی کپی کوچک.
class RegCopy extends StatelessWidget {
  final String text;
  final String label;
  const RegCopy(this.text, {super.key, this.label = 'کپی'});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('کپی شد.')));
        },
        icon: const Icon(Icons.content_copy_rounded, size: 18),
        label: Text(label),
      );
}

/// نوار درصد.
class RegBar extends StatelessWidget {
  final double value;
  final Color? color;
  const RegBar(this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(value: value.clamp(0, 1).toDouble(), minHeight: 8, color: color ?? c.go, backgroundColor: c.field),
    );
  }
}
