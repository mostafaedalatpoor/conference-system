import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cards_pdf.dart';
import '../main.dart';
import '../theme/daftar.dart';
import '../normalize.dart';
import '../state.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final _reserveCount = TextEditingController();
  int _rev = 0;

  Future<void> _pickImage(AdminState s, bool front) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() => front ? s.template.frontImage = path : s.template.backImage = path);
    await s.save();
  }

  Future<Uint8List?> _read(String path) async {
    if (path.isEmpty) return null;
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// اندازه‌ی کارت هر بار پیش از ساخت PDF پرسیده می‌شود.
  Future<bool> _askSize(AdminState s) async {
    final w = TextEditingController(text: s.template.widthMm.toStringAsFixed(0));
    final h = TextEditingController(text: s.template.heightMm.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اندازه‌ی کارت'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اندازه‌ی نهایی کارت را از چاپخانه بپرسید (کارت ویزیت معمولاً ۸۵×۵۵ میلی‌متر).'),
          const SizedBox(height: 12),
          TextField(controller: w, decoration: const InputDecoration(labelText: 'عرض (میلی‌متر)'), keyboardType: TextInputType.number),
          TextField(controller: h, decoration: const InputDecoration(labelText: 'ارتفاع (میلی‌متر)'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ادامه')),
        ],
      ),
    );
    if (ok != true) return false;
    final wv = double.tryParse(latinDigits(w.text));
    final hv = double.tryParse(latinDigits(h.text));
    if (wv == null || hv == null || wv < 20 || hv < 20) return false;
    s.template.widthMm = wv;
    s.template.heightMm = hv;
    await s.save();
    setState(() => _rev++);
    return true;
  }

  Future<void> _saveBytes(AdminState s, String name, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'ذخیره‌ی PDF', fileName: name, type: FileType.custom, allowedExtensions: ['pdf']);
    if (path == null) return;
    await File(path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf').writeAsBytes(bytes);
    s.message = 'ذخیره شد: $path';
    s.messageIsError = false;
    s.notify();
  }

  Future<void> _generateCards(AdminState s) async {
    if (!await _askSize(s)) return;
    if (s.event?.baseUrl.isEmpty ?? true) {
      s.message = 'آدرس پایه‌ی رویداد خالی است.';
      s.messageIsError = true;
      s.notify();
      return;
    }
    final bytes = await s.run('', () async {
      final fonts = await PdfFonts.load();
      return buildCardsPdf(
        s: s,
        fonts: fonts,
        people: s.sortedPeople,
        reserves: s.reserveCards.where((r) => !r.used).toList(),
        frontImage: await _read(s.template.frontImage),
        backImage: await _read(s.template.backImage),
      );
    });
    if (bytes == null || !mounted) return;
    await _saveBytes(s, 'cards-${s.eventCode}.pdf', bytes);
    if (!(s.event?.locked ?? true)) await s.setLocked(true);
  }

  Future<void> _generateLists(AdminState s) async {
    final bytes = await s.run('', () async => buildPaperListsPdf(s: s, fonts: await PdfFonts.load()));
    if (bytes == null || !mounted) return;
    await _saveBytes(s, 'lists-${s.eventCode}.pdf', bytes);
  }

  Widget _num(String label, double value, void Function(double) on, {double width = 130}) => SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey('$label-$_rev'),
          initialValue: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
          decoration: InputDecoration(labelText: label, isDense: true),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final d = double.tryParse(latinDigits(v));
            if (d != null) setState(() => on(d));
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final t = s.template;
    final free = s.reserveCards.where((r) => !r.used).length;
    final people = s.sortedPeople;
    if (_reserveCount.text.isEmpty) {
      _reserveCount.text = '${(people.length / 10).ceil().clamp(1, 1000)}';
    }

    return PageBody(title: 'کارت‌ها', children: [
      const SectionTitle('کارت‌های رزرو (برای ثبت‌نام در محل)'),
      Text('${faDigits(s.reserveCards.length)} کارت رزرو ساخته شده؛ ${faDigits(free)} هنوز آزاد است. '
          'پیشنهاد: حدود ۱۰٪ ثبت‌نامی‌ها (${faDigits((people.length / 10).ceil())} کارت).'),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 120, child: TextField(controller: _reserveCount, decoration: const InputDecoration(labelText: 'تعداد', isDense: true))),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: s.busy
              ? null
              : () {
                  final n = int.tryParse(latinDigits(_reserveCount.text));
                  if (n != null && n > 0) s.addReserveCards(n);
                },
          child: const Text('ساخت کارت رزرو'),
        ),
      ]),
      const SectionTitle('قالب کارت'),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.image_rounded),
          label: Text(t.frontImage.isEmpty ? 'طرح روی کارت' : 'روی: ${t.frontImage.split(Platform.pathSeparator).last}'),
          onPressed: () => _pickImage(s, true),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_rounded),
          label: Text(t.backImage.isEmpty ? 'طرح پشت کارت' : 'پشت: ${t.backImage.split(Platform.pathSeparator).last}'),
          onPressed: () => _pickImage(s, false),
        ),
      ]),
      const SizedBox(height: 8),
      const Hint('طرح‌ها PNG یا JPG، با حاشیه‌ی اضافه‌ی ۳ میلی‌متر از هر طرف و ۳۰۰ DPI باشند '
          '(برای ۸۵×۵۵ میلی‌متر فایل ۹۱×۶۱ میلی‌متر، حدود ۱۰۷۵×۷۲۰ پیکسل). متن مهم دست‌کم ۴ میلی‌متر داخل لبه‌ی برش باشد.'),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _num('مرکز نام: افقی ٪', t.nameX, (v) => t.nameX = v),
        _num('مرکز نام: عمودی ٪', t.nameY, (v) => t.nameY = v),
        _num('اندازه‌ی نام (pt)', t.nameSize, (v) => t.nameSize = v),
        SizedBox(
          width: 130,
          child: TextFormField(
            initialValue: t.nameColor,
            decoration: const InputDecoration(labelText: 'رنگ نام (hex)', isDense: true),
            textDirection: TextDirection.ltr,
            onChanged: (v) => setState(() => t.nameColor = v.replaceAll('#', '').trim()),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: t.showRole, onChanged: (v) => setState(() => t.showRole = v ?? true)),
          const Text('نقش زیر نام'),
        ]),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _num('مرکز QR: افقی ٪', t.qrX, (v) => t.qrX = v),
        _num('مرکز QR: عمودی ٪', t.qrY, (v) => t.qrY = v),
        _num('اندازه‌ی QR (mm)', t.qrSizeMm, (v) => t.qrSizeMm = v),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: t.showSerial, onChanged: (v) => setState(() => t.showSerial = v ?? true)),
          const Text('شماره‌ی کارت زیر QR'),
        ]),
      ]),
      const SectionTitle('پیش‌نمایش'),
      _Preview(s: s, person: people.isEmpty ? null : people.first),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf_rounded),
          onPressed: s.busy || people.isEmpty ? null : () => _generateCards(s),
          label: Text('ساخت PDF کارت‌ها (${faDigits(people.length)} نفر + ${faDigits(free)} رزرو)'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt_rounded),
          onPressed: s.busy || people.isEmpty ? null : () => _generateLists(s),
          label: const Text('PDF لیست پشتیبان کاغذی'),
        ),
        TextButton(onPressed: () => s.save(), child: const Text('ذخیره‌ی تنظیمات قالب')),
      ]),
      const SizedBox(height: 8),
      const Hint(
        'PDF کارت‌ها برای هر کارت یک صفحه‌ی رو و پشت‌سرش یک صفحه‌ی پشت دارد (چاپ دورو)، به ترتیب الفبایی نام خانوادگی. '
        'بعد از ساخت PDF، آدرس پایه قفل می‌شود تا لینک QR کارت‌های چاپ‌شده عوض نشود.',
      ),
    ]);
  }
}

