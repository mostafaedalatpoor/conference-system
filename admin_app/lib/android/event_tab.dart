// تب «رویداد» (طرح ۱۲): آمادگی برای روز اجرا در هفت مرحله، و صفحه‌های هر مرحله:
// تنظیم رویداد (طرح ۱۳)، افراد، کارت (طرح ۱۴ تا ۱۶) و ثبت‌نام آنلاین (طرح ۱۷).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../main.dart';
import '../normalize.dart';
import '../screens/config.dart';
import '../screens/import.dart';
import '../screens/registration.dart';
import '../state.dart';
import 'approvals.dart';
import 'card_flow.dart';
import 'jalali.dart';
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart' show NvPageHeader, confirmDanger;

/// صفحه‌ای از اپ ویندوز (دفتر) داخل سربرگ تازه؛ برای فرم‌های بلند که روی گوشی هم لازم‌اند.
class NvSubPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const NvSubPage({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        NvPageHeader(title: title, subtitle: subtitle),
        Expanded(child: child),
      ]),
    );
  }
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

class EventTab extends StatefulWidget {
  const EventTab({super.key});

  @override
  State<EventTab> createState() => _EventTabState();
}

class _EventTabState extends State<EventTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = StateScope.read(context);
      try {
        if (s.regEditor == null) await s.loadRegPage();
        await s.loadRegistrations();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final e = s.event!;
    final t = s.template;
    final cards = s.settings.usesCards;
    final page = s.regEditor?['page'] as Map?;
    final waiting = (s.regByStatus['pending_approval'] ?? 0) + (s.regByStatus['pending_review'] ?? 0);
    final warnings = cards ? cardWarnings(s).where((w) => w.ok == false).length : 0;
    final incomplete = s.people.values.where((p) => p.missingName).length;
    final identify = const {'scan': 'اسکن کارت', 'card': 'شماره‌ی کارت', 'none': 'بدون کارت'}[s.settings.identifyMode];

    final steps = <(IconData, String, String, bool?, VoidCallback)>[
      (Icons.tune_rounded, 'تنظیم رویداد', '$identify · ${faDigits(s.types.length)} نوع · ${faDigits(s.meals.length)} وعده', s.types.isNotEmpty,
          () => _push(context, const ConfigPage())),
      (Icons.groups_rounded, 'افراد و اکسل', s.people.isEmpty ? 'هنوز کسی وارد نشده' : '${faDigits(s.people.length)} نفر${incomplete > 0 ? ' · ${faDigits(incomplete)} ناقص' : ''}',
          s.people.isNotEmpty, () => _push(context, const NvSubPage(title: 'افراد و اکسل', child: ImportScreen()))),
      if (cards) ...[
        (Icons.straighten_rounded, 'مشخصات کارت', t.setupDone ? cardSpecLine(t) : 'اندازه و رو و QR', t.setupDone, () => _push(context, const CardSpecsPage())),
        (Icons.palette_rounded, 'طراحی کارت', '${hasDesign(s) ? 'پس‌زمینه' : 'بدون پس‌زمینه'} و ${faDigits(elementCount(t))} عنصر', t.setupDone && hasDesign(s),
            () => _push(context, const CardEditorPage())),
      ],
      (Icons.public_rounded, 'ثبت‌نام آنلاین',
          page == null ? 'ساخته نشده (اختیاری)' : '${const {'open': 'باز', 'closed': 'بسته', 'draft': 'پیش‌نویس'}[page['status']] ?? ''}${waiting > 0 ? ' · ${faDigits(waiting)} منتظر تأیید' : ''}',
          page == null ? null : page['status'] == 'open', () => _push(context, const RegOverviewPage())),
      if (cards) ...[
        (Icons.fact_check_rounded, 'بررسی پیش از چاپ', warnings == 0 ? 'هشداری نیست' : '${faDigits(warnings)} هشدار باقی است', warnings == 0 && s.people.isNotEmpty,
            () => _push(context, const CardCheckPage())),
        (Icons.print_rounded, 'ساخت و چاپ کارت‌ها', e.locked ? 'PDF ساخته شد؛ آدرس قفل است' : 'هنوز ساخته نشده', e.locked, () => _push(context, const CardCheckPage())),
      ],
    ];
    final required = steps.where((x) => x.$4 != null).toList();
    final ready = required.where((x) => x.$4 == true).length;
    final left = [for (final x in required) if (x.$4 != true) x.$2];

    return ListView(padding: const EdgeInsets.only(bottom: 110), children: [
      NvTabHeader(
        line: 'آماده‌سازی رویداد',
        title: e.name,
        bottom: 60,
      ),
      Transform.translate(
        offset: const Offset(0, -34),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22), boxShadow: Nv.raised(c)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  [if (e.startDate != null) jalaliLabel(e.startDate!), 'کد رویداد: ${e.code}'].join(' · '),
                  style: nvText(context, 12, color: c.muted),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('آمادگی برای روز اجرا', style: nvText(context, 15, w: FontWeight.w800))),
                  Text('${faDigits(ready)} از ${faDigits(required.length)} آماده', style: nvText(context, 13, w: FontWeight.w800, color: c.brandText)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: required.isEmpty ? 0 : ready / required.length, minHeight: 8, color: c.brand, backgroundColor: c.field),
                ),
                if (left.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('باقی مانده: ${left.join('، ')}.', style: nvText(context, 13, color: c.muted)),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
              child: Column(children: [
                for (var i = 0; i < steps.length; i++)
                  _StepRow(n: i + 1, icon: steps[i].$1, title: steps[i].$2, line: steps[i].$3, done: steps[i].$4, onTap: steps[i].$5, last: i == steps.length - 1),
              ]),
            ),
            const SizedBox(height: 14),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
              child: Column(children: [
                _LinkRow(
                  icon: Icons.link_rounded,
                  title: 'آدرس پایه‌ی لینک QR',
                  line: '${(e.baseUrl.isEmpty ? s.server : e.baseUrl).replaceFirst(RegExp(r'^https?://'), '')}${e.locked ? ' · قفل' : ''}',
                  onTap: () => showNvSheet<void>(context, (_) => const _BaseUrlSheet()),
                ),
                _LinkRow(icon: Icons.schedule_rounded, title: 'برنامه‌ی کنفرانس', line: '${faDigits(s.sessions.length)} جلسه؛ روی صفحه‌ی شخصی',
                    onTap: () => _push(context, const NvSubPage(title: 'برنامه‌ی کنفرانس', child: ConfigScreen(section: 'sessions')))),
                _LinkRow(icon: Icons.swap_horiz_rounded, title: 'رویداد دیگر یا سایت دیگر', line: s.server.replaceFirst(RegExp(r'^https?://'), ''), onTap: () async {
                  s.event = null;
                  s.notify();
                }),
                _LinkRow(icon: Icons.info_rounded, title: 'درباره و پشتیبانی', line: '$appName · ${faDigits(appVersionLabel)}', last: true, onTap: () => _about(context)),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _about(BuildContext context) => showNvSheet<void>(context, (c) {
        final x = NvColors.of(c);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(appName, style: nvText(c, 20, w: FontWeight.w800)),
            Text('$appNameLatin · ${faDigits(appVersionLabel)}', style: nvText(c, 13, color: x.muted)),
            const SizedBox(height: 12),
            Text(makerFull, style: nvText(c, 14)),
            TextButton(onPressed: () => launchUrl(Uri.parse('https://$makerWebsite')), child: const Text(makerWebsite)),
          ]),
        );
      });
}

