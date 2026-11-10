// ساخت کارت روی گوشی (طرح ۱۴ تا ۱۶): ۱. مشخصات (اندازه، جهت، رو، QR، برش و حاشیه‌ی امن)،
// ۲. طرح زمینه روی سرور، ۳. چیدمان با پیش‌نمایش چسبان، مبدأ و X/Y میلی‌متری، و بررسی و ساخت PDF.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../card_design.dart';
import '../card_text_fit.dart';
import '../cards_pdf.dart';
import '../main.dart';
import '../normalize.dart';
import '../screens/cards.dart' show CardSheetSettings;
import '../screens/registration.dart' show saveBytesAs;
import '../state.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart' show NvPageHeader, confirmDanger;

const _ptToMm = 25.4 / 72;

String cardSpecLine(CardTemplate t) => [
      '${faDigits(_fmt(t.widthMm))}×${faDigits(_fmt(t.heightMm))} میلی‌متر',
      t.heightMm > t.widthMm ? 'عمودی' : 'افقی',
      t.doubleSided ? 'دورو' : 'یک‌رو',
      t.qrEnabled ? 'با QR' : 'بدون QR',
    ].join(' · ');

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

bool hasDesign(AdminState s) {
  final t = s.template;
  return t.frontImageUrl.isNotEmpty || (t.frontImage.isNotEmpty && File(t.frontImage).existsSync());
}

int elementCount(CardTemplate t) => t.texts.length + t.images.length + t.shapes.length + (t.qrEnabled ? 1 : 0);

// ---------------------------------------------------------------- عنصرها

/// یک عنصر روی کارت با جای مرکزی درصدی و اندازه‌ی میلی‌متری؛ برای ویرایشگر یکسان.
class _El {
  final String kind; // text | qr | image | shape
  final Object ref;
  _El(this.kind, this.ref);

  String get id => switch (ref) {
        CardText t => t.id,
        CardImage i => i.id,
        CardShape x => x.id,
        _ => 'qr',
      };

  String side(CardTemplate t) => switch (ref) {
        CardText x => x.side,
        CardImage x => x.side,
        CardShape x => x.side,
        _ => t.effectiveQrSide,
      };

  double cx(CardTemplate t) => switch (ref) { CardText x => x.x, CardImage x => x.x, CardShape x => x.x, _ => t.qrX };
  double cy(CardTemplate t) => switch (ref) { CardText x => x.y, CardImage x => x.y, CardShape x => x.y, _ => t.qrY };

  void setCenter(CardTemplate t, double x, double y) {
    switch (ref) {
      case CardText e:
        e
          ..x = x
          ..y = y;
      case CardImage e:
        e
          ..x = x
          ..y = y;
      case CardShape e:
        e
          ..x = x
          ..y = y;
      default:
        t
          ..qrX = x
          ..qrY = y;
    }
  }

  double w(CardTemplate t) => switch (ref) { CardText x => x.widthMm, CardImage x => x.widthMm, CardShape x => x.widthMm, _ => t.qrSizeMm + 6 };
  double h(CardTemplate t) => switch (ref) {
        CardText x => x.maxLines * x.size * cardLineHeight * _ptToMm,
        CardImage x => x.heightMm,
        CardShape x => x.heightMm,
        _ => t.qrSizeMm + 6,
      };

  String anchor(CardTemplate t) => switch (ref) { CardText x => x.anchor, CardImage x => x.anchor, CardShape x => x.anchor, _ => t.qrAnchor };
  void setAnchor(CardTemplate t, String a) {
    switch (ref) {
      case CardText e:
        e.anchor = a;
      case CardImage e:
        e.anchor = a;
      case CardShape e:
        e.anchor = a;
      default:
        t.qrAnchor = a;
    }
  }

  String label(AdminState s) => switch (ref) {
        CardText x => '${x.label} · متن',
        CardImage _ => 'تصویر',
        CardShape _ => 'مستطیل',
        _ => 'QR',
      };
}

List<_El> _elements(CardTemplate t, String side) => [
      for (final x in t.shapes) if (x.side == side) _El('shape', x),
      for (final x in t.images) if (x.side == side) _El('image', x),
      if (t.qrEnabled && t.effectiveQrSide == side) _El('qr', 'qr'),
      for (final x in t.textsFor(side)) _El('text', x),
    ];

// ---------------------------------------------------------------- بررسی‌ها

class CardCheckItem {
  final bool? ok; // true خوب، false مشکل، null هشدار
  final String text;
  const CardCheckItem(this.ok, this.text);
}

/// بررسی‌های پیش از چاپ (بدون فایل اکسل جدا): افراد، نام‌های بلند، ناحیه‌ی امن، QR، طرح.
List<CardCheckItem> cardWarnings(AdminState s) {
  final t = s.template;
  final out = <CardCheckItem>[];
  final people = s.sortedPeople;
  out.add(people.isEmpty ? const CardCheckItem(false, 'هنوز کسی برای کارت وارد نشده.') : CardCheckItem(true, '${faDigits(people.length)} نفر برای کارت آماده‌اند.'));
  if (!hasDesign(s)) out.add(const CardCheckItem(null, 'طرح زمینه انتخاب نشده؛ کارت سفید چاپ می‌شود.'));
  final incomplete = s.people.values.where((p) => p.missingName).length;
  if (incomplete > 0) out.add(CardCheckItem(null, '${faDigits(incomplete)} نفر نام یا نام خانوادگی ندارند؛ کارتشان ناقص چاپ می‌شود.'));
  final subjects = [for (final p in people) personSubject(s, p, const {})];
  var allInside = true;
  for (final side in t.doubleSided ? const ['front', 'back'] : const ['front']) {
    for (final e in _elements(t, side)) {
      final cx = t.widthMm * e.cx(t) / 100, cy = t.heightMm * e.cy(t) / 100, w = e.w(t), h = e.h(t);
      final m = t.safeMm - 0.01;
      if (cx - w / 2 < m || cx + w / 2 > t.widthMm - m || cy - h / 2 < m || cy + h / 2 > t.heightMm - m) {
        allInside = false;
        out.add(CardCheckItem(false, '${e.label(s)} از حاشیه‌ی امن بیرون زده.'));
      }
    }
    for (final ct in t.textsFor(side)) {
      final values = [for (final sub in subjects) if (resolveCardText(ct, sub) case final v?) v];
      if (values.isEmpty) continue;
      final longest = values.reduce((a, b) => a.length >= b.length ? a : b);
      final (size, fits) = fitCardText(longest, ct);
      if (!fits) {
        out.add(CardCheckItem(false, '«$longest» از عرض کادر بیرون می‌زند، حتی با ${faDigits(_fmt(ct.minSize))}pt.'));
      } else if (size < ct.size - 0.05) {
        out.add(CardCheckItem(null, '«$longest» جا نمی‌شود؛ قلم خودکار کوچک می‌شود (${faDigits(_fmt(size))}).'));
      }
    }
  }
  if (allInside && elementCount(t) > 0) out.add(const CardCheckItem(true, 'همه‌ی عنصرها داخل حاشیه‌ی امن‌اند.'));
  if (t.qrEnabled && t.qrSizeMm < s.minQrMm) out.add(CardCheckItem(false, 'QR کوچک است؛ کمینه ${faDigits(_fmt(s.minQrMm))} میلی‌متر.'));
  return out;
}

