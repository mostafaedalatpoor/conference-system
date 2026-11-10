// اجزای طراحی کارت در «کارت‌ها»: سه پرسش اول، متن‌های کارت و ویرایشگرشان، فونت‌ها، فایل اکسل جدا،
// پیش‌نمایش رو و پشت، و بررسی پیش از چاپ.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../card_design.dart';
import '../card_text_fit.dart';
import '../cards_pdf.dart';
import '../excel_import.dart';
import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

const _ptToMm = 25.4 / 72;
const _safeMm = 4.0;

// ---------------------------------------------------------------- سه پرسش اول

/// یک‌رو یا دورو، QR یا نه، و QR روی کدام سمت. یک بار برای هر رویداد؛ بعد از بالای صفحه قابل تغییر.
class CardSetupForm extends StatefulWidget {
  final AdminState s;
  final bool initial;
  final VoidCallback onDone;
  const CardSetupForm({super.key, required this.s, required this.onDone, this.initial = false});

  @override
  State<CardSetupForm> createState() => _CardSetupFormState();
}

class _CardSetupFormState extends State<CardSetupForm> {
  late bool doubleSided = widget.s.template.doubleSided;
  late bool qr = widget.s.template.qrEnabled;
  late String qrSide = widget.s.template.qrSide;

  Future<void> _apply() async {
    final t = widget.s.template;
    final oldSide = t.effectiveQrSide;
    t
      ..doubleSided = doubleSided
      ..qrEnabled = qr
      ..qrSide = doubleSided ? qrSide : 'front'
      ..setupDone = true;
    // شماره‌ی کارت و راهنمای QR که زیر QR بودند، همراه QR به سمت تازه می‌روند.
    final newSide = t.effectiveQrSide;
    if (newSide != oldSide) {
      for (final ct in t.texts) {
        if (ct.source == 'field' && (ct.value == 'serial' || ct.value == 'qr_hint') && ct.side == oldSide) {
          ct.side = newSide;
        }
      }
    }
    final placed = t.qrEnabled && newSide == 'front' && newSide != oldSide && _placeQrBesideTexts(t);
    widget.s.notify();
    await widget.s.saveTemplate();
    if (placed && !widget.s.messageIsError) {
      widget.s.message = 'QR به روی کارت آمد و متن‌ها کنارش چیده شدند؛ در پیش‌نمایش ببینید و اگر لازم است جابه‌جا کنید.';
      widget.s.notify();
    }
    widget.onDone();
  }

