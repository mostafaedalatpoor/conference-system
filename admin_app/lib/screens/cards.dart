import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cards_pdf.dart';
import '../main.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import '../normalize.dart';
import '../sheet_layout.dart';
import '../state.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

/// روی موبایل فقط شیوه‌ی ذخیره‌ی PDF فرق دارد (انتخاب‌گر سیستم)؛ ساخت PDF و انتخاب تصویر طرح روی هر دو هست.
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

class _CardsScreenState extends State<CardsScreen> {
  final _reserveCount = TextEditingController();
  int _rev = 0;
  bool _longName = false;

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
    String? path;
    if (isMobilePlatform) {
      // اندروید پنجره‌ی «ذخیره در مسیر» ویندوز را ندارد؛ انتخاب‌گر سیستم خودش فایل را می‌نویسد.
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره‌ی PDF',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (path == null) return;
    } else {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره‌ی PDF',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) return;
      path = path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';
      await File(path).writeAsBytes(bytes);
    }
    s.message = 'ذخیره شد: $path';
    s.messageIsError = false;
    s.notify();
  }

  bool _checkBase(AdminState s) {
    if (s.event?.baseUrl.isEmpty ?? true) {
      s.message = 'آدرس پایه‌ی رویداد خالی است.';
      s.messageIsError = true;
      s.notify();
      return false;
    }
    return true;
  }

  /// در حالت بوم، اگر کارت در بوم جا نشود پیش از ساخت می‌گوید.
  bool _checkSheet(AdminState s) {
    if (!s.template.sheetMode || sheetLayoutFor(s) != null) return true;
    s.message = 'کارت در این بوم با این حاشیه جا نمی‌شود. بوم بزرگ‌تر یا حاشیه‌ی کمتر انتخاب کنید.';
    s.messageIsError = true;
    s.notify();
    return false;
  }

  Future<void> _generateCards(AdminState s) async {
    if (!await _askSize(s)) return;
    if (!_checkBase(s) || !_checkSheet(s)) return;
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

  /// PDF فقط کارت‌های رزرو آزاد: سبک، روی موبایل هم شدنی.
  Future<void> _generateReserves(AdminState s) async {
    if (!_checkBase(s) || !_checkSheet(s)) return;
    final bytes = await s.run('', () async {
      final fonts = await PdfFonts.load();
      return buildCardsPdf(
        s: s,
        fonts: fonts,
        people: const [],
        reserves: s.reserveCards.where((r) => !r.used).toList(),
        frontImage: await _read(s.template.frontImage),
        backImage: await _read(s.template.backImage),
      );
    });
    if (bytes == null || !mounted) return;
    await _saveBytes(s, 'reserve-cards-${s.eventCode}.pdf', bytes);
  }

  Future<void> _generateLists(AdminState s) async {
    final bytes = await s.run('', () async => buildPaperListsPdf(s: s, fonts: await PdfFonts.load()));
    if (bytes == null || !mounted) return;
    await _saveBytes(s, 'lists-${s.eventCode}.pdf', bytes);
  }

  Widget _num(String label, double value, void Function(double) on, {double width = 130, double step = 0}) {
    final field = TextFormField(
      key: ValueKey('$label-$_rev'),
      initialValue: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      onChanged: (v) {
        final d = double.tryParse(latinDigits(v));
        if (d != null) setState(() => on(d));
      },
    );
    if (step == 0) return SizedBox(width: width, child: field);
    // جابه‌جایی جزئی با گام ثابت؛ روی موبایل دقیق‌تر از کشیدن با انگشت است.
    void nudge(double d) => setState(() {
          on(double.parse((value + d).toStringAsFixed(1)));
          _rev++;
        });
    return SizedBox(
      width: width + 88,
      child: Row(children: [
        IconButton(tooltip: 'کم', onPressed: () => nudge(-step), icon: const Icon(Icons.remove_rounded)),
        Expanded(child: field),
        IconButton(tooltip: 'زیاد', onPressed: () => nudge(step), icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final t = s.template;
    final free = s.reserveCards.where((r) => !r.used).length;
    final people = s.sortedPeople;
    final locked = s.event?.locked ?? false;
    if (_reserveCount.text.isEmpty) {
      _reserveCount.text = '${(people.length / 10).ceil().clamp(1, 1000)}';
    }
    final longest = people.isEmpty
        ? null
        : people.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b);

    return PageBody(title: 'کارت‌ها', children: [
      if (locked)
        const Padding(
          padding: EdgeInsets.only(bottom: DaftarSize.space2),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'کارت‌ها چاپ شده‌اند. تغییر قالب فقط روی کارت‌های رزرو جدید اثر دارد.',
          ),
        ),
      const SectionTitle('کارت‌های رزرو (برای ثبت‌نام در محل)'),
      Text('${faDigits(s.reserveCards.length)} کارت رزرو ساخته شده؛ ${faDigits(free)} هنوز آزاد است. '
          'پیشنهاد: حدود ۱۰٪ ثبت‌نامی‌ها (${faDigits((people.length / 10).ceil())} کارت).'),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 120, child: TextField(controller: _reserveCount, decoration: const InputDecoration(labelText: 'تعداد', isDense: true))),
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
        _num('مرکز نام: افقی ٪', t.nameX, (v) => t.nameX = v, step: 1),
        _num('مرکز نام: عمودی ٪', t.nameY, (v) => t.nameY = v, step: 1),
        _num('اندازه‌ی نام (pt)', t.nameSize, (v) => t.nameSize = v, step: 0.5),
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
        _num('مرکز QR: افقی ٪', t.qrX, (v) => t.qrX = v, step: 1),
        _num('مرکز QR: عمودی ٪', t.qrY, (v) => t.qrY = v, step: 1),
        _num('اندازه‌ی QR (mm)', t.qrSizeMm, (v) => t.qrSizeMm = v, step: 0.5),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: t.showSerial, onChanged: (v) => setState(() => t.showSerial = v ?? true)),
          const Text('شماره‌ی کارت زیر QR'),
        ]),
      ]),
      if (t.qrSizeMm < s.minQrMm)
        Padding(
          padding: const EdgeInsets.only(top: DaftarSize.space2),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'QR کوچک است؛ گوشی‌های قدیمی از فاصله نمی‌خوانند. کمینه برای '
                '${s.settings.qrBehavior == 'vcard' ? 'کارت ویزیت' : 'لینک'} ${faDigits(s.minQrMm.toStringAsFixed(0))} میلی‌متر است.',
          ),
        ),
      const SectionTitle('پیش‌نمایش'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _longName,
        onChanged: longest == null ? null : (v) => setState(() => _longName = v),
        title: const Text('آزمون نام بلند'),
        subtitle: Text(longest == null ? 'هنوز کسی وارد نشده.' : 'طولانی‌ترین نام لیست: ${longest.displayName}'),
      ),
      _Preview(s: s, person: _longName ? longest : (people.isEmpty ? null : people.first)),
      const SectionTitle('چیدمان برای چاپخانه'),
      _SheetSettings(
        s: s,
        cards: people.length + free,
        onChanged: () => setState(() {}),
      ),
      const SectionTitle('بررسی پیش از چاپ'),
      _Preflight(s: s, longest: longest),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf_rounded),
          onPressed: s.busy || people.isEmpty ? null : () => _generateCards(s),
          label: Text('ساخت PDF کارت‌ها (${faDigits(people.length)} نفر + ${faDigits(free)} رزرو)'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.style_rounded),
          onPressed: s.busy || free == 0 ? null : () => _generateReserves(s),
          label: Text('PDF کارت‌های رزرو آزاد (${faDigits(free)})'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt_rounded),
          onPressed: s.busy || people.isEmpty ? null : () => _generateLists(s),
          label: const Text('PDF لیست پشتیبان کاغذی'),
        ),
        TextButton(onPressed: s.busy ? null : s.saveTemplate, child: const Text('ذخیره‌ی قالب روی سرور')),
      ]),
      const SizedBox(height: 8),
      Hint(
        t.sheetMode
            ? 'PDF کارت‌ها روی بوم چیده می‌شود: یک برگ رو و بعدش برگ پشت‌ها با جای آینه‌شده (چاپ دورو)، به ترتیب الفبایی نام خانوادگی. '
            : 'PDF کارت‌ها برای هر کارت یک صفحه‌ی رو و پشت‌سرش یک صفحه‌ی پشت دارد (چاپ دورو)، به ترتیب الفبایی نام خانوادگی. '
        'بعد از ساخت PDF، آدرس پایه قفل می‌شود تا لینک QR کارت‌های چاپ‌شده عوض نشود. '
        'قالب و تنظیم بوم روی سرور ذخیره می‌شود تا ویندوز و گوشی یک قالب ببینند؛ تصویر طرح روی همین دستگاه می‌ماند، پس روی هر دستگاه یک بار انتخابش کنید.',
      ),
    ]);
  }
}