// ---------------------------------------------------------------- ۱. مشخصات کارت (طرح ۱۴)

const _presets = <(String, double, double)>[
  ('۹×۱۳ بج', 90, 130),
  ('۱۰×۱۵', 100, 150),
  ('A6', 105, 148),
  ('کارت بانکی', 85.6, 54),
];

class CardSpecsPage extends StatefulWidget {
  const CardSpecsPage({super.key});

  @override
  State<CardSpecsPage> createState() => _CardSpecsPageState();
}

class _CardSpecsPageState extends State<CardSpecsPage> {
  late final CardTemplate t = StateScope.read(context).template;
  late final _w = TextEditingController(text: _fmt(t.widthMm));
  late final _h = TextEditingController(text: _fmt(t.heightMm));
  late bool _qr = t.qrEnabled;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _size(double w, double h) => setState(() {
        final portrait = t.heightMm > t.widthMm;
        final (a, b) = (w < h ? w : h, w < h ? h : w);
        t
          ..widthMm = portrait ? a : b
          ..heightMm = portrait ? b : a;
        _w.text = _fmt(t.widthMm);
        _h.text = _fmt(t.heightMm);
      });

  Future<void> _save() async {
    final s = StateScope.read(context);
    final w = double.tryParse(latinDigits(_w.text)), h = double.tryParse(latinDigits(_h.text));
    if (w == null || h == null || w < 30 || h < 30 || w > 400 || h > 400) {
      s.message = 'عرض و ارتفاع کارت بین ۳۰ تا ۴۰۰ میلی‌متر باشد.';
      s.messageIsError = true;
      s.notify();
      return;
    }
    t
      ..widthMm = w
      ..heightMm = h
      ..qrEnabled = _qr
      ..setupDone = true;
    if (!t.doubleSided) t.qrSide = 'front';
    // QR ندارد ← نیروها با شماره‌ی کارت کار می‌کنند؛ QR دارد ← اسکن.
    final mode = s.settings.identifyMode;
    final newMode = !_qr && mode == 'scan' ? 'card' : (_qr && mode == 'card' ? 'scan' : mode);
    if (newMode != mode) {
      s.settings.identifyMode = newMode;
      await s.pushConfig();
    }
    await s.saveTemplate();
    if (!mounted || s.messageIsError) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CardBackgroundPage()));
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final portrait = t.heightMm > t.widthMm;
    Widget title(String x) => Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 8), child: Text(x, style: nvText(context, 15, w: FontWeight.w800)));
    Widget seg<T>(T value, List<(T, String, IconData?)> items, ValueChanged<T> on) => SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [for (final (v, l, i) in items) ButtonSegment(value: v, label: Text(l), icon: i == null ? null : Icon(i))],
          selected: {value},
          onSelectionChanged: (v) => on(v.first),
        );
    final matched = _presets.where((p) => ((p.$2 - t.widthMm).abs() < .1 && (p.$3 - t.heightMm).abs() < .1) || ((p.$3 - t.widthMm).abs() < .1 && (p.$2 - t.heightMm).abs() < .1)).firstOrNull;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        const NvPageHeader(title: 'مشخصات کارت', subtitle: 'کارت · مرحله‌ی ۱ از ۳'),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            title('اندازه'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _presets) ChoiceChip(label: Text(p.$1), selected: matched == p, onSelected: (_) => _size(p.$2, p.$3)),
              ChoiceChip(label: const Text('دلخواه'), selected: matched == null, onSelected: (_) {}),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: NvField(label: 'عرض (میلی‌متر)', child: TextField(controller: _w, keyboardType: TextInputType.number, onChanged: (v) => setState(() => t.widthMm = double.tryParse(latinDigits(v)) ?? t.widthMm)))),
              const SizedBox(width: 10),
              Expanded(child: NvField(label: 'ارتفاع (میلی‌متر)', child: TextField(controller: _h, keyboardType: TextInputType.number, onChanged: (v) => setState(() => t.heightMm = double.tryParse(latinDigits(v)) ?? t.heightMm)))),
            ]),
            title('جهت و رو'),
            seg<bool>(portrait, const [(true, 'عمودی', Icons.crop_portrait_rounded), (false, 'افقی', Icons.crop_landscape_rounded)], (v) {
              if (v != portrait) {
                setState(() {
                  final w = t.widthMm;
                  t
                    ..widthMm = t.heightMm
                    ..heightMm = w;
                  _w.text = _fmt(t.widthMm);
                  _h.text = _fmt(t.heightMm);
                });
              }
            }),
            const SizedBox(height: 10),
            seg<bool>(t.doubleSided, const [(false, 'یک‌رو', null), (true, 'دورو', null)], (v) => setState(() => t.doubleSided = v)),
            title('QR روی کارت'),
            seg<bool>(_qr, const [(true, 'دارد', Icons.qr_code_2_rounded), (false, 'ندارد', null)], (v) => setState(() => _qr = v)),
            if (t.doubleSided && _qr) ...[
              const SizedBox(height: 10),
              seg<String>(t.qrSide, const [('front', 'QR روی کارت', null), ('back', 'QR پشت کارت', null)], (v) => setState(() => t.qrSide = v)),
            ],
            const SizedBox(height: 6),
            Text('اگر «ندارد» باشد، سرور هم باخبر می‌شود و اپ نیروها با شماره‌ی کارت کار می‌کند.', style: nvText(context, 12, color: c.muted)),
            title('برش و حاشیه‌ی امن'),
            _Stepper(label: 'حاشیه‌ی برش (bleed)', value: t.bleedMm, step: .5, min: 0, max: 10, onChanged: (v) => setState(() => t.bleedMm = v)),
            _Stepper(label: 'حاشیه‌ی امن', value: t.safeMm, step: .5, min: 0, max: 20, onChanged: (v) => setState(() => t.safeMm = v)),
            const SizedBox(height: 10),
            Center(child: _SpecsDiagram(t: t)),
            const SizedBox(height: 6),
            Center(child: Text('قرمز: برش · سبز: ناحیه‌ی امن', style: nvText(context, 12, color: c.muted))),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
          child: NvButton(label: 'ذخیره و طرح زمینه', busy: s.busy, onPressed: s.busy ? null : _save),
        ),
      ]),
    );
  }
}

