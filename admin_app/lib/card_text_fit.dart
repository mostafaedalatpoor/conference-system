// اندازه‌گیری متن کارت با همان فونت‌ها (برای کوچک‌شدن خودکار، پیش‌نمایش و بررسی پیش از چاپ).

import 'package:flutter/widgets.dart';

import 'card_design.dart';

const cardLineHeight = 1.35;
const _ptPerMm = 72 / 25.4;

FontWeight _weight(int w) => switch (w) {
      >= 800 => FontWeight.w800,
      >= 700 => FontWeight.w700,
      >= 600 => FontWeight.w600,
      _ => FontWeight.w400,
    };

/// سبک متن Flutter برای یک فونت کارت؛ اندازه بر حسب pt (در پیش‌نمایش در مقیاس ضرب می‌شود).
TextStyle cardTextStyle(String font, double size, {Color? color}) {
  final b = builtinFonts[font];
  return TextStyle(
    fontFamily: b != null ? 'Vazirmatn' : customFontFamily(font),
    fontWeight: b != null ? _weight(b.$2) : FontWeight.w400,
    fontSize: size,
    height: cardLineHeight,
    letterSpacing: 0,
    color: color,
  );
}

TextAlign cardTextAlign(String a) => switch (a) {
      'right' => TextAlign.right,
      'left' => TextAlign.left,
      _ => TextAlign.center,
    };

/// بزرگ‌ترین اندازه از [CardText.size] تا [CardText.minSize] (گام نیم pt) که متن در عرض کادر و تعداد خط جا شود.
/// خروجی: (اندازه، جا شد؟). اگر حتی با کمینه جا نشود، کمینه و false.
(double, bool) fitCardText(String text, CardText t) {
  final widthPt = t.widthMm * _ptPerMm;
  for (var sz = t.size; sz >= t.minSize - 1e-6; sz -= 0.5) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: cardTextStyle(t.font, sz)),
      textDirection: TextDirection.rtl,
      textAlign: cardTextAlign(t.align),
      maxLines: t.maxLines,
    )..layout(maxWidth: widthPt);
    final fits = !tp.didExceedMaxLines && tp.width <= widthPt + 0.01;
    tp.dispose();
    if (fits) return (sz, true);
  }
  return (t.minSize < t.size ? t.minSize : t.size, false);
}
