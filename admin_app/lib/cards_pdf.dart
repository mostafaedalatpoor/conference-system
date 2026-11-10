import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'brand.dart';
import 'card_design.dart';
import 'card_text_fit.dart';
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

/// متن راست‌به‌چپ برای PDF. بسته‌ی pdf نیم‌فاصله (ZWNJ) را به‌صورت یک نشانه‌ی دیده‌شدنی می‌کشد؛
/// پس متن در هر نیم‌فاصله به چند تکه شکسته می‌شود: هر تکه جدا شکل می‌گیرد (حرف‌ها به هم نمی‌چسبند)
/// و تکه‌ها بی‌فاصله کنار هم می‌آیند، همان کاری که نیم‌فاصله باید بکند.
pw.Widget rtlText(String text, pw.TextStyle style, {pw.TextAlign textAlign = pw.TextAlign.right, int? maxLines}) =>
    pw.RichText(
      textDirection: pw.TextDirection.rtl,
      textAlign: textAlign,
      maxLines: maxLines,
      text: pw.TextSpan(style: style, children: [
        for (final part in text.split('\u200c'))
          if (part.isNotEmpty) pw.TextSpan(text: part),
      ]),
    );

/// یک کارت برای چاپ: داده‌ی متن‌ها و محتوای QR.
class _CardJob {
  final CardSubject subject;
  final String qrData;
  _CardJob(this.subject, this.qrData);
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

/// فیلدهای سامانه برای یک نفر (منبع «فیلد سامانه» در متن‌های کارت).
Map<String, String> personFields(AdminState s, Person p) => {
      'display_name': '${p.title} ${p.cardFirstName} ${p.lastName}'.trim(),
      'full_name': '${p.cardFirstName} ${p.lastName}'.trim(),
      'first_name': p.cardFirstName,
      'last_name': p.lastName,
      'title': p.title,
      'organization': p.organization,
      'role': s.roleName(p.roleCode),
      'type': s.typeName(p.typeCode),
      'serial': p.serial == null ? '' : faDigits(p.serial!),
      'country': p.country,
      'email': p.email,
      'mobile': faDigits(p.mobile),
      'qr_hint': s.template.qrEnabled ? s.qrHint(reserve: false) : '',
    };

CardSubject personSubject(AdminState s, Person p, Map<String, Map<String, String>> fileRows) => CardSubject(
      isReserve: false,
      fields: personFields(s, p),
      extra: p.extra,
      fileRow: fileRows[p.id] ?? const {},
    );

CardSubject reserveSubject(AdminState s, ReserveCard r) => CardSubject(
      isReserve: true,
      fields: {
        'serial': 'R${faDigits(r.serial)}',
        'qr_hint': s.template.qrEnabled ? s.qrHint(reserve: true) : '',
      },
    );

/// PDF چاپخانه. یک‌رو یا دورو، QR روی رو یا پشت یا بدون QR، و متن‌های کارت. دو چیدمان:
/// - هر کارت یک صفحه: صفحه‌ی رو و (در دورو) بعدش صفحه‌ی پشت.
/// - چیدن روی بوم (A4 و…): چند کارت کنار هم روی هر برگ و (در دورو) بعد از آن برگِ پشت‌ها با جای آینه‌شده،
///   تا بعد از چاپ دورو و برش، پشتِ هر کارت پشت همان کارت و هم‌جهت با آن باشد.
/// کارت‌های رزرو در انتها می‌آیند؛ متن‌های شخصی رویشان چاپ نمی‌شود.
Future<Uint8List> buildCardsPdf({
  required AdminState s,
  required PdfFonts fonts,
  required List<Person> people,
  required List<ReserveCard> reserves,
  Uint8List? frontImage,
  Uint8List? backImage,
  Map<String, Map<String, String>> fileRows = const {},
  /// تصویرهای روی کارت (لوگو): آدرس ← بایت‌ها. تصویری که اینجا نیست چاپ نمی‌شود.
  Map<String, Uint8List> assets = const {},
}) async {
  final t = s.template;
  final w = t.widthMm * PdfPageFormat.mm;
  final h = t.heightMm * PdfPageFormat.mm;
  final images = {
    'front': frontImage == null ? null : pw.MemoryImage(frontImage),
    'back': backImage == null ? null : pw.MemoryImage(backImage),
  };
  final sides = t.doubleSided ? const ['front', 'back'] : const ['front'];
  final assetImages = {for (final e in assets.entries) e.key: pw.MemoryImage(e.value)};

  // سازنده فقط در مشخصات فایل می‌آید، نه روی کارت.
  final doc = pw.Document(
    title: 'کارت‌های ${s.event?.name ?? ''}',
    creator: '$productLatin $appVersionLabel',
    producer: '$productLatin — NewVisionteam ($makerWebsite)',
  );

  final customPdfFonts = <String, pw.Font>{};
  pw.Font pdfFont(String id) {
    switch (id) {
      case 'vazir-regular':
        return fonts.regular;
      case 'vazir-semibold':
        return fonts.semiBold;
      case 'vazir-bold':
        return fonts.bold;
      case 'vazir-extrabold':
        return fonts.extraBold;
    }
    final bytes = s.fontBytes(id);
    if (bytes == null) return fonts.bold; // فونت حذف یا دانلود نشده: وزیرمتن
    return customPdfFonts.putIfAbsent(id, () => pw.Font.ttf(ByteData.sublistView(bytes)));
  }

  PdfColor color(String hex) {
    try {
      return PdfColor.fromHex('#${hex.replaceAll('#', '')}');
    } catch (_) {
      return _cardInk;
    }
  }

  pw.TextAlign align(String a) => switch (a) {
        'right' => pw.TextAlign.right,
        'left' => pw.TextAlign.left,
        _ => pw.TextAlign.center,
      };

  pw.Widget textWidget(CardText ct, String value) {
    final (size, _) = fitCardText(value, ct);
    final boxW = ct.widthMm * PdfPageFormat.mm;
    final boxH = ct.maxLines * size * cardLineHeight;
    final cx = w * ct.x / 100;
    final cy = h * ct.y / 100;
    return pw.Positioned(
      left: cx - boxW / 2,
      top: cy - boxH / 2,
      child: pw.SizedBox(
        width: boxW,
        height: boxH,
        child: pw.Align(
          alignment: pw.Alignment.center,
          child: pw.SizedBox(
            width: boxW,
            child: rtlText(
              value,
              pw.TextStyle(font: pdfFont(ct.font), fontSize: size, color: color(ct.color), lineSpacing: size * (cardLineHeight - 1.15)),
              textAlign: align(ct.align),
              maxLines: ct.maxLines,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget qrWidget(String data) {
    final size = t.qrSizeMm * PdfPageFormat.mm;
    final cx = w * t.qrX / 100;
    final cy = h * t.qrY / 100;
    const quiet = 3 * PdfPageFormat.mm;
    // QR سیاه روی سفید خالص با حاشیه‌ی سکوت حدود ۳ میلی‌متر (۴ ماژول) دورش.
    return pw.Positioned(
      left: cx - size / 2 - quiet,
      top: cy - size / 2 - quiet,
      child: pw.Container(
        color: PdfColors.white,
        padding: const pw.EdgeInsets.all(quiet),
        child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: data, width: size, height: size, drawText: false),
      ),
    );
  }

  pw.Widget shapeWidget(CardShape x) {
    const mm = PdfPageFormat.mm;
    final bw = x.widthMm * mm, bh = x.heightMm * mm;
    return pw.Positioned(
      left: w * x.x / 100 - bw / 2,
      top: h * x.y / 100 - bh / 2,
      child: pw.Container(
        width: bw,
        height: bh,
        decoration: pw.BoxDecoration(color: color(x.color), borderRadius: pw.BorderRadius.circular(x.radiusMm * mm)),
      ),
    );
  }

  pw.Widget imageWidget(CardImage x) {
    const mm = PdfPageFormat.mm;
    final img = assetImages[x.url];
    final bw = x.widthMm * mm, bh = x.heightMm * mm;
    if (img == null) return pw.SizedBox();
    return pw.Positioned(
      left: w * x.x / 100 - bw / 2,
      top: h * x.y / 100 - bh / 2,
      child: pw.SizedBox(width: bw, height: bh, child: pw.Image(img, fit: pw.BoxFit.contain)),
    );
  }

  pw.Widget card(String side, _CardJob j) {
    final img = images[side];
    return pw.SizedBox(
      width: w,
      height: h,
      child: pw.ClipRect(
        child: pw.Stack(children: [
          pw.Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: img == null ? pw.Container(color: PdfColors.white) : pw.Image(img, fit: pw.BoxFit.cover, width: w, height: h),
          ),
          for (final x in t.shapes)
            if (x.side == side && (!j.subject.isReserve || x.onReserve)) shapeWidget(x),
          for (final x in t.images)
            if (x.side == side && (!j.subject.isReserve || x.onReserve)) imageWidget(x),
          if (t.qrEnabled && t.effectiveQrSide == side) qrWidget(j.qrData),
          for (final ct in t.textsFor(side))
            if (resolveCardText(ct, j.subject) case final v?) textWidget(ct, v),
        ]),
      ),
    );
  }

  final jobs = <_CardJob>[
    for (final p in people) _CardJob(personSubject(s, p, fileRows), s.qrDataFor(p)),
    for (final r in reserves) _CardJob(reserveSubject(s, r), s.qrUrl(r.token)),
  ];

  if (!t.sheetMode) {
    final format = PdfPageFormat(w, h, marginAll: 0);
    for (final j in jobs) {
      for (final side in sides) {
        doc.addPage(pw.Page(pageFormat: format, build: (_) => card(side, j)));
      }
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
  pw.Widget place(pw.Widget c, (int, int) cell, int deg) {
    final (ox, oy) = layout.cellOrigin(cell);
    final cx = (ox + layout.cellW / 2) * mm;
    final cy = (oy + layout.cellH / 2) * mm;
    return pw.Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      child: deg == 0 ? c : pw.Transform.rotate(angle: _clockwise(deg), child: c),
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
        for (var k = 0; k < chunk.length; k++) place(card('front', chunk[k]), layout.frontCell(k), layout.frontDegrees),
        ...gridLines(),
      ]),
    ));
    if (t.doubleSided) {
      doc.addPage(pw.Page(
        pageFormat: format,
        build: (_) => pw.Stack(children: [
          for (var k = 0; k < chunk.length; k++)
            place(card('back', chunk[k]), layout.backCell(k, flip), layout.backDegrees(flip)),
        ]),
      ));
    }
  }
  return doc.save();
}

/// pdf: زاویه‌ی مثبت در Transform خلاف ساعت‌گرد است (در آزمون دیداری تأیید شد)؛ ما ساعت‌گرد می‌گوییم.
double _clockwise(int degrees) => -degrees * math.pi / 180;

/// لیست پشتیبان کاغذی: پذیرش الفبایی، و برای هر وعده لیست کسانی که حق دارند.
Future<Uint8List> buildPaperListsPdf({required AdminState s, required PdfFonts fonts}) async {
  final doc = pw.Document(
    title: 'لیست پشتیبان ${s.event?.name ?? ''}',
    creator: '$productLatin $appVersionLabel',
    producer: '$productLatin — NewVisionteam ($makerWebsite)',
  );
  final people = s.sortedPeople;
  final rtl = pw.TextDirection.rtl;

  pw.Widget cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.right}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: rtlText(text, pw.TextStyle(font: bold ? fonts.bold : fonts.regular, fontSize: 9), textAlign: align),
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
        child: rtlText(text, pw.TextStyle(font: fonts.bold, fontSize: 14)),
      );

  final theme = pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(28), textDirection: rtl);

  // پانویس هر صفحه کنار شماره‌ی صفحه: «رویدادیار · newvisionteam.ir».
  pw.Widget footer(pw.Context c) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          rtlText('صفحه‌ی ${faDigits(c.pageNumber)} از ${faDigits(c.pagesCount)}',
              pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700)),
          rtlText('$productName · $makerWebsite', pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700)),
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

/// تصویر طرح یک سمت: فایل همین دستگاه، وگرنه طرحی که روی سرور است.
Future<Uint8List?> cardDesignBytes(AdminState s, String side) async {
  final t = s.template;
  final local = side == 'front' ? t.frontImage : t.backImage;
  if (local.isNotEmpty) {
    final f = File(local);
    if (await f.exists()) return f.readAsBytes();
  }
  return s.assetBytes(side == 'front' ? t.frontImageUrl : t.backImageUrl);
}

/// همه‌ی تصویرهای روی کارت (لوگوها) از سرور.
Future<Map<String, Uint8List>> cardAssetBytes(AdminState s) async {
  final out = <String, Uint8List>{};
  for (final x in s.template.images) {
    final b = await s.assetBytes(x.url);
    if (b != null) out[x.url] = b;
  }
  return out;
}
