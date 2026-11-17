import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import 'report.dart';
import '../state.dart';

class StaffScreen extends StatefulWidget {
  /// روی موبایل، تب «نیروها» دستگاه‌ها را هم نشان می‌دهد.
  final bool showDevices;
  const StaffScreen({super.key, this.showDevices = false});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  int _rev = 0; // برای بازسازی فیلدها بعد از ساخت PIN خودکار

  /// ذخیره؛ اگر کسی دیگر در این فاصله ذخیره کرده باشد، پنجره‌ی تعارض (حالت ۱۱ طراحی).
  Future<void> _save(AdminState s, {bool force = false}) async {
    final conflicts = await s.pushStaff(force: force);
    if (!mounted) return;
    setState(() => _rev++);
    if (conflicts == null) return;
    final who = conflicts.map((c) => c.updatedBy).where((e) => e.isNotEmpty).toSet().join('، ');
    final at = conflicts.map((c) => DateTime.tryParse(c.updatedAt ?? '')).whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('این فهرست را شخص دیگری عوض کرده'),
        content: Text([
          'نیرو: ${conflicts.map((c) => c.name).join('، ')}',
          if (at != null) 'آخرین ذخیره روی سرور: ${hm(at)}${who.isNotEmpty ? ' توسط $who' : ''}',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('انصراف')),
          OutlinedButton(onPressed: () => Navigator.pop(c, 'theirs'), child: const Text('تغییر او را ببین')),
          FilledButton(onPressed: () => Navigator.pop(c, 'mine'), child: const Text('تغییر من را بگذار')),
        ],
      ),
    );
    if (choice == 'theirs') {
      await s.reloadStaff();
      if (mounted) setState(() => _rev++);
    } else if (choice == 'mine') {
      await _save(s, force: true);
    }
  }

  void _randomPins(AdminState s) {
    final r = Random.secure();
    final used = <String>{};
    for (final st in s.staff) {
      if (!st.active || st.hasPin || st.newPin.isNotEmpty) continue;
      String pin;
      do {
        pin = (100000 + r.nextInt(900000)).toString();
      } while (used.contains(pin));
      used.add(pin);
      st.newPin = pin;
    }
    setState(() => _rev++);
    s.notify();
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final anyNewPin = s.staff.any((x) => x.newPin.isNotEmpty);
    return PageBody(title: 'نیروها', children: [
      const Hint(
        'هر نیرو با کد رویداد و PIN خودش وارد اپ گوشی می‌شود. PIN بعد از ذخیره فقط به‌صورت رمزشده روی سرور می‌ماند؛ '
        'اگر فراموش شد، PIN تازه بدهید. نیروی غیرفعال‌شده وارد نمی‌شود و گوشی‌هایش باطل می‌شوند؛ '
        'فقط با «فعال کردن دوباره» برمی‌گردد. اجازه‌ها روی سرور سنجیده می‌شوند.',
      ),
      if (_lastSaved(s) != null)
        Padding(
          padding: const EdgeInsets.only(top: DaftarSize.space2),
          child: Text(_lastSaved(s)!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DaftarColors.of(context).inkMuted)),
        ),
      const SizedBox(height: 12),
      for (final st in s.staff)
        Padding(
          key: ValueKey('${identityHashCode(st)}-$_rev'),
          padding: const EdgeInsets.only(bottom: 6),
          child: LayoutBuilder(builder: (context, c) {
            final name = TextFormField(
              initialValue: st.name,
              enabled: st.active,
              decoration: InputDecoration(
                labelText: 'نام',
                isDense: true,
                suffix: st.active ? null : const DaftarTag('غیرفعال', kind: TagKind.outline),
              ),
              onChanged: (v) => st.name = v.trim(),
            );
            final pin = TextFormField(
              initialValue: st.newPin,
              enabled: st.active,
              decoration: InputDecoration(
                labelText: st.hasPin ? 'PIN جدید (خالی = بدون تغییر)' : 'PIN (۴ تا ۸ رقم)',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              onChanged: (v) => st.newPin = v.trim(),
            );
            final flags = Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Flag('پذیرش', st.canCheckin, st.active ? (v) => setState(() => st.canCheckin = v) : null),
              _Flag('پذیرایی', st.canServe, st.active ? (v) => setState(() => st.canServe = v) : null),
              _Flag('مدیر', st.isAdmin, st.active ? (v) => setState(() => st.isAdmin = v) : null),
            ]);
            // نیروی ذخیره‌نشده از فرم برداشته می‌شود؛ نیروی روی سرور فقط با دکمه‌ی صریح غیرفعال/فعال می‌شود.
            final Widget delete = st.id == null
                ? IconButton(
                    tooltip: 'برداشتن از فرم',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      s.staff.remove(st);
                      s.notify();
                    },
                  )
                : st.active
                    ? TextButton(
                        onPressed: () => setState(() => st.active = false),
                        child: const Text('غیرفعال کردن'),
                      )
                    : TextButton(
                        onPressed: () => setState(() => st.active = true),
                        child: const Text('فعال کردن دوباره'),
                      );
            if (c.maxWidth >= 720) {
              return Row(children: [
                Expanded(child: name),
                const SizedBox(width: 8),
                SizedBox(width: 150, child: pin),
                const SizedBox(width: 8),
                flags,
                delete,
              ]);
            }
            // گوشی: هر نیرو یک کارت عمودی.
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(DaftarSize.space3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [Expanded(child: name), delete]),
                  const SizedBox(height: DaftarSize.space2),
                  pin,
                  flags,
                ]),
              ),
            );
          }),
        ),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('نیروی جدید'),
          onPressed: () {
            s.staff.add(StaffDef(''));
            s.notify();
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.casino_rounded),
          label: const Text('PIN تصادفی برای کسانی که ندارند'),
          onPressed: () => _randomPins(s),
        ),
      ]),
      if (anyNewPin)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'PINها را قبل از ذخیره یادداشت کنید و به هر نیرو بدهید؛ بعد از ذخیره دیگر نمایش داده نمی‌شوند.',
          ),
        ),
      const SizedBox(height: 16),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          icon: const Icon(Icons.cloud_upload_rounded),
          onPressed: s.busy ? null : () => _save(s),
          label: const Text('ذخیره روی سرور'),
        ),
      ),
      const SizedBox(height: 8),
      const Hint('«مدیر» یعنی آن نیرو در اپ گوشی می‌تواند پذیرش اشتباه را لغو کند.'),
      if (widget.showDevices) ...[
        const SectionTitle('دستگاه‌ها'),
        if (s.report == null)
          const Hint('برای دیدن دستگاه‌ها، تب «امروز» را باز کنید.')
        else
          for (final d in (s.report!['devices'] as List? ?? const []))
            DeviceRow(device: (d as Map).cast<String, dynamic>()),
      ],
    ]);
  }
}

/// «آخرین ذخیره روی سرور: ۱۰:۴۲ توسط مهسا»
String? _lastSaved(AdminState s) {
  StaffDef? last;
  DateTime? at;
  for (final st in s.staff) {
    final t = DateTime.tryParse(st.updatedAt ?? '');
    if (t != null && (at == null || t.isAfter(at))) {
      at = t;
      last = st;
    }
  }
  if (last == null || at == null) return null;
  return 'آخرین ذخیره روی سرور: ${hm(at)}${last.updatedBy.isNotEmpty ? ' توسط ${last.updatedBy}' : ''}';
}

class _Flag extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _Flag(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(value: value, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false)),
        Text(label),
        const SizedBox(width: 6),
      ]);
}