/// پیش‌نمایش تقریبی جای نام و QR روی کارت.
class _Preview extends StatelessWidget {
  final AdminState s;
  final Person? person;
  const _Preview({required this.s, required this.person});

  Widget _side(String imagePath, List<Widget> overlay) {
    final t = s.template;
    return SizedBox(
      width: 340,
      child: AspectRatio(
        aspectRatio: t.widthMm / t.heightMm,
        child: LayoutBuilder(builder: (context, c) {
          return Container(
            decoration: BoxDecoration(border: Border.all(color: DaftarColors.of(context).lineStrong), color: Colors.white),
            child: Stack(children: [
              if (imagePath.isNotEmpty && File(imagePath).existsSync())
                Positioned.fill(child: Image.file(File(imagePath), fit: BoxFit.cover)),
              ...overlay.map((w) => w is _At ? w.build2(c.biggest) : w),
            ]),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    Color color;
    try {
      color = Color(int.parse('FF${t.nameColor}', radix: 16));
    } catch (_) {
      color = const Color(0xFF10141A);
    }
    final scale = 340 / (t.widthMm * 72 / 25.4); // pt → پیکسل پیش‌نمایش
    return Wrap(spacing: 16, runSpacing: 16, children: [
      _side(t.frontImage, [
        _At(t.nameX, t.nameY, Text(person?.displayName ?? 'نام نمونه',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: t.nameSize * scale, fontWeight: FontWeight.w800, color: color, letterSpacing: 0))),
      ]),
      _side(t.backImage, [
        _At(t.qrX, t.qrY, Container(
          width: 340 * t.qrSizeMm / t.widthMm,
          height: 340 * t.qrSizeMm / t.widthMm,
          color: Colors.white,
          child: const FittedBox(child: Icon(Icons.qr_code_2_rounded)),
        )),
      ]),
    ]);
  }
}

class _At extends StatelessWidget {
  final double xPct;
  final double yPct;
  final Widget child;
  const _At(this.xPct, this.yPct, this.child);

  Widget build2(Size size) => Positioned(
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
        child: Align(alignment: Alignment(xPct / 50 - 1, yPct / 50 - 1), child: child),
      );

  @override
  Widget build(BuildContext context) => child;
}
