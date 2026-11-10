// صفحه‌ی فرد (طرح ۶)، ویرایش اطلاعات (طرح ۱۹) و موردهای مشکوک با «بررسی شد، علامت را بردار».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';

/// سربرگ صفحه‌های داخلی: برگشت، عنوان، و یک دکمه‌ی اختیاری.
class NvPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final double bottom;
  const NvPageHeader({super.key, required this.title, this.subtitle, this.action, this.bottom = 20});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvHeader(
      radius: 28,
      bottom: bottom,
      child: Row(children: [
        NvRoundIcon(icon: Icons.arrow_forward_rounded, label: 'بازگشت', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (subtitle != null) Text(subtitle!, style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: nvText(context, 19, w: FontWeight.w800, color: c.onBrand, height: 1.4)),
          ]),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

class PersonPage extends StatefulWidget {
  final Person person;
  const PersonPage({super.key, required this.person});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  late Future<List<Map<String, dynamic>>> _timeline;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timeline = StateScope.read(context).loadTimeline(widget.person.id);
  }

  Future<void> _refresh() async {
    final s = StateScope.read(context);
    setState(() => _timeline = s.loadTimeline(widget.person.id));
    await _timeline.catchError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> _undo(AdminState s, Person p) async {
    final ok = await confirmDanger(
      context,
      title: 'لغو پذیرش ${p.listName}؟',
      text: 'وعده‌هایی که گرفته ثبت می‌ماند. نیرو می‌تواند دوباره پذیرش کند. در گزارش ثبت می‌شود.',
      confirm: 'لغو پذیرش',
    );
    if (ok != true) return;
    await s.undoCheckin(p.id);
    await s.reload();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final p = s.people[widget.person.id] ?? widget.person;
    final at = s.checkinAt[p.id];
    final flags = s.flaggedList.where((f) => f['attendee_id']?.toString() == p.id).toList();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final tags = [s.typeName(p.typeCode), s.roleName(p.roleCode), p.organization].where((e) => e.isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: c.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          NvPageHeader(
            title: p.listName,
            subtitle: tags,
            bottom: 40,
            action: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: .16), shape: const StadiumBorder()),
              onPressed: () => showEditPerson(context, p),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('ویرایش'),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // وضعیت امروز: پذیرش و وعده‌ها.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22), boxShadow: Nv.raised(c)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(at != null ? Icons.check_circle_rounded : Icons.schedule_rounded, color: at != null ? c.go : c.muted, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(at != null ? 'پذیرش شده، ساعت ${faDigits(hm(at))}' : 'هنوز پذیرش نشده',
                            style: nvText(context, 16, w: FontWeight.w800)),
                      ),
                    ]),
                    for (var i = 0; i < s.meals.length && i < s.mealIds.length; i++)
                      if (s.meals[i].day.startsWith(today) || s.mealsServed[p.id]?.containsKey(s.mealIds[i]) == true)
                        Builder(builder: (context) {
                          final got = s.mealsServed[p.id]?[s.mealIds[i]];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(children: [
                              Icon(got != null ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: got != null ? c.go : c.line),
                              const SizedBox(width: 10),
                              Expanded(child: Text(s.meals[i].name, style: nvText(context, 14))),
                              Text(got != null ? faDigits(hm(got)) : 'هنوز نه', style: nvText(context, 13, color: c.muted)),
                            ]),
                          );
                        }),
                  ]),
                ),
                if (p.missingName) ...[
                  const SizedBox(height: 12),
                  NvBanner(
                    tone: NvTone.wait,
                    title: 'اطلاعات ناقص',
                    text: 'نام یا نام خانوادگی در اکسل خالی بوده. در لیست هست و پذیرش می‌شود.',
                    action: OutlinedButton(onPressed: () => showEditPerson(context, p), child: const Text('تکمیل اطلاعات')),
                  ),
                ],
                for (final f in flags) ...[const SizedBox(height: 12), FlagCard(flag: f)],
                const SizedBox(height: 12),
                NvCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(children: [
                    if (p.mobile.isNotEmpty)
                      _InfoRow(
                        icon: Icons.call_rounded,
                        text: faDigits(p.mobile),
                        ltr: true,
                        action: TextButton(onPressed: () => launchUrl(Uri.parse('tel:${p.mobile}')), child: const Text('تماس')),
                      ),
                    if (p.email.isNotEmpty)
                      _InfoRow(
                        icon: Icons.mail_rounded,
                        text: p.email,
                        ltr: true,
                        action: IconButton(
                          tooltip: 'کپی',
                          icon: const Icon(Icons.content_copy_rounded),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: p.email));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ایمیل کپی شد.')));
                          },
                        ),
                      ),
                    if (s.settings.usesCards)
                      _InfoRow(
                        icon: Icons.style_rounded,
                        text: p.serial == null ? 'بدون کارت' : 'کارت ${faDigits(p.serial!)}',
                        trailing: switch (p.source) {
                          'walkin' => 'ثبت‌نام در محل',
                          'register' => 'ثبت‌نام آنلاین${p.regCode.isEmpty ? '' : ' ${p.regCode}'}',
                          _ => 'ورود اکسل',
                        },
                      ),
                    if (p.onsiteDue > 0)
                      _InfoRow(icon: Icons.payments_rounded, text: 'تسویه‌ی روز اجرا: ${moneyFa(p.onsiteDue)}', trailing: p.onsiteNote),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('تاریخچه', style: nvText(context, 15, w: FontWeight.w800)),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _timeline,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                    if (snap.hasError) {
                      return const NvBanner(tone: NvTone.neutral, text: 'تاریخچه از سرور نرسید. پایین بکشید تا دوباره امتحان شود.');
                    }
                    final events = [...snap.data!]..sort((a, b) => '${b['device_time']}'.compareTo('${a['device_time']}'));
                    if (events.isEmpty) return Text('هنوز کاری برای این نفر ثبت نشده.', style: nvText(context, 14, color: c.muted));
                    return NvCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(children: [
                        for (final (i, e) in events.indexed) _TimelineRow(e: e, last: i == events.length - 1),
                      ]),
                    );
                  },
                ),
                if (at != null) ...[
                  const SizedBox(height: 18),
                  NvSoftButton(label: 'لغو پذیرش…', fg: c.stop, border: c.stop.withValues(alpha: .4), onPressed: s.busy ? null : () => _undo(s, p)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool ltr;
  final String? trailing;
  final Widget? action;
  const _InfoRow({required this.icon, required this.text, this.ltr = false, this.trailing, this.action});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(children: [
        Icon(icon, size: 20, color: c.brandText),
        const SizedBox(width: 12),
        Expanded(child: Text(text, textDirection: ltr ? TextDirection.ltr : null, textAlign: TextAlign.start, style: nvText(context, 15, w: FontWeight.w600))),
        if (trailing != null && trailing!.isNotEmpty) Text(trailing!, style: nvText(context, 12, color: c.muted)),
        if (action != null) action!,
      ]),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Map<String, dynamic> e;
  final bool last;
  const _TimelineRow({required this.e, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final kind = '${e['kind'] ?? ''}';
    final meal = '${e['meal_name'] ?? ''}'.trim();
    final flagged = e['flag'] != null && e['resolved_at'] == null;
    final (IconData icon, String label) = switch (kind) {
      'checkin' => (Icons.how_to_reg_rounded, 'پذیرش'),
      'checkin_undo' => (Icons.undo_rounded, 'لغو پذیرش'),
      'meal_served' => (Icons.restaurant_rounded, meal.isEmpty ? 'وعده' : meal),
      'walkin_register' => (Icons.person_add_rounded, 'ثبت‌نام در محل'),
      'attendee_update' => (Icons.edit_note_rounded, 'تکمیل اطلاعات'),
      'card_link' => (Icons.add_card_rounded, 'وصل کارت رزرو'),
      'onsite_settled' => (Icons.payments_rounded, 'تسویه شد'),
      'staff_note' => (Icons.campaign_rounded, 'خبر از نیرو'),
      _ => (Icons.circle_outlined, '${e['label'] ?? kind}'),
    };
    final at = DateTime.tryParse('${e['device_time']}')?.toLocal();
    final sub = [
      if (e['flag_label'] != null) '${e['flag_label']}',
      if ('${e['detail'] ?? ''}'.isNotEmpty) '${e['detail']}',
      if ('${e['device_label'] ?? ''}'.isNotEmpty) '${e['device_label']}',
      if ('${e['staff'] ?? ''}'.isNotEmpty) '${e['staff']}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(flagged ? Icons.flag_rounded : icon, size: 20, color: flagged ? c.wait : c.brandText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: nvText(context, 14, w: FontWeight.w700)),
            if (sub.isNotEmpty) Text(sub, style: nvText(context, 12, color: c.muted)),
          ]),
        ),
        if (at != null) Text(faDigits(hm(at)), style: nvText(context, 12, color: c.muted)),
      ]),
    );
  }
}