class _SpecsDiagram extends StatelessWidget {
  final CardTemplate t;
  const _SpecsDiagram({required this.t});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    const maxSide = 200.0;
    final bw = t.widthMm + 2 * t.bleedMm, bh = t.heightMm + 2 * t.bleedMm;
    final k = maxSide / (bw > bh ? bw : bh);
    return Container(
      width: bw * k,
      height: bh * k,
      color: c.surface,
      child: Stack(children: [
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.stop.withValues(alpha: .4))))),
        Positioned(
          left: t.bleedMm * k,
          top: t.bleedMm * k,
          width: t.widthMm * k,
          height: t.heightMm * k,
          child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.stop, width: 1.5))),
        ),
        Positioned(
          left: (t.bleedMm + t.safeMm) * k,
          top: (t.bleedMm + t.safeMm) * k,
          width: (t.widthMm - 2 * t.safeMm) * k,
          height: (t.heightMm - 2 * t.safeMm) * k,
          child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.go, width: 1.5))),
        ),
      ]),
    );
  }
}

/// عدد با − و + (گام ثابت)؛ مناسب انگشت.
class _Stepper extends StatelessWidget {
  final String label;
  final double value, step, min, max;
  final ValueChanged<double> onChanged;
  final String unit;
  const _Stepper({required this.label, required this.value, required this.step, required this.min, required this.max, required this.onChanged, this.unit = 'میلی‌متر'});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    double clamp(double v) => double.parse(v.clamp(min, max).toStringAsFixed(2));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: nvText(context, 14, w: FontWeight.w600))),
        Container(
          height: 44,
          decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
          child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
            IconButton(tooltip: 'کم', onPressed: () => onChanged(clamp(value - step)), icon: const Icon(Icons.remove_rounded)),
            InkWell(
              onTap: () async {
                final ctl = TextEditingController(text: _fmt(value));
                final v = await showDialog<double>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text(label),
                    content: TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(suffixText: unit)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: const Text('انصراف')),
                      FilledButton(onPressed: () => Navigator.pop(d, double.tryParse(latinDigits(ctl.text))), child: const Text('باشه')),
                    ],
                  ),
                );
                if (v != null) onChanged(clamp(v));
              },
              child: SizedBox(width: 64, child: Text(faDigits(_fmt(value)), textAlign: TextAlign.center, style: nvText(context, 15, w: FontWeight.w800))),
            ),
            IconButton(tooltip: 'زیاد', onPressed: () => onChanged(clamp(value + step)), icon: const Icon(Icons.add_rounded)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ۲. طرح زمینه

class CardBackgroundPage extends StatefulWidget {
  const CardBackgroundPage({super.key});

  @override
  State<CardBackgroundPage> createState() => _CardBackgroundPageState();
}

class _CardBackgroundPageState extends State<CardBackgroundPage> {
  final Map<String, String> _notes = {};

  Future<void> _pick(AdminState s, String side) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'], withData: true);
    final bytes = r?.files.single.bytes ?? (r?.files.single.path == null ? null : await File(r!.files.single.path!).readAsBytes());
    if (bytes == null) return;
    final t = s.template;
    // DPI از روی عرض (با حاشیه‌ی برش دو طرف).
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      final dpi = img.width / ((t.widthMm + 2 * t.bleedMm) / 25.4);
      final need = ((t.widthMm + 2 * t.bleedMm) / 25.4 * 300).round();
      final needH = ((t.heightMm + 2 * t.bleedMm) / 25.4 * 300).round();
      _notes[side] = dpi >= 290
          ? '${faDigits(img.width)}×${faDigits(img.height)} پیکسل، ${faDigits(dpi.round())} dpi؛ برای چاپ خوب است.'
          : '${faDigits(dpi.round())} dpi؛ برای چاپ تیز دست‌کم ${faDigits(need)}×${faDigits(needH)} پیکسل لازم است.';
    } catch (_) {
      _notes[side] = 'تصویر خوانده نشد.';
      setState(() {});
      return;
    }
    final url = await s.uploadCardAsset(bytes);
    if (url == null) return;
    setState(() {
      if (side == 'front') {
        t
          ..frontImageUrl = url
          ..frontImage = '';
      } else {
        t
          ..backImageUrl = url
          ..backImage = '';
      }
    });
    await s.saveTemplate();
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final t = s.template;
    Widget side(String side, String label) {
      final url = side == 'front' ? t.frontImageUrl : t.backImageUrl;
      final local = side == 'front' ? t.frontImage : t.backImage;
      return NvCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: nvText(context, 15, w: FontWeight.w800)),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: t.widthMm / t.heightMm,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r12), border: Border.all(color: c.lineSoft)),
              child: url.isNotEmpty
                  ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded)))
                  : (local.isNotEmpty && File(local).existsSync()
                      ? Image.file(File(local), fit: BoxFit.cover)
                      : Center(child: Text('بدون طرح (سفید)', style: nvText(context, 13, color: c.muted)))),
            ),
          ),
          if (_notes[side] != null) ...[const SizedBox(height: 8), Text(_notes[side]!, style: nvText(context, 12, color: c.muted))],
          const SizedBox(height: 10),
          NvSoftButton(label: url.isEmpty ? 'انتخاب تصویر' : 'عوض کردن تصویر', icon: Icons.image_rounded, onPressed: s.busy ? null : () => _pick(s, side)),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        const NvPageHeader(title: 'طرح زمینه', subtitle: 'کارت · مرحله‌ی ۲ از ۳'),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            NvBanner(
              tone: NvTone.info,
              text: 'PNG یا JPG با ۳۰۰ dpi و حاشیه‌ی برش ${faDigits(_fmt(t.bleedMm))} میلی‌متر از هر طرف '
                  '(برای ${faDigits(_fmt(t.widthMm))}×${faDigits(_fmt(t.heightMm))}، فایل ${faDigits(_fmt(t.widthMm + 2 * t.bleedMm))}×${faDigits(_fmt(t.heightMm + 2 * t.bleedMm))} میلی‌متر). '
                  'تصویر روی سرور می‌رود تا همه‌ی دستگاه‌ها یک طرح ببینند.',
            ),
            if (s.busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            side('front', 'روی کارت'),
            if (t.doubleSided) ...[const SizedBox(height: 12), side('back', 'پشت کارت')],
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
          child: NvButton(
            label: 'ادامه: چیدمان',
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CardEditorPage())),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ۳. چیدمان (طرح ۱۵)

