import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';

/// پذیرایی: اسکن پشت‌سرهم کارت‌ها برای وعده‌ی جاری.
/// اگر فرد حق وعده را داشته باشد و هنوز نگرفته باشد، تحویل همان لحظه ثبت می‌شود.
class MealScreen extends StatefulWidget {
  const MealScreen({super.key});

  @override
  State<MealScreen> createState() => _MealScreenState();
}

class _Result {
  final Color color;
  final IconData icon;
  final String title;
  final String detail;
  _Result(this.color, this.icon, this.title, this.detail);
}

class _MealScreenState extends State<MealScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  _Result? _result;
  String? _lastToken;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _clear;
  bool _cameraOn = true;

  @override
  void dispose() {
    _clear?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _show(_Result r) {
    _clear?.cancel();
    setState(() => _result = r);
    _clear = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _result = null);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final store = StoreScope.read(context);
    final meal = store.selectedMeal;
    if (meal == null) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final token = tokenFromScan(raw);
      final now = DateTime.now();
      // همان کارت در چند ثانیه‌ی پشت‌سرهم دوبار حساب نشود.
      if (token != null && token == _lastToken && now.difference(_lastAt).inSeconds < 5) return;
      _lastToken = token;
      _lastAt = now;
      if (token == null) {
        _show(_Result(Colors.grey, Icons.help_outline, 'QR ناشناخته', 'این کد مال کارت کنفرانس نیست.'));
        return;
      }
      final a = store.attendeeForToken(token);
      if (a == null) {
        _show(_Result(Colors.red, Icons.block, 'کارت نامعتبر',
            store.cards.containsKey(token) ? 'این کارت رزرو به کسی وصل نشده.' : 'این کارت در لیست نیست.'));
        return;
      }
      _evaluate(a, meal);
      return;
    }
  }

  void _evaluate(Attendee a, Meal meal) {
    final store = StoreScope.read(context);
    final c = store.checkMeal(a, meal);
    switch (c.verdict) {
      case MealVerdict.ok:
        store.serveMeal(a, meal);
        _show(_Result(Colors.green, Icons.check_circle, 'مجاز — تحویل شود', a.displayName));
        break;
      case MealVerdict.duplicate:
        _show(_Result(Colors.red, Icons.replay, 'قبلاً گرفته', '${a.displayName} — ساعت ${hm(c.previousAt!)}'));
        break;
      case MealVerdict.notEntitled:
        _show(_Result(Colors.red, Icons.do_not_disturb_on, 'این وعده شامل او نیست',
            '${a.displayName} — ${store.typeName(a.registrationTypeId)}'));
        break;
    }
  }

  Future<void> _searchByName() async {
    final store = StoreScope.read(context);
    final meal = store.selectedMeal;
    if (meal == null) return;
    final a = await showDialog<Attendee>(context: context, builder: (_) => const _PickAttendeeDialog());
    if (a != null && mounted) {
      _lastToken = null;
      _evaluate(a, meal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final meal = store.selectedMeal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: DropdownButtonFormField<int>(
            value: meal?.id,
            decoration: const InputDecoration(labelText: 'وعده‌ی جاری', border: OutlineInputBorder()),
            items: [
              for (final m in store.meals)
                DropdownMenuItem(value: m.id, child: Text('${m.name}${m.day != null ? ' — ${m.day}' : ''}')),
            ],
            onChanged: store.selectMeal,
          ),
        ),
        if (meal != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'تحویل‌شده: ${faDigits(store.servedCount(meal.id))} از ${faDigits(store.entitledCount(meal))} نفرِ دارای حق',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: meal == null
              ? const Center(child: Text('اول وعده‌ی جاری را انتخاب کنید.'))
              : Stack(
                  children: [
                    if (_cameraOn)
                      Positioned.fill(child: MobileScanner(controller: _controller, onDetect: _onDetect))
                    else
                      const Center(child: Text('دوربین خاموش است.')),
                    if (_result != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Card(
                          color: _result!.color,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                Icon(_result!.icon, color: Colors.white, size: 44),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_result!.title,
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                                      Text(_result!.detail, style: const TextStyle(color: Colors.white, fontSize: 16)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (meal != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('کارت همراهش نیست؟ جستجوی نام'),
                    onPressed: _searchByName,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _cameraOn ? 'خاموش کردن دوربین' : 'روشن کردن دوربین',
                  icon: Icon(_cameraOn ? Icons.videocam_off : Icons.videocam),
                  onPressed: () => setState(() => _cameraOn = !_cameraOn),
                ),
                IconButton(
                  tooltip: 'چراغ',
                  icon: const Icon(Icons.flash_on),
                  onPressed: _cameraOn ? () => _controller.toggleTorch() : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PickAttendeeDialog extends StatefulWidget {
  const _PickAttendeeDialog();

  @override
  State<_PickAttendeeDialog> createState() => _PickAttendeeDialogState();
}

class _PickAttendeeDialogState extends State<_PickAttendeeDialog> {
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final results = store.search(_q.text, limit: 20);
    return AlertDialog(
      title: const Text('جستجوی نام'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'نام یا موبایل'),
              onChanged: (_) => setState(() {}),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final a in results)
                    ListTile(
                      title: Text(a.displayName),
                      subtitle: Text(store.typeName(a.registrationTypeId)),
                      onTap: () => Navigator.of(context).pop(a),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
    );
  }
}
