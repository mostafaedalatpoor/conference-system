// اجزای ظاهر تازه‌ی اندروید (همان اپ نیروها): سربرگ خمیده، نشانگر همگام‌سازی روی سربرگ، ناوبری شناور،
// اعلان نرم، شیت پایین، فیلد، پلاک دسته و کارت.
import 'package:flutter/material.dart';

import '../normalize.dart';
import 'nv_theme.dart';

TextStyle nvText(BuildContext context, double size, {FontWeight w = FontWeight.w400, Color? color, double? height}) =>
    TextStyle(fontFamily: 'Vazirmatn', fontSize: size, fontWeight: w, color: color ?? NvColors.of(context).ink, height: height);

/// سربرگ رنگ برند با گوشه‌ی پایین خمیده.
class NvHeader extends StatelessWidget {
  final Widget child;
  final double bottom;
  final double radius;
  const NvHeader({super.key, required this.child, this.bottom = 20, this.radius = 32});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, bottom),
      decoration: BoxDecoration(
        color: c.brand,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: c.onBrand), child: IconTheme.merge(data: IconThemeData(color: c.onBrand), child: child)),
    );
  }
}

/// سربرگ ساده با دکمه‌ی برگشت (ثبت‌نام در محل، جستجوی نام).
class NvBackHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  const NvBackHeader({super.key, required this.title, this.subtitle, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvHeader(
      radius: 0,
      child: Row(children: [
        NvRoundIcon(
          icon: Icons.arrow_forward_rounded,
          label: 'بازگشت',
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: nvText(context, 20, w: FontWeight.w800, color: c.onBrand, height: 1.4)),
            if (subtitle != null) Text(subtitle!, style: nvText(context, 12, color: c.onBrand.withValues(alpha: .9))),
          ]),
        ),
      ]),
    );
  }
}

/// دکمه‌ی گرد نیمه‌شفاف روی سربرگ یا دوربین.
class NvRoundIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  const NvRoundIcon({super.key, required this.icon, required this.label, this.onTap, this.size = 44});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.white.withValues(alpha: .16),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: size, child: Icon(icon, size: 24, color: Colors.white)),
          ),
        ),
      );
}

/// نشانگر همگام‌سازی روی سربرگ: «ارسال شد»، «۳ در صف»، «آفلاین · ۳ در صف».
/// ناوبری شناور پایین: گزینه‌ی فعال قرص رنگی با برچسب، بقیه آیکن و برچسب کوچک.
class NvNavBar extends StatelessWidget {
  final List<(IconData, String, bool)> items; // آیکن، برچسب، نشان «نیاز به توجه»
  final int index;
  final ValueChanged<int> onTap;
  const NvNavBar({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Nv.r24),
          boxShadow: [BoxShadow(color: c.ink.withValues(alpha: .12), blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                label: items[i].$2,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Nv.r16),
                  onTap: () => onTap(i),
                  child: i == index
                      ? Container(
                          height: 48,
                          decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(Nv.r16)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(items[i].$1, size: 22, color: c.onBrand),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(items[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: nvText(context, 14, w: FontWeight.w700, color: c.onBrand)),
                            ),
                          ]),
                        )
                      : SizedBox(
                          height: 56,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Badge(
                              isLabelVisible: items[i].$3,
                              smallSize: 8,
                              backgroundColor: c.wait,
                              child: Icon(items[i].$1, size: 24, color: c.muted),
                            ),
                            const SizedBox(height: 2),
                            Text(items[i].$2, style: nvText(context, 12, w: FontWeight.w600, color: c.muted)),
                          ]),
                        ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

enum NvTone { go, wait, stop, info, neutral }

/// اعلان نرم: پس‌زمینه‌ی کم‌رنگ، آیکن پر، تیتر پررنگ و متن.
class NvBanner extends StatelessWidget {
  final NvTone tone;
  final IconData? icon;
  final String? title;
  final String text;
  final Widget? action;
  const NvBanner({super.key, required this.tone, required this.text, this.title, this.icon, this.action});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final (bg, fg, ink, ic) = switch (tone) {
      NvTone.go => (c.goSoft, c.go, c.goInk, Icons.check_circle_rounded),
      NvTone.wait => (c.waitSoft, c.wait, c.waitInk, Icons.schedule_rounded),
      NvTone.stop => (c.stopSoft, c.stop, c.stopInk, Icons.error_rounded),
      NvTone.info => (c.brandSoft, c.brandText, c.ink, Icons.info_rounded),
      NvTone.neutral => (c.field, c.muted, c.ink, Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Nv.r18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? ic, size: 26, color: fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (title != null) Text(title!, style: nvText(context, 15, w: FontWeight.w700, color: ink, height: 1.6)),
            Text(text, style: nvText(context, 14, color: ink, height: 1.6)),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ]),
        ),
      ]),
    );
  }
}

/// فیلد با برچسب بالای کادر.
class NvField extends StatelessWidget {
  final String label;
  final bool optional;
  final Widget child;
  final String? error;
  final String? helper;
  const NvField({super.key, required this.label, required this.child, this.optional = false, this.error, this.helper});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(
        TextSpan(children: [
          TextSpan(text: label),
          if (optional) TextSpan(text: ' (اختیاری)', style: TextStyle(color: c.muted, fontWeight: FontWeight.w500)),
        ]),
        style: nvText(context, 14, w: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      child,
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(Icons.error_rounded, size: 18, color: c.stop),
            const SizedBox(width: 6),
            Expanded(child: Text(error!, style: nvText(context, 13, w: FontWeight.w600, color: c.stop))),
          ]),
        )
      else if (helper != null)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(helper!, style: nvText(context, 13, color: c.muted))),
    ]);
  }
}

