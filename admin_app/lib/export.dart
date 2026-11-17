import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'brand.dart';
import 'cards_pdf.dart' show PdfFonts, pdfText;
import 'jalali.dart';
import 'normalize.dart';

/// خروجی فهرست حضور (گروه ۴): ستون‌ها، فیلترها و سه قالب اکسل، CSV و PDF.
/// ردیف‌ها از مسیر `/admin/events/{code}/export` افزونه می‌آیند.

/// «چه کسانی»: همان مقدار who افزونه.
const exportWho = <String, String>{
  'all': 'همه',
  'checked_in': 'پذیرش‌شده‌ها',
  'absent': 'غایب‌ها',
  'walkin': 'در محل',
  'flagged': 'مشکوک‌ها',
};

/// ستون‌های ثابت؛ ستون هر وعده با کلید `meal:کد` بعد از این‌ها می‌آید.
const exportColumns = <String, String>{
  'first_name': 'نام',
  'last_name': 'نام خانوادگی',
  'mobile': 'موبایل',
  'email': 'ایمیل',
  'organization': 'سازمان',
  'type': 'نوع',
  'role': 'نقش',
  'card': 'کارت',
  'first_checkin': 'اولین پذیرش',
  'last_checkin': 'آخرین پذیرش',
  'checkin_by': 'پذیرش توسط',
  'source': 'منبع',
};

/// ستون‌های پیش‌فرض (طراحی ۱۰-Reports).
const defaultExportColumns = [
  'first_name', 'last_name', 'mobile', 'organization', 'type', 'card', 'first_checkin', 'checkin_by', //
];

enum ExportFormat { xlsx, csv, pdf }

extension ExportFormatX on ExportFormat {
  String get ext => switch (this) { ExportFormat.xlsx => 'xlsx', ExportFormat.csv => 'csv', ExportFormat.pdf => 'pdf' };
  String get label => switch (this) { ExportFormat.xlsx => 'اکسل', ExportFormat.csv => 'CSV', ExportFormat.pdf => 'PDF' };
}

/// سلول امن برای اکسل و CSV: متنی که با = + - @ (یا تب و CR) شروع شود با ' شروع می‌شود تا فرمول اجرا نشود.
String safeCell(String v) => v.isNotEmpty && '=+-@\t\r'.contains(v[0]) ? "'$v" : v;

/// زمان ISO به «تاریخ ساعت» محلی، شمسی یا میلادی.
String exportTime(String? iso, {required bool jalali}) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (!jalali) return '${isoDate(t)} $hm';
  final j = JalaliDate.fromGregorian(t);
  return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')} $hm';
}

/// برچسب ستون، از جمله ستون وعده‌ها.
String exportColumnLabel(String key, List<Map<String, dynamic>> meals) {
  if (key.startsWith('meal:')) {
    final code = key.substring(5);
    for (final m in meals) {
      if (m['code'] == code) return '${m['name']}';
    }
    return code;
  }
  return exportColumns[key] ?? key;
}

/// جدول متنی خروجی: سرستون + ردیف‌ها. سلول‌ها هنوز «امن» نشده‌اند (هر قالب خودش می‌کند).
List<List<String>> exportTable(
  List<Map<String, dynamic>> rows,
  List<String> columns,
  List<Map<String, dynamic>> meals, {
  bool jalali = true,
}) {
  String cell(Map<String, dynamic> r, String k) {
    if (k.startsWith('meal:')) return '${(r['meals'] as Map?)?[k.substring(5)] ?? 0}';
    return switch (k) {
      'first_checkin' || 'last_checkin' => exportTime(r[k]?.toString(), jalali: jalali),
      'card' => r['card'] == null ? '' : '${r['card']}',
      'source' => switch ('${r['source']}') { 'walkin' => 'ثبت در محل', 'manual' => 'دستی', _ => 'اکسل' },
      _ => '${r[k] ?? ''}',
    };
  }

  return [
    [for (final c in columns) exportColumnLabel(c, meals)],
    for (final r in rows) [for (final c in columns) cell(r, c)],
  ];
}

/// CSV با BOM (تا اکسل فارسی را درست باز کند) و سلول‌های امن.
Uint8List toCsv(List<List<String>> table) {
  String q(String v) {
    final s = safeCell(v);
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final body = table.map((r) => r.map(q).join(',')).join('\r\n');
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('$body\r\n')]);
}

/// فایل xlsx راست‌به‌چپ با کتابخانه‌ی excel (همان که ورود اکسل استفاده می‌کند).
Uint8List toXlsx(List<List<String>> table, {String sheet = 'خروجی'}) {
  final ex = Excel.createExcel();
  final def = ex.getDefaultSheet() ?? 'Sheet1';
  ex.rename(def, sheet);
  final sh = ex[sheet];
  sh.isRTL = true;
  for (final r in table) {
    sh.appendRow([for (final c in r) TextCellValue(safeCell(c))]);
  }
  return Uint8List.fromList(ex.encode()!);
}

/// PDF جدول با فونت وزیرمتن؛ ستون اول سمت راست.
Future<Uint8List> toPdf(List<List<String>> table, {required PdfFonts fonts, required String title}) async {
  final rtl = pw.TextDirection.rtl;
  final doc = pw.Document(title: title, creator: '$productLatin $appVersion');
  final landscape = table.isNotEmpty && table.first.length > 6;
  pw.Widget cell(String t, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(pdfText(t),
            textDirection: rtl, style: pw.TextStyle(font: bold ? fonts.bold : fonts.regular, fontSize: 8)),
      );
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      textDirection: rtl,
    ),
    footer: (c) => pw.Text(pdfText('صفحه‌ی ${faDigits(c.pageNumber)} از ${faDigits(c.pagesCount)} · $productName'),
        textDirection: rtl, style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: PdfColors.grey700)),
    build: (_) => [
      pw.Text(pdfText(title), textDirection: rtl, style: pw.TextStyle(font: fonts.bold, fontSize: 13)),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        children: [
          for (var i = 0; i < table.length; i++)
            pw.TableRow(
              decoration: i == 0 ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
              children: table[i].reversed.map((c) => cell(c, bold: i == 0)).toList(),
            ),
        ],
      ),
    ],
  ));
  return doc.save();
}