class _StepRow extends StatelessWidget {
  final int n;
  final IconData icon;
  final String title, line;
  final bool? done;
  final VoidCallback onTap;
  final bool last;
  const _StepRow({required this.n, required this.icon, required this.title, required this.line, required this.done, required this.onTap, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final (Color bg, Color fg, IconData ic) = switch (done) {
      true => (c.goSoft, c.go, Icons.check_circle_rounded),
      false => (c.waitSoft, c.wait, Icons.pending_rounded),
      null => (c.field, c.muted, icon),
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Nv.r12)), child: Icon(ic, color: fg)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${faDigits(n)} · $title', style: nvText(context, 15, w: FontWeight.w800)),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 12, color: done == false ? c.wait : c.muted)),
            ]),
          ),
          Icon(Icons.chevron_left_rounded, color: c.muted),
        ]),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title, line;
  final VoidCallback onTap;
  final bool last;
  const _LinkRow({required this.icon, required this.title, required this.line, required this.onTap, this.last = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
        child: Row(children: [
          Icon(icon, color: c.brandText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: nvText(context, 14, w: FontWeight.w700)),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: line.contains('.') && !line.contains(' ') ? TextDirection.ltr : null, style: nvText(context, 12, color: c.muted)),
            ]),
          ),
          Icon(Icons.chevron_left_rounded, color: c.muted),
        ]),
      ),
    );
  }
}