class CardEditorPage extends StatefulWidget {
  const CardEditorPage({super.key});

  @override
  State<CardEditorPage> createState() => _CardEditorPageState();
}

class _CardEditorPageState extends State<CardEditorPage> {
  String _side = 'front';
  String? _sel;
  final List<String> _undo = [];
  bool _dirty = false;
  Map<String, dynamic>? _dragStart;

  CardTemplate get t => StateScope.read(context).template;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = StateScope.read(context);
      // تصویرهای روی سرور یک بار گرفته می‌شوند تا پیش‌نمایش سریع باشد.
      for (final u in [s.template.frontImageUrl, s.template.backImageUrl, for (final i in s.template.images) i.url]) {
        await s.assetBytes(u);
      }
      if (mounted) setState(() {});
    });
  }

  void _snap() {
    _undo.add(jsonEncode(t.toJson()));
    if (_undo.length > 30) _undo.removeAt(0);
    _dirty = true;
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    final s = StateScope.read(context);
    final keepLocal = (t.frontImage, t.backImage, t.extraFile);
    s.template.load((jsonDecode(_undo.removeLast()) as Map).cast<String, dynamic>());
    t
      ..frontImage = keepLocal.$1
      ..backImage = keepLocal.$2
      ..extraFile = keepLocal.$3;
    setState(() {});
  }

  _El? _selected() => _elements(t, _side).where((e) => e.id == _sel).firstOrNull;

  String _newId(String p) => '$p${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _addImage(AdminState s) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'], withData: true);
    final bytes = r?.files.single.bytes ?? (r?.files.single.path == null ? null : await File(r!.files.single.path!).readAsBytes());
    if (bytes == null) return;
    var ratio = 1.0;
    try {
      final img = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
      ratio = img.height / img.width;
    } catch (_) {}
    final url = await s.uploadCardAsset(bytes);
    if (url == null || !mounted) return;
    await s.assetBytes(url);
    _snap();
    final im = CardImage(id: _newId('i'), side: _side, url: url, widthMm: 20, heightMm: double.parse((20 * ratio).toStringAsFixed(1)), anchor: 'tc');
    final (x, y) = centerFromAnchor('tc', 0, t.safeMm + 1, im.widthMm, im.heightMm, t.widthMm, t.heightMm);
    im
      ..x = x
      ..y = y;
    setState(() {
      t.images.add(im);
      _sel = im.id;
    });
  }

  void _add(String kind) {
    final s = StateScope.read(context);
    _snap();
    setState(() {
      switch (kind) {
        case 'text':
          final ct = CardText(id: _newId('t'), side: _side, source: 'static', value: 'متن تازه', widthMm: t.widthMm - 2 * t.safeMm - 4, size: 12, anchor: 'c');
          t.texts.add(ct);
          _sel = ct.id;
        case 'name':
          final ct = CardText(id: _newId('t'), side: _side, source: 'field', value: 'display_name', widthMm: t.widthMm - 2 * t.safeMm - 4, size: 18, minSize: 10, maxLines: 2, anchor: 'tc', onReserve: false);
          t.texts.add(ct);
          _sel = ct.id;
        case 'shape':
          final sh = CardShape(id: _newId('s'), side: _side, widthMm: t.widthMm, heightMm: 8, color: '0B7A7B', anchor: 'bc');
          final (x, y) = centerFromAnchor('bc', 0, 0, sh.widthMm, sh.heightMm, t.widthMm, t.heightMm);
          sh
            ..x = x
            ..y = y;
          t.shapes.add(sh);
          _sel = sh.id;
        case 'qr':
          t.qrEnabled = true;
          if (t.doubleSided) t.qrSide = _side;
          _sel = 'qr';
      }
    });
    s.notify();
  }

  void _delete(_El e) {
    _snap();
    setState(() {
      switch (e.ref) {
        case CardText x:
          t.texts.remove(x);
        case CardImage x:
          t.images.remove(x);
        case CardShape x:
          t.shapes.remove(x);
        default:
          t.qrEnabled = false;
      }
      _sel = null;
    });
  }

  void _duplicate(_El e) {
    _snap();
    setState(() {
      switch (e.ref) {
        case CardText x:
          final n = CardText.fromJson({...x.toJson(), 'id': _newId('t'), 'y': x.y + 6});
          t.texts.add(n);
          _sel = n.id;
        case CardImage x:
          final n = CardImage.fromJson({...x.toJson(), 'id': _newId('i'), 'y': x.y + 6});
          t.images.add(n);
          _sel = n.id;
        case CardShape x:
          final n = CardShape.fromJson({...x.toJson(), 'id': _newId('s'), 'y': x.y + 6});
          t.shapes.add(n);
          _sel = n.id;
      }
    });
  }

  Future<void> _save({bool thenCheck = false}) async {
    final s = StateScope.read(context);
    await s.saveTemplate();
    if (!mounted || s.messageIsError) return;
    _dirty = false;
    if (thenCheck) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CardCheckPage()));
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final t = s.template;
    if (!t.doubleSided) _side = 'front';
    final sel = _selected();
    final people = s.sortedPeople;
    final sample = people.isEmpty
        ? null
        : personSubject(s, people.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b), const {});

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirmDanger(context, title: 'چیدمان ذخیره نشده', text: 'بدون ذخیره روی سرور برگردیم؟ تغییرها روی همین دستگاه می‌ماند.', confirm: 'بدون ذخیره برگرد');
        if (ok == true && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Column(children: [
          NvPageHeader(
            title: 'چیدمان کارت',
            subtitle: 'کارت · مرحله‌ی ۳ از ۳',
            action: IconButton(
              tooltip: 'برگرداندن آخرین تغییر',
              style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .16), foregroundColor: Colors.white),
              onPressed: _undo.isEmpty ? null : _doUndo,
              icon: const Icon(Icons.undo_rounded),
            ),
          ),
          // پیش‌نمایش چسبان.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: LayoutBuilder(builder: (context, box) {
              final maxH = MediaQuery.sizeOf(context).height * .34;
              var width = box.maxWidth;
              if (width * t.heightMm / t.widthMm > maxH) width = maxH * t.widthMm / t.heightMm;
              return Center(
                child: _CardCanvas(
                  s: s,
                  side: _side,
                  width: width,
                  subject: sample,
                  selected: _sel,
                  onSelect: (id) => setState(() => _sel = id),
                  onDragStart: () => _dragStart = t.toJson(),
                  onDrag: (dxMm, dyMm) {
                    final e = _selected();
                    if (e == null) return;
                    setState(() => e.setCenter(t, e.cx(t) + dxMm / t.widthMm * 100, e.cy(t) + dyMm / t.heightMm * 100));
                  },
                  onDragEnd: () {
                    if (_dragStart != null) {
                      _undo.add(jsonEncode(_dragStart));
                      _dirty = true;
                      _dragStart = null;
                    }
                  },
                ),
              );
            }),
          ),
          // نوار ابزار: رو/پشت و افزودن عنصر.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (t.doubleSided)
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'front', label: Text('رو')), ButtonSegment(value: 'back', label: Text('پشت'))],
                  selected: {_side},
                  onSelectionChanged: (v) => setState(() {
                    _side = v.first;
                    _sel = null;
                  }),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'افزودن عنصر',
                onSelected: (k) => k == 'image' ? _addImage(s) : _add(k),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'name', child: ListTile(leading: Icon(Icons.badge_rounded), title: Text('نام'))),
                  const PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.title_rounded), title: Text('متن'))),
                  const PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image_rounded), title: Text('تصویر (لوگو)'))),
                  const PopupMenuItem(value: 'shape', child: ListTile(leading: Icon(Icons.crop_square_rounded), title: Text('مستطیل رنگی'))),
                  if (!t.qrEnabled || t.effectiveQrSide != _side) const PopupMenuItem(value: 'qr', child: ListTile(leading: Icon(Icons.qr_code_2_rounded), title: Text('QR'))),
                ],
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 4),
                    Text('افزودن', style: nvText(context, 13, w: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          // پنل مشخصات عنصر انتخاب‌شده.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Nv.r24)),
                boxShadow: Nv.raised(c),
              ),
              child: Material(
                color: c.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Nv.r24)),
                child: sel == null
                  ? _ElementList(
                      els: _elements(t, _side),
                      s: s,
                      onPick: (id) => setState(() => _sel = id),
                    )
                  : _ElementPanel(
                      key: ValueKey(sel.id),
                      el: sel,
                      s: s,
                      onBefore: _snap,
                      onChanged: () => setState(() {}),
                      onDelete: () => _delete(sel),
                      onDuplicate: sel.kind == 'qr' ? null : () => _duplicate(sel),
                      onClose: () => setState(() => _sel = null),
                    ),
              ),
            ),
          ),
          Container(
            color: c.surface,
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: Row(children: [
              Expanded(
                child: NvSoftButton(
                  label: 'چیدمان چاپ',
                  icon: Icons.grid_view_rounded,
                  onPressed: () => showNvSheet<void>(
                    context,
                    (_) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: SingleChildScrollView(
                        child: StatefulBuilder(
                          builder: (context, set) => CardSheetSettings(s: s, cards: s.sortedPeople.length + s.reserveCards.where((r) => !r.used).length, onChanged: () {
                            _dirty = true;
                            set(() {});
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: NvButton(label: 'ذخیره و بررسی', busy: s.busy, onPressed: s.busy ? null : () => _save(thenCheck: true))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// بوم کارت: طرح، عنصرها، خط برش و ناحیه‌ی امن؛ لمس عنصر را انتخاب می‌کند و کشیدن جابه‌جا.
class _CardCanvas extends StatelessWidget {
  final AdminState s;
  final String side;
  final double width;
  final CardSubject? subject;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onDragStart;
  final void Function(double dxMm, double dyMm) onDrag;
  final VoidCallback onDragEnd;
  const _CardCanvas({
    required this.s,
    required this.side,
    required this.width,
    required this.subject,
    required this.selected,
    required this.onSelect,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final t = s.template;
    final k = width / t.widthMm; // پیکسل در میلی‌متر
    final height = t.heightMm * k;
    final url = side == 'front' ? t.frontImageUrl : t.backImageUrl;
    final local = side == 'front' ? t.frontImage : t.backImage;
    final bg = s.cachedAsset(url);
    Color col(String hex) {
      try {
        return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
      } catch (_) {
        return const Color(0xFF10141A);
      }
    }

    final sub = subject ??
        const CardSubject(isReserve: false, fields: {
          'display_name': 'دکتر مریم رضایی‌نژاد',
          'full_name': 'مریم رضایی‌نژاد',
          'first_name': 'مریم',
          'last_name': 'رضایی‌نژاد',
          'organization': 'دانشگاه تهران',
          'role': 'سخنران',
          'type': 'ارائه‌دهنده',
          'serial': '۲۱۳',
        });
    final els = _elements(t, side);

    Widget box(_El e, Widget child) {
      final w = e.w(t) * k, h = e.h(t) * k;
      final on = e.id == selected;
      return Positioned(
        left: t.widthMm * e.cx(t) / 100 * k - w / 2,
        top: t.heightMm * e.cy(t) / 100 * k - h / 2,
        width: w,
        height: h,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(e.id),
          onPanStart: (_) {
            onSelect(e.id);
            onDragStart();
          },
          onPanUpdate: (d) => onDrag(d.delta.dx / k, d.delta.dy / k),
          onPanEnd: (_) => onDragEnd(),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: on ? Border.all(color: c.brand, width: 2) : null),
            child: child,
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: Colors.white, boxShadow: Nv.raised(c)),
      clipBehavior: Clip.hardEdge,
      child: Stack(children: [
        if (bg != null)
          Positioned.fill(child: Image.memory(bg, fit: BoxFit.cover))
        else if (local.isNotEmpty && File(local).existsSync())
          Positioned.fill(child: Image.file(File(local), fit: BoxFit.cover)),
        Positioned.fill(child: GestureDetector(onTap: () => onSelect(null))),
        // ناحیه‌ی امن.
        Positioned(
          left: t.safeMm * k,
          top: t.safeMm * k,
          width: (t.widthMm - 2 * t.safeMm) * k,
          height: (t.heightMm - 2 * t.safeMm) * k,
          child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.go.withValues(alpha: .7))))),
        ),
        for (final e in els)
          switch (e.ref) {
            CardShape x => box(e, DecoratedBox(decoration: BoxDecoration(color: col(x.color), borderRadius: BorderRadius.circular(x.radiusMm * k)))),
            CardImage x => box(
                e,
                s.cachedAsset(x.url) != null
                    ? Image.memory(s.cachedAsset(x.url)!, fit: BoxFit.contain)
                    : Container(color: c.field, child: const Icon(Icons.image_rounded))),
            CardText x => box(
                e,
                Builder(builder: (context) {
                  final v = resolveCardText(x, sub) ?? (x.source == 'static' ? x.value : '«${x.label}»');
                  final (size, _) = fitCardText(v, x);
                  return Center(
                    child: Text(
                      v,
                      textDirection: TextDirection.rtl,
                      textAlign: cardTextAlign(x.align),
                      maxLines: x.maxLines,
                      overflow: TextOverflow.clip,
                      style: cardTextStyle(x.font, size * _ptToMm * k, color: col(x.color)),
                    ),
                  );
                })),
            _ => box(
                e,
                Container(
                  color: Colors.white,
                  padding: EdgeInsets.all(3 * k),
                  child: const FittedBox(child: Icon(Icons.qr_code_2_rounded, color: Colors.black)),
                )),
          },
      ]),
    );
  }
}

class _ElementList extends StatelessWidget {
  final List<_El> els;
  final AdminState s;
  final ValueChanged<String> onPick;
  const _ElementList({required this.els, required this.s, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), children: [
      Text('عنصرهای این رو', style: nvText(context, 15, w: FontWeight.w800)),
      Text('روی کارت یا یکی از این‌ها بزنید تا جا و اندازه‌اش را تنظیم کنید. برای جابه‌جایی، عنصر را روی کارت بکشید.',
          style: nvText(context, 12, color: c.muted, height: 1.6)),
      const SizedBox(height: 8),
      for (final e in els.reversed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (e.kind) { 'text' => Icons.title_rounded, 'image' => Icons.image_rounded, 'shape' => Icons.crop_square_rounded, _ => Icons.qr_code_2_rounded }),
          title: Text(e.label(s)),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => onPick(e.id),
        ),
      if (els.isEmpty) Text('هنوز عنصری نیست؛ «افزودن» را بزنید.', style: nvText(context, 14, color: c.muted)),
    ]);
  }
}

const _swatches = ['10141A', 'FFFFFF', '0B7A7B', '138A43', '8A5300', 'B3261E', '1D5FD1', '6B3FA0'];

class _ElementPanel extends StatefulWidget {
  final _El el;
  final AdminState s;
  final VoidCallback onBefore, onChanged, onDelete, onClose;
  final VoidCallback? onDuplicate;
  const _ElementPanel({super.key, required this.el, required this.s, required this.onBefore, required this.onChanged, required this.onDelete, required this.onClose, this.onDuplicate});

  @override
  State<_ElementPanel> createState() => _ElementPanelState();
}

class _ElementPanelState extends State<_ElementPanel> {
  _El get e => widget.el;
  CardTemplate get t => widget.s.template;

  void _change(void Function() f) {
    widget.onBefore();
    f();
    widget.onChanged();
    setState(() {});
  }

  /// جای عنصر (X، Y از مبدأ) با اندازه‌ی تازه، تا با تغییر اندازه گوشه‌ی مبدأ ثابت بماند.
  void _keepCorner(void Function() resize) {
    final a = e.anchor(t);
    final (x, y) = anchorFromCenter(a, e.cx(t), e.cy(t), e.w(t), e.h(t), t.widthMm, t.heightMm);
    resize();
    final (cx, cy) = centerFromAnchor(a, x, y, e.w(t), e.h(t), t.widthMm, t.heightMm);
    e.setCenter(t, cx, cy);
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final a = e.anchor(t);
    final (x, y) = anchorFromCenter(a, e.cx(t), e.cy(t), e.w(t), e.h(t), t.widthMm, t.heightMm);
    void setXY(double nx, double ny) => _change(() {
          final (cx, cy) = centerFromAnchor(a, nx, ny, e.w(t), e.h(t), t.widthMm, t.heightMm);
          e.setCenter(t, cx, cy);
        });

    final ref = e.ref;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 8), children: [
      Row(children: [
        Expanded(child: Text(e.label(widget.s), maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 15, w: FontWeight.w800))),
        if (widget.onDuplicate != null) IconButton(tooltip: 'تکثیر', onPressed: widget.onDuplicate, icon: const Icon(Icons.content_copy_rounded)),
        IconButton(tooltip: 'حذف', onPressed: widget.onDelete, icon: Icon(Icons.delete_rounded, color: c.stop)),
        IconButton(tooltip: 'بستن', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
      ]),
      Text('نقطه‌ی مبدأ و جای عنصر (میلی‌متر)', style: nvText(context, 13, w: FontWeight.w700, color: c.muted)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final k in const ['tr', 'tc', 'tl', 'c', 'br', 'bc', 'bl'])
          ChoiceChip(
            label: Text(cardAnchorLabels[k]!),
            selected: a == k,
            onSelected: (_) => _change(() => e.setAnchor(t, k)),
          ),
      ]),
      _Stepper(label: 'X', value: x, step: .5, min: -500, max: 1000, onChanged: (v) => setXY(v, y)),
      _Stepper(label: 'Y', value: y, step: .5, min: -500, max: 1000, onChanged: (v) => setXY(x, v)),
      Text(
        'مبدأ: ${cardAnchorLabels[a]} · ${a == 'c' ? 'فاصله‌ی مرکز عنصر از مرکز کارت' : 'فاصله‌ی گوشه‌ی هم‌نام عنصر از گوشه‌ی کارت'} · هر لمس ۰٫۵ میلی‌متر',
        style: nvText(context, 12, color: c.muted),
      ),
      const SizedBox(height: 8),
      switch (ref) {
        CardText ct => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Stepper(label: 'عرض کادر', value: ct.widthMm, step: 1, min: 5, max: 500, onChanged: (v) => _change(() => _keepCorner(() => ct.widthMm = v))),
            _Stepper(label: 'اندازه‌ی قلم', unit: 'pt', value: ct.size, step: .5, min: 4, max: 120, onChanged: (v) => _change(() => _keepCorner(() => ct.size = v))),
            _Stepper(label: 'کوچک‌ترین قلم', unit: 'pt', value: ct.minSize, step: .5, min: 4, max: 120, onChanged: (v) => _change(() => ct.minSize = v)),
            _Stepper(label: 'بیشترین خط', unit: 'خط', value: ct.maxLines.toDouble(), step: 1, min: 1, max: 5, onChanged: (v) => _change(() => _keepCorner(() => ct.maxLines = v.round()))),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: ct.source == 'field' && systemFields.containsKey(ct.value) ? 'f:${ct.value}' : (ct.source == 'static' ? 'static' : 'keep'),
              decoration: const InputDecoration(labelText: 'محتوا'),
              items: [
                const DropdownMenuItem(value: 'static', child: Text('متن ثابت')),
                for (final f in systemFields.entries) DropdownMenuItem(value: 'f:${f.key}', child: Text(f.value)),
                if (ct.source == 'column' || ct.source == 'file') DropdownMenuItem(value: 'keep', child: Text(ct.label)),
              ],
              onChanged: (v) {
                if (v == null || v == 'keep') return;
                _change(() {
                  if (v == 'static') {
                    ct
                      ..source = 'static'
                      ..onReserve = true;
                  } else {
                    ct
                      ..source = 'field'
                      ..value = v.substring(2)
                      ..onReserve = false;
                  }
                });
              },
            ),
            if (ct.source == 'static') ...[
              const SizedBox(height: 8),
              TextFormField(initialValue: ct.value, decoration: const InputDecoration(labelText: 'متن'), onChanged: (v) => _change(() => ct.value = v)),
            ],
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right_rounded)),
                ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center_rounded)),
                ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left_rounded)),
              ],
              selected: {ct.align},
              onSelectionChanged: (v) => _change(() => ct.align = v.first),
            ),
            const SizedBox(height: 8),
            _ColorRow(value: ct.color, onChanged: (v) => _change(() => ct.color = v)),
          ]),
        CardImage im => Column(children: [
            _Stepper(label: 'عرض', value: im.widthMm, step: 1, min: 2, max: 500, onChanged: (v) => _change(() => _keepCorner(() {
                  final r = im.heightMm / im.widthMm;
                  im
                    ..widthMm = v
                    ..heightMm = double.parse((v * r).toStringAsFixed(1));
                }))),
          ]),
        CardShape sh => Column(children: [
            _Stepper(label: 'عرض', value: sh.widthMm, step: 1, min: .5, max: 500, onChanged: (v) => _change(() => _keepCorner(() => sh.widthMm = v))),
            _Stepper(label: 'ارتفاع', value: sh.heightMm, step: .5, min: .2, max: 500, onChanged: (v) => _change(() => _keepCorner(() => sh.heightMm = v))),
            _Stepper(label: 'گردی گوشه', value: sh.radiusMm, step: .5, min: 0, max: 50, onChanged: (v) => _change(() => sh.radiusMm = v)),
            _ColorRow(value: sh.color, onChanged: (v) => _change(() => sh.color = v)),
          ]),
        _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Stepper(label: 'اندازه‌ی QR', value: t.qrSizeMm, step: .5, min: 10, max: 80, onChanged: (v) => _change(() => _keepCorner(() => t.qrSizeMm = v))),
            if (t.qrSizeMm < widget.s.minQrMm)
              NvBanner(tone: NvTone.wait, text: 'QR کوچک است؛ گوشی‌های قدیمی از فاصله نمی‌خوانند. کمینه ${faDigits(_fmt(widget.s.minQrMm))} میلی‌متر.'),
            Text('کادر QR حاشیه‌ی سکوت ۳ میلی‌متری را هم دارد.', style: nvText(context, 12, color: c.muted)),
          ]),
      },
    ]);
  }
}

