import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../excel_import.dart';
import '../api.dart';
import '../jalali.dart';
import '../main.dart';
import '../normalize.dart';
import '../theme/firouzeh.dart';
import '../theme/jalali_picker.dart';
import '../theme/widgets.dart';
import '../state.dart';

/// انواع ثبت‌نام، نقش‌ها، وعده‌ها و برنامه.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  void _fillDefaults(AdminState s) {
    if (s.types.isEmpty) {
      s.types = [CodeName('presenter', 'ارائه‌دهنده'), CodeName('participant', 'شرکت‌کننده')];
    }
    if (s.roles.isEmpty) {
      s.roles = [
        CodeName('speaker', 'سخنران'),
        CodeName('reviewer', 'داور'),
        CodeName('guest', 'مهمان'),
        CodeName('staff', 'نیروی اجرایی'),
      ];
    }
    if (s.meals.isEmpty) {
      final d1 = s.event?.startDate ?? '';
      final d2 = s.event?.endDate ?? d1;
      s.meals = [
        MealDef('lunch1', 'ناهار روز اول', d1, {'presenter'}, {'speaker', 'staff'}),
        MealDef('lunch2', 'ناهار روز دوم', d2, {'presenter'}, {'speaker', 'staff'}),
      ];
    }
    s.notify();
  }

  Future<void> _importSessions(AdminState s) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    try {
      final tables = await readTables(f.name, f.bytes!);
      if (tables.isEmpty) return;
      final t = tables.first;
      // ستون‌ها به این ترتیب: روز (شمسی یا میلادی)، شروع، پایان، عنوان، سالن، نوع. روز به ISO میلادی تبدیل می‌شود.
      s.sessions = [
        for (final row in t.rows)
          if (row.length >= 4 && row[0].trim().isNotEmpty && row[3].trim().isNotEmpty)
            SessionDef(parseDateInput(row[0]) ?? row[0].trim(), row[1].trim(), row[2].trim(), row[3].trim(),
                row.length > 4 ? row[4].trim() : '', row.length > 5 ? row[5].trim() : ''),
      ];
      final bad = s.sessions.where((x) => parseIsoDate(x.day) == null).length;
      if (bad > 0) {
        s.message = 'روز ${faDigits(bad)} جلسه خوانا نبود؛ روزش را از تقویم انتخاب کنید.';
        s.messageIsError = true;
      }
      s.notify();
    } catch (e) {
      s.message = 'خواندن فایل برنامه ناموفق بود: $e';
      s.messageIsError = true;
      s.notify();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final empty = s.types.isEmpty && s.roles.isEmpty && s.meals.isEmpty;

    return PageBody(title: 'پیکربندی', children: [
      if (empty)
        Card(
          child: ListTile(
            title: const Text('هنوز پیکربندی‌ای نیست.'),
            subtitle: const Text('مقادیر پیشنهادی (ارائه‌دهنده/شرکت‌کننده، نقش‌ها، ناهار دو روز) را پر کنم؟'),
            trailing: FilledButton(onPressed: () => _fillDefaults(s), child: const Text('پر کن')),
          ),
        ),
      _EventSettingsEditor(s: s),
      const SectionTitle('انواع ثبت‌نام'),
      _CodeNameList(items: s.types, onChanged: s.notify, addLabel: 'نوع جدید', kind: 'registration-types'),
      const SectionTitle('نقش‌ها'),
      _CodeNameList(items: s.roles, onChanged: s.notify, addLabel: 'نقش جدید', kind: 'roles'),
      const SectionTitle('وعده‌های پذیرایی و اینکه به چه کسانی می‌رسد'),
      for (final m in s.meals) _MealEditor(key: ObjectKey(m), meal: m),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('وعده‌ی جدید'),
          onPressed: () {
            s.meals.add(MealDef('meal${s.meals.length + 1}', '', s.event?.startDate ?? '', {}, {}));
            s.notify();
          },
        ),
      ),
      const SectionTitle('برنامه‌ی کنفرانس (روی صفحه‌ی عمومی QR نمایش داده می‌شود)'),
      for (final x in s.sessions) _SessionRow(key: ObjectKey(x), session: x),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('جلسه‌ی جدید'),
          onPressed: () {
            s.sessions.add(SessionDef(s.event?.startDate ?? '', '09:00', '', '', 'سالن اصلی', 'keynote'));
            s.notify();
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('ورود برنامه از اکسل (روز، شروع، پایان، عنوان، سالن، نوع)'),
          onPressed: () => _importSessions(s),
        ),
      ]),
      const SizedBox(height: 24),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          icon: const Icon(Icons.cloud_upload_rounded),
          onPressed: s.busy ? null : s.pushConfig,
          label: const Text('ذخیره روی سرور'),
        ),
      ),
    ]);
  }
}