/// بررسی پیش از چاپ: جاشدن نام‌ها در ناحیه‌ی امن، اندازه و جای QR، کیفیت تصویر طرح.
class _Preflight extends StatelessWidget {
  final AdminState s;
  final Person? longest;
  const _Preflight({required this.s, required this.longest});

  static const _safe = 4.0; // ناحیه‌ی امن، میلی‌متر
  static const _ptPerMm = 72 / 25.4;

  static final _sizes = <String, Future<(int, int)?>>{};

  // تصویر هر مسیر یک بار خوانده می‌شود، نه با هر تغییر فیلد.
  Future<(int, int)?> _imageSize(String path) => _sizes.putIfAbsent(path, () => _readSize(path));

  Future<(int, int)?> _readSize(String path) async {
    if (path.isEmpty) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    final codec = await ui.instantiateImageCodec(await f.readAsBytes());
    final frame = await codec.getNextFrame();
    return (frame.image.width, frame.image.height);
  }

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    final checks = <(bool?, String)>[]; // true خوب، false مشکل، null هشدار

    // ۱. جاشدن طولانی‌ترین نام در ناحیه‌ی امن.
    if (longest != null) {
      final cx = t.widthMm * t.nameX / 100;
      final availMm = 2 * [cx - _safe, t.widthMm - cx - _safe].reduce((a, b) => a < b ? a : b);
      final tp = TextPainter(
        text: TextSpan(
          text: longest!.displayName,
          style: TextStyle(fontFamily: 'Vazirmatn', fontSize: t.nameSize, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      final widthMm = tp.width / _ptPerMm;
      if (availMm <= 0) {
        checks.add((false, 'مرکز نام بیرون از ناحیه‌ی امن است.'));
      } else if (widthMm <= availMm) {
        checks.add((true, 'همه‌ی نام‌ها در یک خط و داخل ناحیه‌ی امن جا می‌شوند.'));
      } else if (widthMm <= availMm * 2) {
        checks.add((null, 'طولانی‌ترین نام («${longest!.displayName}») دو خطی چاپ می‌شود.'));
      } else {
        checks.add((false, 'طولانی‌ترین نام حتی در دو خط جا نمی‌شود؛ اندازه‌ی نام را کم کنید.'));
      }
    }

    // ۲. اندازه‌ی QR.
    checks.add(t.qrSizeMm >= s.minQrMm
        ? (true, 'اندازه‌ی QR ${faDigits(t.qrSizeMm.toStringAsFixed(0))} میلی‌متر؛ کافی است.')
        : (false, 'QR کمتر از ${faDigits(s.minQrMm.toStringAsFixed(0))} میلی‌متر است.'));

    // ۳. QR با حاشیه‌ی سکوت و خط‌های زیرش داخل ناحیه‌ی امن.
    final qx = t.widthMm * t.qrX / 100, qy = t.heightMm * t.qrY / 100, half = t.qrSizeMm / 2 + 3;
    final below = t.showSerial ? 8.0 : 4.0;
    final inside = qx - half >= _safe &&
        qx + half <= t.widthMm - _safe &&
        qy - half >= _safe &&
        qy + half + below <= t.heightMm - _safe;
    checks.add(inside
        ? (true, 'QR و حاشیه‌ی سکوتش داخل ناحیه‌ی امن است.')
        : (false, 'QR یا خط‌های زیرش از ناحیه‌ی امن بیرون زده؛ جایش یا اندازه‌اش را عوض کنید.'));

    return FutureBuilder<List<(int, int)?>>(
      future: Future.wait([_imageSize(t.frontImage), _imageSize(t.backImage)]),
      builder: (context, snap) {
        final all = [...checks];
        final sizes = snap.data;
        if (sizes != null) {
          for (final (label, size) in [('روی', sizes[0]), ('پشت', sizes[1])]) {
            if (size == null) continue;
            final dpi = size.$1 / ((t.widthMm + 6) / 25.4);
            all.add(dpi >= 290
                ? (true, 'تصویر $label: ${faDigits(dpi.round())} dpi.')
                : (dpi >= 150
                    ? (null, 'تصویر $label: ${faDigits(dpi.round())} dpi؛ برای چاپ تیز ۳۰۰ لازم است.')
                    : (false, 'تصویر $label: ${faDigits(dpi.round())} dpi؛ چاپ تار می‌شود.')));
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (ok, text) in all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  ok == true ? Icons.check_circle_rounded : (ok == null ? Icons.warning_rounded : Icons.error_rounded),
                  size: 18,
                  color: ok == true
                      ? DaftarColors.of(context).go
                      : (ok == null ? DaftarColors.of(context).wait : DaftarColors.of(context).stop),
                ),
                const SizedBox(width: DaftarSize.space2),
                Expanded(child: Text(text)),
              ]),
            ),
        ]);
      },
    );
  }
}

