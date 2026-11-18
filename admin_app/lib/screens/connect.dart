import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/firouzeh.dart';
import '../theme/jalali_picker.dart';
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
  // تاریخ‌ها ISO میلادی؛ فقط انتخاب‌گر شمسی است.
  String _start = '';
  String _end = '';
  final _base = TextEditingController();
  String? _filledFor;

  /// «رویداد تازه»: فرم خالی و کد قابل ویرایش، حتی وقتی رویدادی انتخاب شده.
  bool _creating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = StateScope.read(context);
    if (_server.text.isEmpty) _server.text = s.server;
    if (_key.text.isEmpty) _key.text = s.apiKey;
  }

  void _fillFromEvent() {
    final e = StateScope.read(context).event;
    if (_creating || e == null || _filledFor == e.code) return;
    _filledFor = e.code;
    _code.text = e.code;
    _name.text = e.name;
    _start = e.startDate ?? '';
    _end = e.endDate ?? '';
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
          helperText: 'از پیشخوان وردپرس: رویدادیار ← اتصال اپ‌ها ← ساخت کلید. '
              'کلید را هر وقت لازم شد از پیشخوان وردپرس دوباره ببین و کپی کن. '
              'برای هر دستگاه کلید جدا بسازید تا اگر گم شد، فقط همان باطل شود.',
          helperMaxLines: 3,
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
      if (s.events.isNotEmpty || s.event != null)
        Padding(
          padding: const EdgeInsets.only(top: FirouzehSize.space3),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FirouzehTag(
              'دسترسی این کلید: ${s.keyRoleLabel.isNotEmpty ? s.keyRoleLabel : 'مالک'}',
              kind: TagKind.stamp,
            ),
          ),
        ),
      if (s.events.isNotEmpty) ...[
        const SectionTitle('رویدادهای روی سرور'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in s.events)
            ChoiceChip(
              label: Text(eventChipLabel(e.name, e.code)),
              selected: !_creating && s.event?.code == e.code,
              onSelected: (_) {
                setState(() => _creating = false);
                s.selectEvent(e.code);
              },
            ),
        ]),
      ],
      if (s.archivedEvents.isNotEmpty) ...[
        const SectionTitle('بایگانی‌شده‌ها'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in s.archivedEvents)
            ChoiceChip(
              avatar: const Icon(Icons.archive_rounded, size: 18),
              label: Text(eventChipLabel(e.name, e.code)),
              selected: !_creating && s.event?.code == e.code,
              onSelected: (_) {
                setState(() => _creating = false);
                s.selectEvent(e.code);
              },
            ),
        ]),
      ],
      if (s.apiKey.isNotEmpty && s.event != null && !_creating && !s.limited)
        Padding(
          padding: const EdgeInsets.only(top: FirouzehSize.space3),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('رویداد تازه'),
              onPressed: () => setState(() {
                _creating = true;
                _filledFor = null;
                for (final c in [_code, _name, _base]) {
                  c.clear();
                }
                _start = '';
                _end = '';
              }),
            ),
          ),
        ),
      if (s.event?.archived == true && !_creating) ...[
        const SizedBox(height: FirouzehSize.space3),
        Notice(
          tone: NoticeTone.wait,
          text: 'این رویداد بایگانی شده و فقط خواندنی است. گوشی نیروها هم نمی‌توانند واردش شوند.',
          action: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: s.busy || !s.isOwner ? null : () => s.archiveEvent(false),
              child: const Text('برگرداندن از بایگانی'),
            ),
          ),
        ),
      ],
      if (s.apiKey.isNotEmpty && !s.limited) ...[
        SectionTitle(s.event == null || _creating ? 'ساخت رویداد جدید' : 'مشخصات رویداد'),
        // گوشی: کد و نام زیر هم (کنار هم کد بریده می‌شد).
        Builder(builder: (context) {
          final code = TextField(
              controller: _code,
              // کد رویداد بعد از ساخت قابل تغییر نیست؛ تغییرش رویداد تازه می‌ساخت.
              enabled: s.event == null || _creating,
              decoration: InputDecoration(
                labelText: 'کد رویداد (لاتین، مثلاً conf1405)',
                helperText: s.event == null || _creating ? null : 'بعد از ساخت قابل تغییر نیست',
                suffixIcon: s.event == null || _creating ? null : const Icon(Icons.lock_rounded, size: 18),
              ),
              textDirection: TextDirection.ltr,
            );
          final name = TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام رویداد'));
          return MediaQuery.sizeOf(context).width < 640
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [name, const SizedBox(height: 8), code])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: code),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: name),
                ]);
        }),
        const SizedBox(height: 8),
        JalaliRangePicker(
          key: ValueKey(_filledFor),
          start: _start,
          end: _end,
          onChanged: (a, b) => setState(() {
            _start = a;
            _end = b;
          }),
        ),
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
            onPressed: s.busy || (s.event?.archived == true && !_creating)
                ? null
                : () async {
                    final create = s.event == null || _creating;
                    await s.saveEvent(
                      code: create ? _code.text : s.event!.code,
                      name: _name.text,
                      startDate: _start,
                      endDate: _end,
                      baseUrl: _base.text,
                      create: create,
                    );
                    if (create && !s.messageIsError && mounted) setState(() => _creating = false);
                  },
            child: Text(s.event == null || _creating ? 'ساخت رویداد' : 'ذخیره‌ی رویداد'),
          ),
          const SizedBox(width: 12),
          if (_creating)
            TextButton(
              onPressed: () => setState(() {
                _creating = false;
                _filledFor = null;
              }),
              child: const Text('انصراف'),
            ),
          if (s.event != null && !_creating && !s.event!.archived)
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
        // حذف و بایگانی رویداد فقط با کلید «مالک».
        if (s.event != null && !_creating && s.isOwner) _SensitiveActions(s: s),
      ],
    ]);
  }
}

