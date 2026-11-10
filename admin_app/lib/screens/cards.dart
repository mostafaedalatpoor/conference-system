import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cards_pdf.dart';
import 'card_editor.dart';
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
    if (s.template.qrEnabled && (s.event?.baseUrl.isEmpty ?? true)) {
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
        frontImage: await cardDesignBytes(s, 'front'),
        backImage: s.template.doubleSided ? await cardDesignBytes(s, 'back') : null,
        fileRows: (await loadExtraFile(s)).rows,
        assets: await cardAssetBytes(s),
      );
    });
    if (bytes == null || !mounted) return;
    await _saveBytes(s, 'cards-${s.eventCode}.pdf', bytes);
    if (s.template.qrEnabled && !(s.event?.locked ?? true)) await s.setLocked(true);
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
        frontImage: await cardDesignBytes(s, 'front'),
        backImage: s.template.doubleSided ? await cardDesignBytes(s, 'back') : null,
        fileRows: (await loadExtraFile(s)).rows,
        assets: await cardAssetBytes(s),
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

  /// فایل اکسل جدا یک بار خوانده می‌شود و تا عوض‌شدن مسیر یا افراد نگه داشته می‌شود.
  ExtraFileData _file = ExtraFileData.empty;
  String? _fileKey;

  void _ensureFile(AdminState s) {
    final key = '${s.template.extraFile}|${s.people.length}';
    if (key == _fileKey) return;
    _fileKey = key;
    loadExtraFile(s).then((d) {
      if (mounted && key == _fileKey) setState(() => _file = d);
    });
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
    _ensureFile(s);

    // پیش از هر چیز سه پرسش: یک‌رو یا دورو، QR، سمت QR.
    if (!t.setupDone) {
      return PageBody(title: 'کارت‌ها', children: [
        const SectionTitle('نوع کارت'),
        CardSetupForm(s: s, initial: true, onDone: () => setState(() {})),
      ]);
    }

    final longest = people.isEmpty
        ? null
        : people.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b);
    final sample = sampleSubject(s, _longName ? longest : (people.isEmpty ? null : people.first), _file);

    return PageBody(title: 'کارت‌ها', children: [
      if (locked)
        const Padding(
          padding: EdgeInsets.only(bottom: DaftarSize.space2),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'کارت‌ها چاپ شده‌اند. تغییر قالب فقط روی کارت‌های رزرو جدید اثر دارد.',
          ),
        ),
      CardSetupSummary(s: s),
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
      const SectionTitle('طرح زمینه'),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.image_rounded),
          label: Text(t.frontImage.isEmpty ? 'طرح روی کارت' : 'روی: ${t.frontImage.split(Platform.pathSeparator).last}'),
          onPressed: () => _pickImage(s, true),
        ),
        if (t.doubleSided)
          OutlinedButton.icon(
            icon: const Icon(Icons.image_rounded),
            label: Text(t.backImage.isEmpty ? 'طرح پشت کارت' : 'پشت: ${t.backImage.split(Platform.pathSeparator).last}'),
            onPressed: () => _pickImage(s, false),
          ),
      ]),
      const SizedBox(height: 8),
      const Hint('طرح‌ها PNG یا JPG، با حاشیه‌ی اضافه‌ی ۳ میلی‌متر از هر طرف و ۳۰۰ DPI باشند '
          '(برای ۸۵×۵۵ میلی‌متر فایل ۹۱×۶۱ میلی‌متر، حدود ۱۰۷۵×۷۲۰ پیکسل). متن مهم دست‌کم ۴ میلی‌متر داخل لبه‌ی برش باشد.'),
      if (t.qrEnabled) ...[
        SectionTitle(t.effectiveQrSide == 'front' ? 'QR (روی کارت)' : 'QR (پشت کارت)'),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _num('مرکز QR: افقی ٪', t.qrX, (v) => t.qrX = v, step: 1),
          _num('مرکز QR: عمودی ٪', t.qrY, (v) => t.qrY = v, step: 1),
          _num('اندازه‌ی QR (mm)', t.qrSizeMm, (v) => t.qrSizeMm = v, step: 0.5),
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
      ],
      const SectionTitle('متن‌های کارت'),
      CardTextsSection(s: s, file: _file, onChanged: () => setState(() {})),
      const SectionTitle('فونت‌ها'),
      FontsSection(s: s),
      const SectionTitle('فایل اکسل جدا'),
      ExtraFileSection(s: s, data: _file, onChanged: () => setState(() => _fileKey = null)),
      const SectionTitle('پیش‌نمایش'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _longName,
        onChanged: longest == null ? null : (v) => setState(() => _longName = v),
        title: const Text('آزمون نام بلند'),
        subtitle: Text(longest == null ? 'هنوز کسی وارد نشده؛ مقدارهای نمونه نشان داده می‌شود.' : 'طولانی‌ترین نام لیست: ${longest.displayName}'),
      ),
      CardPreview(s: s, subject: sample),
      const SectionTitle('چیدمان برای چاپخانه'),
      _SheetSettings(
        s: s,
        cards: people.length + free,
        onChanged: () => setState(() {}),
      ),
      const SectionTitle('بررسی پیش از چاپ'),
      CardPreflight(s: s, file: _file),
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
        '${t.sheetMode ? (t.doubleSided ? 'PDF کارت‌ها روی بوم چیده می‌شود: یک برگ رو و بعدش برگ پشت‌ها با جای آینه‌شده (چاپ دورو)، ' : 'PDF کارت‌ها روی بوم چیده می‌شود (یک‌رو)، ') : (t.doubleSided ? 'PDF کارت‌ها برای هر کارت یک صفحه‌ی رو و پشت‌سرش یک صفحه‌ی پشت دارد (چاپ دورو)، ' : 'PDF کارت‌ها برای هر کارت یک صفحه دارد، ')}'
        'به ترتیب الفبایی نام خانوادگی. '
        '${t.qrEnabled ? 'بعد از ساخت PDF، آدرس پایه قفل می‌شود تا لینک QR کارت‌های چاپ‌شده عوض نشود. ' : ''}'
        'قالب، متن‌ها و تنظیم بوم روی سرور ذخیره می‌شود تا ویندوز و گوشی یک قالب ببینند؛ تصویر طرح و فایل اکسل جدا روی همین دستگاه می‌ماند، پس روی هر دستگاه یک بار انتخابشان کنید.',
      ),
    ]);
  }
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
            '${faDigits(cards)} کارت = ${faDigits(layout.sheetsFor(cards))} برگ (${faDigits(layout.sheetsFor(cards) * (t.doubleSided ? 2 : 1))} صفحه‌ی PDF).';

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
        Hint('هر کارت در یک صفحه‌ی هم‌اندازه‌ی خودش می‌آید${t.doubleSided ? ': رو، بعد پشت' : ''}. برای چاپخانه‌هایی که خودشان کارت‌ها را روی بوم می‌چینند.')
      else ...[
        Hint(t.doubleSided
            ? 'چند کارت را کنار هم روی بوم می‌چیند، و بعد از هر برگ رو، برگ پشت‌ها را با جای آینه‌شده می‌گذارد تا بعد از چاپ دورو و برش، '
                'پشت هر کارت پشت همان کارت و هم‌جهت با آن باشد. خط نازک جداکننده فقط روی برگ رو است.'
            : 'چند کارت را کنار هم روی بوم می‌چیند، با خط نازک جداکننده برای برش.'),
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
        if (t.doubleSided) ...[
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
        ],
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
            if (t.doubleSided)
              _SheetPreview(title: 'برگ پشت (آینه‌شده)', layout: layout, flip: flip, back: true, count: cards),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: DaftarSize.space2),
            child: Text(
              t.doubleSided
                  ? 'پیش‌نمایش برگ اول. مثلث بالای هر کارت را نشان می‌دهد؛ کارت ۱ (آبی) رو و پشتش را ببینید که روی هم می‌افتند. '
                      'پیش از چاپ همه، یک برگ آزمایشی از چاپخانه بخواهید و رو و پشت را روی هم بگیرید.'
                  : 'پیش‌نمایش برگ اول. مثلث بالای هر کارت را نشان می‌دهد.',
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

/// تنظیم چیدمان چاپ (بوم، حاشیه، برگشت دورو) برای استفاده در صفحه‌های گوشی.
class CardSheetSettings extends StatelessWidget {
  final AdminState s;
  final int cards;
  final VoidCallback onChanged;
  const CardSheetSettings({super.key, required this.s, required this.cards, required this.onChanged});

  @override
  Widget build(BuildContext context) => _SheetSettings(s: s, cards: cards, onChanged: onChanged);
}
