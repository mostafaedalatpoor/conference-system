import 'dart:async';

import 'package:flutter/material.dart';

import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

/// آیا روی این دستگاه، در همین اجرا، بارکدخوان دیده شده؟
/// نشانه‌های بارکدخوان فقط بعد از اولین اسکن واقعی ظاهر می‌شوند.
final scannerSeen = ValueNotifier<bool>(false);

/// F4: برگرداندن فوکوس به ورودی اسکنِ صفحه‌ی فعال.
abstract final class ScanFocus {
  static FocusNode? _active;
  static void request() => _active?.requestFocus();
}

/// فیلد جستجو که بارکدخوان (USB یا بلوتوث در حالت صفحه‌کلید) را هم می‌فهمد.
/// بدون بارکدخوان، فقط یک فیلد جستجوی عادی است و هیچ هشداری ندارد.
/// تشخیص از روی سرعت: کاراکترهایی که با فاصله‌ی کمتر از ۳۰ms می‌آیند و با Enter تمام می‌شوند، اسکن‌اند.
class ScanInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  /// اسکن در این رویداد مجاز است (IdentifyMode = scan).
  final bool scanEnabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  /// متن اسکن‌شده (به لاتین برگردانده‌شده). اگر کارت شناخته شد true برگرداند.
  final bool Function(String raw) onScan;
  final bool autofocus;
  final double height;

  const ScanInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.scanEnabled,
    required this.onChanged,
    required this.onSubmitted,
    required this.onScan,
    this.autofocus = true,
    this.height = DaftarSize.tapLg,
  });

  @override
  State<ScanInputField> createState() => _ScanInputFieldState();
}

class _ScanInputFieldState extends State<ScanInputField> {
  String _lastText = '';

