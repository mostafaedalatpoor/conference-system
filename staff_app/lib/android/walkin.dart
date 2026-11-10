// ثبت‌نام در محل روی اندروید (طرح ۹ تا ۱۱): کارت QR (اول کارت)، کارت بدون QR (اول مشخصات)، رزرو تمام‌شده.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../store.dart';
import 'checkin.dart' show NvCornersPainter;
import 'meal.dart' show NvCameraPermission;
import 'nv_theme.dart';
import 'nv_widgets.dart';
import '../desk/scan_field.dart' show NvScanField;

class NvWalkinScreen extends StatefulWidget {
  final String initialName;

  /// ویندوز: پنل کناری ۵۶۰ (بدون سربرگ)؛ کارت رزرو با بارکدخوان، Ctrl+Enter ثبت و Esc برگشت.
  final bool panel;
  final VoidCallback? onClose;
  const NvWalkinScreen({super.key, this.initialName = '', this.panel = false, this.onClose});

  @override
  State<NvWalkinScreen> createState() => _NvWalkinScreenState();
}

class _NvWalkinScreenState extends State<NvWalkinScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _mobile = TextEditingController();
  final _serial = TextEditingController();
  final _scanFocus = FocusNode();
  PassCard? _card;
  int? _typeId;
  String? _firstError, _lastError, _cardError;

  @override
  void initState() {
    super.initState();
    // متن جستجو: یک کلمه = نام خانوادگی یا نام؛ دو کلمه = نام و نام خانوادگی. موبایل جدا.
    final t = widget.initialName.trim();
    if (normalizeMobile(t).length >= 10) {
      _mobile.text = t;
    } else if (t.contains(' ')) {
      final parts = t.split(RegExp(r'\s+'));
      _first.text = parts.first;
      _last.text = parts.sublist(1).join(' ');
    } else {
      _first.text = t;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_typeId == null) {
      final types = StoreScope.read(context).types;
      final p = types.where((t) => t.code.contains('particip') || t.name.contains('شرکت'));
      _typeId = p.isNotEmpty ? p.first.id : (types.isNotEmpty ? types.first.id : null);
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _mobile, _serial]) {
      c.dispose();
    }
    _scanFocus.dispose();
    super.dispose();
  }

  bool _needsCard(AppStore s) => s.usesCards && s.freeReserveCards.isNotEmpty;

  void _setCard(String input) {
    final (card, err) = StoreScope.read(context).reserveCardFrom(input);
    setState(() {
      _card = card;
      _cardError = err;
      if (card != null) _serial.text = 'R${faDigits(card.serial)}';
    });
  }

  Future<void> _scanCard() async {
    final token = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NvScanPage(title: 'اسکن کارت رزرو')));
    if (token != null && mounted) _setCard(token);
  }

  Future<void> _save() async {
    final s = StoreScope.read(context);
    setState(() {
      _firstError = _first.text.trim().isEmpty ? 'نام را بنویسید.' : null;
      _lastError = _last.text.trim().isEmpty ? 'نام خانوادگی را بنویسید.' : null;
      if (_card == null && _needsCard(s)) {
        _cardError ??= s.cameraScan ? 'کارت رزرو را اسکن کنید یا شماره‌اش را بنویسید.' : 'شماره‌ی روی کارت را بنویسید.';
      }
    });
    if (_firstError != null || _lastError != null || (_card == null && _needsCard(s))) return;
    if (_typeId == null) {
      setState(() => _firstError = 'نوع ثبت‌نامی تعریف نشده است؛ از مدیر بخواهید.');
      return;
    }
    final dup = s.findByMobile(_mobile.text);
    if (dup != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('موبایل تکراری'),
          content: Text('این شماره قبلاً برای «${dup.fullName}» ثبت شده. شاید همین فرد باشد. باز هم ثبت شود؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ثبت شود')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final a = s.walkin(
      firstName: _first.text,
      lastName: _last.text,
      mobile: _mobile.text,
      email: '',
      registrationTypeId: _typeId!,
      card: s.usesCards ? _card : null,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (widget.panel) {
      widget.onClose?.call();
    } else {
      Navigator.of(context).pop();
    }
    messenger.showSnackBar(SnackBar(
      content: Text(_card == null
          ? '${a.fullName} ثبت و پذیرش شد${s.usesCards ? '، بدون کارت' : ''}.'
          : '${a.fullName} ثبت و پذیرش شد — کارت رزرو R${faDigits(_card!.serial)} را بدهید.'),
    ));
  }

  Widget _text(TextEditingController c, String label, {String? error, bool optional = false, bool ltr = false, String? hint}) => NvField(
        label: label,
        optional: optional,
        error: error,
        child: TextField(
          controller: c,
          keyboardType: ltr ? TextInputType.phone : TextInputType.name,
          textDirection: ltr ? TextDirection.ltr : null,
          textAlign: ltr ? TextAlign.left : TextAlign.start,
          style: nvText(context, 17),
          decoration: InputDecoration(hintText: hint),
          onChanged: (_) => setState(() {
            if (c == _first) _firstError = null;
            if (c == _last) _lastError = null;
          }),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final free = s.freeReserveCards.length;
    final noCards = s.usesCards && free == 0 && _card == null;
    final canScan = s.cameraScan || (widget.panel && s.scanEnabled);
    final qrFirst = s.usesCards && canScan && !noCards;
    final numberLast = s.usesCards && !canScan && !noCards;
    final names = widget.panel
        ? <Widget>[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _text(_first, 'نام', error: _firstError)),
              const SizedBox(width: 14),
              Expanded(child: _text(_last, 'نام خانوادگی', error: _lastError, hint: 'بنویسید')),
            ]),
          ]
        : <Widget>[
            _text(_first, 'نام', error: _firstError),
            const SizedBox(height: 14),
            _text(_last, 'نام خانوادگی', error: _lastError, hint: 'نام خانوادگی را بنویسید'),
          ];

    final fields = <Widget>[
      ...names,
      const SizedBox(height: 14),
      _text(_mobile, 'موبایل', optional: true, ltr: true, hint: '09…'),
      if (s.types.length > 1) ...[
        const SizedBox(height: 14),
        Row(children: [
          Text('نوع ثبت‌نام', style: nvText(context, 14, w: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(Nv.r12)),
                child: Row(children: [
                  for (final t in s.types)
                    InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => setState(() => _typeId = t.id),
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: _typeId == t.id
                            ? BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1))])
                            : null,
                        child: Text(t.name,
                            style: nvText(context, 14, w: _typeId == t.id ? FontWeight.w700 : FontWeight.w600, color: _typeId == t.id ? c.ink : c.muted)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ],
    ];

    Widget cardChosen() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.goSoft, borderRadius: BorderRadius.circular(Nv.r18), border: Border.all(color: c.go, width: 1.5)),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.go, borderRadius: BorderRadius.circular(Nv.r14)),
              child: const Icon(Icons.check_rounded, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('کارت رزرو انتخاب شد', style: nvText(context, 13, w: FontWeight.w600, color: c.goInk)),
                Text('R${faDigits(_card!.serial)}', style: nvText(context, 30, w: FontWeight.w800, color: c.goInk, height: 1.25)),
              ]),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: c.surface, side: BorderSide.none),
              onPressed: () => setState(() {
                _card = null;
                _serial.clear();
              }),
              child: const Text('تغییر'),
            ),
          ]),
        );

    Widget numberBox() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('شماره‌ی روی کارت', style: nvText(context, 15, w: FontWeight.w700))),
              Text('${faDigits(free)} کارت رزرو آزاد', style: nvText(context, 12, color: c.muted)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _serial,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: nvText(context, 22, w: FontWeight.w800),
                  decoration: const InputDecoration(hintText: 'R5001'),
                  onChanged: (v) {
                    // انتخاب زنده: با هر رقم بررسی می‌شود آزاد است یا نه.
                    if (latinDigits(v).replaceAll(RegExp(r'\D'), '').length >= 3) {
                      _setCard(v);
                    } else {
                      setState(() {
                        _card = null;
                        _cardError = null;
                      });
                    }
                  },
                  onSubmitted: _setCard,
                ),
              ),
              if (s.cameraScan) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: Nv.field,
                  child: FilledButton.icon(onPressed: _scanCard, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('اسکن')),
                ),
              ],
            ]),
            if (_card != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: c.go),
                  const SizedBox(width: 6),
                  Text('کارت R${faDigits(_card!.serial)} آزاد است', style: nvText(context, 13, w: FontWeight.w700, color: c.go)),
                ]),
              )
            else if (_cardError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.error_rounded, size: 18, color: c.stop),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_cardError!, style: nvText(context, 13, w: FontWeight.w600, color: c.stop))),
                ]),
              ),
          ]),
        );

    Widget scanFirstBox() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r18), border: _cardError != null ? Border.all(color: c.stop, width: 1.5) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('۱. کارت رزرو', style: nvText(context, 15, w: FontWeight.w700))),
              Text('${faDigits(free)} آزاد', style: nvText(context, 12, color: c.muted)),
            ]),
            const SizedBox(height: 10),
            if (widget.panel) ...[
              NvScanField(
                controller: _serial,
                focusNode: _scanFocus,
                hint: 'کارت رزرو را اسکن کنید یا شماره را بنویسید',
                scanEnabled: true,
                showScannerChip: false,
                onChanged: (_) => setState(() => _cardError = null),
                onSubmitted: _setCard,
                onScan: (raw) {
                  _setCard(raw);
                  return _card != null;
                },
              ),
            ] else ...[
            NvButton(label: 'اسکن کارت رزرو', icon: Icons.qr_code_scanner_rounded, onPressed: _scanCard),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _serial,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(hintText: 'یا شماره: R5001'),
                  onSubmitted: _setCard,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(height: Nv.field, child: OutlinedButton(onPressed: () => _setCard(_serial.text), child: const Text('انتخاب'))),
            ]),
            ],
            if (_cardError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_cardError!, style: nvText(context, 13, w: FontWeight.w600, color: c.stop)),
              ),
          ]),
        );

    final body = <Widget>[
      if (noCards) ...[
        const NvBanner(
          tone: NvTone.wait,
          icon: Icons.style_rounded,
          title: 'کارت رزرو تمام شده',
          text: 'این فرد بدون کارت ثبت و پذیرش می‌شود. پذیرایی‌اش با جستجوی نام انجام می‌شود و اگر کارت رزرو تازه رسید، از صفحه‌ی خودش وصل می‌شود.',
        ),
        const SizedBox(height: 14),
        ...fields,
        const SizedBox(height: 14),
        NvCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(Icons.report_rounded, size: 20, color: c.brandText),
            const SizedBox(width: 8),
            Expanded(child: Text('در گزارش مدیر با علامت «بدون کارت» می‌آید', style: nvText(context, 14))),
          ]),
        ),
      ] else if (qrFirst) ...[
        if (_card != null) cardChosen() else scanFirstBox(),
        const SizedBox(height: 14),
        ...fields,
      ] else if (numberLast) ...[
        const NvBanner(tone: NvTone.info, text: 'کارت‌های این رویداد QR ندارند؛ پیدا کردن کارت با شماره‌ی روی آن انجام می‌شود.'),
        const SizedBox(height: 14),
        ...fields,
        const SizedBox(height: 14),
        numberBox(),
      ] else
        ...fields,
    ];

    final label = noCards ? 'ثبت و پذیرش بدون کارت' : (s.usesCards ? 'ثبت، پذیرش و تحویل کارت' : 'ثبت و پذیرش');

    if (widget.panel) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.escape): () => widget.onClose?.call(),
        },
        child: FocusScope(
          autofocus: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: ListView(padding: EdgeInsets.zero, children: body)),
            const SizedBox(height: 14),
            SizedBox(
              height: 64,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.go,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r18)),
                  textStyle: nvText(context, 19, w: FontWeight.w800),
                ),
                onPressed: _save,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_rounded, size: 28),
                  const SizedBox(width: 10),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white70)),
                    child: const Text('Ctrl+Enter', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      body: Column(children: [
        NvBackHeader(
          title: 'ثبت‌نام در محل',
          subtitle: qrFirst ? 'اول کارت رزرو، بعد مشخصات' : (numberLast ? 'اول مشخصات، بعد کارت' : null),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(Nv.gutter), children: body),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
          child: NvButton(label: label, icon: Icons.check_rounded, color: c.go, height: Nv.buttonXl, onPressed: _save),
        ),
      ]),
    );
  }
}

