import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../card_logic.dart';
import '../cards_pdf.dart';
import '../main.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import '../normalize.dart';
import '../state.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

/// روی موبایل PDF نهایی همه‌ی کارت‌ها و انتخاب تصویر طرح «روی ویندوز» است (ScreenAdminMobileCards).
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// عدد برای فیلد ویرایش: ۸۵ یا ۸۵.۵ (ارقام لاتین، چون کاربر رویش تایپ می‌کند).
String _plain(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

class _CardsScreenState extends State<CardsScreen> {
  final _reserveCount = TextEditingController();
  int _rev = 0;
  bool _longName = false;

  /// قالبی که چیدمانش ویرایش می‌شود.
  String _editId = defaultTemplateId;

  /// «هر قالب یک فایل» به‌جای «همه در یک فایل».
  bool _filePerTemplate = false;

  /// متن خام فیلدهای اعتبارسنجی‌شده تا وقتی درست نشده؛ مدل همیشه آخرین مقدار درست را دارد.
  final Map<String, String> _raw = {};
  int _seenCardsRev = -1;

  /// مسیر آخرین فایلی که ذخیره شد، برای پیام «فایل ذخیره شد».
  String? _savedPath;

  CardTemplate _edited(CardTemplateSet set) =>
      set.separate ? (set.byId(_editId) ?? set.defaultTemplate) : set.defaultTemplate;

  /// خطای زنده‌ی فیلدهای مشخصات و رنگ؛ کلید نام فیلد.
  Map<String, String?> _errors(CardTemplateSet set, CardTemplate t) => {
        'w': cardSizeError(_raw['w'] ?? _plain(set.widthMm), 'عرض'),
        'h': cardSizeError(_raw['h'] ?? _plain(set.heightMm), 'ارتفاع'),
        'bleed': bleedError(_raw['bleed'] ?? _plain(set.bleedMm)),
        'color': hexColorError(_raw['color'] ?? t.nameColor),
      };

  Future<void> _pickImage(AdminState s, CardTemplate t, bool front) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    var path = r?.files.single.path;
    if (path == null) return;
    if (isMobilePlatform) {
      // انتخاب‌گر اندروید فایل را در حافظه‌ی موقت می‌گذارد که سیستم پاکش می‌کند؛ یک نسخه پیش برنامه می‌ماند.
      // نام تازه با زمان، تا پیش‌نمایش و بررسی پیش از چاپ تصویر کهنه را از حافظه نخوانند.
      final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}card_images');
      await dir.create(recursive: true);
      final ext = path.split('.').last.toLowerCase();
      final copy = '${dir.path}${Platform.pathSeparator}${t.id}-${front ? 'front' : 'back'}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(path).copy(copy);
      path = copy;
    }
    final picked = path;
    setState(() => front ? t.frontImage = picked : t.backImage = picked);
    await s.save();
  }

  Future<Uint8List?> _read(String path) async {
    if (path.isEmpty) return null;
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<TemplateImages> _images(Iterable<CardTemplate> templates) async => {
        for (final t in templates) t.id: (await _read(t.frontImage), await _read(t.backImage)),
      };

  /// true فقط وقتی فایل واقعاً نوشته شد؛ انصراف یا خطا false.
  Future<bool> _saveBytes(AdminState s, String name, Uint8List bytes) async {
    String? path;
    try {
      if (isMobilePlatform) {
        // اندروید پنجره‌ی «ذخیره در مسیر» ویندوز را ندارد؛ انتخاب‌گر سیستم خودش فایل را می‌نویسد.
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'ذخیره‌ی PDF',
          fileName: name,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: bytes,
        );
        if (path == null) return false;
      } else {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'ذخیره‌ی PDF',
          fileName: name,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (path == null) return false;
        path = path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';
        await File(path).writeAsBytes(bytes);
      }
    } catch (e) {
      s.message = 'فایل ذخیره نشد: $e';
      s.messageIsError = true;
      s.notify();
      return false;
    }
    _savedPath = path;
    s.message = 'ذخیره شد: $path';
    s.messageIsError = false;
    s.notify();
    return true;
  }

  /// «هر قالب یک فایل»: یک پوشه انتخاب و همه‌ی فایل‌ها در آن نوشته می‌شوند (فقط ویندوز).
  Future<bool> _saveMany(AdminState s, List<(String, Uint8List)> files) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'پوشه‌ی ذخیره‌ی PDFها');
    if (dir == null) return false;
    final targets = [for (final (name, _) in files) File('$dir${Platform.pathSeparator}$name')];
    final existing = [for (final f in targets) if (f.existsSync()) f.path.split(Platform.pathSeparator).last];
    if (existing.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('جایگزینی فایل‌ها'),
          content: Text('${faDigits(existing.length)} فایل با همین نام در این پوشه هست:\n${existing.join('\n')}\nجایگزین شوند؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('جایگزین کن')),
          ],
        ),
      );
      if (ok != true) return false;
    }
    try {
      for (var i = 0; i < files.length; i++) {
        await targets[i].writeAsBytes(files[i].$2);
      }
    } catch (e) {
      s.message = 'فایل‌ها ذخیره نشدند: $e';
      s.messageIsError = true;
      s.notify();
      return false;
    }
    _savedPath = '${faDigits(files.length)} فایل در $dir';
    s.message = 'ذخیره شد: ${files.map((f) => f.$1).join('، ')} در $dir';
    s.messageIsError = false;
    s.notify();
    return true;
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

  static String _fileSafe(String name) {
    final x = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-');
    return x.isEmpty ? 'template' : x;
  }

  /// فایل‌های PDF کارت: «همه در یک فایل» یا «هر قالب یک فایل» (رزروها در فایل قالب رزرو).
  List<(String, List<CardItem>)> _plan(AdminState s, {required bool draft}) {
    final set = s.cards;
    final people = s.sortedPeople;
    final reserves = s.reserveCards.where((r) => !r.used).toList();
    final prefix = '${draft ? 'draft-' : ''}cards-${s.eventCode}';
    if (!(_filePerTemplate && set.separate)) {
      return [
        (
          '$prefix.pdf',
          [
            for (final p in people) CardItem.person(p, s.templateOf(p)),
            for (final r in reserves) CardItem.reserve(r, set.reserveTemplate),
          ]
        ),
      ];
    }
    final groups = groupByTemplate(set, people, typeOf: (p) => p.typeCode, roleOf: (p) => p.roleCode);
    final byId = <String, List<CardItem>>{
      for (final (t, list) in groups) t.id: [for (final p in list) CardItem.person(p, t)],
    };
    if (reserves.isNotEmpty) {
      final rt = set.reserveTemplate;
      byId.putIfAbsent(rt.id, () => []).addAll([for (final r in reserves) CardItem.reserve(r, rt)]);
    }
    return [
      for (final t in set.templates)
        if (byId[t.id] != null) ('$prefix-${_fileSafe(t.name)}.pdf', byId[t.id]!),
    ];
  }

  /// ساخت PDF کارت‌ها. پیش‌نویس نوشته‌ی «پیش‌نویس» دارد و هرگز قفل نمی‌کند؛
  /// نسخه‌ی نهایی فقط بعد از ذخیره‌ی موفق و تأیید «بله، قفل کن» آدرس پایه را قفل می‌کند.
  Future<void> _generateCards(AdminState s, {required bool draft}) async {
    if (!_checkBase(s)) return;
    await s.save();
    final plan = _plan(s, draft: draft);
    final built = await s.run('', () async {
      final fonts = await PdfFonts.load();
      final images = await _images(s.cards.activeTemplates);
      return [
        for (final (name, items) in plan)
          (name, await buildCardsPdf(s: s, fonts: fonts, items: items, images: images, draft: draft)),
      ];
    });
    if (built == null || !mounted) return;
    final bool saved;
    if (built.length == 1) {
      saved = await _saveBytes(s, built.single.$1, built.single.$2);
    } else if (isMobilePlatform) {
      // روی گوشی انتخاب پوشه به فایل‌نوشتن مستقیم راه نمی‌دهد؛ هر فایل جدا ذخیره می‌شود.
      var all = true;
      for (final (name, bytes) in built) {
        if (!mounted || !await _saveBytes(s, name, bytes)) {
          all = false;
          break;
        }
      }
      saved = all;
    } else {
      saved = await _saveMany(s, built);
    }
    if (!saved || draft || !mounted || (s.event?.locked ?? true)) return;
    final name = (_savedPath ?? built.first.$1).split(Platform.pathSeparator).last;
    final lock = isMobilePlatform ? await _askLockSheet(name) : await _askLockDialog(name);
    if (lock == true) await s.setLocked(true);
  }

  Future<bool?> _askLockDialog(String name) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('فایل ذخیره شد: $name'),
          content: const Text('به چاپخانه می‌دهید؟ با «بله»، آدرس سایت روی QR قفل می‌شود.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('فعلاً نه')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بله، قفل کن')),
          ],
        ),
      );

  /// روی گوشی همان پرسش به شکل برگه‌ی پایین صفحه (طراحی 16-CardCheck).
  Future<bool?> _askLockSheet(String name) => showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(DaftarSize.space4, 0, DaftarSize.space4, DaftarSize.space5),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('فایل ذخیره شد: $name', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: DaftarSize.space2),
              const Hint('به چاپخانه می‌دهید؟ با «بله»، آدرس سایت روی QR قفل می‌شود.'),
              const SizedBox(height: DaftarSize.space4),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('فعلاً نه'))),
                const SizedBox(width: DaftarSize.space3),
                Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بله، قفل کن'))),
              ]),
            ]),
          ),
        ),
      );

  /// PDF فقط کارت‌های رزرو آزاد: سبک، روی موبایل هم شدنی.
  Future<void> _generateReserves(AdminState s) async {
    if (!_checkBase(s)) return;
    final t = s.cards.reserveTemplate;
    final bytes = await s.run('', () async {
      final fonts = await PdfFonts.load();
      return buildCardsPdf(
        s: s,
        fonts: fonts,
        items: [for (final r in s.reserveCards.where((r) => !r.used)) CardItem.reserve(r, t)],
        images: await _images([t]),
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
      key: ValueKey('$label-$_editId-$_rev'),
      initialValue: _plain(value),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      onChanged: (v) {
        final d = parseDecimal(v);
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

  /// فیلد با اعتبارسنجی زنده: متن خام نگه داشته می‌شود و مدل فقط با مقدار درست عوض می‌شود.
  Widget _checked(
    String id,
    String label,
    String initial,
    String? error,
    void Function(String) apply, {
    double width = 210,
    bool ltr = false,
    TextInputType keyboard = TextInputType.number,
  }) =>
      SizedBox(
        width: width,
        child: DaftarField(
          label: label,
          error: error,
          child: TextFormField(
            key: ValueKey('$id-$_editId-$_rev'),
            initialValue: _raw[id] ?? initial,
            keyboardType: keyboard,
            textDirection: ltr ? TextDirection.ltr : null,
            decoration: InputDecoration(
              isDense: true,
              suffixIcon: error == null ? null : Icon(Icons.error_rounded, color: DaftarColors.of(context).stop),
            ),
            onChanged: (v) => setState(() {
              _raw[id] = v;
              apply(v);
            }),
          ),
        ),
      );

  Future<void> _deleteTemplate(AdminState s, CardTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف قالب «${t.name}»'),
        content: const Text('کسانی که این قالب را می‌گرفتند قالب پیش‌فرض می‌گیرند. تا «ذخیره‌ی قالب روی سرور» نزنید، سرور تغییری نمی‌بیند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      s.cards.templates.remove(t);
      if (s.cards.reserveTemplateId == t.id) s.cards.reserveTemplateId = s.cards.defaultTemplate.id;
      _editId = s.cards.defaultTemplate.id;
      _raw.remove('color');
      _rev++;
    });
  }

  String _ruleSummary(AdminState s, CardTemplate t) {
    if (t.isDefault) return 'قالب «${t.name}» برای: همه‌ی کسانی که قالب دیگری نمی‌گیرند';
    final names = [
      for (final r in s.roles) if (t.roles.contains(r.code)) r.name,
      for (final ty in s.types) if (t.types.contains(ty.code)) ty.name,
    ];
    return names.isEmpty
        ? 'قالب «${t.name}» هنوز قاعده ندارد و به کسی نمی‌خورد.'
        : 'قالب «${t.name}» برای: ${names.join('، ')}';
  }

  /// قالب‌ها: کلید «قالب جدا برای هر دسته»، انتخاب قالب، نام و قاعده‌ی نقش/نوع.
  List<Widget> _templateSection(AdminState s, CardTemplate t) {
    final set = s.cards;
    return [
      const SectionTitle('قالب‌ها'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: set.separate,
        onChanged: (v) => setState(() {
          set.separate = v;
          _raw.remove('color');
          _rev++;
        }),
        title: const Text('قالب جدا برای هر دسته'),
        subtitle: const Text('خاموش: همه‌ی افراد یک قالب دارند'),
      ),
      if (set.separate) ...[
        Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
          for (final x in set.templates)
            ChoiceChip(
              label: Text(x.name),
              selected: x.id == t.id,
              onSelected: (_) => setState(() {
                _editId = x.id;
                _raw.remove('color');
                _rev++;
              }),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: const Text('قالب تازه'),
            onPressed: () => setState(() {
              final n = set.duplicate(t);
              _editId = n.id;
              _raw.remove('color');
              _rev++;
            }),
          ),
        ]),
        const SizedBox(height: DaftarSize.space2),
        Hint(_ruleSummary(s, t)),
        const SizedBox(height: DaftarSize.space3),
        Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space2, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(
            width: 220,
            child: DaftarField(
              label: 'نام قالب',
              error: t.name.trim().isEmpty ? 'نام قالب را بنویسید' : null,
              child: TextFormField(
                key: ValueKey('tname-${t.id}-$_rev'),
                initialValue: t.name,
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) => setState(() => t.name = v),
              ),
            ),
          ),
          if (!t.isDefault)
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('حذف قالب'),
              onPressed: () => _deleteTemplate(s, t),
            ),
        ]),
        if (!t.isDefault) ...[
          const SizedBox(height: DaftarSize.space3),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('نقش:  '),
            for (final r in s.roles)
              FilterChip(
                avatar: const Icon(Icons.person_outline_rounded, size: 16),
                label: Text(r.name),
                selected: t.roles.contains(r.code),
                onSelected: (v) => setState(() => v ? t.roles.add(r.code) : t.roles.remove(r.code)),
              ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('نوع ثبت‌نام:  '),
            for (final ty in s.types)
              FilterChip(
                label: Text(ty.name),
                selected: t.types.contains(ty.code),
                onSelected: (v) => setState(() => v ? t.types.add(ty.code) : t.types.remove(ty.code)),
              ),
          ]),
          const SizedBox(height: 6),
          const Hint('اگر نقش کسی به یک قالب و نوع ثبت‌نامش به قالب دیگری بخورد، قالب نقش برنده است.'),
        ],
        const SizedBox(height: DaftarSize.space3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 260,
            child: DaftarField(
              label: 'قالب کارت‌های رزرو',
              child: DropdownButtonFormField<String>(
                key: ValueKey('reserve-${set.templates.length}-$_rev'),
                initialValue: set.reserveTemplate.id,
                isDense: true,
                items: [for (final x in set.templates) DropdownMenuItem(value: x.id, child: Text(x.name))],
                onChanged: (v) => setState(() => set.reserveTemplateId = v ?? set.defaultTemplate.id),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final set = s.cards;
    if (_seenCardsRev != s.cardsRev) {
      // قالب‌ها از سرور یا فایل تازه خوانده شدند: متن خام کهنه دور ریخته می‌شود.
      _seenCardsRev = s.cardsRev;
      _raw.clear();
      _rev++;
    }
    final t = _edited(set);
    final errors = _errors(set, t);
    final errorCount = errors.values.where((e) => e != null).length + (t.name.trim().isEmpty ? 1 : 0);
    final hasErrors = errorCount > 0;
    final free = s.reserveCards.where((r) => !r.used).length;
    final people = s.sortedPeople;
    final mine = set.separate ? people.where((p) => s.templateOf(p).id == t.id).toList() : people;
    final mobile = isMobilePlatform;
    final locked = s.event?.locked ?? false;
    if (_reserveCount.text.isEmpty) {
      _reserveCount.text = '${(people.length / 10).ceil().clamp(1, 1000)}';
    }
    final longest = mine.isEmpty ? null : mine.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b);
    final g = CardPageGeometry(trimW: set.widthMm, trimH: set.heightMm, bleed: set.bleedMm, cropMarks: set.cropMarks);
    final files = _filePerTemplate && set.separate ? _plan(s, draft: false).length : 1;
    final host = Uri.tryParse(s.event?.baseUrl ?? '')?.host ?? '';
    final noArtwork = set.activeTemplates.every((x) =>
        (x.frontImage.isEmpty || !File(x.frontImage).existsSync()) && (x.backImage.isEmpty || !File(x.backImage).existsSync()));

    final errorLabel = '${faDigits(errorCount)} فیلد خطا دارد';
    final bleedHint = set.bleedMm > 0
        ? 'طرح‌ها PNG یا JPG، با حاشیه‌ی اضافه‌ی ${fmtMm(set.bleedMm)} میلی‌متر از هر طرف و ۳۰۰ DPI باشند '
            '(برای ${fmtMm(set.widthMm)}×${fmtMm(set.heightMm)} میلی‌متر فایل ${fmtMm(g.bleedW)}×${fmtMm(g.bleedH)} میلی‌متر، '
            'حدود ${faDigits((g.bleedW / 25.4 * 300).round())}×${faDigits((g.bleedH / 25.4 * 300).round())} پیکسل). '
            'متن مهم دست‌کم ۴ میلی‌متر داخل لبه‌ی برش باشد.'
        : 'طرح‌ها PNG یا JPG، ${fmtMm(set.widthMm)}×${fmtMm(set.heightMm)} میلی‌متر و ۳۰۰ DPI باشند. '
            'بدون حاشیه‌ی برش، لبه‌ی کارت ممکن است سفید بماند. متن مهم دست‌کم ۴ میلی‌متر داخل لبه‌ی برش باشد.';

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
      const SectionTitle('مشخصات کارت'),
      Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, crossAxisAlignment: WrapCrossAlignment.start, children: [
        _checked('w', 'عرض (میلی‌متر)', _plain(set.widthMm), errors['w'], (v) {
          if (cardSizeError(v, 'عرض') == null) set.widthMm = parseDecimal(v)!;
        }),
        _checked('h', 'ارتفاع (میلی‌متر)', _plain(set.heightMm), errors['h'], (v) {
          if (cardSizeError(v, 'ارتفاع') == null) set.heightMm = parseDecimal(v)!;
        }),
        _checked('bleed', 'حاشیه‌ی برش (bleed)', _plain(set.bleedMm), errors['bleed'], (v) {
          if (bleedError(v) == null) set.bleedMm = parseDecimal(v)!;
        }),
      ]),
      const SizedBox(height: DaftarSize.space2),
      const Hint('اندازه‌ی نهایی کارت را از چاپخانه بپرسید (کارت ویزیت معمولاً ۸۵×۵۵ میلی‌متر). '
          'ارقام فارسی و ممیز «٫» هم پذیرفته می‌شود.'),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: set.cropMarks,
        onChanged: (v) => setState(() => set.cropMarks = v ?? false),
        title: const Text('علامت برش'),
        subtitle: Text(set.cropMarks
            ? 'دور هر صفحه ${fmtMm(g.slug)} میلی‌متر نوار سفید برای علامت‌ها می‌آید؛ '
                'صفحه‌ی PDF ${fmtMm(g.pageW)}×${fmtMm(g.pageH)} میلی‌متر می‌شود.'
            : 'صفحه‌ی PDF ${fmtMm(g.pageW)}×${fmtMm(g.pageH)} میلی‌متر (کارت + حاشیه‌ی برش) است.'),
      ),
      ..._templateSection(s, t),
      SectionTitle(set.separate ? 'چیدمان قالب «${t.name}»' : 'قالب کارت'),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.image_rounded),
          label: Text(t.frontImage.isEmpty ? 'طرح روی کارت' : 'روی: ${isMobilePlatform ? 'انتخاب شد' : t.frontImage.split(Platform.pathSeparator).last}'),
          onPressed: () => _pickImage(s, t, true),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_rounded),
          label: Text(t.backImage.isEmpty ? 'طرح پشت کارت' : 'پشت: ${isMobilePlatform ? 'انتخاب شد' : t.backImage.split(Platform.pathSeparator).last}'),
          onPressed: () => _pickImage(s, t, false),
        ),
      ]),
      const SizedBox(height: 8),
      Hint(bleedHint),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [
        _num('مرکز نام: افقی ٪', t.nameX, (v) => t.nameX = v, step: 1),
        _num('مرکز نام: عمودی ٪', t.nameY, (v) => t.nameY = v, step: 1),
        _num('اندازه‌ی نام (pt)', t.nameSize, (v) => t.nameSize = v, step: 0.5),
        _checked('color', 'رنگ نام (hex)', t.nameColor, errors['color'], (v) {
          final hex = normalizeHex(v);
          if (hex != null) t.nameColor = hex;
        }, width: 230, ltr: true, keyboard: TextInputType.text),
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
        subtitle: Text(longest == null
            ? (set.separate ? 'هنوز کسی این قالب را نمی‌گیرد.' : 'هنوز کسی وارد نشده.')
            : 'طولانی‌ترین نام لیست: ${longest.displayName}'),
      ),
      _Preview(s: s, t: t, person: _longName ? longest : (mine.isEmpty ? null : mine.first)),
      const SectionTitle('بررسی پیش از چاپ'),
      _Preflight(s: s, people: people),
      const SectionTitle('ساخت PDF'),
      if (!locked && host.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: DaftarSize.space3),
          child: Notice(
            tone: NoticeTone.stop,
            icon: Icons.lock_rounded,
            title: 'آدرس سایت روی QR قفل می‌شود',
            text: 'پس از ساخت کارت‌ها و تأیید شما، QR به $host گره می‌خورد. اگر دامنه عوض شود، باید کارت‌ها دوباره چاپ شوند. '
                'پیش‌نویس قفل نمی‌کند.',
          ),
        ),
      if (set.separate && set.templates.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: DaftarSize.space3),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('همه در یک فایل')),
              ButtonSegment(value: true, label: Text('هر قالب یک فایل')),
            ],
            selected: {_filePerTemplate},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _filePerTemplate = v.first),
          ),
        ),
      if (mobile && noArtwork)
        const Padding(
          padding: EdgeInsets.only(bottom: DaftarSize.space3),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'طرح روی و پشت روی این گوشی انتخاب نشده؛ کارت‌ها روی زمینه‌ی سفید (فقط نام و QR) ساخته می‌شوند. '
                'طرح را از «قالب کارت» انتخاب کنید (تصویر طرح هر دستگاه جداست). ساخت همه‌ی کارت‌ها روی گوشی ممکن است کمی طول بکشد.',
          ),
        ),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton(
          onPressed: s.busy || people.isEmpty || hasErrors ? null : () => _generateCards(s, draft: true),
          child: const Text('ساخت پیش‌نویس (بدون قفل)'),
        ),
        FilledButton.icon(
          icon: Icon(locked ? Icons.picture_as_pdf_rounded : Icons.lock_rounded),
          onPressed: s.busy || people.isEmpty || hasErrors ? null : () => _generateCards(s, draft: false),
          label: Text(hasErrors
              ? errorLabel
              : '${locked ? 'ساخت PDF کارت‌ها' : 'ساخت و قفل…'} (${faDigits(people.length)} نفر + ${faDigits(free)} رزرو)'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.style_rounded),
          onPressed: s.busy || free == 0 || hasErrors ? null : () => _generateReserves(s),
          label: Text('PDF کارت‌های رزرو آزاد (${faDigits(free)})'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt_rounded),
          onPressed: s.busy || people.isEmpty ? null : () => _generateLists(s),
          label: const Text('PDF لیست پشتیبان کاغذی'),
        ),
        TextButton(
          onPressed: s.busy || hasErrors ? null : s.saveTemplate,
          child: Text(hasErrors ? errorLabel : 'ذخیره‌ی قالب روی سرور'),
        ),
      ]),
      const SizedBox(height: 8),
      Hint(
        'PDF کارت‌ها برای هر کارت یک صفحه‌ی رو و پشت‌سرش یک صفحه‌ی پشت دارد (چاپ دورو)، به ترتیب الفبایی نام خانوادگی'
        '${files > 1 ? '، در ${faDigits(files)} فایل جدا (یکی برای هر قالب)' : ''}'
        '${set.cropMarks ? '، با علامت برش' : ''}. '
        'آدرس پایه فقط بعد از ذخیره‌ی PDF نهایی و تأیید «بله، قفل کن» قفل می‌شود تا لینک QR کارت‌های چاپ‌شده عوض نشود. '
        'قالب روی سرور ذخیره می‌شود تا ویندوز و گوشی یک قالب ببینند؛ تصویر طرح روی همین رایانه می‌ماند.',
      ),
    ]);
  }
}