/// پیش‌نمایش جای نام و QR روی کارت، با خط برش و ناحیه‌ی امن ۴ میلی‌متری.
class _Preview extends StatelessWidget {
  final AdminState s;
  final Person? person;
  const _Preview({required this.s, required this.person});

  Widget _side(BuildContext context, double width, String imagePath, List<Widget> overlay) {
    final t = s.template;
    final x = DaftarColors.of(context);
    final pxPerMm = width / t.widthMm;
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: t.widthMm / t.heightMm,
        child: LayoutBuilder(builder: (context, c) {
          return Container(
            decoration: BoxDecoration(border: Border.all(color: x.lineStrong), color: Colors.white),
            child: Stack(children: [
              if (imagePath.isNotEmpty && File(imagePath).existsSync())
                Positioned.fill(child: Image.file(File(imagePath), fit: BoxFit.cover)),
              // ناحیه‌ی امن (نقطه‌چین در طراحی؛ اینجا خط نازک)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(4 * pxPerMm),
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: x.stamp.withValues(alpha: .5), width: 1)),
                  ),
                ),
              ),
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
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth < 340 ? c.maxWidth : 340.0;
      final scale = width / (t.widthMm * 72 / 25.4); // pt → پیکسل پیش‌نمایش
      final role = person == null ? '' : s.roleName(person!.roleCode);
      return Wrap(spacing: 16, runSpacing: 16, children: [
        _side(context, width, t.frontImage, [
          _At(
            t.nameX,
            t.nameY,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4 * width / t.widthMm),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(person?.displayName ?? 'نام نمونه',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(fontSize: t.nameSize * scale, fontWeight: FontWeight.w800, color: color, letterSpacing: 0)),
                if (t.showRole && role.isNotEmpty)
                  Text(role,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: t.nameSize * 9 / 16 * scale, fontWeight: FontWeight.w600, color: color)),
              ]),
            ),
          ),
        ]),
        _side(context, width, t.backImage, [
          _At(t.qrX, t.qrY, Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.all(3 * width / t.widthMm),
              color: Colors.white,
              child: SizedBox(
                width: width * t.qrSizeMm / t.widthMm,
                height: width * t.qrSizeMm / t.widthMm,
                child: const FittedBox(child: Icon(Icons.qr_code_2_rounded, color: Colors.black)),
              ),
            ),
            if (t.showSerial)
              Text('۲۱۳', style: TextStyle(fontSize: 8 * scale, color: const Color(0xFF10141A))),
            Text(s.qrHint(reserve: false), style: TextStyle(fontSize: 7 * scale, color: const Color(0xFF10141A))),
          ])),
        ]),
      ]);
    });
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


