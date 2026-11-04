import 'package:flutter/material.dart';

import '../main.dart';

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
    return PageBody(children: [
      const SectionTitle('اتصال به سایت'),
      TextField(controller: _server, decoration: const InputDecoration(labelText: 'آدرس سایت'), textDirection: TextDirection.ltr),
      const SizedBox(height: 8),
      TextField(
        controller: _key,
        decoration: const InputDecoration(
          labelText: 'کلید API',
          helperText: 'از پیشخوان وردپرس: کنفرانس ← تنظیمات ← ساخت کلید',
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
              onPressed: s.busy ? null : () => s.setLocked(!s.event!.locked),
              child: Text(s.event!.locked ? 'برداشتن قفل آدرس پایه' : 'قفل آدرس پایه'),
            ),
        ]),
      ],
    ]);
  }
}
