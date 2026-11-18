// تب «رویداد» (طرح ۱۲): آمادگی برای روز اجرا، و صفحه‌های کامل هر مرحله زیر سربرگ خمیده:
// تنظیم رویداد، نیروها، افراد و اکسل، کارت‌ها، گزارش و خروجی، اتصال و بایگانی.
import 'package:flutter/material.dart';

import '../brand.dart';
import '../main.dart';
import '../normalize.dart';
import '../screens/cards.dart';
import '../screens/config.dart';
import '../screens/connect.dart';
import '../screens/import.dart';
import '../screens/report.dart';
import '../registration/reg_home.dart';
import '../screens/staff.dart';
import 'jalali.dart';
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart' show NvPageHeader, confirmDanger;

/// صفحه‌ی کامل اپ داخل سربرگ تازه؛ برای فرم‌های بلند که روی گوشی هم لازم‌اند.
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
        const MessageBar(),
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
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final e = s.event!;
    final cards = s.settings.usesCards;
    final incomplete = s.people.values.where((p) => p.missingName).length;
    final identify = const {'scan': 'اسکن کارت', 'card': 'شماره‌ی کارت', 'none': 'بدون کارت'}[s.settings.identifyMode];
    final noPin = s.staff.where((x) => x.active && !x.hasPin && x.newPin.isEmpty).length;
    final unprinted = s.people.values.where((p) => p.isActive && !p.printed).length;

    Widget sub(String title, Widget child) => NvSubPage(title: title, subtitle: e.name, child: child);
    final steps = <(IconData, String, String, bool?, VoidCallback)>[
      (Icons.tune_rounded, 'تنظیم رویداد', '$identify · ${faDigits(s.types.length)} نوع · ${faDigits(s.meals.length)} وعده', s.types.isNotEmpty,
          () => _push(context, sub('تنظیم رویداد', const ConfigScreen()))),
      (Icons.badge_rounded, 'نیروها و PIN', s.staff.isEmpty ? 'نیرویی تعریف نشده' : '${faDigits(s.staff.length)} نیرو${noPin > 0 ? ' · ${faDigits(noPin)} بدون PIN' : ''}',
          s.staff.isNotEmpty && noPin == 0, () => _push(context, sub('نیروها و PIN', const StaffScreen()))),
      (Icons.groups_rounded, 'افراد و اکسل', s.people.isEmpty ? 'هنوز کسی وارد نشده' : '${faDigits(s.people.length)} نفر${incomplete > 0 ? ' · ${faDigits(incomplete)} ناقص' : ''}',
          s.people.isNotEmpty, () => _push(context, sub('افراد و اکسل', const ImportScreen()))),
      if (cards)
        (Icons.style_rounded, 'کارت‌ها و چاپ', e.locked ? 'PDF ساخته شد؛ آدرس قفل است${unprinted > 0 ? ' · ${faDigits(unprinted)} چاپ‌نشده' : ''}' : 'قالب، بررسی و ساخت PDF',
            e.locked, () => _push(context, sub('کارت‌ها و چاپ', const CardsScreen()))),
      (Icons.how_to_reg_rounded, 'ثبت‌نام آنلاین', s.regWaiting > 0 ? '${faDigits(s.regWaiting)} منتظر تصمیم' : 'صفحه، پرداخت، ثبت‌نام‌ها و گزارش مالی (اختیاری)', null,
          () => _push(context, const RegHomePage())),
      (Icons.insights_rounded, 'گزارش و خروجی', 'گزارش روزانه، اکسل، CSV و PDF', null, () => _push(context, sub('گزارش و خروجی', const ReportScreen()))),
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
                _LinkRow(icon: Icons.swap_horiz_rounded, title: 'اتصال، رویداد دیگر، بایگانی', line: s.server.replaceFirst(RegExp(r'^https?://'), ''),
                    onTap: () => _push(context, const NvSubPage(title: 'اتصال و رویداد', child: ConnectScreen()))),
                _LinkRow(icon: Icons.info_rounded, title: 'درباره و پشتیبانی', line: '$appName · ${faDigits(appVersion)}', last: true, onTap: () => _about(context)),
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
            Text('$appNameLatin · ${faDigits(appVersion)}', style: nvText(c, 13, color: x.muted)),
            const SizedBox(height: 12),
            Text(makerFull, style: nvText(c, 14)),
            SelectableText(makerWebsite, style: nvText(c, 14, color: x.brandText)),
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

