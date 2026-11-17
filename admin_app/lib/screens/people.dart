import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import 'person_edit.dart';
import 'report.dart';

/// تب «افراد» در اپ مدیریت: جستجو و تاریخچه‌ی هر نفر، برای جواب‌دادن در همان لحظه.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Person> _search(AdminState s) {
    final q = normalizeText(_q.text);
    if (q.isEmpty) return const [];
    final words = q.split(' ');
    final digits = normalizeMobile(_q.text);
    final out = <Person>[];
    // همه‌ی افراد، با ثبت‌نام در محل و غیرفعال‌ها (sortedPeople فقط کارت‌دارهای فعال اکسل است).
    final all = s.people.values.toList()
      ..sort((a, b) {
        final c = normalizeText(a.lastName).compareTo(normalizeText(b.lastName));
        return c != 0 ? c : normalizeText(a.firstName).compareTo(normalizeText(b.firstName));
      });
    for (final p in all) {
      final key = normalizeText('${p.firstName} ${p.lastName} ${p.mobile} ${p.email} ${p.organization} ${p.serial ?? ''}');
      if (words.every(key.contains) || (digits.length >= 4 && normalizeMobile(p.mobile).contains(digits))) out.add(p);
      if (out.length >= 60) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final results = _search(s);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(DaftarSize.space4),
        child: Row(children: [
          Expanded(child: TextField(
          controller: _q,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'نام، موبایل یا شماره‌ی کارت',
          ),
          onChanged: (_) => setState(() {}),
        )),
          const SizedBox(width: DaftarSize.space2),
          IconButton.filledTonal(
            tooltip: 'افزودن فرد',
            icon: const Icon(Icons.person_add_rounded),
            onPressed: s.event?.archived == true ? null : () => showPersonEditor(context),
          ),
        ]),
      ),
      Divider(color: x.line),
      Expanded(
        child: _q.text.trim().isEmpty
            ? SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.people_alt_rounded,
                  title: '${faDigits(s.people.values.where((p) => p.isActive).length)} نفر در لیست',
                  hint: 'نام کسی را بنویسید تا ببینید چه گرفته و کی پذیرش شده.',
                ),
              )
            : results.isEmpty
                ? SingleChildScrollView(
                    child: EmptyState(icon: Icons.person_search_rounded, title: 'کسی با «${_q.text.trim()}» پیدا نشد'))
                : ListView(children: [
                    for (final p in results)
                      Material(
                        color: x.surface,
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonPage(person: p))),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: DaftarSize.tapXl),
                            padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space4, vertical: DaftarSize.space2),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.displayName, style: theme.textTheme.titleMedium),
                                  Text(
                                    [s.typeName(p.typeCode), s.roleName(p.roleCode), p.organization]
                                        .where((e) => e.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted),
                                  ),
                                ]),
                              ),
                              if (!p.isActive) const DaftarTag('غیرفعال', kind: TagKind.outline),
                              const SizedBox(width: DaftarSize.space2),
                              if (p.serial != null && s.settings.usesCards)
                                Text('کارت ${faDigits(p.serial!)}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted, fontFeatures: tabularFigures)),
                              const SizedBox(width: DaftarSize.space2),
                              Icon(Icons.chevron_left_rounded, color: x.inkMuted),
                            ]),
                          ),
                        ),
                      ),
                  ]),
      ),
    ]);
  }
}