/// حذف نوع یا نقشی که روی سرور است. اگر افرادی دارد، سرور 409 می‌دهد و مدیر مقصد انتقال را انتخاب می‌کند.
Future<void> _deleteServerItem(BuildContext context, AdminState s, String kind, CodeName it) async {
  final isRole = kind == 'roles';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('حذف «${it.name}»؟'),
      content: Text(isRole ? 'این نقش از رویداد حذف می‌شود.' : 'این نوع از رویداد حذف می‌شود.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
        FilledButton(style: firouzehDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await s.run('«${it.name}» حذف شد.', () async {
      try {
        await s.deleteConfigItem(kind, it.code);
      } on ApiException catch (e) {
        if (e.code != 'cd_in_use' || !context.mounted) rethrow;
        final d = ((e.data as Map?) ?? {}).cast<String, dynamic>();
        final n = ((d['attendees'] as int?) ?? 0) + ((d['deleted_attendees'] as int?) ?? 0);
        final others = (isRole ? s.roles : s.types).where((x) => x.code != it.code && (isRole ? s.serverRoleCodes : s.serverTypeCodes).contains(x.code)).toList();
        String? target = others.isEmpty ? null : others.first.code;
        final move = await showDialog<String>(
          context: context,
          builder: (c) => StatefulBuilder(
            builder: (c, setState) => AlertDialog(
              title: Text('«${it.name}» ${faDigits(n)} نفر دارد'),
              content: SizedBox(
                width: 420,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('به‌جای حذف، این افراد را به مورد دیگری منتقل کنید.'),
                  const SizedBox(height: FirouzehSize.space3),
                  if (others.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: target,
                      decoration: const InputDecoration(labelText: 'انتقال به'),
                      items: [for (final o in others) DropdownMenuItem(value: o.code, child: Text(o.name))],
                      onChanged: (v) => setState(() => target = v),
                    )
                  else if (!isRole)
                    const Notice(tone: NoticeTone.wait, text: 'نوع دیگری روی سرور نیست؛ اول یک نوع دیگر بسازید و ذخیره کنید.'),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('نه، برگرد')),
                if (isRole)
                  TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('بی‌نقش کن و حذف')),
                if (target != null)
                  FilledButton(onPressed: () => Navigator.pop(c, target), child: const Text('انتقال و حذف')),
              ],
            ),
          ),
        );
        if (move == null) {
          throw ApiException('cancel', 'حذف انجام نشد.', 0);
        }
        await s.deleteConfigItem(kind, it.code, moveTo: move.isEmpty ? null : move, clear: move.isEmpty);
      }
    });
  } catch (_) {}
}

class _CodeNameList extends StatelessWidget {
  final List<CodeName> items;
  final VoidCallback onChanged;
  final String addLabel;

  /// مسیر API حذف (registration-types یا roles).
  final String kind;
  const _CodeNameList({required this.items, required this.onChanged, required this.addLabel, required this.kind});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final onServer = kind == 'roles' ? s.serverRoleCodes : s.serverTypeCodes;
    return Column(children: [
      for (final it in items)
        Padding(
          key: ObjectKey(it),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
              width: 180,
              // کد موردی که روی سرور است عوض نمی‌شود (تغییرش مورد تازه می‌ساخت).
              child: TextFormField(
                initialValue: it.code,
                enabled: !onServer.contains(it.code),
                decoration: const InputDecoration(labelText: 'کد لاتین', isDense: true),
                textDirection: TextDirection.ltr,
                onChanged: (v) => it.code = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: it.name,
                decoration: const InputDecoration(labelText: 'نام', isDense: true),
                onChanged: (v) => it.name = v.trim(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: onServer.contains(it.code) ? 'حذف از رویداد' : 'برداشتن از فرم',
              onPressed: s.busy
                  ? null
                  : () {
                      if (onServer.contains(it.code)) {
                        _deleteServerItem(context, s, kind, it);
                      } else {
                        items.remove(it);
                        onChanged();
                      }
                    },
            ),
          ]),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(addLabel),
          onPressed: () {
            items.add(CodeName('', ''));
            onChanged();
          },
        ),
      ),
    ]);
  }
}