/// کارت یک مورد مشکوک با «بررسی شد، علامت را بردار» (یا برگرداندن علامت).
class FlagCard extends StatelessWidget {
  final Map<String, dynamic> flag;
  const FlagCard({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final resolved = flag['resolved_at'] != null;
    final at = DateTime.tryParse('${flag['device_time']}')?.toLocal();
    final text = [
      if ('${flag['detail'] ?? ''}'.isNotEmpty) '${flag['detail']}',
      if (at != null) 'ساعت ${faDigits(hm(at))}',
      if ('${flag['device'] ?? ''}'.isNotEmpty) '${flag['device']}',
      if ('${flag['staff'] ?? ''}'.isNotEmpty) '${flag['staff']}',
      if (resolved) 'بررسی شد${'${flag['resolved_by'] ?? ''}'.isEmpty ? '' : ' (${flag['resolved_by']})'}',
    ].join(' · ');
    return NvBanner(
      tone: resolved ? NvTone.neutral : NvTone.wait,
      icon: resolved ? Icons.flag_outlined : Icons.flag_rounded,
      title: '${flag['flag_label']}${'${flag['name'] ?? ''}'.isEmpty ? '' : ' — ${flag['name']}'}',
      text: text,
      action: TextButton(
        onPressed: s.busy ? null : () => s.resolveFlag((flag['seq'] as num).toInt(), resolved: !resolved),
        child: Text(resolved ? 'علامت را برگردان' : 'بررسی شد، علامت را بردار'),
      ),
    );
  }
}

/// همه‌ی موردهای مشکوک، اول بررسی‌نشده‌ها.
class FlagsPage extends StatelessWidget {
  const FlagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final flags = s.flaggedList;
    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        NvPageHeader(title: 'موارد مشکوک', subtitle: '${faDigits(flags.where((f) => f['resolved_at'] == null).length)} بررسی‌نشده'),
        for (final f in flags)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: InkWell(
              onTap: () {
                final p = s.people[f['attendee_id']?.toString()];
                if (p != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonPage(person: p)));
              },
              child: FlagCard(flag: f),
            ),
          ),
      ]),
    );
  }
}