/// آدرس پایه‌ی لینک QR و قفل آن.
class _BaseUrlSheet extends StatefulWidget {
  const _BaseUrlSheet();

  @override
  State<_BaseUrlSheet> createState() => _BaseUrlSheetState();
}

class _BaseUrlSheetState extends State<_BaseUrlSheet> {
  late final _url = TextEditingController(text: StateScope.read(context).event?.baseUrl ?? '');

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final e = s.event!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('آدرس پایه‌ی لینک QR', style: nvText(context, 20, w: FontWeight.w800)),
        const SizedBox(height: 12),
        NvField(
          label: 'آدرس',
          helper: e.locked ? 'قفل است چون PDF کارت‌ها ساخته شده؛ QR کارت‌های چاپ‌شده به این آدرس وابسته است.' : 'خالی = همین سایت. لینک هر کارت: آدرس/c/توکن',
          child: TextField(controller: _url, enabled: !e.locked, textDirection: TextDirection.ltr, textAlign: TextAlign.left),
        ),
        const SizedBox(height: 14),
        if (!e.locked)
          NvButton(
            label: 'ذخیره',
            busy: s.busy,
            onPressed: s.busy
                ? null
                : () async {
                    await s.saveEvent(code: e.code, name: e.name, startDate: e.startDate ?? '', endDate: e.endDate ?? '', baseUrl: _url.text.trim());
                    if (context.mounted && !s.messageIsError) Navigator.pop(context);
                  },
          )
        else
          NvSoftButton(
            label: 'برداشتن قفل…',
            fg: c.stop,
            border: c.stop.withValues(alpha: .4),
            onPressed: () async {
              final ok = await confirmDanger(context,
                  title: 'برداشتن قفل آدرس؟',
                  text: 'اگر بعد از چاپ کارت‌ها آدرس عوض شود، QR همه‌ی کارت‌های چاپ‌شده دیگر کار نمی‌کند و باید دوباره چاپ شوند.',
                  confirm: 'قفل را بردار');
              if (ok == true) await s.setLocked(false);
            },
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- تنظیم رویداد (طرح ۱۳)

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  late String _saved;
  late final TextEditingController _redirect, _email, _url;

  String _snap(AdminState s) => jsonEncode({
        ...s.settings.toJson(),
        'by_type': {for (final e in s.settings.contactByType.entries) e.key: [e.value.$1, e.value.$2]},
      });

  @override
  void initState() {
    super.initState();
    final st = StateScope.read(context);
    _saved = _snap(st);
    _redirect = TextEditingController(text: st.settings.redirectUrl);
    _email = TextEditingController(text: st.settings.organizerEmail);
    _url = TextEditingController(text: st.settings.organizerUrl);
  }

  @override
  void dispose() {
    _redirect.dispose();
    _email.dispose();
    _url.dispose();
    super.dispose();
  }

  int _dirty(AdminState s) {
    final a = jsonDecode(_saved) as Map, b = jsonDecode(_snap(s)) as Map;
    var n = 0;
    for (final k in {...a.keys, ...b.keys}) {
      if (jsonEncode(a[k]) != jsonEncode(b[k])) n++;
    }
    return n;
  }

  void _revert(AdminState s) {
    final j = (jsonDecode(_saved) as Map).cast<String, dynamic>();
    s.settings.load(j);
    s.settings.contactByType = {
      for (final e in ((j['by_type'] as Map?) ?? const {}).entries) '${e.key}': ((e.value as List)[0] == true, (e.value as List)[1] == true),
    };
    _redirect.text = s.settings.redirectUrl;
    _email.text = s.settings.organizerEmail;
    _url.text = s.settings.organizerUrl;
    s.notify();
  }

  Future<void> _save(AdminState s) async {
    await s.pushConfig();
    if (!s.messageIsError && mounted) setState(() => _saved = _snap(s));
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final st = s.settings;
    final dirty = _dirty(s);

    Widget radio(String group, String value, String current, IconData icon, String title, String sub, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: current == value ? c.brand.withValues(alpha: .08) : c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Nv.r18),
              side: BorderSide(color: current == value ? c.brand : c.lineSoft, width: current == value ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(Nv.r18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(icon, color: c.brandText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: nvText(context, 15, w: FontWeight.w800)),
                      Text(sub, style: nvText(context, 12, color: c.muted)),
                    ]),
                  ),
                  Icon(current == value ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: current == value ? c.brand : c.line),
                ]),
              ),
            ),
          ),
        );
    Widget title(String t, [String? sub]) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: nvText(context, 16, w: FontWeight.w800)),
            if (sub != null) Text(sub, style: nvText(context, 13, color: c.muted, height: 1.6)),
          ]),
        );
    Widget link(IconData icon, String t, String line, Widget page) => _LinkRow(icon: icon, title: t, line: line, onTap: () => _push(context, page));

    return PopScope(
      canPop: dirty == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirmDanger(context, title: 'تغییرات ذخیره نشده', text: '${faDigits(dirty)} تغییر روی سرور نرفته. بدون ذخیره برگردیم؟', confirm: 'بدون ذخیره برگرد');
        if (ok == true && context.mounted) {
          _revert(s);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Column(children: [
          const NvPageHeader(title: 'تنظیم رویداد', subtitle: 'مرحله‌ی ۱'),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              title('شناسایی افراد در ورودی', 'نیروها چطور افراد را پیدا می‌کنند؟ اپ نیروها خودش را با آن تنظیم می‌کند.'),
              radio('id', 'scan', st.identifyMode, Icons.qr_code_scanner_rounded, 'اسکن کارت', 'کارت QR؛ دوربین گوشی یا بارکدخوان', () => setState(() => st.identifyMode = 'scan')),
              radio('id', 'card', st.identifyMode, Icons.style_rounded, 'شماره‌ی کارت', 'کارت بدون اسکن؛ شماره را تایپ می‌کنند', () => setState(() => st.identifyMode = 'card')),
              radio('id', 'none', st.identifyMode, Icons.manage_search_rounded, 'بدون کارت', 'فقط جستجوی نام یا موبایل', () => setState(() => st.identifyMode = 'none')),
              if (st.usesCards) ...[
                title('وقتی QR با گوشی خود فرد باز شود'),
                radio('qr', 'person', st.qrBehavior, Icons.badge_rounded, 'صفحه‌ی شخصی هر فرد', 'نام، نقش، سازمان و برنامه', () => setState(() => st.qrBehavior = 'person')),
                radio('qr', 'redirect', st.qrBehavior, Icons.open_in_new_rounded, 'رفتن به یک آدرس', 'مثلاً سایت همایش', () => setState(() => st.qrBehavior = 'redirect')),
                if (st.qrBehavior == 'redirect')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _redirect,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'آدرس مقصد', hintText: 'https://…'),
                      onChanged: (v) => setState(() => st.redirectUrl = v.trim()),
                    ),
                  ),
                radio('qr', 'vcard', st.qrBehavior, Icons.contact_page_rounded, 'افزودن به مخاطبان', 'کارت ویزیت vCard', () => setState(() => st.qrBehavior = 'vcard')),
              ],
              title('اطلاعات تماس روی صفحه‌ی شخصی', 'برای هر نوع ثبت‌نام جدا. پیش‌فرض خاموش است تا حریم افراد حفظ شود.'),
              NvCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(children: [
                  for (final ty in s.types) ...[
                    for (final (i, label) in const [(0, 'موبایل'), (1, 'ایمیل')])
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${ty.name} · $label', style: nvText(context, 14)),
                        value: (st.contactByType[ty.code] ?? (st.shareMobile, st.shareEmail)).let((v) => i == 0 ? v.$1 : v.$2),
                        onChanged: (on) => setState(() {
                          final v = st.contactByType[ty.code] ?? (st.shareMobile, st.shareEmail);
                          st.contactByType[ty.code] = i == 0 ? (on, v.$2) : (v.$1, on);
                        }),
                      ),
                  ],
                  if (s.types.isEmpty) Padding(padding: const EdgeInsets.all(10), child: Text('اول نوع‌های ثبت‌نام را بسازید.', style: nvText(context, 13, color: c.muted))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('کسی که در ثبت‌نام «خیر» زده، فقط نام و سازمانش دیده می‌شود.', style: nvText(context, 12, color: c.muted)),
              ),
              title('نوع‌ها، نقش‌ها و وعده‌ها'),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
                child: Column(children: [
                  link(Icons.groups_rounded, 'نوع افراد', s.types.map((t) => t.name).join('، ').ifEmpty('تعریف نشده'),
                      const NvSubPage(title: 'نوع افراد', child: ConfigScreen(section: 'types'))),
                  link(Icons.mic_rounded, 'نقش‌ها', s.roles.map((t) => t.name).join('، ').ifEmpty('تعریف نشده'),
                      const NvSubPage(title: 'نقش‌ها', child: ConfigScreen(section: 'roles'))),
                  link(Icons.restaurant_rounded, 'وعده‌های پذیرایی', s.meals.map((m) => m.name).join('، ').ifEmpty('تعریف نشده'),
                      const NvSubPage(title: 'وعده‌های پذیرایی', subtitle: 'ساعت شروع اختیاری است', child: ConfigScreen(section: 'meals'))),
                ]),
              ),
              title('راه ارتباط با برگزارکننده', 'پایین صفحه‌ی شخصی افراد دیده می‌شود.'),
              NvField(
                label: 'ایمیل',
                optional: true,
                child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, onChanged: (v) => setState(() => st.organizerEmail = v.trim())),
              ),
              const SizedBox(height: 10),
              NvField(
                label: 'صفحه‌ی پشتیبانی',
                optional: true,
                child: TextField(controller: _url, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: 'https://…'), onChanged: (v) => setState(() => st.organizerUrl = v.trim())),
              ),
            ]),
          ),
          if (dirty > 0)
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
              child: Row(children: [
                Icon(Icons.edit_rounded, size: 18, color: c.wait),
                const SizedBox(width: 6),
                Expanded(child: Text('تغییرات ذخیره‌نشده: ${faDigits(dirty)} مورد', style: nvText(context, 13, w: FontWeight.w700, color: c.wait))),
                TextButton(onPressed: () => setState(() => _revert(s)), child: const Text('انصراف')),
                const SizedBox(width: 6),
                FilledButton(onPressed: s.busy ? null : () => _save(s), child: Text(s.busy ? 'در حال ذخیره…' : 'ذخیره')),
              ]),
            ),
        ]),
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

