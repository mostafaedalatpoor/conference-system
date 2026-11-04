import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
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
  int? _typeId;
  PassCard? _card;
  String? _error;

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
        _error = 'این کارت در لیست نیست. اگر کارت تازه است، از «وضعیت» لیست را دوباره بگیرید.';
      } else if (!c.isReserve) {
        _card = null;
        _error = 'این کارت رزرو نیست؛ مال ${store.attendeeForToken(token)?.fullName ?? 'شخص دیگری'} است.';
      } else if (store.cardOwner.containsKey(token)) {
        _card = null;
        _error = 'این کارت رزرو قبلاً به ${store.attendeeForToken(token)?.fullName ?? 'کسی'} وصل شده.';
      } else {
        _card = c;
        _serial.text = faDigits(c.serial);
        _error = null;
      }
    });
  }

  void _setCardFromSerial(String s) {
    final store = StoreScope.read(context);
    final n = int.tryParse(latinDigits(s.trim()));
    if (n == null) return;
    final match = store.cards.values.where((c) => c.isReserve && c.serial == n);
    if (match.isEmpty) {
      setState(() {
        _card = null;
        _error = 'کارت رزرو با این شماره پیدا نشد.';
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
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = 'نام و نام خانوادگی لازم است.');
      return;
    }
    if (_typeId == null) {
      setState(() => _error = 'نوع ثبت‌نامی تعریف نشده است.');
      return;
    }
    if (_card == null) {
      setState(() => _error = 'یک کارت رزرو اسکن کنید یا شماره‌اش را بنویسید.');
      return;
    }
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
      content: Text('${a.fullName} ثبت و پذیرش شد — کارت رزرو شماره‌ی ${faDigits(_card!.serial)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final free = store.freeReserveCards.length;
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام در محل')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _first, decoration: const InputDecoration(labelText: 'نام')),
          const SizedBox(height: 10),
          TextField(controller: _last, decoration: const InputDecoration(labelText: 'نام خانوادگی')),
          const SizedBox(height: 10),
          TextField(
            controller: _mobile,
            decoration: const InputDecoration(labelText: 'موبایل'),
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'ایمیل (اختیاری)'),
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _typeId,
            decoration: const InputDecoration(labelText: 'نوع ثبت‌نام'),
            items: [for (final t in store.types) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (v) => setState(() => _typeId = v),
          ),
          const SizedBox(height: 20),
          Text('کارت رزرو (${faDigits(free)} کارت آزاد مانده)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serial,
                  decoration: const InputDecoration(labelText: 'شماره‌ی روی کارت'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _setCardFromSerial,
                  onChanged: (_) {
                    if (_card != null) setState(() => _card = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'انتخاب با شماره',
                onPressed: () => _setCardFromSerial(_serial.text),
                icon: const Icon(Icons.check),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('اسکن'),
              ),
            ],
          ),
          if (_card != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('کارت شماره‌ی ${faDigits(_card!.serial)} آماده‌ی وصل‌شدن است.',
                  style: const TextStyle(color: Colors.green)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('ثبت، پذیرش و تحویل کارت', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
