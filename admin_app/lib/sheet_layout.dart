// چیدن کارت‌ها روی بوم چاپ (A4، A3، دلخواه…) برای چاپخانه، با پشتِ آینه‌شده برای چاپ دورو.
// این فایل فقط محاسبه است (بدون Flutter) تا جداگانه آزمون شود.

import 'dart:math' as math;

/// بوم‌های آماده. اندازه‌ها میلی‌متر و عمودی‌اند (عرض کمتر از ارتفاع).
const sheetPresets = <String, (double, double)>{
  'A2': (420, 594),
  'A3': (297, 420),
  'A4': (210, 297),
  'A5': (148, 210),
  'A6': (105, 148),
  'SRA3': (320, 450),
};

/// چاپ دورو: برگ از کدام لبه‌ی کاغذ برمی‌گردد؟
enum DuplexFlip { longEdge, shortEdge }

class SheetLayout {
  /// اندازه‌ی صفحه بعد از انتخاب جهت (میلی‌متر).
  final double pageW, pageH;

  /// کارت‌ها ۹۰ درجه (ساعت‌گرد) روی برگ خوابیده‌اند؟
  final bool rotated;
  final int cols, rows;

  /// اندازه‌ی هر خانه روی صفحه؛ برای کارت چرخیده، عرض و ارتفاع کارت جابه‌جاست.
  final double cellW, cellH;
  final double originX, originY;
  final double cardW, cardH;

  const SheetLayout({
    required this.pageW,
    required this.pageH,
    required this.rotated,
    required this.cols,
    required this.rows,
    required this.cellW,
    required this.cellH,
    required this.originX,
    required this.originY,
    required this.cardW,
    required this.cardH,
  });

  int get perSheet => cols * rows;
  bool get landscape => pageW > pageH;

  int sheetsFor(int cards) => cards <= 0 ? 0 : (cards + perSheet - 1) ~/ perSheet;

  /// وقتی برگ از «لبه‌ی بلند» یا «لبه‌ی کوتاه» برمی‌گردد، محور برگشت روی صفحه عمودی است؟
  /// عمودی = ستون‌ها آینه می‌شوند؛ افقی = ردیف‌ها آینه می‌شوند.
  bool flipsColumns(DuplexFlip f) {
    final portraitLike = pageH >= pageW;
    return f == DuplexFlip.longEdge ? portraitLike : !portraitLike;
  }

  /// خانه‌ی رو برای کارت شماره‌ی [i] (از صفر) در برگ؛ ردیف به ردیف از راست به چپ مثل خواندن فارسی.
  (int col, int row) frontCell(int i) {
    final r = (i % perSheet) ~/ cols;
    final c = (i % perSheet) % cols;
    return (cols - 1 - c, r);
  }

  /// خانه‌ی پشت همان کارت: آینه‌ی خانه‌ی رو حول محور برگشت.
  (int col, int row) backCell(int i, DuplexFlip f) {
    final (c, r) = frontCell(i);
    return flipsColumns(f) ? (cols - 1 - c, r) : (c, rows - 1 - r);
  }

  /// چرخش ساعت‌گرد (درجه) محتوای رو روی برگ.
  int get frontDegrees => rotated ? 90 : 0;

  /// چرخش ساعت‌گرد محتوای پشت: وقتی محور برگشت عمودی است −θ و وقتی افقی است ۱۸۰−θ.
  int backDegrees(DuplexFlip f) => flipsColumns(f) ? (360 - frontDegrees) % 360 : (180 - frontDegrees + 360) % 360;

  /// گوشه‌ی بالا‌چپ خانه روی صفحه (میلی‌متر).
  (double x, double y) cellOrigin((int col, int row) cell) => (originX + cell.$1 * cellW, originY + cell.$2 * cellH);
}

/// بهترین چیدمان: جهت برگ (عمودی یا افقی) و، اگر [autoRotate] روشن است، چرخاندن کارت را آزمایش می‌کند
/// و هر کدام که کارت بیشتری جا بدهد برمی‌دارد. با تساوی: بدون چرخش و عمودی. اگر کارت اصلاً جا نشود null.
SheetLayout? computeSheetLayout({
  required double sheetW,
  required double sheetH,
  required double margin,
  required double cardW,
  required double cardH,
  bool autoRotate = true,
}) {
  if (sheetW <= 0 || sheetH <= 0 || cardW <= 0 || cardH <= 0 || margin < 0) return null;
  final short = math.min(sheetW, sheetH);
  final long = math.max(sheetW, sheetH);
  SheetLayout? best;
  for (final (pw, ph) in [(short, long), (long, short)]) {
    for (final rotated in autoRotate ? [false, true] : [false]) {
      final cw = rotated ? cardH : cardW;
      final ch = rotated ? cardW : cardH;
      // 1e-6 تا خطای اعشاری یک ستون را از دست ندهد.
      final cols = ((pw - 2 * margin) / cw + 1e-6).floor();
      final rows = ((ph - 2 * margin) / ch + 1e-6).floor();
      if (cols < 1 || rows < 1) continue;
      final cand = SheetLayout(
        pageW: pw,
        pageH: ph,
        rotated: rotated,
        cols: cols,
        rows: rows,
        cellW: cw,
        cellH: ch,
        originX: (pw - cols * cw) / 2,
        originY: (ph - rows * ch) / 2,
        cardW: cardW,
        cardH: cardH,
      );
      if (best == null || cand.perSheet > best.perSheet) best = cand;
    }
  }
  return best;
}