/// موردی که به یک نفر وصل نیست (مثلاً خبر نیرو بدون نام).
class FlagPage extends StatelessWidget {
  final Map<String, dynamic> flag;
  const FlagPage({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final live = s.flaggedList.where((f) => f['seq'] == flag['seq']).firstOrNull ?? flag;
    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(children: [
        NvPageHeader(title: '${live['flag_label']}'),
        Padding(padding: const EdgeInsets.all(16), child: FlagCard(flag: live)),
      ]),
    );
  }
}

/// پرسش تأیید برای کار حساس؛ دکمه‌ی خطر قرمز.
Future<bool?> confirmDanger(BuildContext context, {required String title, required String text, required String confirm}) {
  final c = NvColors.of(context);
  return showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('نه، برگرد')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: c.stop), onPressed: () => Navigator.pop(d, true), child: Text(confirm)),
      ],
    ),
  );
}

/// ویرایش اطلاعات یک نفر (طرح ۱۹). خانه‌ی خالی مقدار قبلی را نگه می‌دارد؛ ✕ آن را پاک می‌کند.
Future<void> showEditPerson(BuildContext context, Person p) =>
    showNvSheet<void>(context, (c) => _EditPerson(p: p));

class _EditPerson extends StatefulWidget {
  final Person p;
  const _EditPerson({required this.p});