  /// QR که به روی کارت می‌آید و روی متن‌ها می‌افتد: QR سمت چپ و متن‌ها در باقی جای راست.
  /// فقط پیشنهاد اول است؛ همه‌چیز بعداً قابل جابه‌جایی است.
  bool _placeQrBesideTexts(CardTemplate t) {
    const quiet = 3.0, gap = 2.0, below = 8.0;
    final size = t.qrSizeMm.clamp(10.0, t.heightMm - 2 * _safeMm - 2 * quiet - below);
    final qx = _safeMm + quiet + size / 2;
    final qy = (t.heightMm - below) / 2;
    final half = size / 2 + quiet;
    bool overlaps(CardText ct) {
      final cx = t.widthMm * ct.x / 100, cy = t.heightMm * ct.y / 100;
      final hh = ct.maxLines * ct.size * cardLineHeight * _ptToMm / 2;
      return cx - ct.widthMm / 2 < qx + half && cx + ct.widthMm / 2 > qx - half && cy - hh < qy + half && cy + hh > qy - half;
    }

    final qrTexts = {'serial', 'qr_hint'};
    final others = [
      for (final ct in t.textsFor('front'))
        if (!(ct.source == 'field' && qrTexts.contains(ct.value))) ct,
    ];
    if (!others.any(overlaps)) return false;
    t
      ..qrSizeMm = size
      ..qrX = qx / t.widthMm * 100
      ..qrY = qy / t.heightMm * 100;
    // شماره و راهنما زیر QR.
    var y = qy + half + 2;
    for (final ct in t.textsFor('front')) {
      if (ct.source == 'field' && qrTexts.contains(ct.value)) {
        ct
          ..x = t.qrX
          ..y = y / t.heightMm * 100
          ..widthMm = size + 2 * quiet;
        y += 3.7;
      }
    }
    // بقیه‌ی متن‌ها در ستون راست، با همان ترتیب عمودی.
    final left = qx + half + gap, right = t.widthMm - _safeMm;
    for (final ct in others) {
      ct
        ..x = (left + right) / 2 / t.widthMm * 100
        ..widthMm = right - left;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.s.settings;
    Widget q(String title, Widget control) => Padding(
          padding: const EdgeInsets.only(bottom: DaftarSize.space4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: DaftarSize.space2),
            control,
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.initial) ...[
        const Hint('پیش از طراحی، سه چیز را مشخص کنید. بعداً از بالای همین صفحه قابل تغییر است.'),
        const SizedBox(height: DaftarSize.space4),
      ],
      q(
        '۱. کارت یک‌رو است یا دورو؟',
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('یک‌رو')),
            ButtonSegment(value: true, label: Text('دورو')),
          ],
          selected: {doubleSided},
          onSelectionChanged: (v) => setState(() {
            doubleSided = v.first;
            if (!doubleSided) qrSide = 'front';
          }),
        ),
      ),
      q(
        '۲. QR روی کارت ساخته شود؟',
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('بله')),
            ButtonSegment(value: false, label: Text('نه')),
          ],
          selected: {qr},
          onSelectionChanged: (v) => setState(() => qr = v.first),
        ),
      ),
      if (qr && doubleSided)
        q(
          '۳. QR روی کدام سمت باشد؟',
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'front', label: Text('رو')),
              ButtonSegment(value: 'back', label: Text('پشت')),
            ],
            selected: {qrSide},
            onSelectionChanged: (v) => setState(() => qrSide = v.first),
          ),
        )
      else if (qr)
        const Padding(
          padding: EdgeInsets.only(bottom: DaftarSize.space4),
          child: Hint('کارت یک‌رو است، پس QR روی همان رو می‌آید.'),
        ),
      if (!qr && settings.identifyMode == 'scan')
        const Padding(
          padding: EdgeInsets.only(bottom: DaftarSize.space4),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'رویداد روی «کارت QR، با اسکن» است ولی کارت QR ندارد؛ نیروها نمی‌توانند کارت را اسکن کنند و باید نام را جستجو کنند. '
                'اگر اسکن نمی‌خواهید، در «پیکربندی» حالت را «کارت، بدون اسکن» کنید.',
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton(
          onPressed: widget.s.busy ? null : _apply,
          child: Text(widget.initial ? 'ادامه' : 'ذخیره'),
        ),
      ),
    ]);
  }
}

