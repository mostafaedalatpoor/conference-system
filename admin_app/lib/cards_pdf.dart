import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'brand.dart';
import 'normalize.dart';
import 'sheet_layout.dart';
import 'state.dart';

class PdfFonts {
  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font bold;
  final pw.Font extraBold;
  PdfFonts(this.regular, this.semiBold, this.bold, this.extraBold);

  static Future<PdfFonts> load() async {
    Future<pw.Font> f(String w) async => pw.Font.ttf(await rootBundle.load('assets/fonts/Vazirmatn-$w.ttf'));
    return PdfFonts(await f('Regular'), await f('SemiBold'), await f('Bold'), await f('ExtraBold'));
  }
}

/// رنگ متن کارت چاپی (ink سامانه‌ی طراحی).
const _cardInk = PdfColor.fromInt(0xFF10141A);

/// یک کارت برای چاپ: متن رو، و محتوای پشت.
class _CardJob {
  final String? name;
  final String? subtitle;
  final String qrData;
  final String serialLabel;
  final String hint;
  _CardJob(this.name, this.subtitle, this.qrData, this.serialLabel, this.hint);
}

/// کارت‌ها را برای [AdminState.template] جا می‌دهد؛ null یعنی در بوم انتخاب‌شده جا نمی‌شود.
SheetLayout? sheetLayoutFor(AdminState s) {
  final t = s.template;
  return computeSheetLayout(
    sheetW: t.sheetW,
    sheetH: t.sheetH,
    margin: t.sheetMargin,
    cardW: t.widthMm,
    cardH: t.heightMm,
    autoRotate: t.autoRotate,
  );
}

