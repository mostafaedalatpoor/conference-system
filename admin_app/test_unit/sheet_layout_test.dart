import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:conference_admin/sheet_layout.dart';

/// نقطه‌ی (u, v) در قاب کارت (u راست، v پایین، میلی‌متر) را با چرخش ساعت‌گرد [deg] به صفحه می‌برد.
/// کارت داخل خانه‌اش وسط می‌نشیند و دور مرکز می‌چرخد.
(double, double) place(SheetLayout l, (int, int) cell, int deg, double u, double v) {
  final (ox, oy) = l.cellOrigin(cell);
  final cx = ox + l.cellW / 2, cy = oy + l.cellH / 2;
  final du = u - l.cardW / 2, dv = v - l.cardH / 2;
  final a = deg * math.pi / 180; // y رو به پایین: ماتریس چرخش استاندارد = ساعت‌گرد
  return (cx + du * math.cos(a) - dv * math.sin(a), cy + du * math.sin(a) + dv * math.cos(a));
}

void main() {
  test('A4 85x55: 10 cards, landscape or portrait picked by count', () {
    final l = computeSheetLayout(sheetW: 210, sheetH: 297, margin: 10, cardW: 85, cardH: 55)!;
    expect(l.perSheet, 10); // عمودی: ۲ ستون × ۵ ردیف
    expect(l.landscape, false);
    expect(l.rotated, false);
  });

  test('auto rotate only when it fits more', () {
    // کارت 100x50 روی 210x297 با حاشیه‌ی ۱۰: بدون چرخش ۱×۵=۵، با چرخش ۳×۳=۹ (50x100)
    final off = computeSheetLayout(sheetW: 210, sheetH: 297, margin: 10, cardW: 100, cardH: 50, autoRotate: false)!;
    final on = computeSheetLayout(sheetW: 210, sheetH: 297, margin: 10, cardW: 100, cardH: 50)!;
    expect(off.rotated, false);
    expect(on.perSheet >= off.perSheet, true);
    final same = computeSheetLayout(sheetW: 210, sheetH: 297, margin: 10, cardW: 85, cardH: 55)!;
    expect(same.rotated, false); // با تساوی چرخش نمی‌دهد
  });

  test('card larger than sheet does not fit', () {
    expect(computeSheetLayout(sheetW: 100, sheetH: 100, margin: 10, cardW: 120, cardH: 50), isNull);
  });

  test('custom sheet in landscape input is normalised', () {
    final l = computeSheetLayout(sheetW: 297, sheetH: 210, margin: 10, cardW: 85, cardH: 55)!;
    expect(l.perSheet, 10);
  });

  // قلب مسئله: بعد از برگشتن برگ، پشتِ هر کارت باید دقیقاً پشت همان کارت و هم‌جهت باشد.
  for (final flip in DuplexFlip.values) {
    for (final rotate in [false, true]) {
      for (final size in [(210.0, 297.0), (297.0, 210.0), (100.0, 50.0)]) {
        test('back matches front: $flip rotate=$rotate card ${size.$1}x${size.$2}', () {
          final cardW = size.$1 == 100 ? 100.0 : 85.0, cardH = size.$1 == 100 ? 50.0 : 55.0;
          final sheetW = size.$1 == 100 ? 210.0 : size.$1, sheetH = size.$1 == 100 ? 297.0 : size.$2;
          final l = computeSheetLayout(sheetW: sheetW, sheetH: sheetH, margin: 10, cardW: cardW, cardH: cardH, autoRotate: rotate)!;
          for (var i = 0; i < l.perSheet; i++) {
            final fc = l.frontCell(i), bc = l.backCell(i, flip);
            final fd = l.frontDegrees, bd = l.backDegrees(flip);
            for (final (u, v) in [(0.0, 0.0), (cardW, 0.0), (0.0, cardH), (cardW, cardH), (10.0, 5.0)]) {
              // نقطه‌ی فیزیکی کارت با مختصات قاب رو (u,v)؛ در تصویر پشتِ بالا‌راست‌خوان، همان نقطه (W−u, v) است.
              final (fx, fy) = place(l, fc, fd, u, v);
              final (bx, by) = place(l, bc, bd, cardW - u, v);
              // برگشتن برگ: نقطه‌ی (x,y) رو در صفحه‌ی پشت به آینه‌اش می‌رود.
              final (ex, ey) = l.flipsColumns(flip) ? (l.pageW - fx, fy) : (fx, l.pageH - fy);
              expect(bx, closeTo(ex, 1e-6), reason: 'i=$i u=$u v=$v');
              expect(by, closeTo(ey, 1e-6), reason: 'i=$i u=$u v=$v');
            }
          }
        });
      }
    }
  }

  test('front order is right-to-left, rows top-down', () {
    final l = computeSheetLayout(sheetW: 210, sheetH: 297, margin: 10, cardW: 85, cardH: 55)!;
    expect(l.frontCell(0), (1, 0)); // اولین کارت بالا-راست
    expect(l.frontCell(1), (0, 0));
    expect(l.frontCell(2), (1, 1));
  });
}
