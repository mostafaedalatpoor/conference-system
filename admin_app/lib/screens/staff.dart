import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// نیروهایی که پین‌شان دیده می‌شود (آیکن چشم).
  final Set<int> _shown = {};

  /// ذخیره؛ اگر کسی دیگر در این فاصله ذخیره کرده باشد، پنجره‌ی تعارض (حالت ۱۱ طراحی).
  Future<void> _save(AdminState s, {bool force = false}) async {
    // نیروهای تازه‌ای که پین گرفته‌اند، برای برگه‌ی «نیروی تازه ساخته شد».
    final fresh = [for (final st in s.staff) if (st.id == null && st.newPin.isNotEmpty) st.name];
    final conflicts = await s.pushStaff(force: force);
    if (!mounted) return;
    setState(() => _rev++);
    if (conflicts == null && !s.messageIsError) {
      for (final name in fresh) {
        final st = s.staff.where((x) => x.name == name).firstOrNull;
        if (st?.pin != null && mounted) await _showCreated(st!);
      }
    }
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

  /// پین تصادفی ۴ رقمی که با پین‌های دیده‌شده‌ی دیگر یکی نیست (سرور هم تکراری را رد می‌کند).
  String _randomPin(AdminState s) {
    final r = Random.secure();
    final used = {for (final st in s.staff) ...[if (st.pin != null) st.pin!, if (st.newPin.isNotEmpty) st.newPin]};
    String pin;
    do {
      pin = (1000 + r.nextInt(9000)).toString();
    } while (used.contains(pin));
    return pin;
  }

  void _randomPins(AdminState s) {
    for (final st in s.staff) {
      if (!st.active || st.hasPin || st.newPin.isNotEmpty) continue;
      st.newPin = _randomPin(s);
    }
    setState(() => _rev++);
    s.notify();
  }

  Future<void> _copy(String pin) async {
    await Clipboard.setData(ClipboardData(text: pin));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پین کپی شد.')));
  }

  /// برگه‌ی «نیروی تازه ساخته شد» (۱۱-StaffPin): نام، پین درشت با چشم و کپی، «بستن».
  Future<void> _showCreated(StaffDef st) {
    var visible = true;
    final roles = [if (st.canCheckin) 'پذیرش', if (st.canServe) 'پذیرایی', if (st.isAdmin) 'مدیر'].join('، ');
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final x = DaftarColors.of(c);
          final theme = Theme.of(c);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DaftarSize.space4, 0, DaftarSize.space4, DaftarSize.space5),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('نیروی تازه ساخته شد', style: theme.textTheme.titleLarge),
                const SizedBox(height: DaftarSize.space3),
                Container(
                  padding: const EdgeInsets.all(DaftarSize.space3),
                  decoration: BoxDecoration(color: x.sunken, borderRadius: BorderRadius.circular(DaftarSize.radiusMd)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('نیرو', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                    Text([st.name, if (roles.isNotEmpty) roles].join(' · '), style: theme.textTheme.titleMedium),
                  ]),
                ),
                const SizedBox(height: DaftarSize.space3),
                Container(
                  padding: const EdgeInsets.all(DaftarSize.space4),
                  decoration: BoxDecoration(color: x.stampSoft, borderRadius: BorderRadius.circular(DaftarSize.radiusLg)),
                  child: Column(children: [
                    Text(
                      visible ? faDigits(st.pin!) : '•' * st.pin!.length,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 10, fontFeatures: tabularFigures),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        tooltip: visible ? 'پنهان کردن' : 'نشان دادن',
                        onPressed: () => setSheet(() => visible = !visible),
                        icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      ),
                      IconButton(tooltip: 'کپی پین', onPressed: () => _copy(st.pin!), icon: const Icon(Icons.content_copy_rounded)),
                    ]),
                  ]),
                ),
                const SizedBox(height: DaftarSize.space4),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(DaftarSize.tapLg)),
                  onPressed: () => Navigator.pop(c),
                  child: const Text('بستن'),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  /// خانه‌ی پین در ردیف نیرو (۱۱-StaffPin و ۰۴-Phones): پوشیده با چشم و کپی، «پین قدیمی ثبت‌شده نیست · بساز»،
  /// یا فیلد پین تازه وقتی مدیر «پین تازه» یا «بساز» زده.
  Widget _pinCell(AdminState s, StaffDef st) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    if (st.newPin.isNotEmpty || (st.id == null)) {
      return TextFormField(
        initialValue: st.newPin,
        enabled: st.active,
        decoration: InputDecoration(
          labelText: 'پین (خودکار یا دلخواه ۴ رقمی)',
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'پین تصادفی',
            icon: const Icon(Icons.casino_rounded, size: 18),
            onPressed: () => setState(() {
              st.newPin = _randomPin(s);
              _rev++;
            }),
          ),
        ),
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        onChanged: (v) => st.newPin = v.trim(),
      );
    }
    final make = TextButton(
      onPressed: st.active
          ? () => setState(() {
                st.newPin = _randomPin(s);
                _rev++;
              })
          : null,
      child: Text(st.pin != null ? 'پین تازه' : 'بساز'),
    );
    if (st.pin == null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(st.pinLegacy ? 'پین قدیمی ثبت‌شده نیست ·' : 'پین ندارد ·',
              style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
        ),
        make,
      ]);
    }
    final shown = _shown.contains(st.id);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('پین', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
      const SizedBox(width: DaftarSize.space2),
      Text(shown ? faDigits(st.pin!) : '•' * st.pin!.length,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 3, fontFeatures: tabularFigures)),
      IconButton(
        tooltip: shown ? 'پنهان کردن' : 'نشان دادن',
        icon: Icon(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
        onPressed: () => setState(() => shown ? _shown.remove(st.id) : _shown.add(st.id!)),
      ),
      IconButton(tooltip: 'کپی پین', icon: const Icon(Icons.content_copy_rounded, size: 20), onPressed: () => _copy(st.pin!)),
      if (st.active) make,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final anyNewPin = s.staff.any((x) => x.newPin.isNotEmpty);
    return PageBody(title: 'نیروها', children: [
      const Hint(
        'هر نیرو با کد رویداد و پین خودش وارد اپ گوشی می‌شود. پین هر نیرو اینجا با آیکن چشم دیده و با کپی کپی می‌شود؛ '
        'اگر لازم شد «پین تازه» بدهید. نیروی غیرفعال‌شده وارد نمی‌شود و گوشی‌هایش باطل می‌شوند؛ '
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
            final pin = _pinCell(s, st);
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
                SizedBox(width: 300, child: Align(alignment: AlignmentDirectional.centerStart, child: pin)),
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
                  Align(alignment: AlignmentDirectional.centerStart, child: pin),
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
          label: const Text('پین تصادفی برای کسانی که ندارند'),
          onPressed: () => _randomPins(s),
        ),
      ]),
      if (anyNewPin)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Hint('پین‌های تازه با «ذخیره روی سرور» ثبت می‌شوند و بعد هم همین‌جا دیده می‌شوند.'),
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