/// خلاصه‌ی سه پرسش بالای صفحه، با «تغییر».
class CardSetupSummary extends StatelessWidget {
  final AdminState s;
  const CardSetupSummary({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    final text = [
      t.doubleSided ? 'کارت دورو' : 'کارت یک‌رو',
      !t.qrEnabled ? 'بدون QR' : (t.effectiveQrSide == 'front' ? 'QR روی رو' : 'QR روی پشت'),
    ].join('، ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space3, vertical: DaftarSize.space2),
      decoration: BoxDecoration(
        color: DaftarColors.of(context).sunken,
        borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
      ),
      child: Row(children: [
        const Icon(Icons.style_rounded, size: 20),
        const SizedBox(width: DaftarSize.space2),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.labelLarge)),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('نوع کارت'),
              content: SizedBox(width: 460, child: CardSetupForm(s: s, onDone: () => Navigator.pop(c))),
            ),
          ),
          child: const Text('تغییر'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- فونت‌ها

class FontsSection extends StatelessWidget {
  final AdminState s;
  const FontsSection({super.key, required this.s});

  Future<void> _add(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ttf'], withData: true);
    final f = r?.files.single;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null) return;
    final problem = checkFontFile(bytes);
    if (problem != null) {
      s.message = problem;
      s.messageIsError = true;
      s.notify();
      return;
    }
    if (!context.mounted) return;
    final name = TextEditingController(text: f.name.replaceAll(RegExp(r'\.ttf$', caseSensitive: false), ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('نام فونت'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام (مثلاً «ایران‌سنس پررنگ»)')),
          const SizedBox(height: DaftarSize.space3),
          const Hint('مسئولیت مجوز استفاده از فونت با شماست.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بارگذاری')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) await s.uploadFont(name.text.trim(), Uint8List.fromList(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Hint('وزیرمتن همراه اپ است. فونت دیگر را به‌صورت فایل TTF اضافه کنید؛ روی سرور ذخیره می‌شود و روی ویندوز و گوشی هر دو هست. '
          'هر وزن (معمولی، پررنگ) یک فایل جداست.'),
      const SizedBox(height: DaftarSize.space2),
      Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final b in builtinFonts.values) DaftarTag(b.$1),
        for (final f in s.fonts)
          InputChip(
            label: Text(f.name, style: TextStyle(fontFamily: customFontFamily(f.id))),
            onDeleted: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('حذف فونت'),
                  content: Text('«${f.name}» حذف شود؟ متن‌هایی که این فونت را دارند با وزیرمتن چاپ می‌شوند.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
                    FilledButton(style: daftarDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
                  ],
                ),
              );
              if (ok == true) await s.deleteFont(f.id);
            },
            deleteIcon: Icon(Icons.close_rounded, size: 16, color: x.inkMuted),
          ),
        OutlinedButton.icon(
          onPressed: s.busy ? null : () => _add(context),
          icon: const Icon(Icons.font_download_rounded),
          label: const Text('افزودن فونت (TTF)'),
        ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- فایل اکسل جدا

/// داده‌ی فایل اکسل جدا که به افراد وصل شده.
class ExtraFileData {
  final List<String> headers;
  final Map<String, Map<String, String>> rows;
  final String? error;
  const ExtraFileData(this.headers, this.rows, [this.error]);
  static const empty = ExtraFileData([], {});
}

Future<ExtraFileData> loadExtraFile(AdminState s) async {
  final path = s.template.extraFile;
  if (path.isEmpty) return ExtraFileData.empty;
  final f = File(path);
  if (!await f.exists()) return const ExtraFileData([], {}, 'فایل اکسل جدا روی این دستگاه پیدا نشد؛ دوباره انتخابش کنید.');
  try {
    final tables = await readTables(f.uri.pathSegments.last, await f.readAsBytes());
    if (tables.isEmpty) return const ExtraFileData([], {}, 'فایل اکسل جدا خالی است.');
    final t = tables.first;
    final mapping = guessMapping(t.headers);
    if (!mapping.containsKey('email') && !mapping.containsKey('mobile') && !mapping.containsKey('full_name') &&
        !(mapping.containsKey('first_name') && mapping.containsKey('last_name'))) {
      return ExtraFileData(
        t.headers,
        const {},
        'در فایل جدا ستون ایمیل، موبایل یا نام پیدا نشد؛ ردیف‌ها به افراد وصل نمی‌شوند.',
      );
    }
    final rows = matchExtraFile(
      headers: t.headers,
      rows: t.rows,
      mapping: mapping,
      personKeys: {for (final p in s.people.values) p.id: (p.email, p.mobile, p.fullName)},
    );
    return ExtraFileData([for (final h in t.headers) if (h.trim().isNotEmpty) h.trim()], rows);
  } catch (e) {
    return ExtraFileData([], {}, 'خواندن فایل اکسل جدا ناموفق بود: $e');
  }
}

class ExtraFileSection extends StatelessWidget {
  final AdminState s;
  final ExtraFileData data;
  final VoidCallback onChanged;
  const ExtraFileSection({super.key, required this.s, required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Hint('برای متن‌هایی که از یک فایل اکسل دیگر می‌آیند. ردیف‌ها با ایمیل، یا اگر نبود موبایل، یا اگر نبود نام کامل به افراد وصل می‌شوند. '
          'این فایل روی همین دستگاه می‌ماند، مثل تصویر طرح.'),
      const SizedBox(height: DaftarSize.space2),
      Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.table_chart_rounded),
          label: Text(t.extraFile.isEmpty ? 'انتخاب فایل اکسل جدا' : 'فایل: ${t.extraFile.split(Platform.pathSeparator).last}'),
          onPressed: () async {
            final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
            final path = r?.files.single.path;
            if (path == null) return;
            t.extraFile = path;
            await s.save();
            onChanged();
          },
        ),
        if (t.extraFile.isNotEmpty)
          TextButton(
            onPressed: () async {
              t.extraFile = '';
              await s.save();
              onChanged();
            },
            child: const Text('برداشتن فایل'),
          ),
      ]),
      if (data.error != null)
        Padding(padding: const EdgeInsets.only(top: DaftarSize.space2), child: Notice(tone: NoticeTone.wait, text: data.error!))
      else if (t.extraFile.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: DaftarSize.space2),
          child: Notice(
            tone: data.rows.length < s.people.length ? NoticeTone.wait : NoticeTone.go,
            text: '${faDigits(data.rows.length)} از ${faDigits(s.people.length)} نفر در فایل جدا پیدا شد. '
                'ستون‌ها: ${data.headers.join('، ')}',
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- متن‌های کارت

/// ستون‌های اضافه‌ی اکسل ورود که در افراد ذخیره شده‌اند.
List<String> importedColumns(AdminState s) {
  final set = <String>{};
  for (final p in s.people.values) {
    set.addAll(p.extra.keys);
  }
  return set.toList()..sort();
}

class CardTextsSection extends StatelessWidget {
  final AdminState s;
  final ExtraFileData file;
  final VoidCallback onChanged;
  const CardTextsSection({super.key, required this.s, required this.file, required this.onChanged});

  Future<void> _edit(BuildContext context, CardText? existing, String side) async {
    final t = s.template;
    final draft = existing?.copy() ??
        CardText(
          id: 't${DateTime.now().microsecondsSinceEpoch}',
          side: side,
          source: 'static',
          widthMm: t.widthMm - 2 * _safeMm,
        );
    final result = await showDialog<String>(
      context: context,
      builder: (c) => _CardTextEditor(s: s, draft: draft, file: file, isNew: existing == null),
    );
    if (result == 'save') {
      if (existing == null) {
        t.texts.add(draft);
      } else {
        t.texts[t.texts.indexOf(existing)] = draft;
      }
    } else if (result == 'delete' && existing != null) {
      t.texts.remove(existing);
    } else {
      return;
    }
    await s.save();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    Widget sideList(String side, String title) {
      final list = [for (final ct in t.texts) if (ct.side == side) ct];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: DaftarSize.space1),
        if (list.isEmpty) const Hint('متنی نیست.'),
        for (final ct in list)
          Container(
            margin: const EdgeInsets.only(bottom: DaftarSize.space1),
            decoration: BoxDecoration(
              color: x.surface,
              border: Border.all(color: x.line),
              borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
            ),
            child: ListTile(
              dense: true,
              title: Text(ct.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${textSources[ct.source]}، '
                '${builtinFonts[ct.font]?.$1 ?? s.fonts.where((f) => f.id == ct.font).map((f) => f.name).firstOrNull ?? 'فونت حذف‌شده'}، '
                '${faDigits(ct.size.toStringAsFixed(ct.size == ct.size.roundToDouble() ? 0 : 1))}pt'
                '${ct.onReserve ? '' : '، نه روی رزرو'}',
              ),
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: () => _edit(context, ct, side),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('افزودن متن'),
            onPressed: () => _edit(context, null, side),
          ),
        ),
      ]);
    }

    return LayoutBuilder(builder: (context, c) {
      final front = sideList('front', 'روی کارت');
      if (!t.doubleSided) return front;
      final back = sideList('back', 'پشت کارت');
      if (c.maxWidth < 700) return Column(children: [front, const SizedBox(height: DaftarSize.space3), back]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: front),
        const SizedBox(width: DaftarSize.space4),
        Expanded(child: back),
      ]);
    });
  }
}

class _CardTextEditor extends StatefulWidget {
  final AdminState s;
  final CardText draft;
  final ExtraFileData file;
  final bool isNew;
  const _CardTextEditor({required this.s, required this.draft, required this.file, required this.isNew});