/// تنظیم بوم چاپ برای چاپخانه: اندازه، حاشیه، جهت برگشتن برگ، چرخاندن خودکار، و پیش‌نمایش برگ اول.
class _SheetSettings extends StatelessWidget {
  final AdminState s;
  final int cards;
  final VoidCallback onChanged;
  const _SheetSettings({required this.s, required this.cards, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final layout = t.sheetMode ? sheetLayoutFor(s) : null;
    void set(void Function() f) {
      f();
      s.notify();
      onChanged();
    }

    Widget num(String label, double value, void Function(double) on, {double width = 120}) => SizedBox(
          width: width,
          child: TextFormField(
            key: ValueKey('$label-${t.sheetPreset}-$value-${t.sheetMode}'),
            initialValue: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
            decoration: InputDecoration(labelText: label, isDense: true),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final d = double.tryParse(latinDigits(v));
              if (d != null && d > 0) {
                on(d);
                s.notify();
              }
            },
          ),
        );

    final presetItems = [
      for (final e in sheetPresets.entries)
        DropdownMenuItem(
          value: e.key,
          child: Text('${e.key}  (${faDigits(e.value.$1.toStringAsFixed(0))}×${faDigits(e.value.$2.toStringAsFixed(0))} میلی‌متر)'),
        ),
      const DropdownMenuItem(value: 'custom', child: Text('اندازه‌ی دلخواه')),
    ];

    final flip = t.duplex == 'short' ? DuplexFlip.shortEdge : DuplexFlip.longEdge;
    final String? summary = layout == null
        ? null
        : 'برگ ${t.sheetPreset == 'custom' ? 'دلخواه' : t.sheetPreset} ${layout.landscape ? 'افقی' : 'عمودی'}، '
            '${faDigits(layout.cols)} ستون × ${faDigits(layout.rows)} ردیف = ${faDigits(layout.perSheet)} کارت در هر برگ'
            '${layout.rotated ? '، کارت‌ها ۹۰ درجه چرخیده‌اند' : ''}. '
            '${faDigits(cards)} کارت = ${faDigits(layout.sheetsFor(cards))} برگ (${faDigits(layout.sheetsFor(cards) * 2)} صفحه‌ی PDF).';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('هر کارت یک صفحه')),
          ButtonSegment(value: true, label: Text('چیدن روی بوم')),
        ],
        selected: {t.sheetMode},
        onSelectionChanged: (v) => set(() => t.sheetMode = v.first),
      ),
      const SizedBox(height: DaftarSize.space2),
      if (!t.sheetMode)
        const Hint('هر کارت در یک صفحه‌ی هم‌اندازه‌ی خودش می‌آید: رو، بعد پشت. برای چاپخانه‌هایی که خودشان کارت‌ها را روی بوم می‌چینند.')
      else ...[
        const Hint('چند کارت را کنار هم روی بوم می‌چیند، و بعد از هر برگ رو، برگ پشت‌ها را با جای آینه‌شده می‌گذارد تا بعد از چاپ دورو و برش، '
            'پشت هر کارت پشت همان کارت و هم‌جهت با آن باشد. خط نازک جداکننده فقط روی برگ رو است.'),
        const SizedBox(height: DaftarSize.space3),
        Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: t.sheetPreset,
              decoration: const InputDecoration(labelText: 'سایز بوم', isDense: true),
              items: presetItems,
              onChanged: (v) => set(() {
                t.sheetPreset = v ?? 'A4';
                final p = sheetPresets[t.sheetPreset];
                if (p != null) {
                  t.sheetW = p.$1;
                  t.sheetH = p.$2;
                }
              }),
            ),
          ),
          if (t.sheetPreset == 'custom') ...[
            num('عرض بوم (mm)', t.sheetW, (v) => t.sheetW = v),
            num('ارتفاع بوم (mm)', t.sheetH, (v) => t.sheetH = v),
          ],
          num('حاشیه‌ی برگ (mm)', t.sheetMargin, (v) => t.sheetMargin = v),
        ]),
        const SizedBox(height: DaftarSize.space3),
        Text('چاپ دورو: برگ از کدام لبه برمی‌گردد؟', style: theme.textTheme.labelLarge),
        const SizedBox(height: DaftarSize.space1),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'long', label: Text('از لبه‌ی بلند')),
            ButtonSegment(value: 'short', label: Text('از لبه‌ی کوتاه')),
          ],
          selected: {t.duplex},
          onSelectionChanged: (v) => set(() => t.duplex = v.first),
        ),
        const Hint('همان گزینه را در چاپگر یا چاپخانه بزنید («Flip on long edge / short edge»). اگر مطمئن نیستید «از لبه‌ی بلند» که حالت عادی است.'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: t.autoRotate,
          onChanged: (v) => set(() => t.autoRotate = v),
          title: const Text('چرخاندن خودکار کارت‌ها ۹۰ درجه'),
          subtitle: const Text('فقط وقتی جای بیشتری در برگ آزاد کند. پشت هر کارت همراه رویش می‌چرخد.'),
        ),
        const SizedBox(height: DaftarSize.space2),
        if (layout == null)
          const Notice(
            tone: NoticeTone.stop,
            text: 'کارت در این بوم با این حاشیه جا نمی‌شود. بوم بزرگ‌تر یا حاشیه‌ی کمتر انتخاب کنید.',
          )
        else ...[
          Notice(tone: NoticeTone.info, text: summary!),
          if (layout.perSheet < 4)
            Padding(
              padding: const EdgeInsets.only(top: DaftarSize.space2),
              child: Notice(
                tone: NoticeTone.wait,
                text: 'فقط ${faDigits(layout.perSheet)} کارت در هر برگ جا می‌شود؛ شاید بوم بزرگ‌تری بخواهید.',
              ),
            ),
          const SizedBox(height: DaftarSize.space3),
          Wrap(spacing: DaftarSize.space5, runSpacing: DaftarSize.space3, children: [
            _SheetPreview(title: 'برگ رو', layout: layout, flip: flip, back: false, count: cards),
            _SheetPreview(title: 'برگ پشت (آینه‌شده)', layout: layout, flip: flip, back: true, count: cards),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: DaftarSize.space2),
            child: Text(
              'پیش‌نمایش برگ اول. مثلث بالای هر کارت را نشان می‌دهد؛ کارت ۱ (آبی) رو و پشتش را ببینید که روی هم می‌افتند. '
              'پیش از چاپ همه، یک برگ آزمایشی از چاپخانه بخواهید و رو و پشت را روی هم بگیرید.',
              style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted),
            ),
          ),
        ],
      ],
    ]);
  }
}

