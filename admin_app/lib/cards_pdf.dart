import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'normalize.dart';
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

/// PDF چاپخانه: برای هر کارت یک صفحه‌ی رو (طرح + نام) و بعد یک صفحه‌ی پشت (طرح + QR).
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
  final format = PdfPageFormat(w, h, marginAll: 0);
  final front = frontImage == null ? null : pw.MemoryImage(frontImage);
  final back = backImage == null ? null : pw.MemoryImage(backImage);
  final color = PdfColor.fromHex(t.nameColor.startsWith('#') ? t.nameColor : '#${t.nameColor}');

  final doc = pw.Document(title: 'کارت‌های ${s.event?.name ?? ''}');

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

  void frontPage(String? name, String? subtitle) {
    doc.addPage(pw.Page(
      pageFormat: format,
      build: (_) => pw.Stack(children: [
        pw.Positioned(left: 0, top: 0, right: 0, bottom: 0, child: bg(front)),
        if (name != null)
          centered(
            t.nameX,
            t.nameY,
            t.nameSize * 2.6 + (subtitle != null ? t.nameSize : 0),
            pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
              pw.Text(name,
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  style: pw.TextStyle(font: fonts.extraBold, fontSize: t.nameSize, color: color)),
              if (subtitle != null && subtitle.isNotEmpty)
                pw.Text(subtitle,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fonts.semiBold, fontSize: t.nameSize * 9 / 16, color: color)),
            ]),
          ),
      ]),
    ));
  }

  void backPage(String token, String serialLabel) {
    final size = t.qrSizeMm * PdfPageFormat.mm;
    final cx = w * t.qrX / 100;
    final cy = h * t.qrY / 100;
    doc.addPage(pw.Page(
      pageFormat: format,
      build: (_) => pw.Stack(children: [
        pw.Positioned(left: 0, top: 0, right: 0, bottom: 0, child: bg(back)),
        pw.Positioned(
          left: cx - size / 2,
          top: cy - size / 2,
          child: pw.Container(
            color: PdfColors.white,
            padding: pw.EdgeInsets.all(size * 0.06),
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: s.qrUrl(token),
              width: size * 0.88,
              height: size * 0.88,
              drawText: false,
            ),
          ),
        ),
        if (t.showSerial)
          pw.Positioned(
            left: cx - size,
            top: cy + size / 2 + 2,
            child: pw.SizedBox(
              width: size * 2,
              child: pw.Text(serialLabel,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fonts.semiBold, fontSize: 8, color: _cardInk)),
            ),
          ),
      ]),
    ));
  }

  for (final p in people) {
    final role = t.showRole ? s.roleName(p.roleCode) : '';
    frontPage(p.displayName, role.isNotEmpty ? role : null);
    backPage(p.token!, faDigits(p.serial ?? ''));
  }
  for (final r in reserves) {
    frontPage(null, null);
    backPage(r.token, 'R${faDigits(r.serial)}');
  }
  return doc.save();
}

/// لیست پشتیبان کاغذی: پذیرش الفبایی، و برای هر وعده لیست کسانی که حق دارند.
Future<Uint8List> buildPaperListsPdf({required AdminState s, required PdfFonts fonts}) async {
  final doc = pw.Document(title: 'لیست پشتیبان ${s.event?.name ?? ''}');
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

  doc.addPage(pw.MultiPage(
    pageTheme: theme,
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