extension _IfEmpty on String {
  String ifEmpty(String v) => isEmpty ? v : this;
}

// ---------------------------------------------------------------- ثبت‌نام آنلاین (طرح ۱۷)

class RegOverviewPage extends StatefulWidget {
  const RegOverviewPage({super.key});

  @override
  State<RegOverviewPage> createState() => _RegOverviewPageState();
}

class _RegOverviewPageState extends State<RegOverviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = StateScope.read(context);
      try {
        await s.loadRegPage();
        await s.loadRegistrations();
      } catch (_) {}
    });
  }

  Future<void> _setStatus(AdminState s, String status) async {
    final page = s.regEditor?['page'];
    if (page is! Map) return;
    final cfg = jsonDecode(jsonEncode(page)) as Map<String, dynamic>;
    cfg['status'] = status;
    await s.saveRegPage(cfg);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final ed = s.regEditor;
    final page = ed?['page'] as Map?;
    final url = ed?['url'] as String?;
    final waiting = (s.regByStatus['pending_approval'] ?? 0) + (s.regByStatus['pending_review'] ?? 0);
    final total = s.regByStatus.values.fold<int>(0, (a, b) => a + b);
    final status = '${page?['status'] ?? 'draft'}';
    final types = (page?['types'] as List? ?? const []).cast<Map>();
    final addons = (page?['addons'] as List? ?? const []).cast<Map>();
    final fields = (page?['custom_fields'] as List? ?? const []).cast<Map>();
    final pay = (page?['payment'] as Map?) ?? const {};
    String typeName(String code) => s.types.where((t) => t.code == code).firstOrNull?.name ?? code;
    String price(Map m) => (m['price'] ?? 0) > 0 ? moneyFa((m['price'] as num).toInt()).replaceAll(' تومان', '') : 'رایگان';

    final sections = <(IconData, String, String, int)>[
      (Icons.link_rounded, 'آدرس و ورود به لیست', '${page?['use_prefix'] == true ? 'register/' : ''}${page?['path'] ?? ''} · ${const {'direct': 'مستقیم', 'approval': 'با تأیید مدیر', 'separate': 'جدا'}[page?['list_mode']] ?? ''}', 1),
      (Icons.info_rounded, 'اطلاعات صفحه', 'عنوان، توضیح، روزها، مکان، تصویر', 2),
      (Icons.palette_rounded, 'ظاهر', 'رنگ برند، تیره یا روشن', 3),
      (Icons.sell_rounded, 'انواع ثبت‌نام و قیمت', types.where((t) => t['visible'] != false).map((t) => '${typeName('${t['code']}')} ${price(t)}').join(' · '), 4),
      (Icons.groups_rounded, 'ظرفیت کل و فیلدها', (page?['capacity'] ?? 0) > 0 ? 'ظرفیت ${faDigits(page?['capacity'])}' : 'بدون سقف', 5),
      (Icons.quiz_rounded, 'پرسش‌ها', fields.isEmpty ? 'پرسشی نیست' : '${faDigits(fields.length)} پرسش · ${faDigits(fields.where((f) => f['required'] == true).length)} اجباری', 6),
      (Icons.restaurant_rounded, 'گزینه‌های اضافه', addons.isEmpty ? 'گزینه‌ای نیست' : addons.map((a) => a['title']).join(' · '), 7),
      (Icons.credit_card_rounded, 'پرداخت', const {'gateway': 'درگاه', 'link': 'لینک بیرونی', 'card': 'کارت‌به‌کارت'}[pay['method']] ?? '', 8),
      (Icons.task_alt_rounded, 'صفحه‌ی تأیید', 'لینک صفحه‌ی شخصی و متن پایان', 9),
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        const NvPageHeader(title: 'ثبت‌نام آنلاین', subtitle: 'مرحله‌ی ۵', bottom: 48),
        Transform.translate(
          offset: const Offset(0, -28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22), boxShadow: Nv.raised(c)),
                child: ed == null
                    ? const LinearProgressIndicator()
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Icon(Icons.how_to_reg_rounded, color: status == 'open' ? c.go : c.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              page == null
                                  ? 'هنوز ساخته نشده'
                                  : '${const {'open': 'ثبت‌نام باز است', 'closed': 'ثبت‌نام بسته است', 'draft': 'پیش‌نویس'}[status]} · ${faDigits(total)} نفر ثبت‌نام کرده‌اند',
                              style: nvText(context, 15, w: FontWeight.w800),
                            ),
                          ),
                        ]),
                        if (page != null) ...[
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 'open', label: Text('باز')),
                              ButtonSegment(value: 'closed', label: Text('بسته')),
                              ButtonSegment(value: 'draft', label: Text('پیش‌نویس')),
                            ],
                            selected: {status},
                            onSelectionChanged: s.busy ? null : (v) => _setStatus(s, v.first),
                          ),
                        ],
                        if (url != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
                            child: Row(children: [
                              Icon(Icons.link_rounded, color: c.brandText, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(url.replaceFirst(RegExp(r'^https?://'), ''), textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 13, w: FontWeight.w700))),
                              IconButton(
                                tooltip: 'کپی',
                                icon: const Icon(Icons.content_copy_rounded, size: 20),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: url));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('آدرس کپی شد.')));
                                },
                              ),
                              IconButton(tooltip: 'باز کردن', icon: const Icon(Icons.open_in_new_rounded, size: 20), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
                            ]),
                          ),
                        ],
                      ]),
              ),
              if (waiting > 0) ...[
                const SizedBox(height: 12),
                Material(
                  color: c.waitSoft,
                  borderRadius: BorderRadius.circular(Nv.r18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Nv.r18),
                    onTap: () => _push(context, const ApprovalsPage()),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Icon(Icons.pending_actions_rounded, color: c.wait),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${faDigits(waiting)} ثبت‌نام منتظر تأیید', style: nvText(context, 14, w: FontWeight.w800, color: c.waitInk))),
                        Icon(Icons.chevron_left_rounded, color: c.wait),
                      ]),
                    ),
                  ),
                ),
              ] else if (total > 0) ...[
                const SizedBox(height: 12),
                NvSoftButton(label: 'همه‌ی ثبت‌نام‌ها', icon: Icons.list_alt_rounded, onPressed: () => _push(context, const ApprovalsPage())),
              ],
              const SizedBox(height: 14),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
                child: Column(children: [
                  for (var i = 0; i < sections.length; i++)
                    _LinkRow(
                      icon: sections[i].$1,
                      title: sections[i].$2,
                      line: sections[i].$3.ifEmpty('—'),
                      last: i == sections.length - 1,
                      onTap: () => _push(context, NvSubPage(title: sections[i].$2, subtitle: 'صفحه‌ی ثبت‌نام', child: RegPageScreen(section: sections[i].$4))),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              const NvBanner(tone: NvTone.info, text: 'بستن ثبت‌نام، ثبت‌شده‌ها را نگه می‌دارد؛ فقط ثبت‌نام تازه را متوقف می‌کند.'),
            ]),
          ),
        ),
      ]),
    );
  }
}