/// بررسی پیش از چاپ: پوشش قالب‌ها، و برای هر قالب جاشدن نام‌ها، اندازه و جای QR، اندازه و کیفیت تصویر طرح.
class _Preflight extends StatelessWidget {
  final AdminState s;
  final List<Person> people;
  const _Preflight({required this.s, required this.people});

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

  /// بررسی‌های چیدمان یک قالب با طولانی‌ترین نام کسانی که آن را می‌گیرند.
  List<(bool?, String)> _layoutChecks(CardTemplate t, Person? longest, String prefix) {
    final set = s.cards;
    final checks = <(bool?, String)>[]; // true خوب، false مشکل، null هشدار

    // ۱. جاشدن طولانی‌ترین نام در ناحیه‌ی امن.
    if (longest != null) {
      final cx = set.widthMm * t.nameX / 100;
      final availMm = 2 * [cx - _safe, set.widthMm - cx - _safe].reduce((a, b) => a < b ? a : b);
      final tp = TextPainter(
        text: TextSpan(
          text: longest.displayName,
          style: TextStyle(fontFamily: 'Vazirmatn', fontSize: t.nameSize, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      final widthMm = tp.width / _ptPerMm;
      if (availMm <= 0) {
        checks.add((false, '$prefixمرکز نام بیرون از ناحیه‌ی امن است.'));
      } else if (widthMm <= availMm) {
        checks.add((true, '$prefixهمه‌ی نام‌ها در یک خط و داخل ناحیه‌ی امن جا می‌شوند.'));
      } else if (widthMm <= availMm * 2) {
        checks.add((null, '$prefixطولانی‌ترین نام («${longest.displayName}») دو خطی چاپ می‌شود.'));
      } else {
        checks.add((false, '$prefixطولانی‌ترین نام حتی در دو خط جا نمی‌شود؛ اندازه‌ی نام را کم کنید.'));
      }
    }

    // ۲. اندازه‌ی QR.
    checks.add(t.qrSizeMm >= s.minQrMm
        ? (true, '$prefixاندازه‌ی QR ${faDigits(t.qrSizeMm.toStringAsFixed(0))} میلی‌متر؛ کافی است.')
        : (false, '${prefix}QR کمتر از ${faDigits(s.minQrMm.toStringAsFixed(0))} میلی‌متر است.'));

    // ۳. QR با حاشیه‌ی سکوت و خط‌های زیرش داخل ناحیه‌ی امن.
    final qx = set.widthMm * t.qrX / 100, qy = set.heightMm * t.qrY / 100, half = t.qrSizeMm / 2 + 3;
    final below = t.showSerial ? 8.0 : 4.0;
    final inside = qx - half >= _safe &&
        qx + half <= set.widthMm - _safe &&
        qy - half >= _safe &&
        qy + half + below <= set.heightMm - _safe;
    checks.add(inside
        ? (true, '${prefix}QR و حاشیه‌ی سکوتش داخل ناحیه‌ی امن است.')
        : (false, '${prefix}QR یا خط‌های زیرش از ناحیه‌ی امن بیرون زده؛ جایش یا اندازه‌اش را عوض کنید.'));
    return checks;
  }

  @override
  Widget build(BuildContext context) {
    final set = s.cards;
    final templates = set.activeTemplates;
    final groups = <String, List<Person>>{for (final t in templates) t.id: []};
    for (final p in people) {
      groups[s.templateOf(p).id]!.add(p);
    }
    final reserveId = set.reserveTemplate.id;
    final hasFree = s.reserveCards.any((r) => !r.used);
    // قالب‌هایی که کارتی با آن‌ها ساخته می‌شود؛ بقیه فقط یک هشدار می‌گیرند.
    final used = [
      for (final t in templates)
        if (groups[t.id]!.isNotEmpty || (hasFree && t.id == reserveId)) t,
    ];
    final multi = set.separate && templates.length > 1;

    final checks = <(bool?, String)>[];
    if (set.separate) {
      final unmatched = people.length - groups.values.fold<int>(0, (a, l) => a + l.length);
      checks.add((
        unmatched == 0,
        '${faDigits(templates.length)} قالب · ${faDigits(people.length)} نفر · ${faDigits(unmatched)} نفر بدون قالب '
            '(${templates.map((t) => '${t.name} ${faDigits(groups[t.id]!.length)}').join('، ')})',
      ));
      for (final t in templates) {
        if (!used.contains(t)) checks.add((null, 'قالب «${t.name}» به کسی نمی‌خورد و کارتی با آن ساخته نمی‌شود.'));
      }
    }
    for (final t in used) {
      final list = groups[t.id]!;
      final longest = list.isEmpty ? null : list.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b);
      checks.addAll(_layoutChecks(t, longest, multi ? 'قالب «${t.name}»: ' : ''));
    }

    final g = CardPageGeometry(trimW: set.widthMm, trimH: set.heightMm, bleed: set.bleedMm);
    final paths = [for (final t in used) ...[t.frontImage, t.backImage]];
    return FutureBuilder<List<(int, int)?>>(
      future: Future.wait(paths.map(_imageSize)),
      builder: (context, snap) {
        final all = [...checks];
        final sizes = snap.data;
        if (sizes != null) {
          for (var i = 0; i < used.length; i++) {
            final t = used[i];
            for (final (j, label) in [(0, 'روی'), (1, 'پشت')]) {
              final size = sizes[i * 2 + j];
              if (size == null) continue;
              final side = multi ? '$label «${t.name}»' : label;
              // ۴. اندازه‌ی طرح: نسبت و اندازه با کارت + حاشیه‌ی برش.
              final fit = artworkFit(pxW: size.$1, pxH: size.$2, needW: g.bleedW, needH: g.bleedH);
              all.add((fit.ok ? true : null, artworkMessage(side, fit)));
              // ۵. کیفیت: طرح کل ناحیه را می‌پوشاند، پس محور تنگ‌تر dpi واقعی است.
              final dpi = [size.$1 / (g.bleedW / 25.4), size.$2 / (g.bleedH / 25.4)].reduce((a, b) => a < b ? a : b);
              all.add(dpi >= 290
                  ? (true, 'تصویر $side: ${faDigits(dpi.round())} dpi.')
                  : (dpi >= 150
                      ? (null, 'تصویر $side: ${faDigits(dpi.round())} dpi؛ برای چاپ تیز ۳۰۰ لازم است.')
                      : (false, 'تصویر $side: ${faDigits(dpi.round())} dpi؛ چاپ تار می‌شود.')));
            }
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
  final CardTemplate t;
  final Person? person;
  const _Preview({required this.s, required this.t, required this.person});

  Widget _side(BuildContext context, double width, String imagePath, List<Widget> overlay) {
    final set = s.cards;
    final x = DaftarColors.of(context);
    final pxPerMm = width / set.widthMm;
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: set.widthMm / set.heightMm,
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
    final set = s.cards;
    final color = Color(int.parse('FF${normalizeHex(t.nameColor) ?? '10141A'}', radix: 16));
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth < 340 ? c.maxWidth : 340.0;
      final scale = width / (set.widthMm * 72 / 25.4); // pt → پیکسل پیش‌نمایش
      final role = person == null ? '' : s.roleName(person!.roleCode);
      return Wrap(spacing: 16, runSpacing: 16, children: [
        _side(context, width, t.frontImage, [
          _At(
            t.nameX,
            t.nameY,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4 * width / set.widthMm),
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
              padding: EdgeInsets.all(3 * width / set.widthMm),
              color: Colors.white,
              child: SizedBox(
                width: width * t.qrSizeMm / set.widthMm,
                height: width * t.qrSizeMm / set.widthMm,
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