/// دکمه‌ی اصلی بزرگ (برند، سبز «تیک»، کهربایی «مجوز»).
class NvButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double height;
  final bool busy;
  const NvButton({super.key, required this.label, this.icon, this.onPressed, this.color, this.height = Nv.button, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return SizedBox(
      height: height,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? c.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: (color ?? c.brand).withValues(alpha: .45),
          disabledForegroundColor: Colors.white,
        ),
        onPressed: busy ? null : onPressed,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (busy)
            const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
          else if (icon != null)
            Icon(icon, size: height >= 62 ? 28 : 24),
          if (busy || icon != null) const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: nvText(context, height >= 62 ? 18 : 17, w: FontWeight.w800, color: Colors.white))),
        ]),
      ),
    );
  }
}

/// دکمه‌ی خاکستری روشن تمام‌عرض («نفر بعدی»‌ی دوم، «انصراف»).
class NvSoftButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onPressed;
  final Color? border;
  final Color? fg;
  const NvSoftButton({super.key, required this.label, this.icon, this.iconColor, this.onPressed, this.border, this.fg});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Material(
      color: border == null ? c.field : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Nv.r16),
        side: border == null ? BorderSide.none : BorderSide(color: border!, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Nv.r16),
        onTap: onPressed,
        child: SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 22, color: iconColor ?? c.brandText), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: nvText(context, 15, w: FontWeight.w700, color: fg ?? c.ink))),
          ]),
        ),
      ),
    );
  }
}

/// برچسب کوچک نوع/نقش.
class NvTag extends StatelessWidget {
  final String text;
  final bool outline;
  const NvTag(this.text, {super.key, this.outline = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : c.tag,
        borderRadius: BorderRadius.circular(8),
        border: outline ? Border.all(color: c.line) : null,
      ),
      // widthFactor: ۱ تا برچسب به اندازه‌ی متنش بماند و تمام عرض را نگیرد.
      child: Center(
        widthFactor: 1,
        child: Text(text, style: nvText(context, 13, w: FontWeight.w600, color: outline ? c.muted : c.ink)),
      ),
    );
  }
}

/// چیپ وضعیت گرد («مجاز»، «گرفته ۱۲:۴۰»، «شامل نیست»).
class NvStatusChip extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color bg, fg;
  const NvStatusChip({super.key, required this.text, required this.icon, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 4),
          Text(text, style: nvText(context, 13, w: FontWeight.w700, color: fg)),
        ]),
      );
}

/// مربع تیره‌ی حرف دسته.
class NvLetter extends StatelessWidget {
  final String letter;
  final double size;
  const NvLetter(this.letter, {super.key, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(size * .23)),
      child: Text(letter, style: nvText(context, size * .54, w: FontWeight.w800, color: c.surface, height: 1.2)),
    );
  }
}

/// ردیف «دسته‌ی ر · کارت ۲۱۳» با توضیح.
class NvPlateRow extends StatelessWidget {
  final String letter;
  final String title;
  final String hint;
  const NvPlateRow({super.key, required this.letter, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r16)),
      child: Row(children: [
        NvLetter(letter),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: nvText(context, 17, w: FontWeight.w700)),
            Text(hint, style: nvText(context, 13, color: c.muted)),
          ]),
        ),
      ]),
    );
  }
}

/// دستگیره‌ی بالای شیت.
class NvHandle extends StatelessWidget {
  const NvHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 44,
          height: 5,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(color: NvColors.of(context).line.withValues(alpha: .6), borderRadius: BorderRadius.circular(3)),
        ),
      );
}

/// شیت پایین با گوشه‌ی گرد و دستگیره؛ محتوا اسکرول می‌شود اگر بلند باشد.
Future<T?> showNvSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: NvColors.of(context).scrim,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NvHandle(),
            const SizedBox(height: 10),
            builder(c),
          ]),
        ),
      ),
    );

/// کارت سفید با گوشه‌ی گرد.
class NvCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool raised;
  const NvCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.raised = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    // Material، تا ListTile و Switch داخلش اثر لمس و رنگ درست داشته باشند.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(raised ? Nv.r22 : Nv.r18), boxShadow: raised ? Nv.raised(c) : null),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(raised ? Nv.r22 : Nv.r18),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// پیشرفت دایره‌ای «۴۴٪».
class NvRing extends StatelessWidget {
  final double value;
  const NvRing({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return SizedBox.square(
      dimension: 56,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.square(
          dimension: 56,
          child: CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 6,
            color: c.brand,
            backgroundColor: c.chip,
            strokeCap: StrokeCap.round,
          ),
        ),
        Text('${faDigits((value * 100).round())}٪', style: nvText(context, 13, w: FontWeight.w800, color: c.brandText)),
      ]),
    );
  }
}

/// حالت خالی.
class NvEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  const NvEmpty({super.key, required this.icon, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
          child: Icon(icon, size: 36, color: c.muted),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: nvText(context, 16, w: FontWeight.w700)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, textAlign: TextAlign.center, style: nvText(context, 14, color: c.muted, height: 1.6)),
        ],
      ]),
    );
  }
}

String moneyFa(int n) => '${faDigits(n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '٬'))} تومان';

/// «میز پذیرش ۱ · سینا»
