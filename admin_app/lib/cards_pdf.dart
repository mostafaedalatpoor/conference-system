import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'brand.dart';
import 'card_logic.dart';
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

/// یک کارت در PDF: فرد (با نام) یا رزرو (بدون نام)، همراه قالبش.
class CardItem {
  final Person? person;
  final ReserveCard? reserve;
  final CardTemplate template;
  const CardItem.person(Person this.person, this.template) : reserve = null;
  const CardItem.reserve(ReserveCard this.reserve, this.template) : person = null;
}

/// تصویر طرح روی و پشت، به ازای شناسه‌ی قالب.
typedef TemplateImages = Map<String, (Uint8List?, Uint8List?)>;

/// PDF چاپخانه: برای هر کارت یک صفحه‌ی رو (طرح + نام) و بعد یک صفحه‌ی پشت (طرح + QR).
/// صفحه (عرض + ۲×حاشیه‌ی برش) × (ارتفاع + ۲×حاشیه‌ی برش) است و طرح تا لبه‌ی حاشیه‌ی برش کشیده می‌شود؛
/// با علامت برش، دورش نوار باریکی برای علامت‌ها می‌آید. پیش‌نویس روی هر صفحه نوشته‌ی «پیش‌نویس» دارد.
Future<Uint8List> buildCardsPdf({
  required AdminState s,
  required PdfFonts fonts,
  required List<CardItem> items,
  required TemplateImages images,
  bool draft = false,
}) async {
  final set = s.cards;
  final g = CardPageGeometry(trimW: set.widthMm, trimH: set.heightMm, bleed: set.bleedMm, cropMarks: set.cropMarks);
  const mm = PdfPageFormat.mm;
  final format = PdfPageFormat(g.pageW * mm, g.pageH * mm, marginAll: 0);
  // اندازه و گوشه‌ی کارت (لبه‌ی برش) روی صفحه؛ جای نام و QR نسبت به همین است.
  final w = set.widthMm * mm;
  final h = set.heightMm * mm;
  final ox = g.trimLeft * mm;
  final oy = g.trimTop * mm;

  // هر تصویر یک بار در فایل جاسازی می‌شود، هر چند صفحه که از آن استفاده کنند.
  final memo = <String, (pw.MemoryImage?, pw.MemoryImage?)>{};
  (pw.MemoryImage?, pw.MemoryImage?) imagesOf(CardTemplate t) => memo.putIfAbsent(t.id, () {
        final i = images[t.id];
        return (
          i?.$1 == null ? null : pw.MemoryImage(i!.$1!),
          i?.$2 == null ? null : pw.MemoryImage(i!.$2!),
        );
      });

  // سازنده فقط در مشخصات فایل می‌آید، نه روی کارت.
  final doc = pw.Document(
    title: '${draft ? 'پیش‌نویس ' : ''}کارت‌های ${s.event?.name ?? ''}',
    creator: '$productLatin $appVersion',
    producer: '$productLatin — NewVisionteam ($makerWebsite)',
  );

  pw.Widget bg(pw.MemoryImage? img) => pw.Positioned(
        left: g.bleedLeft * mm,
        top: g.bleedTop * mm,
        child: img == null
            ? pw.Container(width: g.bleedW * mm, height: g.bleedH * mm, color: PdfColors.white)
            : pw.Image(img, fit: pw.BoxFit.cover, width: g.bleedW * mm, height: g.bleedH * mm),
      );

  // علامت برش: خط ۰٫۲۵pt مشکی، بیرون از حاشیه‌ی برش.
  final marks = [
    for (final l in g.markLines())
      l.y1 == l.y2
          ? pw.Positioned(
              left: l.x1 * mm,
              top: l.y1 * mm - 0.125,
              child: pw.Container(width: (l.x2 - l.x1) * mm, height: 0.25, color: PdfColors.black))
          : pw.Positioned(
              left: l.x1 * mm - 0.125,
              top: l.y1 * mm,
              child: pw.Container(width: 0.25, height: (l.y2 - l.y1) * mm, color: PdfColors.black)),
  ];

  final watermark = pw.Positioned(
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
    child: pw.Padding(
      padding: pw.EdgeInsets.all(w / 12),
      child: pw.Opacity(
        opacity: 0.35,
        child: pw.Watermark(
          angle: 0.5,
          // نیم‌فاصله در PDF درست نقش نمی‌بندد، پس اینجا فاصله‌ی معمولی.
          child: pw.Text('پیش نویس · برای چاپ نیست',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fonts.extraBold, color: PdfColors.red)),
        ),
      ),
    ),
  );

  pw.Page page(pw.MemoryImage? img, List<pw.Widget> content) => pw.Page(
        pageFormat: format,
        build: (_) => pw.Stack(children: [
          bg(img),
          ...content,
          ...marks,
          if (draft) watermark,
        ]),
      );

  /// متن وسط‌چین با مرکز (cx, cy) بر حسب درصد کارت.
  pw.Widget centered(double cxPct, double cyPct, double boxH, pw.Widget child) {
    final cx = w * cxPct / 100;
    final cy = h * cyPct / 100;
    final half = [cx, w - cx].reduce((a, b) => a < b ? a : b);
    return pw.Positioned(
      left: ox + cx - half,
      top: oy + cy - boxH / 2,
      child: pw.SizedBox(width: half * 2, height: boxH, child: pw.Center(child: child)),
    );
  }

  void frontPage(CardTemplate t, String? name, String? subtitle) {
    final color = PdfColor.fromHex('#${normalizeHex(t.nameColor) ?? '10141A'}');
    doc.addPage(page(imagesOf(t).$1, [
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
    ]));
  }

  void backPage(CardTemplate t, String qrData, String serialLabel, String hint) {
    final size = t.qrSizeMm * mm;
    final cx = ox + w * t.qrX / 100;
    final cy = oy + h * t.qrY / 100;
    const quiet = 3 * mm;
    doc.addPage(page(imagesOf(t).$2, [
      // QR سیاه روی سفید خالص با حاشیه‌ی سکوت حدود ۳ میلی‌متر (۴ ماژول) دورش.
      pw.Positioned(
        left: cx - size / 2 - quiet,
        top: cy - size / 2 - quiet,
        child: pw.Container(
          color: PdfColors.white,
          padding: pw.EdgeInsets.all(quiet),
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
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
            child: pw.Text(serialLabel,
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
          child: pw.Text(hint,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: _cardInk)),
        ),
      ),
    ]));
  }

  for (final it in items) {
    final t = it.template;
    final p = it.person;
    if (p != null) {
      final role = t.showRole ? s.roleName(p.roleCode) : '';
      frontPage(t, p.displayName, role.isNotEmpty ? role : null);
      backPage(t, s.qrDataFor(p), faDigits(p.serial ?? ''), s.qrHint(reserve: false));
    } else {
      final r = it.reserve!;
      frontPage(t, null, null);
      backPage(t, s.qrUrl(r.token), 'R${faDigits(r.serial)}', s.qrHint(reserve: true));
    }
  }
  return doc.save();
}

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