/// مشخصات و تاریخچه‌ی یک نفر (PersonTimeline).
class PersonPage extends StatefulWidget {
  final Person person;
  const PersonPage({super.key, required this.person});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  late Future<List<Map<String, dynamic>>> _timeline;
  DateTime _at = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    _at = DateTime.now();
    _timeline = StateScope.read(context).loadTimeline(widget.person.id);
  }

  String _label(Map<String, dynamic> e) {
    final kind = '${e['kind'] ?? ''}';
    final meal = '${e['meal_name'] ?? ''}'.trim();
    final reason = '${e['reason'] ?? ''}'.trim();
    return switch (kind) {
      'checkin' => 'پذیرش شد',
      'checkin_undo' => reason.isEmpty ? 'پذیرش لغو شد' : 'پذیرش لغو شد · دلیل: $reason',
      'meal_undo' => '${meal.isEmpty ? 'تحویل وعده' : 'تحویل $meal'} برگشت${reason.isEmpty ? '' : ' · دلیل: $reason'}',
      'meal_served' => meal.isEmpty ? 'وعده تحویل شد' : '$meal تحویل شد',
      'walkin_register' => 'ثبت‌نام در محل',
      _ => '${e['label'] ?? kind}',
    };
  }

  /// «کارت گم شد» (حالت ۱۳ طراحی): کارت رزرو بده، یا کارت تازه با همان شماره. کارت قبلی باطل می‌شود.
  Future<void> _lostCard(AdminState s, Person p) async {
    final free = s.reserveCards.where((r) => !r.used).length;
    var mode = free > 0 ? 'reserve' : 'new';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('کارت ${p.displayName} گم شد'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (value, title, sub, enabled) in [
              ('reserve', 'کارت رزرو بده', free == 0 ? 'کارت رزرو آزاد نمانده.' : '${faDigits(free)} کارت رزرو آزاد؛ همین حالا تحویل بدهید.', free > 0),
              ('new', 'کارت تازه با همان شماره', 'در «کارت‌ها ← چاپ‌نشده‌ها» چاپ می‌شود.', true),
            ])
              ListTile(
                enabled: enabled,
                contentPadding: EdgeInsets.zero,
                leading: Icon(mode == value ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                title: Text(title),
                subtitle: Text(sub),
                onTap: () => setState(() => mode = value),
              ),
            const SizedBox(height: DaftarSize.space2),
            const Notice(tone: NoticeTone.wait, text: 'کارت قبلی باطل می‌شود: اسکنش در گوشی نیروها رد می‌شود و صفحه‌ی شخصی‌اش باز نمی‌شود.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ادامه')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await s.replaceCard(p.id, mode);
    if (mounted) setState(() {});
  }

  Future<void> _merge(AdminState s, Person keep, Person from) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('ادغام «${from.displayName}» در «${keep.displayName}»؟'),
        content: Text('پذیرش، وعده‌ها و کارت «${from.displayName}» به این نفر منتقل می‌شود، '
            'جاهای خالی اطلاعات این نفر از او پر می‌شود و «${from.displayName}» از فهرست حذف می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ادغام')),
        ],
      ),
    );
    if (ok != true) return;
    if (await s.mergePeople(keep.id, from.id) && mounted) setState(_load);
  }

  Future<void> _undoMeal(AdminState s, Person p, MealDef m) async {
    const reasons = ['اشتباه زدم', 'ثبت تکراری', 'دیگر'];
    var reason = reasons.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('لغو تحویل ${m.name} به ${p.displayName}؟'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('در گزارش ثبت می‌شود و گوشی‌ها با همگام‌سازی بعدی می‌بینند.'),
            const SizedBox(height: DaftarSize.space3),
            Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
              for (final r in reasons)
                ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => setState(() => reason = r)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
            FilledButton(style: daftarDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('لغو تحویل')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await s.undoMeal(p.id, m.code, reason: reason);
    if (mounted) setState(_load);
  }

  Future<void> _undo(AdminState s, Person p) async {
    const reasons = ['اشتباه زدم', 'انصراف داد', 'ثبت تکراری', 'دیگر'];
    var reason = reasons.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('لغو پذیرش ${p.displayName}؟'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ثبت وعده‌های او می‌ماند. می‌توانید دوباره پذیرش کنید.'),
            const SizedBox(height: DaftarSize.space3),
            const Text('دلیل لغو'),
            const SizedBox(height: DaftarSize.space2),
            Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
              for (final r in reasons)
                ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => setState(() => reason = r)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
            FilledButton(style: daftarDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('لغو پذیرش')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await s.undoCheckin(p.id, reason: reason);
    if (mounted) setState(_load);
  }

  /// حذف از رویداد. اگر پذیرش یا وعده دارد، می‌پرسد «فقط غیرفعال کن» یا «حذف کن» (حالت ۱۰ طراحی).
  Future<void> _delete(AdminState s, Person p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف ${p.displayName} از رویداد؟'),
        content: const Text('از فهرست افراد، گوشی نیروها و گزارش کنار می‌رود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
          FilledButton(style: daftarDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('حذف کن')),
        ],
      ),
    );
    if (ok != true) return;
    final activity = await s.deletePerson(p.id);
    if (!mounted) return;
    if (activity == null) {
      if (!s.messageIsError) Navigator.of(context).pop();
      return;
    }
    final checkins = (activity['checkins'] as int?) ?? 0;
    final meals = (activity['meals'] as int?) ?? 0;
    final what = [
      if (checkins > 0) 'پذیرش',
      if (meals > 0) '${faDigits(meals)} وعده‌ی',
    ].join(' و ');
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف ${p.displayName} از رویداد؟'),
        content: Text('$what او از گزارش حذف می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('نه، برگرد')),
          OutlinedButton(onPressed: () => Navigator.pop(c, 'inactive'), child: const Text('فقط غیرفعال کن')),
          FilledButton(style: daftarDangerStyle(c), onPressed: () => Navigator.pop(c, 'delete'), child: const Text('حذف کن')),
        ],
      ),
    );
    if (choice == 'inactive') {
      await s.setPersonStatus(p.id, 'inactive');
    } else if (choice == 'delete') {
      await s.deletePerson(p.id, force: true);
      if (mounted && !s.messageIsError) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final p = s.people[widget.person.id] ?? widget.person;
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final details = <(String, String, bool)>[
      ('سازمان', p.organization, false),
      ('موبایل', p.mobile, true),
      ('ایمیل', p.email, true),
      if (s.settings.usesCards) ('شماره‌ی کارت', p.serial == null ? '' : faDigits(p.serial!), false),
    ].where((d) => d.$2.isNotEmpty);
    final flagged = ((s.report?['flagged'] as List?) ?? const [])
        .cast<Map>()
        .where((f) => '${f['name'] ?? ''}'.trim() == p.fullName || '${f['name'] ?? ''}'.trim() == p.displayName)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(p.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit_rounded),
            label: const Text('ویرایش'),
            onPressed: s.event?.archived == true ? null : () => showPersonEditor(context, person: p),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_load);
          await _timeline.catchError((_) => <Map<String, dynamic>>[]);
        },
        child: ListView(padding: const EdgeInsets.all(DaftarSize.space4), children: [
          Text(p.displayName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: DaftarSize.space2),
          Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
            for (final t in [s.typeName(p.typeCode), s.roleName(p.roleCode)].where((e) => e.isNotEmpty)) DaftarTag(t),
            if (p.source == 'walkin') const DaftarTag('ثبت‌نام در محل', kind: TagKind.outline),
            if (!p.isActive) const DaftarTag('غیرفعال', kind: TagKind.outline),
          ]),
          if (!p.isActive)
            Padding(
              padding: const EdgeInsets.only(top: DaftarSize.space3),
              child: Notice(
                tone: NoticeTone.neutral,
                text: 'غیرفعال: در گوشی نیروها و گزارش دیده نمی‌شود. تاریخچه‌اش می‌ماند.',
                action: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: s.busy ? null : () => s.setPersonStatus(p.id, 'active'),
                    child: const Text('فعال کردن دوباره'),
                  ),
                ),
              ),
            ),
          const SizedBox(height: DaftarSize.space3),
          for (final d in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 100, child: Text(d.$1, style: theme.textTheme.bodyMedium?.copyWith(color: x.inkMuted))),
                Expanded(
                  child: SelectableText(d.$2, textDirection: d.$3 ? TextDirection.ltr : null, textAlign: TextAlign.start),
                ),
              ]),
            ),
          if (s.settings.usesCards && p.token != null)
            Padding(
              padding: const EdgeInsets.only(top: DaftarSize.space3),
              child: Row(children: [
                Icon(Icons.style_rounded, size: 20, color: x.stamp),
                const SizedBox(width: DaftarSize.space2),
                Expanded(
                  child: Text([
                    'کارت ${faDigits(p.serial ?? '')}',
                    p.printed ? 'چاپ شده${p.printCount > 1 ? ' ×${faDigits(p.printCount)}' : ''}' : 'چاپ‌نشده',
                  ].join(' · ')),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: x.stop, side: BorderSide(color: x.stop, width: 1.5)),
                  onPressed: s.busy || s.event?.archived == true ? null : () => _lostCard(s, p),
                  child: const Text('کارت گم شد…'),
                ),
              ]),
            ),
          for (final d in s.possibleDuplicatesOf(p))
            Padding(
              padding: const EdgeInsets.only(top: DaftarSize.space3),
              child: Notice(
                tone: NoticeTone.wait,
                title: 'احتمالاً همان «${d.displayName}» است',
                text: normalizeMobile(d.mobile).isNotEmpty && normalizeMobile(d.mobile) == normalizeMobile(p.mobile)
                    ? 'موبایل یکسان است.'
                    : 'ایمیل یکسان است.',
                action: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(onPressed: s.busy ? null : () => _merge(s, p, d), child: const Text('ادغام…')),
                ),
              ),
            ),
          if (s.meals.any((m) => m.id != null)) ...[
            const SectionTitle('پذیرایی'),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _timeline,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done || snap.hasError) return const SizedBox.shrink();
                final counts = mealCountsFromTimeline(snap.data!);
                return Column(children: [
                  for (final m in s.meals.where((m) => m.id != null && (m.active || (counts[m.id] ?? 0) > 0)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: DaftarSize.space1),
                      child: Row(children: [
                        Icon(
                          (counts[m.id] ?? 0) > 0 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: (counts[m.id] ?? 0) > 0 ? x.go : x.line,
                        ),
                        const SizedBox(width: DaftarSize.space2),
                        Expanded(child: Text(m.name)),
                        if ((counts[m.id] ?? 0) > 1)
                          Text('${faDigits(counts[m.id]!)} بار', style: theme.textTheme.bodySmall?.copyWith(color: x.wait)),
                        if ((counts[m.id] ?? 0) > 0)
                          TextButton(
                            onPressed: s.busy || s.event?.archived == true ? null : () => _undoMeal(s, p, m),
                            child: const Text('لغو تحویل…'),
                          )
                        else
                          Text('هنوز نه', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                      ]),
                    ),
                ]);
              },
            ),
          ],
          const SectionTitle('تاریخچه'),
          Text('داده‌ی سرور تا ${hm(_at)}', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
          const SizedBox(height: DaftarSize.space2),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _timeline,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(DaftarSize.space4), child: LinearProgressIndicator());
              }
              if (snap.hasError) {
                return const Notice(
                  tone: NoticeTone.neutral,
                  text: 'تاریخچه‌ی این نفر از سرور در دسترس نیست. افزونه‌ی سایت باید به‌روز شود.',
                );
              }
              final events = [...snap.data!]
                ..sort((a, b) => '${a['device_time']}'.compareTo('${b['device_time']}'));
              if (events.isEmpty) return const Hint('هنوز کاری برای این نفر ثبت نشده.');
              // چندروزه: سرفصل «روز ۱»، «روز ۲» بین رخدادها.
              final multiDay = events.map((e) => e['day']).whereType<String>().toSet().length > 1;
              // سرفصل وقتی روز رخداد با رخداد قبلی فرق دارد.
              bool header(int i) =>
                  multiDay && events[i]['day'] is String && (i == 0 || events[i]['day'] != events[i - 1]['day']);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < events.length; i++) ...[
                  if (header(i))
                    Padding(
                      padding: const EdgeInsets.only(top: DaftarSize.space3),
                      child: Text(s.dayName(events[i]['day'] as String),
                          style: theme.textTheme.labelLarge?.copyWith(color: x.stamp, fontWeight: FontWeight.w800)),
                    ),
                  Builder(builder: (context) {
                    final e = events[i];
                    return Container(
                    padding: const EdgeInsets.symmetric(vertical: DaftarSize.space2),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(
                        e['flag'] != null ? Icons.warning_rounded : Icons.check_circle_rounded,
                        size: 20,
                        color: e['flag'] != null ? x.wait : x.go,
                      ),
                      const SizedBox(width: DaftarSize.space2),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_label(e), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            [
                              if (e['flag_label'] != null) '${e['flag_label']}',
                              if ('${e['device_label'] ?? ''}'.isNotEmpty) '${e['device_label']}',
                              if ('${e['staff'] ?? ''}'.isNotEmpty) '${e['staff']}',
                              if (e['kind'] == 'checkin_undo' && '${e['actor'] ?? ''}'.isNotEmpty && e['actor'] != e['staff'])
                                '${e['actor']}',
                            ].join('، '),
                            style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted),
                          ),
                        ]),
                      ),
                      if (DateTime.tryParse('${e['device_time']}') != null)
                        Text(hm(DateTime.parse('${e['device_time']}')),
                            style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted, fontFeatures: tabularFigures)),
                    ]),
                  );
                  }),
                ],
              ]);
            },
          ),
          const SizedBox(height: DaftarSize.space5),
          // لغو پذیرش فقط برای کسی که الان پذیرش‌شده است (سرور هم همین را می‌سنجد).
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _timeline,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done || snap.hasError) return const SizedBox.shrink();
              if (!isCheckedInFromTimeline(snap.data!, day: s.settings.dailyAttendance ? todayIso() : null)) {
                return Notice(tone: NoticeTone.neutral, text: '${p.displayName} هنوز پذیرش نشده.');
              }
              return OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(DaftarSize.tapMin),
                  foregroundColor: x.stop,
                  side: BorderSide(color: x.stop, width: 1.5),
                ),
                onPressed: s.busy ? null : () => _undo(s, p),
                child: const Text('لغو پذیرش…'),
              );
            },
          ),
          const SizedBox(height: DaftarSize.space3),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(DaftarSize.tapMin),
              foregroundColor: x.stop,
              side: BorderSide(color: x.stop, width: 1.5),
            ),
            icon: const Icon(Icons.delete_rounded),
            onPressed: s.busy ? null : () => _delete(s, p),
            label: const Text('حذف از رویداد…'),
          ),
          const SizedBox(height: DaftarSize.space1),
          Text(
            'اگر پذیرش یا وعده دارد، می‌توانید به‌جای حذف غیرفعالش کنید.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted),
          ),
          if (flagged.isNotEmpty) ...[
            const SectionTitle('موارد مشکوک در گزارش'),
            for (final f in flagged)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(Icons.warning_rounded, size: 18, color: x.wait),
                  const SizedBox(width: DaftarSize.space2),
                  Expanded(child: Text('${f['flag_label']}')),
                  if (DateTime.tryParse('${f['device_time']}') != null)
                    Text(relativeTime(DateTime.parse('${f['device_time']}')),
                        style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}