/// PDF چاپخانه. دو حالت:
/// - هر کارت یک صفحه: صفحه‌ی رو (طرح + نام) و بعدش صفحه‌ی پشت (طرح + QR).
/// - چیدن روی بوم (A4 و…): چند کارت کنار هم روی هر برگ و بعد از آن برگِ پشت‌ها با جای آینه‌شده،
///   تا بعد از چاپ دورو و برش، پشتِ هر کارت پشت همان کارت و هم‌جهت با آن باشد.
/// کارت‌های رزرو در انتها می‌آیند، بدون نام.
Future<Uint8List> buildCardsPdf({
  required AdminState s,
  required PdfFonts fonts,
  required List<Person> people,
  required List<ReserveCard> reserves,
  Uint8List? frontImage,
  Uint8List? backImage,
}) async {
  final t = s.template;
  final w = t.widthMm * PdfPageFormat.mm;
  final h = t.heightMm * PdfPageFormat.mm;
  final front = frontImage == null ? null : pw.MemoryImage(frontImage);
  final back = backImage == null ? null : pw.MemoryImage(backImage);
  final color = PdfColor.fromHex(t.nameColor.startsWith('#') ? t.nameColor : '#${t.nameColor}');

  // سازنده فقط در مشخصات فایل می‌آید، نه روی کارت.
  final doc = pw.Document(
    title: 'کارت‌های ${s.event?.name ?? ''}',
    creator: '$productLatin $appVersion',
    producer: '$productLatin — NewVisionteam ($makerWebsite)',
  );

  pw.Widget bg(pw.MemoryImage? img) =>
      img == null ? pw.Container(color: PdfColors.white) : pw.Image(img, fit: pw.BoxFit.cover, width: w, height: h);

  /// متن وسط‌چین با مرکز (cx, cy) بر حسب درصد.
  pw.Widget centered(double cxPct, double cyPct, double boxH, pw.Widget child) {
    final cx = w * cxPct / 100;
    final cy = h * cyPct / 100;
    final half = [cx, w - cx].reduce((a, b) => a < b ? a : b);
    return pw.Positioned(
      left: cx - half,
      top: cy - boxH / 2,
      child: pw.SizedBox(width: half * 2, height: boxH, child: pw.Center(child: child)),
    );
  }

  pw.Widget frontCard(_CardJob j) => pw.SizedBox(
        width: w,
        height: h,
        child: pw.ClipRect(
          child: pw.Stack(children: [
            pw.Positioned(left: 0, top: 0, right: 0, bottom: 0, child: bg(front)),
            if (j.name != null)
              centered(
                t.nameX,
                t.nameY,
                t.nameSize * 2.6 + (j.subtitle != null ? t.nameSize : 0),
                pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                  pw.Text(j.name!,
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.center,
                      maxLines: 2,
                      style: pw.TextStyle(font: fonts.extraBold, fontSize: t.nameSize, color: color)),
                  if (j.subtitle != null && j.subtitle!.isNotEmpty)
                    pw.Text(j.subtitle!,
                        textDirection: pw.TextDirection.rtl,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: fonts.semiBold, fontSize: t.nameSize * 9 / 16, color: color)),
                ]),
              ),
          ]),
        ),
      );

  pw.Widget backCard(_CardJob j) {
    final size = t.qrSizeMm * PdfPageFormat.mm;
    final cx = w * t.qrX / 100;
    final cy = h * t.qrY / 100;
    const quiet = 3 * PdfPageFormat.mm;
    return pw.SizedBox(
      width: w,
      height: h,
      child: pw.ClipRect(
        child: pw.Stack(children: [
          pw.Positioned(left: 0, top: 0, right: 0, bottom: 0, child: bg(back)),
          // QR سیاه روی سفید خالص با حاشیه‌ی سکوت حدود ۳ میلی‌متر (۴ ماژول) دورش.
          pw.Positioned(
            left: cx - size / 2 - quiet,
            top: cy - size / 2 - quiet,
            child: pw.Container(
              color: PdfColors.white,
              padding: pw.EdgeInsets.all(quiet),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: j.qrData,
                width: size,
                height: size,
                drawText: false,
              ),
            ),
          ),
          if (t.showSerial)
            pw.Positioned(
              left: cx - size,
              top: cy + size / 2 + quiet,
              child: pw.SizedBox(
                width: size * 2,
                child: pw.Text(j.serialLabel,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fonts.semiBold, fontSize: 8, color: _cardInk)),
              ),
            ),
          // خط راهنمای زیر QR: اسکن با دوربین معمولی چه می‌کند (۷pt).
          pw.Positioned(
            left: cx - size,
            top: cy + size / 2 + quiet + (t.showSerial ? 10 : 0),
            child: pw.SizedBox(
              width: size * 2,
              child: pw.Text(j.hint,
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: _cardInk)),
            ),
          ),
        ]),
      ),
    );
  }

  final jobs = <_CardJob>[
    for (final p in people)
      _CardJob(
        p.displayName,
        (t.showRole ? s.roleName(p.roleCode) : '').isNotEmpty ? s.roleName(p.roleCode) : null,
        s.qrDataFor(p),
        faDigits(p.serial ?? ''),
        s.qrHint(reserve: false),
      ),
    for (final r in reserves) _CardJob(null, null, s.qrUrl(r.token), 'R${faDigits(r.serial)}', s.qrHint(reserve: true)),
  ];

  if (!t.sheetMode) {
    final format = PdfPageFormat(w, h, marginAll: 0);
    for (final j in jobs) {
      doc.addPage(pw.Page(pageFormat: format, build: (_) => frontCard(j)));
      doc.addPage(pw.Page(pageFormat: format, build: (_) => backCard(j)));
    }
    return doc.save();
  }

  final layout = sheetLayoutFor(s);
  if (layout == null) {
    throw StateError('کارت ${faDigits(t.widthMm.toStringAsFixed(0))}×${faDigits(t.heightMm.toStringAsFixed(0))} '
        'در این بوم با این حاشیه جا نمی‌شود.');
  }
  final flip = t.duplex == 'short' ? DuplexFlip.shortEdge : DuplexFlip.longEdge;
  const mm = PdfPageFormat.mm;
  final format = PdfPageFormat(layout.pageW * mm, layout.pageH * mm, marginAll: 0);

  /// کارت را وسط خانه‌اش می‌گذارد و [deg] درجه ساعت‌گرد دور مرکز خودش می‌چرخاند.
  /// جعبه‌ی کارت همیشه اندازه‌ی خود کارت است؛ فقط محتوایش می‌چرخد و وسط خانه‌ی چرخیده می‌ماند.
  pw.Widget place(pw.Widget card, (int, int) cell, int deg) {
    final (ox, oy) = layout.cellOrigin(cell);
    final cx = (ox + layout.cellW / 2) * mm;
    final cy = (oy + layout.cellH / 2) * mm;
    return pw.Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      child: deg == 0 ? card : pw.Transform.rotate(angle: _clockwise(deg), child: card),
    );
  }

  // خط جداکننده‌ی نازک بین کارت‌ها: فقط روی رو، چون اگر چاپ دورو چند دهم میلی‌متر جابه‌جا شود
  // خط پشت با رو نمی‌خواند و خراب دیده می‌شود.
  const line = PdfColors.grey500;
  const hair = 0.3;
  List<pw.Widget> gridLines() => [
        for (var c = 0; c <= layout.cols; c++)
          pw.Positioned(
            left: (layout.originX + c * layout.cellW) * mm - hair / 2,
            top: layout.originY * mm,
            child: pw.Container(width: hair, height: layout.rows * layout.cellH * mm, color: line),
          ),
        for (var r = 0; r <= layout.rows; r++)
          pw.Positioned(
            left: layout.originX * mm,
            top: (layout.originY + r * layout.cellH) * mm - hair / 2,
            child: pw.Container(width: layout.cols * layout.cellW * mm, height: hair, color: line),
          ),
      ];

  for (var start = 0; start < jobs.length; start += layout.perSheet) {
    final chunk = jobs.sublist(start, (start + layout.perSheet).clamp(0, jobs.length));
    doc.addPage(pw.Page(
      pageFormat: format,
      build: (_) => pw.Stack(children: [
        for (var k = 0; k < chunk.length; k++) place(frontCard(chunk[k]), layout.frontCell(k), layout.frontDegrees),
        ...gridLines(),
      ]),
    ));
    doc.addPage(pw.Page(
      pageFormat: format,
      build: (_) => pw.Stack(children: [
        for (var k = 0; k < chunk.length; k++) place(backCard(chunk[k]), layout.backCell(k, flip), layout.backDegrees(flip)),
      ]),
    ));
  }
  return doc.save();
}

