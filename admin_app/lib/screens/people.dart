import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
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
    for (final p in s.sortedPeople) {
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
        child: TextField(
          controller: _q,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'نام، موبایل یا شماره‌ی کارت',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      Divider(color: x.line),
      Expanded(
        child: _q.text.trim().isEmpty
            ? SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.people_alt_rounded,
                  title: '${faDigits(s.people.length)} نفر در لیست',
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
    return switch (kind) {
      'checkin' => 'پذیرش شد',
      'checkin_undo' => 'پذیرش لغو شد',
      'meal_served' => meal.isEmpty ? 'وعده تحویل شد' : '$meal تحویل شد',
      'walkin_register' => 'ثبت‌نام در محل',
      _ => '${e['label'] ?? kind}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final p = widget.person;
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
      appBar: AppBar(title: Text(p.displayName, overflow: TextOverflow.ellipsis)),
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
          ]),
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
              return Column(children: [
                for (final e in events)
                  Container(
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
                            ].join('، '),
                            style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted),
                          ),
                        ]),
                      ),
                      if (DateTime.tryParse('${e['device_time']}') != null)
                        Text(hm(DateTime.parse('${e['device_time']}')),
                            style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted, fontFeatures: tabularFigures)),
                    ]),
                  ),
              ]);
            },
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