  /// زمان رسیدن هر کاراکتر متن فعلی؛ برای تشخیص سرعت بارکدخوان.
  final List<DateTime> _times = [];
  bool _reading = false;
  Timer? _readingOff;
  String? _warning;
  Timer? _warningOff;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
    ScanFocus._active = widget.focusNode;
    _lastText = widget.controller.text;
    final old = DateTime.fromMillisecondsSinceEpoch(0);
    _times.addAll(List.filled(_lastText.length, old));
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    if (ScanFocus._active == widget.focusNode) ScanFocus._active = null;
    _readingOff?.cancel();
    _warningOff?.cancel();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  /// همه‌ی تغییرهای متن، چه تایپ و چه پاک‌شدن از بیرون (نفر بعدی، Esc)، از اینجا می‌گذرند
  /// تا زمان‌ها هیچ‌وقت کهنه نمانند.
  void _onText() {
    final text = widget.controller.text;
    if (text == _lastText) return;
    final now = DateTime.now();
    if (text.startsWith(_lastText)) {
      for (var i = _lastText.length; i < text.length; i++) {
        _times.add(now);
      }
    } else if (_lastText.startsWith(text)) {
      _times.removeRange(text.length, _times.length);
    } else {
      // جایگزینی کامل: زمان‌های قبلی معنا ندارند.
      _times
        ..clear()
        ..addAll(List.filled(text.length, now));
    }
    _lastText = text;
    if (widget.scanEnabled && _scanStart(text) <= text.length - 4) {
      if (!_reading) setState(() => _reading = true);
      _readingOff?.cancel();
      _readingOff = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _reading = false);
      });
    }
  }

  /// شروع بلندترین دنباله‌ی انتهای متن که با سرعت بارکدخوان آمده:
  /// میانگین فاصله‌ی کاراکترها کمتر از ۳۵ms و هیچ فاصله‌ای بیشتر از ۲۵۰ms
  /// (یک گیر کوتاه برنامه وسط اسکن آن را نمی‌شکند).
  int _scanStart(String text) {
    final n = _times.length;
    if (n < 2) return n;
    var start = n - 1;
    for (var i = n - 2; i >= 0; i--) {
      final gap = _times[i + 1].difference(_times[i]).inMilliseconds;
      if (gap > 250) break;
      final avg = _times[n - 1].difference(_times[i]).inMilliseconds / (n - 1 - i);
      if (avg > 35) break;
      start = i;
    }
    return start;
  }

  void _changed(String text) => widget.onChanged(text);

  void _warn(String text) {
    _warningOff?.cancel();
    setState(() => _warning = text);
    _warningOff = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _warning = null);
    });
  }

  void _submitted(String text) {
    final start = _scanStart(text).clamp(0, text.length);
    final scanned = text.substring(start);
    final fresh = _times.isNotEmpty && DateTime.now().difference(_times.last).inMilliseconds < 300;
    final isScan = widget.scanEnabled && scanned.length >= 8 && fresh;
    if (!isScan) {
      widget.onSubmitted(text);
      return;
    }
    final persian = hasPersianLetters(scanned);
    final raw = persian ? latinizeLayout(scanned) : scanned;
    widget.controller.clear();
    widget.onChanged('');
    scannerSeen.value = true;
    final ok = widget.onScan(raw);
    if (persian) {
      _warn(ok
          ? 'صفحه‌کلید ویندوز فارسی است. کارت خوانده شد؛ برای اطمینان زبان را انگلیسی کنید (Alt+Shift).'
          : 'کارت خوانده نشد چون صفحه‌کلید فارسی است. زبان را انگلیسی کنید (Alt+Shift) و دوباره اسکن کنید.');
    }
    widget.focusNode.requestFocus();
    setState(() => _reading = false);
  }

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: scannerSeen,
      builder: (context, seen, _) {
        final lostFocus = widget.scanEnabled && seen && !widget.focusNode.hasFocus;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: widget.height,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.search,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  prefixIcon: Icon(_reading ? Icons.qr_code_scanner_rounded : Icons.search_rounded),
                  hintText: _reading ? 'در حال خواندن…' : widget.hint,
                  fillColor: lostFocus ? x.sunken : null,
                  enabledBorder: _reading
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
                          borderSide: BorderSide(color: x.go, width: 2))
                      : null,
                  focusedBorder: _reading
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
                          borderSide: BorderSide(color: x.go, width: 2))
                      : null,
                  suffixIcon: widget.controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'پاک کردن (Esc)',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            widget.controller.clear();
                            _changed('');
                            widget.focusNode.requestFocus();
                          },
                        ),
                ),
                onChanged: _changed,
                onSubmitted: _submitted,
              ),
            ),
            if (lostFocus)
              Padding(
                padding: const EdgeInsets.only(top: DaftarSize.space2),
                child: Material(
                  color: x.sunken,
                  borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
                    onTap: widget.focusNode.requestFocus,
                    child: Padding(
                      padding: const EdgeInsets.all(DaftarSize.space3),
                      child: Row(children: [
                        Icon(Icons.pause_circle_rounded, color: x.ink, size: 20),
                        const SizedBox(width: DaftarSize.space2),
                        Expanded(
                          child: Text('اسکن متوقف است. برای اسکن اینجا کلیک کنید یا F4 بزنید.',
                              style: theme.textTheme.bodySmall?.copyWith(color: x.ink)),
                        ),
                      ]),
                    ),
                  ),
                ),
              )
            else if (widget.scanEnabled && seen)
              Padding(
                padding: const EdgeInsets.only(top: DaftarSize.space2),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space2, vertical: 2),
                    decoration: BoxDecoration(
                      color: x.goSoft,
                      borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 14, color: x.go),
                      const SizedBox(width: DaftarSize.space1),
                      Text('بارکدخوان وصل است',
                          style: theme.textTheme.bodySmall?.copyWith(color: x.go, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            if (_warning != null)
              Padding(
                padding: const EdgeInsets.only(top: DaftarSize.space2),
                child: Notice(tone: NoticeTone.wait, icon: Icons.keyboard_rounded, text: _warning!),
              ),
          ],
        );
      },
    );
  }
}

/// کلید در قاب کوچک کنار کاری که می‌کند (Shortcut).
class KeyHints extends StatelessWidget {
  final List<(String, String)> items;
  const KeyHints(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: x.inkMuted);
    return Wrap(spacing: DaftarSize.space4, runSpacing: DaftarSize.space2, children: [
      for (final (k, label) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: x.surface,
              border: Border.all(color: x.lineStrong),
              borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
            ),
            child: Text(k, textDirection: TextDirection.ltr, style: style?.copyWith(color: x.ink, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Text(label, style: style),
        ]),
    ]);
  }
}