  @override
  State<_CardTextEditor> createState() => _CardTextEditorState();
}

class _CardTextEditorState extends State<_CardTextEditor> {
  int _rev = 0;
  CardText get d => widget.draft;

  Widget _num(String label, double value, void Function(double) on, {double step = 0, double width = 120, int digits = 1}) {
    final field = TextFormField(
      key: ValueKey('$label-$_rev'),
      initialValue: value.toStringAsFixed(value == value.roundToDouble() ? 0 : digits),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      onChanged: (v) {
        final n = double.tryParse(latinDigits(v));
        if (n != null) setState(() => on(n));
      },
    );
    if (step == 0) return SizedBox(width: width, child: field);
    return SizedBox(
      width: width + 88,
      child: Row(children: [
        IconButton(
          tooltip: 'کم',
          icon: const Icon(Icons.remove_rounded),
          onPressed: () => setState(() {
            on(double.parse((value - step).toStringAsFixed(1)));
            _rev++;
          }),
        ),
        Expanded(child: field),
        IconButton(
          tooltip: 'زیاد',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => setState(() {
            on(double.parse((value + step).toStringAsFixed(1)));
            _rev++;
          }),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final t = s.template;
    final theme = Theme.of(context);
    final columns = importedColumns(s);
    final fontItems = <DropdownMenuItem<String>>[
      for (final e in builtinFonts.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
      for (final f in s.fonts) DropdownMenuItem(value: f.id, child: Text(f.name, style: TextStyle(fontFamily: customFontFamily(f.id)))),
    ];
    if (!fontItems.any((i) => i.value == d.font)) d.font = 'vazir-bold';

    Widget valueField() {
      switch (d.source) {
        case 'static':
          return TextFormField(
            key: ValueKey('static-$_rev'),
            initialValue: d.value,
            decoration: const InputDecoration(labelText: 'متن'),
            onChanged: (v) => setState(() => d.value = v),
          );
        case 'field':
          return DropdownButtonFormField<String>(
            initialValue: systemFields.containsKey(d.value) ? d.value : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'فیلد'),
            items: [for (final e in systemFields.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => d.value = v ?? ''),
          );
        case 'column':
          if (columns.isEmpty) {
            return const Notice(
              tone: NoticeTone.wait,
              text: 'در فایل ورود شرکت‌کننده‌ها ستون اضافه‌ای نبوده. ستون‌هایی که به فیلدی نگاشت نمی‌شوند هنگام ورود اکسل نگه داشته می‌شوند؛ '
                  'اگر فایل را پیش از این نسخه وارد کرده‌اید، یک بار دوباره واردش کنید.',
            );
          }
          return DropdownButtonFormField<String>(
            initialValue: columns.contains(d.value) ? d.value : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ستون'),
            items: [for (final c in columns) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => d.value = v ?? ''),
          );
        default:
          if (widget.file.headers.isEmpty) {
            return const Notice(tone: NoticeTone.wait, text: 'اول در «فایل اکسل جدا» فایل را انتخاب کنید.');
          }
          return DropdownButtonFormField<String>(
            initialValue: widget.file.headers.contains(d.value) ? d.value : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ستون فایل جدا'),
            items: [for (final c in widget.file.headers) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => d.value = v ?? ''),
          );
      }
    }

    const gap = SizedBox(height: DaftarSize.space3);
    return AlertDialog(
      title: Text(widget.isNew ? 'متن تازه' : 'ویرایش متن'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (t.doubleSided) ...[
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'front', label: Text('روی کارت')),
                  ButtonSegment(value: 'back', label: Text('پشت کارت')),
                ],
                selected: {d.side},
                onSelectionChanged: (v) => setState(() => d.side = v.first),
              ),
              gap,
            ],
            DropdownButtonFormField<String>(
              initialValue: d.source,
              decoration: const InputDecoration(labelText: 'منبع متن'),
              items: [for (final e in textSources.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() {
                d.source = v ?? 'static';
                d.value = '';
                d.onReserve = d.source == 'static';
                _rev++;
              }),
            ),
            gap,
            valueField(),
            gap,
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: d.prefix,
                  decoration: const InputDecoration(labelText: 'پیش‌وند (اختیاری)', isDense: true),
                  onChanged: (v) => d.prefix = v,
                ),
              ),
              const SizedBox(width: DaftarSize.space2),
              Expanded(
                child: TextFormField(
                  initialValue: d.suffix,
                  decoration: const InputDecoration(labelText: 'پس‌وند (اختیاری)', isDense: true),
                  onChanged: (v) => d.suffix = v,
                ),
              ),
            ]),
            gap,
            Text('ظاهر', style: theme.textTheme.labelLarge),
            const SizedBox(height: DaftarSize.space2),
            DropdownButtonFormField<String>(
              initialValue: d.font,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'فونت', isDense: true),
              items: fontItems,
              onChanged: (v) => setState(() => d.font = v ?? 'vazir-bold'),
            ),
            gap,
            Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
              _num('اندازه (pt)', d.size, (v) => d.size = v.clamp(4, 120), step: 0.5),
              _num('کمینه‌ی کوچک‌شدن (pt)', d.minSize, (v) => d.minSize = v.clamp(4, 120), width: 150),
              SizedBox(
                width: 130,
                child: TextFormField(
                  initialValue: d.color,
                  decoration: const InputDecoration(labelText: 'رنگ (hex)', isDense: true, prefixText: '#'),
                  textDirection: TextDirection.ltr,
                  onChanged: (v) => setState(() => d.color = v.replaceAll('#', '').trim()),
                ),
              ),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<int>(
                  initialValue: d.maxLines,
                  decoration: const InputDecoration(labelText: 'بیشترین خط', isDense: true),
                  items: [for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text(faDigits(i)))],
                  onChanged: (v) => setState(() => d.maxLines = v ?? 1),
                ),
              ),
            ]),
            gap,
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right_rounded), label: Text('راست')),
                ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center_rounded), label: Text('وسط')),
                ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left_rounded), label: Text('چپ')),
              ],
              selected: {d.align},
              onSelectionChanged: (v) => setState(() => d.align = v.first),
            ),
            gap,
            Text('جا روی کارت', style: theme.textTheme.labelLarge),
            const SizedBox(height: DaftarSize.space2),
            Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
              _num('مرکز: افقی ٪', d.x, (v) => d.x = v.clamp(0, 100), step: 1),
              _num('مرکز: عمودی ٪', d.y, (v) => d.y = v.clamp(0, 100), step: 1),
              _num('عرض کادر (mm)', d.widthMm, (v) => d.widthMm = v.clamp(5, 500), step: 1),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: d.onReserve,
              onChanged: (v) => setState(() => d.onReserve = v),
              title: const Text('روی کارت‌های رزرو هم چاپ شود'),
              subtitle: const Text('کارت رزرو صاحب ندارد؛ متن‌های شخصی رویش خالی‌اند.'),
            ),
            const Hint('اگر مقدار این متن برای کسی خالی باشد، متن و پیش‌وندش روی کارت او چاپ نمی‌شود. '
                'اگر متن در کادر جا نشود، تا «کمینه» کوچک می‌شود.'),
          ]),
        ),
      ),
      actions: [
        if (!widget.isNew)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: DaftarColors.of(context).stop),
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('حذف'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: d.source != 'static' && d.value.isEmpty ? null : () => Navigator.pop(context, 'save'),
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- پیش‌نمایش

/// نمونه‌ی یک کارت برای پیش‌نمایش: نفر انتخاب‌شده، یا اگر کسی نیست مقدارهای نمونه.
CardSubject sampleSubject(AdminState s, Person? p, ExtraFileData file) {
  if (p != null) return personSubject(s, p, file.rows);
  return CardSubject(isReserve: false, fields: {
    'display_name': 'دکتر نام نمونه',
    'full_name': 'نام نمونه',
    'first_name': 'نام',
    'last_name': 'نمونه',
    'title': 'دکتر',
    'organization': 'سازمان نمونه',
    'role': 'سخنران',
    'type': 'ارائه‌دهنده',
    'serial': '۲۱۳',
    'qr_hint': s.template.qrEnabled ? s.qrHint(reserve: false) : '',
  }, extra: {
    // ستون‌ها نام خودشان را نشان می‌دهند تا جای متن در پیش‌نمایش دیده شود.
    for (final t in s.template.texts)
      if (t.source == 'column') t.value: '«${t.value}»',
  }, fileRow: {
    for (final t in s.template.texts)
      if (t.source == 'file') t.value: '«${t.value}»',
  });
}

class CardPreview extends StatelessWidget {
  final AdminState s;
  final CardSubject subject;
  const CardPreview({super.key, required this.s, required this.subject});

  Widget _side(BuildContext context, double width, String side) {
    final t = s.template;
    final x = DaftarColors.of(context);
    final pxPerMm = width / t.widthMm;
    final ptPx = _ptToMm * pxPerMm;
    final image = side == 'front' ? t.frontImage : t.backImage;
    Color col(String hex) {
      try {
        return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
      } catch (_) {
        return const Color(0xFF10141A);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(side == 'front' ? 'رو' : 'پشت', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: DaftarSize.space1),
      SizedBox(
        width: width,
        height: width * t.heightMm / t.widthMm,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: x.lineStrong), color: Colors.white),
          clipBehavior: Clip.hardEdge,
          child: Stack(children: [
            if (image.isNotEmpty && File(image).existsSync())
              Positioned.fill(child: Image.file(File(image), fit: BoxFit.cover))
            else if ((side == 'front' ? t.frontImageUrl : t.backImageUrl).isNotEmpty)
              Positioned.fill(child: Image.network(side == 'front' ? t.frontImageUrl : t.backImageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
            for (final sh in t.shapes)
              if (sh.side == side)
                Positioned(
                  left: (t.widthMm * sh.x / 100 - sh.widthMm / 2) * pxPerMm,
                  top: (t.heightMm * sh.y / 100 - sh.heightMm / 2) * pxPerMm,
                  width: sh.widthMm * pxPerMm,
                  height: sh.heightMm * pxPerMm,
                  child: DecoratedBox(decoration: BoxDecoration(color: col(sh.color), borderRadius: BorderRadius.circular(sh.radiusMm * pxPerMm))),
                ),
            for (final im in t.images)
              if (im.side == side)
                Positioned(
                  left: (t.widthMm * im.x / 100 - im.widthMm / 2) * pxPerMm,
                  top: (t.heightMm * im.y / 100 - im.heightMm / 2) * pxPerMm,
                  width: im.widthMm * pxPerMm,
                  height: im.heightMm * pxPerMm,
                  child: Image.network(im.url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_rounded)),
                ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(_safeMm * pxPerMm),
                child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: x.stamp.withValues(alpha: .5)))),
              ),
            ),
            if (t.qrEnabled && t.effectiveQrSide == side)
              Positioned(
                left: (t.widthMm * t.qrX / 100 - t.qrSizeMm / 2 - 3) * pxPerMm,
                top: (t.heightMm * t.qrY / 100 - t.qrSizeMm / 2 - 3) * pxPerMm,
                child: Container(
                  color: Colors.white,
                  padding: EdgeInsets.all(3 * pxPerMm),
                  child: SizedBox.square(
                    dimension: t.qrSizeMm * pxPerMm,
                    child: const FittedBox(child: Icon(Icons.qr_code_2_rounded, color: Colors.black)),
                  ),
                ),
              ),
            for (final ct in t.textsFor(side))
              if (resolveCardText(ct, subject) case final v?)
                Builder(builder: (context) {
                  final (size, _) = fitCardText(v, ct);
                  final boxW = ct.widthMm * pxPerMm;
                  final boxH = ct.maxLines * size * cardLineHeight * ptPx;
                  return Positioned(
                    left: t.widthMm * ct.x / 100 * pxPerMm - boxW / 2,
                    top: t.heightMm * ct.y / 100 * pxPerMm - boxH / 2,
                    width: boxW,
                    height: boxH,
                    child: Center(
                      child: SizedBox(
                        width: boxW,
                        child: Text(
                          v,
                          textDirection: TextDirection.rtl,
                          textAlign: cardTextAlign(ct.align),
                          maxLines: ct.maxLines,
                          overflow: TextOverflow.clip,
                          style: cardTextStyle(ct.font, size * ptPx, color: col(ct.color)),
                        ),
                      ),
                    ),
                  );
                }),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final width = c.maxWidth < 360 ? c.maxWidth : 360.0;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          _side(context, width, 'front'),
          if (s.template.doubleSided) _side(context, width, 'back'),
        ]);
      });
}

