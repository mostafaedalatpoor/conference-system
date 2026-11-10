// فیلد جستجو و اسکن ویندوز با ظاهر تازه: بارکدخوان (USB یا بلوتوث در حالت صفحه‌کلید) را از روی سرعت
// تایپ تشخیص می‌دهد؛ بدون بارکدخوان، فقط یک فیلد جستجوی عادی است.
import 'dart:async';

import 'package:flutter/material.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../normalize.dart';

/// زمان آخرین اسکن واقعی بارکدخوان در همین اجرا؛ تا پیش از اولین اسکن null است.
final scannerLastAt = ValueNotifier<DateTime?>(null);

/// قاب کوچک کلید میان‌بر («F1»، «Ctrl+Z»).
class NvKbd extends StatelessWidget {
  final String keys;
  final bool onBrand;
  const NvKbd(this.keys, {super.key, this.onBrand = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onBrand ? Colors.white.withValues(alpha: .2) : c.surface,
        borderRadius: BorderRadius.circular(5),
        border: onBrand ? null : Border.all(color: c.line),
        boxShadow: onBrand ? null : [BoxShadow(color: c.lineSoft, offset: const Offset(0, 2))],
      ),
      child: switch (keys) {
        '↑' => Icon(Icons.arrow_upward_rounded, size: 13, color: onBrand ? Colors.white : c.muted),
        '↓' => Icon(Icons.arrow_downward_rounded, size: 13, color: onBrand ? Colors.white : c.muted),
        _ => Text(keys, textDirection: TextDirection.ltr, style: nvText(context, 11, w: FontWeight.w700, color: onBrand ? Colors.white : c.muted)),
      },
    );
  }
}

/// کلید و کاری که می‌کند، کنار هم.
class NvKeyHint extends StatelessWidget {
  final List<String> keys;
  final String label;
  const NvKeyHint(this.keys, this.label, {super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in keys) ...[NvKbd(k), const SizedBox(width: 4)],
        const SizedBox(width: 2),
        Text(label, style: nvText(context, 12, color: NvColors.of(context).muted)),
      ]);
}

enum NvScanLook { search, bar }

class NvScanField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  /// متن دوم کم‌رنگ کنار راهنما (فقط در نوار پذیرایی).
  final String? hintMore;
  final bool scanEnabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  /// متن اسکن‌شده (به لاتین برگردانده‌شده). اگر کارت شناخته شد true برگرداند.
  final bool Function(String raw) onScan;
  final NvScanLook look;
  final bool autofocus;

  /// چیپ «بارکدخوان کار می‌کند» داخل فیلد.
  final bool showScannerChip;

  const NvScanField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.scanEnabled,
    required this.onChanged,
    required this.onSubmitted,
    required this.onScan,
    this.hintMore,
    this.look = NvScanLook.search,
    this.autofocus = true,
    this.showScannerChip = true,
  });

  @override
  State<NvScanField> createState() => _NvScanFieldState();
}

