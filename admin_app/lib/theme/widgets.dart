// اجزای مشترک «دفتر»: Notice، Tag، Meter، EmptyState، Field.
// این فایل در هر دو اپ یکسان است.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'daftar.dart';

/// لحن اعلان درون صفحه.
enum NoticeTone { info, neutral, go, wait, stop }

/// اعلان درون صفحه: پس‌زمینه‌ی کم‌رنگ کامل با آیکن، بدون نوار رنگی کناری.
/// متن همیشه ink است؛ فقط آیکن رنگ لحن را دارد.
class Notice extends StatelessWidget {
  final NoticeTone tone;
  final String text;
  final String? title;
  final Widget? action;
  final IconData? icon;
  const Notice({super.key, required this.tone, required this.text, this.title, this.action, this.icon});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final (bg, fg, ic) = switch (tone) {
      NoticeTone.info => (x.stampSoft, x.stamp, Icons.info_rounded),
      NoticeTone.neutral => (x.sunken, x.ink, Icons.info_outline_rounded),
      NoticeTone.go => (x.goSoft, x.go, Icons.check_circle_rounded),
      NoticeTone.wait => (x.waitSoft, x.wait, Icons.schedule_rounded),
      NoticeTone.stop => (x.stopSoft, x.stop, Icons.error_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(DaftarSize.space3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(DaftarSize.radiusSm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? ic, color: fg, size: 22),
          const SizedBox(width: DaftarSize.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) Text(title!, style: theme.textTheme.labelLarge?.copyWith(color: x.ink)),
                SelectableText(text, style: theme.textTheme.bodyMedium?.copyWith(color: x.ink)),
                if (action != null) ...[const SizedBox(height: DaftarSize.space2), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum TagKind { plain, outline, stamp }

/// برچسب کوتاه برای نوع ثبت‌نام، نقش و نوع ارائه. گوشه‌ی ۴px، بدون رنگ معنایی.
class DaftarTag extends StatelessWidget {
  final String text;
  final TagKind kind;
  const DaftarTag(this.text, {super.key, this.kind = TagKind.plain});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final (bg, fg, border) = switch (kind) {
      TagKind.plain => (x.sunken, x.ink, null),
      TagKind.outline => (Colors.transparent, x.inkMuted, x.line),
      TagKind.stamp => (x.stampSoft, x.stamp, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space2, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

/// پیشرفت یک شمارش: «پذیرش‌شده ۱۲۴ از ۲۸۰». نوار جوهری روی sunken؛ پیشرفت خبر خوب یا بد نیست.
class Meter extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final String Function(int) format;
  final bool compact;
  const Meter({
    super.key,
    required this.label,
    required this.value,
    required this.total,
    required this.format,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final big = compact ? theme.textTheme.titleMedium : theme.textTheme.displayLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
            const Spacer(),
            Text(format(value), style: big?.copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w800)),
            Text(' از ${format(total)}',
                style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted, fontFeatures: tabularFigures)),
          ],
        ),
        const SizedBox(height: DaftarSize.space1),
        ClipRRect(
          borderRadius: BorderRadius.circular(DaftarSize.radiusPill),
          child: LinearProgressIndicator(
            value: total <= 0 ? 0 : (value / total).clamp(0.0, 1.0),
            minHeight: 4,
            color: x.action,
            backgroundColor: x.sunken,
          ),
        ),
      ],
    );
  }
}

/// حالت خالی: آیکن کم‌رنگ، یک جمله‌ی پررنگ، یک جمله‌ی راهنما و در صورت نیاز یک دکمه.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.hint, this.action});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DaftarSize.space5, DaftarSize.space6, DaftarSize.space5, DaftarSize.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: x.lineStrong),
          const SizedBox(height: DaftarSize.space3),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (hint != null) ...[
            const SizedBox(height: DaftarSize.space1),
            Text(hint!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: x.inkMuted)),
          ],
          if (action != null) ...[const SizedBox(height: DaftarSize.space4), action!],
        ],
      ),
    );
  }
}

/// فیلد با برچسب ثابت **بالای** کادر (نه برچسب شناور)، راهنما و خطای زیر همان فیلد.
class DaftarField extends StatelessWidget {
  final String label;
  final bool optional;
  final Widget child;
  final String? error;
  final String? helper;
  const DaftarField({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
    this.error,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label),
            if (optional) TextSpan(text: ' (اختیاری)', style: TextStyle(color: x.inkMuted, fontWeight: FontWeight.w400)),
          ]),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_rounded, size: 18, color: x.stop),
              const SizedBox(width: 6),
              Expanded(child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: x.stop))),
            ]),
          )
        else if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(helper!, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
          ),
      ],
    );
  }
}

/// لرزش نتیجه: مجاز = یک ضربه‌ی متوسط؛ رد = دو ضربه‌ی سنگین با ۱۲۰ms فاصله.
Future<void> verdictHaptic(bool ok) async {
  if (ok) return HapticFeedback.mediumImpact();
  await HapticFeedback.heavyImpact();
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await HapticFeedback.heavyImpact();
}