/// پیش‌نمایش یک برگ: خانه‌ها با شماره‌ی کارت و مثلثی که «بالای کارت» را نشان می‌دهد.
class _SheetPreview extends StatelessWidget {
  final String title;
  final SheetLayout layout;
  final DuplexFlip flip;
  final bool back;
  final int count;
  const _SheetPreview({required this.title, required this.layout, required this.flip, required this.back, required this.count});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    const long = 300.0;
    final scale = long / (layout.pageW > layout.pageH ? layout.pageW : layout.pageH);
    final w = layout.pageW * scale, h = layout.pageH * scale;
    final n = count < layout.perSheet ? count : layout.perSheet;
    final deg = back ? layout.backDegrees(flip) : layout.frontDegrees;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.labelLarge),
      const SizedBox(height: DaftarSize.space1),
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: x.lineStrong)),
        child: Stack(children: [
          for (var k = 0; k < n; k++)
            Builder(builder: (context) {
              final cell = back ? layout.backCell(k, flip) : layout.frontCell(k);
              final (ox, oy) = layout.cellOrigin(cell);
              return Positioned(
                left: ox * scale,
                top: oy * scale,
                width: layout.cellW * scale,
                height: layout.cellH * scale,
                child: Container(
                  decoration: BoxDecoration(
                    color: k == 0 ? x.stampSoft : null,
                    border: Border.all(color: x.line),
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: deg * math.pi / 180,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.arrow_drop_up_rounded, size: 18, color: k == 0 ? x.stamp : x.inkMuted),
                        Text(faDigits(k + 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF10141A),
                              fontWeight: k == 0 ? FontWeight.w800 : FontWeight.w500,
                              height: 1,
                            )),
                      ]),
                    ),
                  ),
                ),
              );
            }),
        ]),
      ),
    ]);
  }
}
