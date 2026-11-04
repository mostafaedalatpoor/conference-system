import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import 'scanner.dart';

/// ثبت‌نام در محل: نام و موبایل، بعد وصل‌کردن یک کارت رزرو.
class WalkinScreen extends StatefulWidget {
  final String initialName;
  const WalkinScreen({super.key, this.initialName = ''});

  @override
  State<WalkinScreen> createState() => _WalkinScreenState();
}

class _WalkinScreenState extends State<WalkinScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _serial = TextEditingController();
  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _serialFocus = FocusNode();
  int? _typeId;
  PassCard? _card;

  // خطای هر فیلد زیر همان فیلد نمایش داده می‌شود.
  String? _firstError, _lastError, _typeError, _cardError;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty && !RegExp(r'\d').hasMatch(widget.initialName)) {
      _first.text = parts.first;
      if (parts.length > 1) _last.text = parts.sublist(1).join(' ');
    } else if (parts.isNotEmpty) {
      _mobile.text = widget.initialName;
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _mobile, _email, _serial]) {
      c.dispose();
    }
    for (final f in [_firstFocus, _lastFocus, _mobileFocus, _emailFocus, _serialFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_typeId == null) {
      final types = StoreScope.read(context).types;
      final participant = types.where((t) => t.code.contains('particip') || t.name.contains('شرکت'));
      _typeId = participant.isNotEmpty ? participant.first.id : (types.isNotEmpty ? types.first.id : null);
    }
  }

  void _setCardFromToken(String token) {
    final store = StoreScope.read(context);
    final c = store.cards[token];
    setState(() {
      if (c == null) {
        _card = null;
        _cardError = 'این کارت در لیست نیست. اگر کارت تازه است، از «وضعیت» لیست را دوباره بگیرید.';
      } else if (!c.isReserve) {
        _card = null;
        _cardError = 'این کارت رزرو نیست؛ مال ${store.attendeeForToken(token)?.fullName ?? 'شخص دیگری'} است.';
      } else if (store.cardOwner.containsKey(token)) {
        _card = null;
        _cardError = 'این کارت رزرو قبلاً به ${store.attendeeForToken(token)?.fullName ?? 'کسی'} وصل شده.';
      } else {
        _card = c;
        _serial.text = faDigits(c.serial);
        _cardError = null;
      }
    });
  }

  /// شماره‌ی روی کارت رزرو «R5001» چاپ می‌شود؛ R، r و ر اول شماره نادیده گرفته می‌شود.
  void _setCardFromSerial(String s) {
    final store = StoreScope.read(context);
    final cleaned = latinDigits(s.trim()).replaceFirst(RegExp(r'^[Rrر]\s*'), '');
    final n = int.tryParse(cleaned);
    if (n == null) {
      setState(() => _cardError = 'شماره‌ی روی کارت را بنویسید، مثلاً ۵۰۰۱.');
      return;
    }
    final match = store.cards.values.where((c) => c.isReserve && c.serial == n);
    if (match.isEmpty) {
      setState(() {
        _card = null;
        _cardError = 'کارت رزرو با شماره‌ی ${faDigits(n)} پیدا نشد.';
      });
    } else {
      _setCardFromToken(match.first.token);
    }
  }

  Future<void> _scan() async {
    final token = await ScannerPage.scan(context, title: 'اسکن کارت رزرو');
    if (token != null && mounted) _setCardFromToken(token);
  }

  Future<void> _save() async {
    final store = StoreScope.read(context);
    setState(() {
      _firstError = _first.text.trim().isEmpty ? 'نام را بنویسید.' : null;
      _lastError = _last.text.trim().isEmpty ? 'نام خانوادگی را بنویسید.' : null;
      _typeError = _typeId == null ? 'نوع ثبت‌نامی تعریف نشده است؛ از مدیر بخواهید.' : null;
      if (_card == null) _cardError ??= 'یک کارت رزرو اسکن کنید یا شماره‌اش را بنویسید.';
    });
    // فوکوس خودکار روی اولین فیلد مشکل‌دار.
    if (_firstError != null) return _firstFocus.requestFocus();
    if (_lastError != null) return _lastFocus.requestFocus();
    if (_typeError != null) return;
    if (_card == null) return _serialFocus.requestFocus();

    final dup = store.findByMobile(_mobile.text);
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
    final a = store.walkin(
      firstName: _first.text,
      lastName: _last.text,
      mobile: _mobile.text,
      email: _email.text,
      registrationTypeId: _typeId!,
      card: _card!,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${a.fullName} ثبت و پذیرش شد — کارت رزرو ${faDigits(_card!.serial)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final free = store.freeReserveCards.length;
    const gap = SizedBox(height: DaftarSize.space4);

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام در محل')),
      body: ListView(
        padding: const EdgeInsets.all(DaftarSize.space4),
        children: [
          DaftarField(
            label: 'نام',
            error: _firstError,
            child: TextField(
              controller: _first,
              focusNode: _firstFocus,
              autofocus: _first.text.isEmpty,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _firstError == null ? null : setState(() => _firstError = null),
              onSubmitted: (_) => _lastFocus.requestFocus(),
            ),
          ),
          gap,
          DaftarField(
            label: 'نام خانوادگی',
            error: _lastError,
            child: TextField(
              controller: _last,
              focusNode: _lastFocus,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _lastError == null ? null : setState(() => _lastError = null),
              onSubmitted: (_) => _mobileFocus.requestFocus(),
            ),
          ),
          gap,
          DaftarField(
            label: 'موبایل',
            optional: true,
            child: TextField(
              controller: _mobile,
              focusNode: _mobileFocus,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _emailFocus.requestFocus(),
            ),
          ),
          gap,
          DaftarField(
            label: 'ایمیل',
            optional: true,
            child: TextField(
              controller: _email,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _serialFocus.requestFocus(),
            ),
          ),
          gap,
          DaftarField(
            label: 'نوع ثبت‌نام',
            error: _typeError,
            child: store.types.length <= 3 && store.types.isNotEmpty
                ? SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [for (final t in store.types) ButtonSegment(value: t.id, label: Text(t.name))],
                    selected: {if (_typeId != null) _typeId!},
                    onSelectionChanged: (v) => setState(() => _typeId = v.first),
                  )
                : DropdownButtonFormField<int>(
                    initialValue: _typeId,
                    items: [for (final t in store.types) DropdownMenuItem(value: t.id, child: Text(t.name))],
                    onChanged: (v) => setState(() => _typeId = v),
                  ),
          ),
          const SizedBox(height: DaftarSize.space5),
          Row(children: [
            Expanded(child: Text('کارت رزرو', style: theme.textTheme.titleMedium)),
            Text('${faDigits(free)} کارت آزاد',
                style: theme.textTheme.bodySmall?.copyWith(color: free == 0 ? x.stop : x.inkMuted)),
          ]),
          const SizedBox(height: DaftarSize.space2),
          if (_card != null)
            // خانه‌ی پر: پلاک شماره‌ی کارت درشت با تیک.
            Container(
              padding: const EdgeInsets.all(DaftarSize.space4),
              decoration: BoxDecoration(
                color: x.goSoft,
                borderRadius: BorderRadius.circular(DaftarSize.radiusMd),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: x.go, size: 32),
                const SizedBox(width: DaftarSize.space3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('کارت رزرو وصل می‌شود', style: theme.textTheme.bodySmall?.copyWith(color: x.ink)),
                    Text('R${faDigits(_card!.serial)}',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                  ]),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _card = null;
                    _serial.clear();
                  }),
                  child: const Text('تعویض'),
                ),
              ]),
            )
          else
            DaftarField(
              label: 'شماره‌ی روی کارت',
              error: _cardError,
              helper: 'کارت را اسکن کنید یا شماره را بنویسید (R5001 یا 5001).',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serial,
                      focusNode: _serialFocus,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _setCardFromSerial,
                      onChanged: (_) => _cardError == null ? null : setState(() => _cardError = null),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: 'انتخاب با شماره',
                          onPressed: () => _setCardFromSerial(_serial.text),
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: DaftarSize.space2),
                  OutlinedButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('اسکن'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: DaftarSize.space6),
          FilledButton.icon(
            style: daftarGoStyle(context),
            icon: const Icon(Icons.how_to_reg_rounded),
            label: const Text('ثبت، پذیرش و تحویل کارت'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