class _MealEditor extends StatelessWidget {
  final MealDef meal;
  const _MealEditor({super.key, required this.meal});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final children = <Widget>[
            SizedBox(
              width: 140,
              child: TextFormField(
                initialValue: meal.code,
                enabled: !s.serverMealCodes.contains(meal.code),
                decoration: const InputDecoration(labelText: 'کد', isDense: true),
                textDirection: TextDirection.ltr,
                onChanged: (v) => meal.code = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: narrow ? c.maxWidth - 140 - 12 - 4 : c.maxWidth - 140 - 180 - 24 - 64,
              child: TextFormField(
                initialValue: meal.name,
                decoration: const InputDecoration(labelText: 'نام وعده', isDense: true),
                onChanged: (v) => meal.name = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: JalaliDateField(
                label: 'روز',
                value: meal.day,
                dense: true,
                clearable: true,
                emptyText: 'همه‌ی روزها',
                dialogTitle: 'روز وعده',
                rangeStart: parseIsoDate(s.event?.startDate),
                rangeEnd: parseIsoDate(s.event?.endDate),
                onChanged: (v) {
                  meal.day = v;
                  s.notify();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: s.serverMealCodes.contains(meal.code) ? 'حذف از رویداد' : 'برداشتن از فرم',
              onPressed: s.busy
                  ? null
                  : () {
                      if (s.serverMealCodes.contains(meal.code)) {
                        _deleteMeal(context, s, meal);
                      } else {
                        s.meals.remove(meal);
                        s.notify();
                      }
                    },
            ),
            ];
            return Wrap(spacing: 0, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children);
          }),
          if (!meal.active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice(
                tone: NoticeTone.neutral,
                text: 'غیرفعال: در گوشی نیروها دیده نمی‌شود؛ تحویل‌های قبلی در گزارش می‌ماند.',
                action: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: s.busy ? null : () => s.setMealActive(meal.code, true),
                    child: const Text('فعال کردن دوباره'),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            const Text('حق دارند:  '),
            for (final t in s.types)
              FilterChip(
                label: Text(t.name),
                selected: meal.types.contains(t.code),
                onSelected: (v) {
                  v ? meal.types.add(t.code) : meal.types.remove(t.code);
                  s.notify();
                },
              ),
            for (final r in s.roles)
              FilterChip(
                avatar: const Icon(Icons.person_outline_rounded, size: 16),
                label: Text(r.name),
                selected: meal.roles.contains(r.code),
                onSelected: (v) {
                  v ? meal.roles.add(r.code) : meal.roles.remove(r.code);
                  s.notify();
                },
              ),
          ]),
        ]),
      ),
    );
  }
}

/// وعده‌ای که تحویل ثبت‌شده دارد حذف نمی‌شود؛ به‌جایش غیرفعال می‌شود.
Future<void> _deleteMeal(BuildContext context, AdminState s, MealDef meal) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('حذف «${meal.name}»؟'),
      content: const Text('این وعده و قاعده‌ی «حق دارند» آن حذف می‌شود.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
        FilledButton(style: firouzehDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  int? served;
  await s.run('«${meal.name}» حذف شد.', () async {
    try {
      await s.deleteConfigItem('meals', meal.code);
    } on ApiException catch (e) {
      if (e.code != 'cd_in_use') rethrow;
      served = ((e.data as Map?)?['served'] as int?) ?? 0;
    }
  });
  if (served == null || !context.mounted) return;
  s.message = null;
  s.notify();
  final deactivate = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('«${meal.name}» ${faDigits(served!)} تحویل ثبت‌شده دارد'),
      content: const Text('به‌جای حذف، غیرفعالش کنید: در گوشی نیروها دیده نمی‌شود و تحویل‌های قبلی در گزارش می‌ماند.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('غیرفعال کن')),
      ],
    ),
  );
  if (deactivate == true) await s.setMealActive(meal.code, false);
}

const sessionKinds = {
  'opening': 'افتتاحیه',
  'keynote': 'سخنرانی',
  'panel': 'پنل',
  'paper': 'سشن مقاله',
  'workshop': 'کارگاه',
  'break': 'پذیرایی',
};

