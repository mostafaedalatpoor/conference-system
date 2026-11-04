import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

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
    return PageBody(children: [
      const SectionTitle('نیروهای اجرایی'),
      const Text(
        'هر نیرو با کد رویداد و PIN خودش وارد اپ گوشی می‌شود. PIN بعد از ذخیره فقط به‌صورت رمزشده روی سرور می‌ماند؛ '
        'اگر فراموش شد، PIN تازه بدهید. نیرویی که از لیست حذف شود، گوشی‌هایش هم باطل می‌شوند.',
        style: TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 12),
      for (final st in s.staff)
        Padding(
          key: ValueKey('${identityHashCode(st)}-$_rev'),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: st.name,
                decoration: const InputDecoration(labelText: 'نام', isDense: true),
                onChanged: (v) => st.name = v.trim(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextFormField(
                initialValue: st.newPin,
                decoration: InputDecoration(
                  labelText: st.hasPin ? 'PIN جدید (خالی = بدون تغییر)' : 'PIN (۴ تا ۸ رقم)',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                onChanged: (v) => st.newPin = v.trim(),
              ),
            ),
            const SizedBox(width: 8),
            _Flag('پذیرش', st.canCheckin, (v) => setState(() => st.canCheckin = v)),
            _Flag('پذیرایی', st.canServe, (v) => setState(() => st.canServe = v)),
            _Flag('مدیر', st.isAdmin, (v) => setState(() => st.isAdmin = v)),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                s.staff.remove(st);
                s.notify();
              },
            ),
          ]),
        ),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('نیروی جدید'),
          onPressed: () {
            s.staff.add(StaffDef(''));
            s.notify();
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.casino_outlined),
          label: const Text('PIN تصادفی برای کسانی که ندارند'),
          onPressed: () => _randomPins(s),
        ),
      ]),
      if (anyNewPin)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('PINها را قبل از ذخیره یادداشت کنید و به هر نیرو بدهید؛ بعد از ذخیره دیگر نمایش داده نمی‌شوند.',
              style: TextStyle(color: Colors.orange)),
        ),
      const SizedBox(height: 16),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          icon: const Icon(Icons.cloud_upload),
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
      const Text('«مدیر» یعنی آن نیرو در اپ گوشی می‌تواند پذیرش اشتباه را لغو کند.', style: TextStyle(color: Colors.grey)),
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