class _NvScanFieldState extends State<NvScanField> {
  String _lastText = '';
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
    _lastText = widget.controller.text;
    _times.addAll(List.filled(_lastText.length, DateTime.fromMillisecondsSinceEpoch(0)));
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    _readingOff?.cancel();
    _warningOff?.cancel();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  /// همه‌ی تغییرهای متن، چه تایپ و چه پاک‌شدن از بیرون، از اینجا می‌گذرند تا زمان‌ها کهنه نمانند.
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
      _times
        ..clear()
        ..addAll(List.filled(text.length, now));
    }
    _lastText = text;
    if (widget.scanEnabled && _scanStart() <= text.length - 4) {
      if (!_reading) setState(() => _reading = true);
      _readingOff?.cancel();
      _readingOff = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _reading = false);
      });
    }
  }

  /// شروع دنباله‌ی انتهای متن که با سرعت بارکدخوان آمده: میانگین فاصله کمتر از ۳۵ms و هیچ فاصله‌ای بیش از ۲۵۰ms.
  int _scanStart() {
    final n = _times.length;
    if (n < 2) return n;
    var start = n - 1;
    for (var i = n - 2; i >= 0; i--) {
      if (_times[i + 1].difference(_times[i]).inMilliseconds > 250) break;
      if (_times[n - 1].difference(_times[i]).inMilliseconds / (n - 1 - i) > 35) break;
      start = i;
    }
    return start;
  }

  void _warn(String text) {
    _warningOff?.cancel();
    setState(() => _warning = text);
    _warningOff = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _warning = null);
    });
  }

  void _submitted(String text) {
    final start = _scanStart().clamp(0, text.length);
    final scanned = text.substring(start);
    final fresh = _times.isNotEmpty && DateTime.now().difference(_times.last).inMilliseconds < 300;
    final isScan = widget.scanEnabled && scanned.length >= 8 && fresh;
    if (!isScan) {
      widget.onSubmitted(text);
      widget.focusNode.requestFocus();
      return;
    }
    final persian = hasPersianLetters(scanned);
    final raw = persian ? latinizeLayout(scanned) : scanned;
    widget.controller.clear();
    widget.onChanged('');
    scannerLastAt.value = DateTime.now();
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
    final c = NvColors.of(context);
    final bar = widget.look == NvScanLook.bar;
    return ValueListenableBuilder<DateTime?>(
      valueListenable: scannerLastAt,
      builder: (context, lastScan, _) {
        final paused = widget.scanEnabled && lastScan != null && !widget.focusNode.hasFocus;
        final ring = _reading ? c.go : (paused ? c.line : c.brand);
        final empty = widget.controller.text.isEmpty;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: widget.focusNode.requestFocus,
            child: Container(
              height: bar ? 64 : 60,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: paused ? c.field : c.surface,
                borderRadius: BorderRadius.circular(Nv.r16),
                border: Border.all(color: ring, width: 2),
              ),
              child: Row(children: [
                if (bar)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: paused ? c.muted : c.brand,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.brand.withValues(alpha: .2), spreadRadius: 4)],
                    ),
                  )
                else
                  Icon(_reading ? Icons.qr_code_scanner_rounded : Icons.search_rounded, size: 26, color: c.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Stack(alignment: AlignmentDirectional.centerStart, children: [
                    if (empty)
                      IgnorePointer(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: _reading ? 'در حال خواندن…' : (paused ? 'اسکن متوقف است؛ برای اسکن اینجا کلیک کنید' : widget.hint),
                              style: bar ? nvText(context, 17, w: FontWeight.w700) : nvText(context, 19, w: FontWeight.w500, color: c.muted),
                            ),
                            if (widget.hintMore != null && !_reading && !paused)
                              TextSpan(text: ' · ${widget.hintMore}', style: nvText(context, 13, w: FontWeight.w500, color: c.muted)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      autofocus: widget.autofocus,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.search,
                      style: nvText(context, 20, w: FontWeight.w600),
                      cursorColor: c.brand,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: widget.onChanged,
                      onSubmitted: _submitted,
                    ),
                  ]),
                ),
                if (widget.scanEnabled && !bar && widget.showScannerChip) ...[
                  const SizedBox(width: 10),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: lastScan != null ? c.goSoft : c.tag, borderRadius: BorderRadius.circular(15)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 16, color: lastScan != null ? c.goInk : c.muted),
                      const SizedBox(width: 6),
                      Text(
                        lastScan != null ? 'بارکدخوان کار می‌کند · آخرین اسکن ${faDigits(hm(lastScan))}' : 'کارت را اسکن کنید',
                        style: nvText(context, 12, w: FontWeight.w600, color: lastScan != null ? c.goInk : c.muted),
                      ),
                    ]),
                  ),
                ],
                if (!empty) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'پاک کردن (Esc)',
                    icon: Icon(Icons.close_rounded, color: c.muted),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onChanged('');
                      widget.focusNode.requestFocus();
                    },
                  ),
                ] else if (bar)
                  Icon(Icons.qr_code_scanner_rounded, size: 26, color: c.brand),
              ]),
            ),
          ),
          if (_warning != null) ...[
            const SizedBox(height: 8),
            NvBanner(tone: NvTone.wait, icon: Icons.keyboard_rounded, text: _warning!),
          ],
        ]);
      },
    );
  }
}