// ---------------------------------------------------------------- بررسی پیش از چاپ

class CardPreflight extends StatelessWidget {
  final AdminState s;
  final ExtraFileData file;
  const CardPreflight({super.key, required this.s, required this.file});

  static final _sizes = <String, Future<(int, int)?>>{};
  Future<(int, int)?> _imageSize(String path) => _sizes.putIfAbsent(path, () async {
        if (path.isEmpty) return null;
        final f = File(path);
        if (!await f.exists()) return null;
        final codec = await ui.instantiateImageCodec(await f.readAsBytes());
        final frame = await codec.getNextFrame();
        return (frame.image.width, frame.image.height);
      });

  @override
  Widget build(BuildContext context) {
    final t = s.template;
    final checks = <(bool?, String)>[]; // true خوب، false مشکل، null هشدار
    final subjects = [
      for (final p in s.sortedPeople) personSubject(s, p, file.rows),
      if (s.reserveCards.isNotEmpty) reserveSubject(s, s.reserveCards.first),
    ];

    // هر متن: طولانی‌ترین مقدار در کادر جا می‌شود؟ کادر داخل ناحیه‌ی امن است؟
    for (final side in t.doubleSided ? const ['front', 'back'] : const ['front']) {
      for (final ct in t.textsFor(side)) {
        final values = [for (final sub in subjects) if (resolveCardText(ct, sub) case final v?) v];
        if (ct.source == 'static' && values.isEmpty && ct.value.trim().isNotEmpty) values.add(ct.value);
        if (values.isEmpty) {
          if (ct.source != 'static') checks.add((null, '${ct.label}: برای هیچ‌کس مقداری ندارد.'));
          continue;
        }
        final longest = values.reduce((a, b) => a.length >= b.length ? a : b);
        final (size, fits) = fitCardText(longest, ct);
        if (!fits) {
          checks.add((false, '${ct.label}: «$longest» حتی با ${faDigits(ct.minSize.toStringAsFixed(0))}pt جا نمی‌شود؛ کادر را پهن‌تر یا خط را بیشتر کنید.'));
        } else if (size < ct.size) {
          checks.add((null, '${ct.label}: متن‌های بلند تا ${faDigits(size.toStringAsFixed(1))}pt کوچک می‌شوند.'));
        }
        final cx = t.widthMm * ct.x / 100, cy = t.heightMm * ct.y / 100;
        final boxH = ct.maxLines * size * cardLineHeight * _ptToMm;
        final inside = cx - ct.widthMm / 2 >= _safeMm - 0.01 &&
            cx + ct.widthMm / 2 <= t.widthMm - _safeMm + 0.01 &&
            cy - boxH / 2 >= _safeMm - 0.01 &&
            cy + boxH / 2 <= t.heightMm - _safeMm + 0.01;
        if (!inside) checks.add((false, '${ct.label}: کادر متن از ناحیه‌ی امن بیرون زده.'));
        if (!builtinFonts.containsKey(ct.font) && s.fontBytes(ct.font) == null) {
          checks.add((false, '${ct.label}: فونتش روی این دستگاه نیست و با وزیرمتن چاپ می‌شود.'));
        }
      }
    }
    if (checks.where((c) => c.$1 != true).isEmpty && t.texts.isNotEmpty) {
      checks.add((true, 'همه‌ی متن‌ها جا می‌شوند و داخل ناحیه‌ی امن‌اند.'));
    }

    if (t.qrEnabled) {
      checks.add(t.qrSizeMm >= s.minQrMm
          ? (true, 'اندازه‌ی QR ${faDigits(t.qrSizeMm.toStringAsFixed(0))} میلی‌متر؛ کافی است.')
          : (false, 'QR کمتر از ${faDigits(s.minQrMm.toStringAsFixed(0))} میلی‌متر است.'));
      final qx = t.widthMm * t.qrX / 100, qy = t.heightMm * t.qrY / 100, half = t.qrSizeMm / 2 + 3;
      final inside = qx - half >= _safeMm && qx + half <= t.widthMm - _safeMm && qy - half >= _safeMm && qy + half <= t.heightMm - _safeMm;
      checks.add(inside
          ? (true, 'QR و حاشیه‌ی سکوتش داخل ناحیه‌ی امن است.')
          : (false, 'QR از ناحیه‌ی امن بیرون زده؛ جایش یا اندازه‌اش را عوض کنید.'));
      // متنی که روی QR یا حاشیه‌ی سکوتش بیفتد اسکن را خراب می‌کند.
      for (final ct in t.textsFor(t.effectiveQrSide)) {
        final cx = t.widthMm * ct.x / 100, cy = t.heightMm * ct.y / 100;
        final halfH = ct.maxLines * ct.size * cardLineHeight * _ptToMm / 2;
        const tol = 0.2; // میلی‌متر؛ لبه‌ی کادر متن بالاتر از خود حروف است
        final overlaps = cx - ct.widthMm / 2 < qx + half - tol &&
            cx + ct.widthMm / 2 > qx - half + tol &&
            cy - halfH < qy + half - tol &&
            cy + halfH > qy - half + tol;
        if (overlaps) checks.add((false, '${ct.label}: کادر متن روی QR افتاده؛ متن یا QR را جابه‌جا کنید.'));
      }
    } else if (s.settings.identifyMode == 'scan') {
      checks.add((null, 'کارت QR ندارد ولی رویداد روی «کارت QR، با اسکن» است؛ نیروها باید نام را جستجو کنند.'));
    }

    return FutureBuilder<List<(int, int)?>>(
      future: Future.wait([_imageSize(t.frontImage), if (t.doubleSided) _imageSize(t.backImage)]),
      builder: (context, snap) {
        final all = [...checks];
        final sizes = snap.data;
        if (sizes != null) {
          for (var i = 0; i < sizes.length; i++) {
            final size = sizes[i];
            if (size == null) continue;
            final label = i == 0 ? 'رو' : 'پشت';
            final dpi = size.$1 / ((t.widthMm + 6) / 25.4);
            all.add(dpi >= 290
                ? (true, 'تصویر $label: ${faDigits(dpi.round())} dpi.')
                : (dpi >= 150
                    ? (null, 'تصویر $label: ${faDigits(dpi.round())} dpi؛ برای چاپ تیز ۳۰۰ لازم است.')
                    : (false, 'تصویر $label: ${faDigits(dpi.round())} dpi؛ چاپ تار می‌شود.')));
          }
        }
        final x = DaftarColors.of(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (ok, text) in all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  ok == true ? Icons.check_circle_rounded : (ok == null ? Icons.warning_rounded : Icons.error_rounded),
                  size: 18,
                  color: ok == true ? x.go : (ok == null ? x.wait : x.stop),
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