class _SessionRow extends StatelessWidget {
  final SessionDef session;
  const _SessionRow({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.read(context);
    Widget f(String label, String init, void Function(String) on, {double? w, bool ltr = false}) {
      final field = TextFormField(
        initialValue: init,
        decoration: InputDecoration(labelText: label, isDense: true),
        textDirection: ltr ? TextDirection.ltr : null,
        onChanged: (v) => on(v.trim()),
      );
      return w == null ? Expanded(child: field) : SizedBox(width: w, child: field);
    }

    Widget day(double w) => SizedBox(
          width: w,
          child: JalaliDateField(
            label: 'روز',
            value: session.day,
            dense: true,
            dialogTitle: 'روز جلسه',
            rangeStart: parseIsoDate(s.event?.startDate),
            rangeEnd: parseIsoDate(s.event?.endDate),
            onChanged: (v) {
              session.day = v;
              s.notify();
            },
          ),
        );

    if (MediaQuery.sizeOf(context).width < 720) {
      // گوشی: عنوان یک خط کامل، بقیه زیرش.
      Widget g(String label, String init, void Function(String) on, double w, {bool ltr = false}) => SizedBox(
            width: w,
            child: TextFormField(
              initialValue: init,
              decoration: InputDecoration(labelText: label, isDense: true),
              textDirection: ltr ? TextDirection.ltr : null,
              onChanged: (v) => on(v.trim()),
            ),
          );
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              f('عنوان', session.title, (v) => session.title = v),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  s.sessions.remove(session);
                  s.notify();
                },
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              day(180),
              g('شروع', session.start, (v) => session.start = v, 80, ltr: true),
              g('پایان', session.end, (v) => session.end = v, 80, ltr: true),
              g('سالن', session.hall, (v) => session.hall = v, 140),
            ]),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        day(180),
        const SizedBox(width: 6),
        f('شروع', session.start, (v) => session.start = v, w: 70, ltr: true),
        const SizedBox(width: 6),
        f('پایان', session.end, (v) => session.end = v, w: 70, ltr: true),
        const SizedBox(width: 6),
        f('عنوان', session.title, (v) => session.title = v),
        const SizedBox(width: 6),
        f('سالن', session.hall, (v) => session.hall = v, w: 130),
        const SizedBox(width: 6),
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<String>(
            value: sessionKinds.containsKey(session.kind) ? session.kind : null,
            isDense: true,
            decoration: const InputDecoration(labelText: 'نوع', isDense: true),
            items: [for (final e in sessionKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => session.kind = v ?? '',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () {
            s.sessions.remove(session);
            s.notify();
          },
        ),
      ]),
    );
  }
}