class _ColorRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ColorRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Row(children: [
      Text('رنگ', style: nvText(context, 14, w: FontWeight.w600)),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final h in _swatches)
            InkWell(
              onTap: () => onChanged(h),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(int.parse('FF$h', radix: 16)),
                  shape: BoxShape.circle,
                  border: Border.all(color: value.toUpperCase() == h ? c.brand : c.line, width: value.toUpperCase() == h ? 3 : 1),
                ),
              ),
            ),
          IconButton(
            tooltip: 'کد رنگ',
            icon: const Icon(Icons.colorize_rounded),
            onPressed: () async {
              final ctl = TextEditingController(text: value);
              final v = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('کد رنگ (hex)'),
                  content: TextField(controller: ctl, autofocus: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(prefixText: '#')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('انصراف')),
                    FilledButton(onPressed: () => Navigator.pop(d, ctl.text.replaceAll('#', '').trim().toUpperCase()), child: const Text('باشه')),
                  ],
                ),
              );
              if (v != null && RegExp(r'^[0-9A-F]{6}$').hasMatch(v)) onChanged(v);
            },
          ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- بررسی و ساخت (طرح ۱۶)

class CardCheckPage extends StatefulWidget {
  const CardCheckPage({super.key});

  @override
  State<CardCheckPage> createState() => _CardCheckPageState();
}