/// «کارهای حساس»: بایگانی و حذف رویداد، هر دو با تأیید.
class _SensitiveActions extends StatelessWidget {
  final AdminState s;
  const _SensitiveActions({required this.s});

  @override
  Widget build(BuildContext context) {
    final x = FirouzehColors.of(context);
    final e = s.event!;
    final style = OutlinedButton.styleFrom(
      foregroundColor: x.stop,
      side: BorderSide(color: x.stop, width: 1.5),
      minimumSize: const Size(0, FirouzehSize.tapMin),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('کارهای حساس'),
      Wrap(spacing: FirouzehSize.space3, runSpacing: FirouzehSize.space2, children: [
        if (!e.archived)
          OutlinedButton.icon(
            style: style,
            icon: const Icon(Icons.archive_rounded),
            label: const Text('بایگانی رویداد…'),
            onPressed: s.busy
                ? null
                : () async {
                    if (await _confirmArchive(context) == true) await s.archiveEvent(true);
                  },
          ),
        OutlinedButton.icon(
          style: style,
          icon: const Icon(Icons.delete_rounded),
          label: const Text('حذف رویداد…'),
          onPressed: s.busy ? null : () => _deleteEvent(context, s),
        ),
      ]),
    ]);
  }
}

Future<bool?> _confirmArchive(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('بایگانی رویداد؟'),
        content: const Text('رویداد از فهرست کنار می‌رود و فقط خواندنی می‌شود. هر وقت خواستید برش می‌گردانید.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
          FilledButton(style: firouzehDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('بایگانی')),
        ],
      ),
    );

/// حذف رویداد در دو مرحله: پیامد را نشان می‌دهد و تایپ کد رویداد را می‌خواهد.
/// رویدادی که کار ثبت‌شده دارد حذف نمی‌شود؛ پیشنهاد بایگانی داده می‌شود.
Future<void> _deleteEvent(BuildContext context, AdminState s) async {
  final e = s.event!;
  Map<String, dynamic> impact;
  try {
    impact = await s.eventImpact();
  } catch (err) {
    s.message = 'پیامد حذف از سرور گرفته نشد: $err';
    s.messageIsError = true;
    s.notify();
    return;
  }
  if (!context.mounted) return;
  int n(String k) => (impact[k] as int?) ?? 0;
  final summary = '${faDigits(n('attendees'))} نفر، ${faDigits(n('checkins'))} پذیرش، '
      '${faDigits(n('meals_served'))} تحویل و ${faDigits(n('staff'))} نیرو';
  if (n('log') > 0) {
    final archive = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف رویداد «${e.name}»؟'),
        content: SizedBox(
          width: 440,
          child: Notice(
            tone: NoticeTone.stop,
            text: 'این رویداد $summary دارد. چون کار ثبت‌شده دارد، حذف نمی‌شود. '
                'اول از گزارش خروجی بگیرید، بعد بایگانی‌اش کنید.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
          if (!e.archived)
            FilledButton(style: firouzehDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('بایگانی')),
        ],
      ),
    );
    if (archive == true) await s.archiveEvent(true);
    return;
  }
  final code = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('حذف رویداد «${e.name}»؟'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Notice(tone: NoticeTone.stop, text: '$summary حذف می‌شود. این کار برگشت ندارد.'),
            const SizedBox(height: FirouzehSize.space4),
            FirouzehField(
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
          FilledButton(
            style: firouzehDangerStyle(c),
            onPressed: code.text.trim() == e.code ? () => Navigator.pop(c, true) : null,
            child: const Text('حذف رویداد'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await s.run('', () => s.deleteEvent(code.text.trim()));
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
            const SizedBox(height: FirouzehSize.space4),
            FirouzehField(
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
            style: firouzehDangerStyle(c),
            onPressed: code.text.trim() == e.code ? () => Navigator.pop(c, true) : null,
            child: const Text('قفل را بردار'),
          ),
        ],
      ),
    ),
  );
}


/// برچسب چیپ رویداد: «نام (کد)» با جداسازی جهت (نام فارسی با حرف لاتین، کد لاتین)؛ اگر نام همان کد است (بی‌توجه به حروف بزرگ و کوچک) فقط یکی.
String eventChipLabel(String name, String code) =>
    name.trim().isEmpty || name.trim().toLowerCase() == code.trim().toLowerCase() ? code : '\u2067$name\u2069 (\u2066$code\u2069)';
