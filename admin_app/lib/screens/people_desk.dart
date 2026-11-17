import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/firouzeh.dart';
import '../theme/widgets.dart';
import 'people.dart';
import 'person_edit.dart';

/// فیلترهای تب افراد ویندوز (طراحی ۰۲-People).
enum PeopleFilter { all, arrived, notArrived, incomplete, inactive }

/// آیا ردیف خروجی [row] از فرد [p] با فیلتر می‌خواند؟ (تابع خالص، با آزمون)
bool peopleFilterMatch(PeopleFilter f, Person p, Map<String, dynamic>? row) => switch (f) {
      PeopleFilter.all => p.isActive,
      PeopleFilter.arrived => p.isActive && row?['checked_in'] == true,
      PeopleFilter.notArrived => p.isActive && row?['checked_in'] != true,
      PeopleFilter.incomplete => p.isActive && p.mobile.isEmpty && p.email.isEmpty,
      PeopleFilter.inactive => !p.isActive,
    };

/// تب «افراد» اپ ویندوز: جدول با جستجو و فیلتر، صفحه‌ی فرد در کنار، و کار گروهی (غیرفعال، حذف).
class PeopleDeskScreen extends StatefulWidget {
  const PeopleDeskScreen({super.key});

  @override
  State<PeopleDeskScreen> createState() => _PeopleDeskScreenState();
}