class _CardCheckPageState extends State<CardCheckPage> {
  final _reserve = TextEditingController();

  @override
  void dispose() {
    _reserve.dispose();
    super.dispose();
  }

  Future<Uint8List?> _build(AdminState s, {required List<Person> people, required bool reserves}) => s.run('', () async {
        final fonts = await PdfFonts.load();
        return buildCardsPdf(
          s: s,
          fonts: fonts,
          people: people,
          reserves: reserves ? s.reserveCards.where((r) => !r.used).toList() : const [],
          frontImage: await cardDesignBytes(s, 'front'),
          backImage: s.template.doubleSided ? await cardDesignBytes(s, 'back') : null,
          assets: await cardAssetBytes(s),
        );
      });

  Future<void> _test(AdminState s) async {
    final people = s.sortedPeople;
    if (people.isEmpty) return;
    final longest = people.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b);
    final bytes = await _build(s, people: [longest], reserves: false);
    if (bytes != null) await saveBytesAs(s, 'test-card-${s.eventCode}.pdf', 'pdf', bytes);
  }

  Future<void> _all(AdminState s) async {
    final ok = await confirmDanger(
      context,
      title: 'ساخت کارت‌ها و قفل آدرس؟',
      text: 'بعد از ساخت، QR کارت‌ها به ${(s.event?.baseUrl.isNotEmpty ?? false) ? s.event!.baseUrl : s.server} گره می‌خورد و آدرس قفل می‌شود. '
          'اگر دامنه عوض شود، باید کارت‌ها دوباره چاپ شوند. روی گوشی برای لیست‌های بزرگ چند دقیقه طول می‌کشد.',
      confirm: 'بساز و قفل کن',
    );
    if (ok != true) return;
    final bytes = await _build(s, people: s.sortedPeople, reserves: true);
    if (bytes == null) return;
    await saveBytesAs(s, 'cards-${s.eventCode}.pdf', 'pdf', bytes);
    if (s.template.qrEnabled && !(s.event?.locked ?? true)) await s.setLocked(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final checks = cardWarnings(s);
    final free = s.reserveCards.where((r) => !r.used).length;
    if (_reserve.text.isEmpty) _reserve.text = '${(s.people.length / 10).ceil().clamp(1, 1000)}';

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        const NvPageHeader(title: 'بررسی و ساخت کارت', subtitle: 'مرحله‌ی ۶ و ۷'),
        if (s.busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${faDigits(s.sortedPeople.length)} نفر + ${faDigits(free)} کارت رزرو', style: nvText(context, 13, w: FontWeight.w700, color: c.muted)),
            ),
            NvCard(
              child: Column(children: [
                for (final ch in checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(
                        ch.ok == true ? Icons.check_circle_rounded : (ch.ok == false ? Icons.error_rounded : Icons.warning_rounded),
                        color: ch.ok == true ? c.go : (ch.ok == false ? c.stop : c.wait),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(ch.text, style: nvText(context, 14, height: 1.6))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            NvCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('چاپ آزمایشی یک کارت', style: nvText(context, 15, w: FontWeight.w800)),
                Text('پیش از چاپ همه، یک کارت (با بلندترین نام) را چاپ و با گوشی نیرو اسکن کنید.', style: nvText(context, 13, color: c.muted, height: 1.6)),
                const SizedBox(height: 10),
                NvSoftButton(label: 'ساخت PDF یک کارت', icon: Icons.print_rounded, onPressed: s.busy || s.people.isEmpty ? null : () => _test(s)),
              ]),
            ),
            const SizedBox(height: 12),
            if (s.template.qrEnabled)
              NvBanner(
                tone: NvTone.wait,
                icon: Icons.lock_rounded,
                title: 'آدرس سایت روی QR قفل می‌شود',
                text: 'پس از ساخت کارت‌ها، QR به ${((s.event?.baseUrl.isNotEmpty ?? false) ? s.event!.baseUrl : s.server).replaceFirst(RegExp(r'^https?://'), '')} گره می‌خورد. اگر دامنه عوض شود، باید کارت‌ها دوباره چاپ شوند.',
              ),
            const SizedBox(height: 12),
            NvCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('کارت‌های رزرو (برای ثبت‌نام در محل)', style: nvText(context, 15, w: FontWeight.w800)),
                Text('${faDigits(s.reserveCards.length)} ساخته شده؛ ${faDigits(free)} آزاد. پیشنهاد: حدود ۱۰٪ افراد.', style: nvText(context, 13, color: c.muted)),
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(width: 90, child: TextField(controller: _reserve, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعداد'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NvSoftButton(
                      label: 'ساخت کارت رزرو',
                      onPressed: s.busy
                          ? null
                          : () {
                              final n = int.tryParse(latinDigits(_reserve.text));
                              if (n != null && n > 0) s.addReserveCards(n);
                            },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                NvSoftButton(
                  label: 'PDF کارت‌های رزرو آزاد (${faDigits(free)})',
                  icon: Icons.style_rounded,
                  onPressed: s.busy || free == 0
                      ? null
                      : () async {
                          final b = await _build(s, people: const [], reserves: true);
                          if (b != null) await saveBytesAs(s, 'reserve-cards-${s.eventCode}.pdf', 'pdf', b);
                        },
                ),
              ]),
            ),
            const SizedBox(height: 12),
            NvSoftButton(
              label: 'PDF لیست پشتیبان کاغذی',
              icon: Icons.list_alt_rounded,
              onPressed: s.busy || s.people.isEmpty
                  ? null
                  : () async {
                      final b = await s.run('', () async => buildPaperListsPdf(s: s, fonts: await PdfFonts.load()));
                      if (b != null) await saveBytesAs(s, 'lists-${s.eventCode}.pdf', 'pdf', b);
                    },
            ),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
          child: NvButton(
            label: s.template.qrEnabled ? 'ساخت کارت‌ها و قفل آدرس' : 'ساخت کارت‌ها',
            icon: s.template.qrEnabled ? Icons.lock_rounded : Icons.picture_as_pdf_rounded,
            busy: s.busy,
            onPressed: s.busy || s.sortedPeople.isEmpty ? null : () => _all(s),
          ),
        ),
      ]),
    );
  }
}