/// pdf: زاویه‌ی مثبت در Transform خلاف ساعت‌گرد است (در آزمون دیداری تأیید شد)؛ ما ساعت‌گرد می‌گوییم.
double _clockwise(int degrees) => -degrees * math.pi / 180;

/// لیست پشتیبان کاغذی: پذیرش الفبایی، و برای هر وعده لیست کسانی که حق دارند.
Future<Uint8List> buildPaperListsPdf({required AdminState s, required PdfFonts fonts}) async {
  final doc = pw.Document(
    title: 'لیست پشتیبان ${s.event?.name ?? ''}',
    creator: '$productLatin $appVersion',
    producer: '$productLatin — NewVisionteam ($makerWebsite)',
  );
  final people = s.sortedPeople;
  final rtl = pw.TextDirection.rtl;

  pw.Widget cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.right}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text,
            textDirection: rtl,
            textAlign: align,
            style: pw.TextStyle(font: bold ? fonts.bold : fonts.regular, fontSize: 9)),
      );

  // جدول‌های pdf چپ‌به‌راست چیده می‌شوند، پس ستون‌ها برعکس داده می‌شوند تا ستون اول سمت راست باشد.
  pw.Widget table(List<String> header, List<List<String>> rows, Map<int, pw.TableColumnWidth> widths) {
    final n = header.length;
    final rev = <int, pw.TableColumnWidth>{for (final e in widths.entries) n - 1 - e.key: e.value};
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: rev,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: header.reversed.map((h) => cell(h, bold: true)).toList(),
        ),
        for (final r in rows) pw.TableRow(children: r.reversed.map((c) => cell(c)).toList()),
      ],
    );
  }

  pw.Widget title(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(text, textDirection: rtl, style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
      );

  final theme = pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(28), textDirection: rtl);

  // پانویس هر صفحه کنار شماره‌ی صفحه: «رویدادیار · newvisionteam.ir».
  pw.Widget footer(pw.Context c) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('صفحه‌ی ${faDigits(c.pageNumber)} از ${faDigits(c.pagesCount)}',
              textDirection: rtl, style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700)),
          pw.Text('$productName · $makerWebsite',
              textDirection: rtl, style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageTheme: theme,
    footer: footer,
    build: (_) => [
      title('لیست پذیرش — ${s.event?.name ?? ''}'),
      table(
        ['ردیف', 'نام خانوادگی', 'نام', 'نوع ثبت‌نام', 'کارت', 'پذیرش'],
        [
          for (var i = 0; i < people.length; i++)
            [
              faDigits(i + 1),
              people[i].lastName,
              '${people[i].title} ${people[i].firstName}'.trim(),
              s.typeName(people[i].typeCode),
              faDigits(people[i].serial ?? ''),
              '',
            ],
        ],
        {
          0: const pw.FixedColumnWidth(30),
          4: const pw.FixedColumnWidth(40),
          5: const pw.FixedColumnWidth(45),
        },
      ),
    ],
  ));

  for (final m in s.meals) {
    final entitled = people.where((p) => m.types.contains(p.typeCode) || (p.roleCode != null && m.roles.contains(p.roleCode))).toList();
    doc.addPage(pw.MultiPage(
      pageTheme: theme,
      footer: footer,
      build: (_) => [
        title('${m.name} — ${faDigits(entitled.length)} نفر'),
        table(
          ['ردیف', 'نام خانوادگی', 'نام', 'کارت', 'تحویل'],
          [
            for (var i = 0; i < entitled.length; i++)
              [faDigits(i + 1), entitled[i].lastName, entitled[i].firstName, faDigits(entitled[i].serial ?? ''), ''],
          ],
          {
            0: const pw.FixedColumnWidth(30),
            3: const pw.FixedColumnWidth(40),
            4: const pw.FixedColumnWidth(45),
          },
        ),
      ],
    ));
  }
  return doc.save();
}