class _PeopleDeskScreenState extends State<PeopleDeskScreen> {
  final _q = TextEditingController();
  PeopleFilter _filter = PeopleFilter.all;
  Map<String, Map<String, dynamic>> _rows = {};
  List<Map<String, dynamic>> _meals = [];
  final Set<String> _checked = {};
  String? _open;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await StateScope.read(context).exportRows(includeInactive: true);
      _rows = {
        for (final r in ((d['rows'] as List?) ?? const []).cast<Map>()) '${r['id']}': r.cast<String, dynamic>(),
      };
      _meals = ((d['meals'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      // افزونه‌ی قدیمی مسیر export ندارد؛ جدول بدون وضعیت پذیرش نشان داده می‌شود.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _bulk(AdminState s, String status) async {
    final ids = _checked.toList();
    if (status == 'deleted') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('حذف ${faDigits(ids.length)} نفر از رویداد؟'),
          content: const Text('کسانی که پذیرش یا وعده دارند حذف نمی‌شوند و می‌مانند؛ می‌توانید غیرفعالشان کنید.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
            FilledButton(style: firouzehDangerStyle(c), onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final r = await s.setPeopleStatusBulk(ids, status);
    if (r == null || !mounted) return;
    s.message = '${faDigits(r.$1)} نفر ${status == 'deleted' ? 'حذف' : (status == 'inactive' ? 'غیرفعال' : 'فعال')} شد.'
        '${r.$2 > 0 ? ' ${faDigits(r.$2)} نفر چون پذیرش یا وعده دارند ماندند.' : ''}';
    s.notify();
    setState(_checked.clear);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    final all = s.people.values.toList()
      ..sort((a, b) {
        final c = normalizeText(a.lastName).compareTo(normalizeText(b.lastName));
        return c != 0 ? c : normalizeText(a.firstName).compareTo(normalizeText(b.firstName));
      });
    final q = normalizeText(_q.text);
    bool search(Person p) =>
        q.isEmpty ||
        q.split(' ').every(normalizeText('${p.displayName} ${p.mobile} ${p.email} ${p.organization} ${p.serial ?? ''}').contains);
    int count(PeopleFilter f) => all.where((p) => peopleFilterMatch(f, p, _rows[p.id])).length;
    final list = all.where((p) => peopleFilterMatch(_filter, p, _rows[p.id]) && search(p)).toList();
    final open = _open == null ? null : s.people[_open];
    final arrived = count(PeopleFilter.arrived);

    Widget status(Person p) {
      final r = _rows[p.id];
      final (text, fg, bg) = !p.isActive
          ? ('غیرفعال', x.inkMuted, x.sunken)
          : r?['checked_in'] == true
              ? (DateTime.tryParse('${r!['last_checkin']}') == null ? 'آمده' : hm(DateTime.parse('${r['last_checkin']}')), x.go, x.goSoft)
              : (p.mobile.isEmpty && p.email.isEmpty ? 'ناقص' : 'هنوز نیامده', x.inkMuted, x.sunken);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(FirouzehSize.radiusPill)),
        child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      );
    }

    Widget meals(Person p) {
      final m = (_rows[p.id]?['meals'] as Map?) ?? const {};
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (final meal in _meals)
          Tooltip(
            message: '${meal['name']}',
            child: Icon(Icons.restaurant_rounded,
                size: 18, color: (m[meal['code']] ?? 0) as int > 1 ? x.stop : ((m[meal['code']] ?? 0) as int > 0 ? x.go : x.line)),
          ),
      ]);
    }

    final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('${faDigits(count(PeopleFilter.all))} نفر · ${faDigits(arrived)} پذیرش‌شده',
              style: theme.textTheme.bodyMedium?.copyWith(color: x.inkMuted)),
        ),
        IconButton(tooltip: 'به‌روزرسانی', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        FilledButton.icon(
          onPressed: s.event?.archived == true ? null : () async {
            if (await showPersonEditor(context)) await _load();
          },
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('افزودن فرد'),
        ),
      ]),
      const SizedBox(height: FirouzehSize.space3),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'نام، موبایل، شماره‌ی کارت یا سازمان'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
      const SizedBox(height: FirouzehSize.space2),
      Wrap(spacing: FirouzehSize.space2, runSpacing: FirouzehSize.space2, children: [
        for (final (f, label) in const [
          (PeopleFilter.all, 'همه'),
          (PeopleFilter.arrived, 'آمده'),
          (PeopleFilter.notArrived, 'نیامده'),
          (PeopleFilter.incomplete, 'ناقص'),
          (PeopleFilter.inactive, 'غیرفعال'),
        ])
          ChoiceChip(label: Text('$label ${faDigits(count(f))}'), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
      ]),
      if (_loading) const LinearProgressIndicator(),
      const SizedBox(height: FirouzehSize.space2),
      Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: list.isEmpty
              ? const EmptyState(icon: Icons.person_search_rounded, title: 'کسی پیدا نشد')
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return Material(
                      color: p.id == _open ? x.stampSoft : x.surface,
                      child: InkWell(
                        onTap: () => setState(() => _open = p.id),
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: FirouzehSize.space3),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
                          child: Row(children: [
                            Checkbox(
                              value: _checked.contains(p.id),
                              onChanged: (v) => setState(() => v == true ? _checked.add(p.id) : _checked.remove(p.id)),
                            ),
                            Expanded(flex: 3, child: Text(p.displayName, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                            Expanded(flex: 2, child: Text([s.typeName(p.typeCode), s.roleName(p.roleCode)].where((e) => e.isNotEmpty).join(' · '), overflow: TextOverflow.ellipsis)),
                            Expanded(flex: 2, child: Text(p.organization, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: 110, child: Align(alignment: AlignmentDirectional.centerStart, child: status(p))),
                            SizedBox(width: 90, child: meals(p)),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      if (_checked.isNotEmpty) ...[
        const SizedBox(height: FirouzehSize.space2),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FirouzehSize.space3, vertical: FirouzehSize.space2),
            child: Row(children: [
              Expanded(child: Text('${faDigits(_checked.length)} انتخاب شد', style: theme.textTheme.titleSmall)),
              TextButton(onPressed: () => setState(_checked.clear), child: const Text('لغو انتخاب')),
              if (_filter == PeopleFilter.inactive)
                OutlinedButton(onPressed: s.busy ? null : () => _bulk(s, 'active'), child: const Text('فعال'))
              else
                OutlinedButton(onPressed: s.busy ? null : () => _bulk(s, 'inactive'), child: const Text('غیرفعال')),
              const SizedBox(width: FirouzehSize.space2),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: x.stop, side: BorderSide(color: x.stop, width: 1.5)),
                onPressed: s.busy ? null : () => _bulk(s, 'deleted'),
                child: const Text('حذف…'),
              ),
            ]),
          ),
        ),
      ],
    ]);

    return Padding(
      padding: const EdgeInsets.all(FirouzehSize.space5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: table),
        if (open != null) ...[
          const SizedBox(width: FirouzehSize.space4),
          SizedBox(
            width: 400,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              // صفحه‌ی فرد همان صفحه‌ی موبایل است؛ بعد از حذف، فرد از فهرست می‌رود و پنل بسته می‌شود.
              child: PersonPage(key: ValueKey(open.id), person: open, embedded: true),
            ),
          ),
        ],
      ]),
    );
  }
}