/// گزینه‌ی انتخابی بزرگ با عنوان و توضیح (برای تنظیم‌هایی که پیامد دارند).
class _Choice extends StatelessWidget {
  final bool selected;
  final String title;
  final String text;
  final VoidCallback onTap;
  const _Choice({required this.selected, required this.title, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FirouzehSize.space2),
      child: Material(
        color: selected ? x.stampSoft : x.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FirouzehSize.radiusSm),
          side: BorderSide(color: selected ? x.stamp : x.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(FirouzehSize.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FirouzehSize.space3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? x.stamp : x.lineStrong, size: 20),
              const SizedBox(width: FirouzehSize.space3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  Text(text, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// IdentifyMode، QrBehavior و خط سازنده در صفحه‌ی عمومی.
class _EventSettingsEditor extends StatelessWidget {
  final AdminState s;
  const _EventSettingsEditor({required this.s});

  @override
  Widget build(BuildContext context) {
    final st = s.settings;
    final locked = s.event?.locked ?? false;
    void set(void Function() f) {
      f();
      s.notify();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('شناسایی در روز اجرا'),
      const Hint('اسکن امکان است، نه شرط. اپ نیروها خودش را با این انتخاب تطبیق می‌دهد و هر کار همیشه با جستجوی نام هم شدنی است.'),
      const SizedBox(height: FirouzehSize.space2),
      _Choice(
        selected: st.identifyMode == 'scan',
        title: 'کارت QR، با اسکن',
        text: 'پذیرش با جستجوی نام یا اسکن؛ پذیرایی با دوربین گوشی یا بارکدخوان، و جستجوی نام.',
        onTap: () => set(() => st.identifyMode = 'scan'),
      ),
      _Choice(
        selected: st.identifyMode == 'card',
        title: 'کارت، بدون اسکن',
        text: 'دکمه‌ی اسکن و دوربین نمایش داده نمی‌شود؛ پذیرش با نام یا شماره‌ی کارت، پذیرایی با جستجوی نام.',
        onTap: () => set(() => st.identifyMode = 'card'),
      ),
      _Choice(
        selected: st.identifyMode == 'none',
        title: 'بدون کارت',
        text: 'همه‌چیز با جستجوی نام. ثبت‌نام در محل کارت نمی‌خواهد و مرحله‌ی «کارت‌ها» پنهان می‌شود.',
        onTap: () => set(() => st.identifyMode = 'none'),
      ),
      if (locked && st.identifyMode == 'none')
        const Padding(
          padding: EdgeInsets.only(top: FirouzehSize.space1),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'کارت‌ها چاپ شده‌اند. با «بدون کارت»، شماره‌ی کارت دیگر در اپ نیروها نمایش داده نمی‌شود.',
          ),
        ),
      if (st.usesCards) ...[
        const SectionTitle('QR روی کارت برای دیگران چه کند؟'),
        const Hint('اپ نیروها در هر سه حالت فرد را می‌شناسد. این انتخاب فقط برای گوشی‌های دیگر (شرکت‌کننده، داور، اسپانسر) است.'),
        const SizedBox(height: FirouzehSize.space2),
        _Choice(
          selected: st.qrBehavior == 'person',
          title: 'صفحه‌ی فرد (پیش‌فرض)',
          text: 'نام، نقش، سازمان و برنامه. بعد از چاپ هم قابل تغییر است.',
          onTap: () => set(() => st.qrBehavior = 'person'),
        ),
        _Choice(
          selected: st.qrBehavior == 'redirect',
          title: 'انتقال به یک آدرس',
          text: 'مستقیم یک آدرس باز می‌شود، مثلاً سایت یا برنامه‌ی رویداد. بعد از چاپ هم قابل تغییر است.',
          onTap: () => set(() => st.qrBehavior = 'redirect'),
        ),
        if (st.qrBehavior == 'redirect')
          Padding(
            padding: const EdgeInsets.only(bottom: FirouzehSize.space2),
            child: TextFormField(
              initialValue: st.redirectUrl,
              decoration: const InputDecoration(
                labelText: 'آدرس مقصد',
                helperText: 'اگر خالی یا خراب باشد، صفحه‌ی فرد نمایش داده می‌شود.',
              ),
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              onChanged: (v) => st.redirectUrl = v.trim(),
            ),
          ),
        _Choice(
          selected: st.qrBehavior == 'vcard',
          title: 'کارت ویزیت (vCard)',
          text: 'پنجره‌ی «افزودن به مخاطبین» گوشی، بدون اینترنت. با ساخت PDF قفل می‌شود و برگشت ندارد.',
          onTap: locked ? () {} : () => set(() => st.qrBehavior = 'vcard'),
        ),
        if (st.qrBehavior == 'vcard')
          const Padding(
            padding: EdgeInsets.only(bottom: FirouzehSize.space2),
            child: Notice(
              tone: NoticeTone.wait,
              text: 'اطلاعات تماس روی کارت چاپ می‌شود و هر کسی با دوربین می‌خواندش؛ کارت گم‌شده هم دوباره صادر نمی‌شود. '
                  'QR کارت ویزیت پرتراکم‌تر است و دست‌کم ۳۰ میلی‌متر چاپ می‌شود.',
            ),
          ),
        if (st.qrBehavior != 'redirect') ...[
          const SizedBox(height: FirouzehSize.space2),
          Text('اطلاعات تماسی که به اشتراک گذاشته می‌شود', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: FirouzehSize.space2),
          Wrap(spacing: FirouzehSize.space2, runSpacing: FirouzehSize.space2, children: [
            for (final (label, value, setter) in <(String, bool, void Function(bool))>[
              ('نام و عنوان', st.shareName, (v) => st.shareName = v),
              ('سازمان', st.shareOrg, (v) => st.shareOrg = v),
              ('ایمیل', st.shareEmail, (v) => st.shareEmail = v),
              ('موبایل', st.shareMobile, (v) => st.shareMobile = v),
              ('کشور', st.shareCountry, (v) => st.shareCountry = v),
            ])
              FilterChip(label: Text(label), selected: value, onSelected: (v) => set(() => setter(v))),
          ]),
        ],
      ],
      const SectionTitle('روز اجرا'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.dailyAttendance,
        onChanged: (v) => set(() => st.dailyAttendance = v),
        title: const Text('حضور روزانه'),
        subtitle: const Text('پذیرش هر روز جدا ثبت می‌شود؛ «قبلاً پذیرش شده» فقط همان روز را می‌بیند. برای رویداد چندروزه.'),
      ),
      const SectionTitle('صفحه‌ی عمومی'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.showMakerCredit,
        onChanged: (v) => set(() => st.showMakerCredit = v),
        title: const Text('خط «ساخته‌شده با رویدادیار · نگاه جدید» زیر برنامه'),
      ),
      const Notice(
        tone: NoticeTone.info,
        text: 'این تنظیم‌ها با «ذخیره روی سرور» به گوشی‌ها و صفحه‌ی عمومی می‌رسد.',
      ),
    ]);
  }
}
