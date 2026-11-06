import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _server = TextEditingController();
  final _key = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _base = TextEditingController();
  String? _filledFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = StateScope.read(context);
    if (_server.text.isEmpty) _server.text = s.server;
    if (_key.text.isEmpty) _key.text = s.apiKey;
  }

  void _fillFromEvent() {
    final e = StateScope.read(context).event;
    if (e == null || _filledFor == e.code) return;
    _filledFor = e.code;
    _code.text = e.code;
    _name.text = e.name;
    _start.text = e.startDate ?? '';
    _end.text = e.endDate ?? '';
    _base.text = e.baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    _fillFromEvent();
    return PageBody(title: 'اتصال و رویداد', children: [
      const SectionTitle('اتصال به سایت'),
      TextField(controller: _server, decoration: const InputDecoration(labelText: 'آدرس سایت'), textDirection: TextDirection.ltr),
      const SizedBox(height: 8),
      TextField(
        controller: _key,
        decoration: const InputDecoration(
          labelText: 'کلید API',
          helperText: 'از پیشخوان وردپرس: رویدادیار ← تنظیمات ← ساخت کلید',
        ),
        obscureText: true,
        textDirection: TextDirection.ltr,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton(
          onPressed: s.busy ? null : () => s.connect(_server.text, _key.text),
          child: const Text('اتصال'),
        ),
      ),
      if (s.events.isNotEmpty) ...[
        const SectionTitle('رویدادهای روی سرور'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in s.events)
            ChoiceChip(
              label: Text('${e.name} (${e.code})'),
              selected: s.event?.code == e.code,
              onSelected: (_) => s.selectEvent(e.code),
            ),
        ]),
      ],
      if (s.apiKey.isNotEmpty) ...[
        SectionTitle(s.event == null ? 'ساخت رویداد جدید' : 'مشخصات رویداد'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'کد رویداد (لاتین، مثلاً conf1405)'),
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام رویداد'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _start,
              decoration: const InputDecoration(labelText: 'تاریخ شروع (میلادی، 2026-11-11)'),
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _end,
              decoration: const InputDecoration(labelText: 'تاریخ پایان (میلادی)'),
              textDirection: TextDirection.ltr,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _base,
          enabled: !(s.event?.locked ?? false),
          decoration: InputDecoration(
            labelText: 'آدرس پایه‌ی لینک QR',
            helperText: s.event?.locked == true
                ? 'قفل است چون PDF کارت‌ها ساخته شده؛ لینک کارت‌های چاپ‌شده به این آدرس وابسته است.'
                : 'خالی = آدرس همین سایت. لینک هر کارت می‌شود: آدرس پایه/c/توکن',
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton(
            onPressed: s.busy
                ? null
                : () => s.saveEvent(
                      code: _code.text,
                      name: _name.text,
                      startDate: _start.text,
                      endDate: _end.text,
                      baseUrl: _base.text,
                    ),
            child: const Text('ذخیره‌ی رویداد'),
          ),
          const SizedBox(width: 12),
          if (s.event != null)
            OutlinedButton(
              onPressed: s.busy
                  ? null
                  : () async {
                      if (!s.event!.locked) return s.setLocked(true);
                      if (await _confirmUnlock(context, s.event!) == true) await s.setLocked(false);
                    },
              child: Text(s.event!.locked ? 'برداشتن قفل آدرس پایه' : 'قفل آدرس پایه'),
            ),
        ]),
      ],
    ]);
  }
}

/// برداشتن قفل آدرس پایه کار خطرناکی است: QR همه‌ی کارت‌های چاپ‌شده به این آدرس وابسته است.
/// برای تأیید، تایپ کد رویداد لازم است.
Future<bool?> _confirmUnlock(BuildContext context, EventInfo e) {
  final code = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('برداشتن قفل آدرس پایه'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Notice(
              tone: NoticeTone.stop,
              text: 'اگر بعد از چاپ کارت‌ها آدرس پایه عوض شود، QR همه‌ی کارت‌های چاپ‌شده دیگر کار نمی‌کند '
                  'و باید دوباره چاپ شوند.',
            ),
            const SizedBox(height: DaftarSize.space4),
            DaftarField(
              label: 'برای تأیید، کد رویداد را بنویسید: ${e.code}',
              child: TextField(
                controller: code,
                autofocus: true,
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(
            style: daftarDangerStyle(c),
            onPressed: code.text.trim() == e.code ? () => Navigator.pop(c, true) : null,
            child: const Text('قفل را بردار'),
          ),
        ],
      ),
    ),
  );
}