/// دوربین ساده که اولین کارت کنفرانس را برمی‌گرداند.
class NvScanPage extends StatefulWidget {
  final String title;
  const NvScanPage({super.key, required this.title});

  @override
  State<NvScanPage> createState() => _NvScanPageState();
}

class _NvScanPageState extends State<NvScanPage> {
  final _cam = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _cam,
            errorBuilder: (context, error) => NvCameraPermission(onRetry: () => _cam.start(), onByName: () => Navigator.of(context).pop(), byNameLabel: 'شماره را دستی بنویسید'),
            onDetect: (cap) {
              if (_done) return;
              for (final b in cap.barcodes) {
                final t = b.rawValue == null ? null : tokenFromScan(b.rawValue!);
                if (t != null) {
                  _done = true;
                  Navigator.of(context).pop(t);
                  return;
                }
                if (b.rawValue != null) setState(() => _hint = 'این QR مال کارت کنفرانس نیست.');
              }
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(child: const SizedBox.square(dimension: 220, child: CustomPaint(painter: NvCornersPainter()))),
          ),
        ),
        Positioned(
          top: top + 12,
          left: 16,
          right: 16,
          child: Row(children: [
            NvRoundIcon(icon: Icons.close_rounded, label: 'بستن', onTap: () => Navigator.of(context).pop()),
            Expanded(child: Text(widget.title, textAlign: TextAlign.center, style: nvText(context, 16, w: FontWeight.w700, color: Colors.white))),
            NvRoundIcon(icon: Icons.flashlight_on_rounded, label: 'چراغ قوه', onTap: () => _cam.toggleTorch()),
          ]),
        ),
        if (_hint != null)
          Positioned(left: 16, right: 16, bottom: 40 + MediaQuery.paddingOf(context).bottom, child: NvBanner(tone: NvTone.wait, text: _hint!)),
      ]),
    );
  }
}
