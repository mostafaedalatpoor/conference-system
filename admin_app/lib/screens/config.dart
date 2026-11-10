import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../excel_import.dart';
import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
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
      // ستون‌ها به این ترتیب: روز (میلادی)، شروع، پایان، عنوان، سالن، نوع
      s.sessions = [
        for (final row in t.rows)
          if (row.length >= 4 && row[0].trim().isNotEmpty && row[3].trim().isNotEmpty)
            SessionDef(row[0].trim(), row[1].trim(), row[2].trim(), row[3].trim(), row.length > 4 ? row[4].trim() : '',
                row.length > 5 ? row[5].trim() : ''),
      ];
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
      _CodeNameList(items: s.types, onChanged: s.notify, addLabel: 'نوع جدید'),
      const SectionTitle('نقش‌ها'),
      _CodeNameList(items: s.roles, onChanged: s.notify, addLabel: 'نقش جدید'),
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

class _CodeNameList extends StatelessWidget {
  final List<CodeName> items;
  final VoidCallback onChanged;
  final String addLabel;
  const _CodeNameList({required this.items, required this.onChanged, required this.addLabel});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final it in items)
        Padding(
          key: ObjectKey(it),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
              width: 180,
              child: TextFormField(
                initialValue: it.code,
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
              tooltip: 'حذف از این فرم (روی سرور حذف نمی‌شود)',
              onPressed: () {
                items.remove(it);
                onChanged();
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
                decoration: const InputDecoration(labelText: 'کد', isDense: true),
                textDirection: TextDirection.ltr,
                onChanged: (v) => meal.code = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: narrow ? c.maxWidth - 140 - 12 - 4 : c.maxWidth - 140 - 150 - 24 - 64 - 112,
              child: TextFormField(
                initialValue: meal.name,
                decoration: const InputDecoration(labelText: 'نام وعده', isDense: true),
                onChanged: (v) => meal.name = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: TextFormField(
                initialValue: meal.day,
                decoration: const InputDecoration(labelText: 'روز (میلادی)', isDense: true),
                textDirection: TextDirection.ltr,
                onChanged: (v) => meal.day = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: TextFormField(
                initialValue: faDigits(meal.time),
                decoration: const InputDecoration(labelText: 'ساعت (اختیاری)', hintText: '۱۳:۰۰', isDense: true),
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.datetime,
                onChanged: (v) => meal.time = latinDigits(v.trim()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                s.meals.remove(meal);
                s.notify();
              },
            ),
            ];
            return Wrap(spacing: 0, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children);
          }),
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
              g('روز', session.day, (v) => session.day = v, 120, ltr: true),
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
        f('روز', session.day, (v) => session.day = v, w: 110, ltr: true),
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
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DaftarSize.space2),
      child: Material(
        color: selected ? x.stampSoft : x.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
          side: BorderSide(color: selected ? x.stamp : x.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(DaftarSize.space3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? x.stamp : x.lineStrong, size: 20),
              const SizedBox(width: DaftarSize.space3),
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
      const SizedBox(height: DaftarSize.space2),
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
          padding: EdgeInsets.only(top: DaftarSize.space1),
          child: Notice(
            tone: NoticeTone.wait,
            text: 'کارت‌ها چاپ شده‌اند. با «بدون کارت»، شماره‌ی کارت دیگر در اپ نیروها نمایش داده نمی‌شود.',
          ),
        ),
      if (st.usesCards) ...[
        const SectionTitle('QR روی کارت برای دیگران چه کند؟'),
        const Hint('اپ نیروها در هر سه حالت فرد را می‌شناسد. این انتخاب فقط برای گوشی‌های دیگر (شرکت‌کننده، داور، اسپانسر) است.'),
        const SizedBox(height: DaftarSize.space2),
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
            padding: const EdgeInsets.only(bottom: DaftarSize.space2),
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
            padding: EdgeInsets.only(bottom: DaftarSize.space2),
            child: Notice(
              tone: NoticeTone.wait,
              text: 'اطلاعات تماس روی کارت چاپ می‌شود و هر کسی با دوربین می‌خواندش؛ کارت گم‌شده هم دوباره صادر نمی‌شود. '
                  'QR کارت ویزیت پرتراکم‌تر است و دست‌کم ۳۰ میلی‌متر چاپ می‌شود.',
            ),
          ),
        if (st.qrBehavior != 'redirect') ...[
          const SizedBox(height: DaftarSize.space2),
          Text('اطلاعات تماسی که به اشتراک گذاشته می‌شود', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: DaftarSize.space2),
          Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
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