  @override
  State<_EditPerson> createState() => _EditPersonState();
}

class _EditPersonState extends State<_EditPerson> {
  late final Map<String, TextEditingController> _c = {
    'title': TextEditingController(text: widget.p.title),
    'first': TextEditingController(text: widget.p.cardFirstName),
    'last': TextEditingController(text: widget.p.lastName),
    'mobile': TextEditingController(text: widget.p.mobile),
    'email': TextEditingController(text: widget.p.email),
    'org': TextEditingController(text: widget.p.organization),
  };
  final Set<String> _cleared = {};
  late String? _role = widget.p.roleCode;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String k, String label, {bool ltr = false, TextInputType? type, IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NvField(
          label: label,
          child: TextField(
            controller: _c[k],
            keyboardType: type,
            textDirection: ltr ? TextDirection.ltr : null,
            textAlign: ltr ? TextAlign.left : TextAlign.start,
            decoration: InputDecoration(
              prefixIcon: icon == null ? null : Icon(icon),
              hintText: _cleared.contains(k) ? 'پاک می‌شود' : null,
              suffixIcon: _c[k]!.text.isEmpty && !_cleared.contains(k)
                  ? null
                  : IconButton(
                      tooltip: 'پاک کردن این خانه',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _c[k]!.clear();
                        _cleared.add(k);
                      }),
                    ),
            ),
            onChanged: (_) => setState(() => _cleared.remove(k)),
          ),
        ),
      );

  Future<void> _save() async {
    final s = StateScope.read(context);
    final p = widget.p;
    String v(String k) => _c[k]!.text.trim();
    // خانه‌ی خالی چیزی را پاک نمی‌کند، مگر با ✕.
    String pick(String k, String old) => v(k).isNotEmpty ? v(k) : (_cleared.contains(k) ? '' : old);
    p
      ..title = pick('title', p.title)
      ..organization = pick('org', p.organization)
      ..email = pick('email', p.email).toLowerCase()
      ..mobile = normalizeMobile(pick('mobile', p.mobile))
      ..roleCode = _role;
    if (v('first').isNotEmpty) p.firstName = v('first');
    if (v('last').isNotEmpty) p.lastName = v('last');
    await s.uploadPeople([p]);
    if (mounted && !s.messageIsError) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('ویرایش اطلاعات', style: nvText(context, 20, w: FontWeight.w800)),
          Text(widget.p.listName, style: nvText(context, 13, color: c.muted)),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(width: 110, child: _field('title', 'عنوان')),
            const SizedBox(width: 10),
            Expanded(child: _field('first', 'نام')),
          ]),
          _field('last', 'نام خانوادگی'),
          _field('mobile', 'موبایل', ltr: true, type: TextInputType.phone, icon: Icons.call_rounded),
          _field('email', 'ایمیل', ltr: true, type: TextInputType.emailAddress, icon: Icons.mail_rounded),
          _field('org', 'سازمان'),
          if (s.roles.isNotEmpty)
            NvField(
              label: 'نقش',
              child: DropdownButtonFormField<String?>(
                initialValue: _role,
                items: [
                  const DropdownMenuItem(value: null, child: Text('بدون نقش')),
                  for (final r in s.roles) DropdownMenuItem(value: r.code, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _role = v),
              ),
            ),
          const SizedBox(height: 12),
          const NvBanner(tone: NvTone.info, text: 'خالی گذاشتن یک خانه، مقدار قبلی را پاک نمی‌کند. برای پاک کردن، ✕ کنار آن را بزنید.'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: NvSoftButton(label: 'انصراف', onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 10),
            Expanded(child: NvButton(label: 'ذخیره', busy: s.busy, onPressed: s.busy ? null : _save)),
          ]),
        ]),
      ),
    );
  }
}
