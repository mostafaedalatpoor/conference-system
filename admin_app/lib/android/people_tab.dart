// تب «افراد» (طرح ۵): جستجو، فیلتر (همه، آمده، نیامده، ناقص)، و وضعیت هر نفر کنار نامش.
import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart';

class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  final _q = TextEditingController();
  String _filter = 'all';
  DateTime _at = DateTime.now();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await StateScope.read(context).reload();
    if (mounted) setState(() => _at = DateTime.now());
  }

  List<Person> _list(AdminState s) {
    final all = s.people.values.toList();
    bool keep(Person p) => switch (_filter) {
          'in' => s.checkinAt.containsKey(p.id),
          'out' => !s.checkinAt.containsKey(p.id),
          'incomplete' => p.missingName,
          _ => true,
        };
    final q = normalizeText(_q.text);
    if (q.isEmpty) {
      if (_filter == 'all') {
        // جستجوی خالی: آخرین پذیرش‌ها.
        return [for (final id in s.recentCheckins) if (s.people[id] != null) s.people[id]!];
      }
      return all.where(keep).toList()..sort((a, b) => a.sortName.compareTo(b.sortName));
    }
    final words = q.split(' ');
    final digits = normalizeMobile(_q.text);
    final out = <Person>[];
    for (final p in all) {
      final key = normalizeText('${p.title} ${p.firstName} ${p.lastName} ${p.mobile} ${p.email} ${p.organization} ${p.serial ?? ''} ${p.regCode}');
      final hit = words.every(key.contains) || (digits.length >= 4 && normalizeMobile(p.mobile).contains(digits));
      if (hit && keep(p)) out.add(p);
      if (out.length >= 80) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final list = _list(s);
    final inCount = s.checkinAt.keys.where(s.people.containsKey).length;
    final incomplete = s.people.values.where((p) => p.missingName).length;
    final empty = _q.text.trim().isEmpty;

    Widget chip(String id, String label) {
      final on = _filter == id;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Material(
          color: on ? c.brand : c.surface,
          shape: StadiumBorder(side: on ? BorderSide.none : BorderSide(color: c.lineSoft)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _filter = id),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text(label, style: nvText(context, 12, w: FontWeight.w700, color: on ? c.onBrand : c.ink)),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
        NvTabHeader(
          line: '${faDigits(s.people.length)} نفر · ${faDigits(inCount)} پذیرش‌شده',
          title: 'افراد',
          bottom: 64,
          trailing: NvHeaderPill(icon: Icons.sync_rounded, text: faDigits(hm(_at)), onTap: _reload),
        ),
        Transform.translate(
          offset: const Offset(0, -36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Nv.r18), boxShadow: Nv.raised(c)),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'نام، موبایل، شماره‌ی کارت یا کد ثبت‌نام',
                    prefixIcon: Icon(Icons.search_rounded, color: c.brandText),
                    suffixIcon: empty ? null : IconButton(tooltip: 'پاک کردن', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_q.clear)),
                    filled: true,
                    fillColor: c.surface,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Nv.r18), borderSide: BorderSide(color: c.brand, width: 2)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Nv.r18), borderSide: BorderSide(color: c.brand, width: 2)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  chip('all', 'همه ${faDigits(s.people.length)}'),
                  chip('in', 'آمده ${faDigits(inCount)}'),
                  chip('out', 'نیامده ${faDigits(s.people.length - inCount)}'),
                  chip('incomplete', 'ناقص ${faDigits(incomplete)}'),
                ]),
              ),
              const SizedBox(height: 14),
              if (empty && _filter == 'all')
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                  child: Row(children: [
                    Expanded(child: Text('آخرین پذیرش‌ها', style: nvText(context, 14, w: FontWeight.w800))),
                    Text('برای همه، نام را بنویسید', style: nvText(context, 12, color: c.muted)),
                  ]),
                ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(children: [
                    Icon(Icons.search_off_rounded, size: 44, color: c.muted),
                    const SizedBox(height: 8),
                    Text(empty ? 'هنوز کسی پذیرش نشده' : 'کسی با «${_q.text.trim()}» پیدا نشد',
                        style: nvText(context, 16, w: FontWeight.w800)),
                    if (!empty) ...[
                      Text('نام، موبایل یا شماره‌ی کارت را دوباره بررسی کنید.', style: nvText(context, 13, color: c.muted)),
                      const SizedBox(height: 10),
                      NvSoftButton(label: 'پاک کردن جستجو', onPressed: () => setState(_q.clear)),
                    ],
                  ]),
                )
              else
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
                  child: Column(children: [
                    for (var i = 0; i < list.length; i++) NvPersonRow(p: list[i], last: i == list.length - 1),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// ردیف یک نفر با برچسب وضعیت (پذیرش‌شده ساعت … / هنوز نیامده / ناقص) و وعده‌های امروز.
class NvPersonRow extends StatelessWidget {
  final Person p;
  final bool last;
  const NvPersonRow({super.key, required this.p, this.last = false});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final at = s.checkinAt[p.id];
    final sub = [
      s.roleName(p.roleCode).isNotEmpty ? s.roleName(p.roleCode) : s.typeName(p.typeCode),
      if (p.organization.isNotEmpty) p.organization,
      if (p.source == 'walkin') 'ثبت‌نام در محل',
      if (p.serial != null && s.settings.usesCards) 'کارت ${faDigits(p.serial!)}',
      if (p.missingName && p.mobile.isEmpty) 'بدون موبایل',
    ].join(' · ');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final todayMeals = [
      for (var i = 0; i < s.meals.length && i < s.mealIds.length; i++)
        if (s.meals[i].day.startsWith(today)) s.mealIds[i],
    ];
    final letter = (p.lastName.trim().isNotEmpty ? p.lastName : p.cardFirstName).trim();
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonPage(person: p))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.missingName ? c.waitSoft : (at != null ? c.brand.withValues(alpha: .14) : c.field),
              borderRadius: BorderRadius.circular(Nv.r14),
            ),
            child: Text(letter.isEmpty ? '؟' : String.fromCharCode(letter.runes.first),
                style: nvText(context, 16, w: FontWeight.w800, color: p.missingName ? c.wait : (at != null ? c.brandText : c.muted))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 15, w: FontWeight.w800)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 12, color: c.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (p.missingName)
              NvStatusChip(text: 'ناقص', icon: Icons.edit_note_rounded, bg: c.waitSoft, fg: c.wait)
            else if (at != null)
              NvStatusChip(text: faDigits(hm(at)), icon: Icons.check_circle_rounded, bg: c.goSoft, fg: c.go)
            else
              NvStatusChip(text: 'هنوز نیامده', icon: Icons.schedule_rounded, bg: c.field, fg: c.muted),
            if (at != null && todayMeals.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final m in todayMeals)
                  Icon(Icons.restaurant_rounded, size: 14, color: s.mealsServed[p.id]?.containsKey(m) == true ? c.go : c.line),
              ]),
            ],
            if (p.source == 'walkin' && p.serial == null && s.settings.usesCards) ...[
              const SizedBox(height: 4),
              NvStatusChip(text: 'بدون کارت', icon: Icons.credit_card_off_rounded, bg: c.field, fg: c.muted),
            ],
          ]),
        ]),
      ),
    );
  }
}
