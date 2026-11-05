import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
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

  void _randomPins(AdminState s) {
    final r = Random.secure();
    final used = <String>{};
    for (final st in s.staff) {
      if (st.hasPin || st.newPin.isNotEmpty) continue;
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
        'اگر فراموش شد، PIN تازه بدهید. نیرویی که از لیست حذف شود، گوشی‌هایش هم باطل می‌شوند.',
      ),
      const SizedBox(height: 12),
      for (final st in s.staff)
        Padding(
          key: ValueKey('${identityHashCode(st)}-$_rev'),
          padding: const EdgeInsets.only(bottom: 6),
          child: LayoutBuilder(builder: (context, c) {
            final name = TextFormField(
              initialValue: st.name,
              decoration: const InputDecoration(labelText: 'نام', isDense: true),
              onChanged: (v) => st.name = v.trim(),
            );
            final pin = TextFormField(
              initialValue: st.newPin,
              decoration: InputDecoration(
                labelText: st.hasPin ? 'PIN جدید (خالی = بدون تغییر)' : 'PIN (۴ تا ۸ رقم)',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              onChanged: (v) => st.newPin = v.trim(),
            );
            final flags = Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Flag('پذیرش', st.canCheckin, (v) => setState(() => st.canCheckin = v)),
              _Flag('پذیرایی', st.canServe, (v) => setState(() => st.canServe = v)),
              _Flag('مدیر', st.isAdmin, (v) => setState(() => st.isAdmin = v)),
            ]);
            final delete = IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                s.staff.remove(st);
                s.notify();
              },
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
          onPressed: s.busy
              ? null
              : () async {
                  await s.pushStaff();
                  setState(() => _rev++);
                },
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

class _Flag extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Flag(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Text(label),
        const SizedBox(width: 6),
      ]);
}
