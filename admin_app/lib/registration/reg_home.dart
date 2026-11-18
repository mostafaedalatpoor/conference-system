// صفحه‌ی «ثبت‌نام آنلاین» (بوم ۱۷-RegPage): وضعیت و آدرس، صف تصمیم، و راه به ویزارد، ثبت‌نام‌ها، گزارش مالی و اتصال‌ها.
import 'package:flutter/material.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../main.dart';
import '../normalize.dart';
import 'reg_api.dart';
import 'reg_connect.dart';
import 'reg_finance.dart';
import 'reg_list.dart';
import 'reg_widgets.dart';
import 'reg_wizard.dart';

class RegHomePage extends StatefulWidget {
  const RegHomePage({super.key});

  @override
  State<RegHomePage> createState() => _RegHomePageState();
}

class _RegHomePageState extends State<RegHomePage> {
  RegEditor? _ed;
  RegList? _list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = StateScope.read(context);
    final ed = await s.loadRegEditor();
    final list = ed?.exists == true ? await s.loadRegistrations(archived: false) : null;
    if (!mounted) return;
    setState(() {
      _ed = ed ?? _ed;
      _list = list ?? _list;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _setStatus(String v) async {
    final ed = _ed;
    if (ed == null || !ed.exists) return;
    ed.config['status'] = v;
    final r = await StateScope.read(context).saveRegPage(ed.config, ok: v == 'open' ? 'ثبت‌نام باز شد.' : (v == 'closed' ? 'ثبت‌نام بسته شد.' : 'پیش‌نویس شد.'));
    if (mounted && r != null) setState(() => _ed = r);
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final ed = _ed;
    if (ed == null) {
      return const RegScaffold(title: 'ثبت‌نام آنلاین', children: [NvCard(raised: true, child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())))]);
    }
    final cfg = ed.config;
    final status = '${cfg['status']}';
    final n = _list?.active ?? 0;
    final waiting = (_list?.byStatus['pending_approval'] ?? 0) + (_list?.byStatus['pending_review'] ?? 0);
    final types = (cfg['types'] as List).cast<Map>().where((t) => t['visible'] != false).toList();
    final p = (cfg['payment'] as Map).cast<String, dynamic>();
    final msg = (cfg['messages'] as Map?)?.cast<String, dynamic>() ?? {};
    final deadline = '${cfg['deadline'] ?? ''}';
    final (IconData sIcon, Color sBg, Color sFg, String sTitle) = !ed.exists
        ? (Icons.edit_note_rounded, c.field, c.muted, 'هنوز ساخته نشده')
        : switch (status) {
            'open' => (Icons.how_to_reg_rounded, c.goSoft, c.go, 'ثبت‌نام باز است'),
            'closed' => (Icons.event_busy_rounded, c.stopSoft, c.stop, 'ثبت‌نام بسته است'),
            _ => (Icons.edit_note_rounded, c.waitSoft, c.wait, 'پیش‌نویس'),
          };
    Widget row(IconData icon, String title, String line, int step) => InkWell(
          onTap: () => _open(RegWizardPage(editor: ed, step: step)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(children: [
              Icon(icon, color: c.brandText),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title, style: nvText(context, 14, w: FontWeight.w800)),
                  Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: nvText(context, 12, color: c.muted)),
                ]),
              ),
              Icon(Icons.chevron_left_rounded, color: c.muted),
            ]),
          ),
        );
    return RegScaffold(
      title: 'ثبت‌نام آنلاین',
      subtitle: StateScope.of(context).event?.name,
      overlap: 44,
      onRefresh: _load,
      bottom: ed.exists
          ? Row(children: [
              Expanded(flex: 10, child: NvSoftButton(label: 'ثبت‌نام‌ها', onPressed: () => _open(RegListPage(editor: ed)))),
              const SizedBox(width: 10),
              Expanded(flex: 14, child: NvButton(label: 'راه‌اندازی و ویرایش', onPressed: () => _open(RegWizardPage(editor: ed)))),
            ])
          : NvButton(label: 'ساختن صفحه‌ی ثبت‌نام', icon: Icons.add_rounded, onPressed: () => _open(RegWizardPage(editor: ed))),
      children: [
        RegCard(raised: true, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: sBg, shape: BoxShape.circle),
              child: Icon(sIcon, color: sFg, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sTitle, style: nvText(context, 17, w: FontWeight.w800)),
                Text(
                  ed.exists
                      ? [if (deadline.isNotEmpty) 'تا ${faDigits(deadline)}', '${faDigits(n)} نفر ثبت‌نام کرده‌اند'].join(' · ')
                      : 'شرکت‌کنندگان خودشان ثبت‌نام می‌کنند، پرداخت می‌کنند و وارد لیست می‌شوند.',
                  style: nvText(context, 12, color: c.muted),
                ),
              ]),
            ),
          ]),
          if (ed.exists)
            RegSeg<String>(value: status, options: const [('open', 'باز'), ('closed', 'بسته'), ('draft', 'پیش‌نویس')], onChanged: _setStatus),
          if (ed.url != null)
            Container(
              padding: const EdgeInsetsDirectional.only(start: 14),
              decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r16)),
              child: Row(children: [
                Icon(Icons.link_rounded, color: c.brandText),
                const SizedBox(width: 8),
                Expanded(child: Text(ed.url!.replaceFirst(RegExp(r'^https?://'), ''), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: nvText(context, 13))),
                RegCopy(ed.url!, label: ''),
              ]),
            ),
        ]),
        if (waiting > 0)
          Material(
            color: c.waitSoft,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _open(RegListPage(editor: ed, filter: 'attention')),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.pending_actions_rounded, color: c.wait),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${faDigits(waiting)} ثبت‌نام منتظر تصمیم شما', style: nvText(context, 14, w: FontWeight.w800, color: c.waitInk))),
                  Icon(Icons.chevron_left_rounded, color: c.wait),
                ]),
              ),
            ),
          ),
        NvCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            row(Icons.link_rounded, 'آدرس و ورود به لیست', ed.exists ? '${ed.fullPath} · ${const {'direct': 'مستقیم', 'approval': 'با تأیید مدیر', 'separate': 'جدا'}[cfg['list_mode']] ?? ''}' : 'آدرس صفحه را تعیین کنید', 1),
            Divider(color: c.lineSoft, height: 1),
            row(Icons.info_outline_rounded, 'محتوا و ظاهر', 'عنوان، توضیح، زمان و مکان، رنگ', 2),
            Divider(color: c.lineSoft, height: 1),
            row(Icons.sell_outlined, 'نوع‌ها و قیمت', types.isEmpty ? 'نوعی دیده نمی‌شود' : types.map((t) => '${ed.typeName('${t['code']}')} ${regMoney((t['price'] as num?) ?? 0, unit: false, free: true)}').join(' · '), 3),
            Divider(color: c.lineSoft, height: 1),
            row(Icons.quiz_outlined, 'پرسش‌ها و گزینه‌های اضافه',
                '${faDigits((cfg['custom_fields'] as List).length)} پرسش · ${faDigits((cfg['addons'] as List).length)} گزینه', 4),
            Divider(color: c.lineSoft, height: 1),
            row(Icons.credit_card_rounded, 'پرداخت', regPayMethods[p['method']] ?? '', 5),
            Divider(color: c.lineSoft, height: 1),
            row(Icons.sms_outlined, 'پیام به ثبت‌نام‌کننده',
                [if (msg['sms'] == true) 'پیامک', if (msg['email'] == true) 'ایمیل'].join(' و ').ifEmpty('خاموش'), 6),
          ]),
        ),
        if (ed.exists)
          NvCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.groups_rounded, color: c.brandText),
                title: const Text('ثبت‌نام‌ها'),
                subtitle: Text('${faDigits(n)} نفر · بایگانی ${faDigits(_list?.archived ?? 0)}'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => _open(RegListPage(editor: ed)),
              ),
              Divider(color: c.lineSoft, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.payments_outlined, color: c.brandText),
                title: const Text('گزارش مالی'),
                subtitle: const Text('دریافت‌شده، در جریان، تسویه‌ی روز اجرا'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => _open(const RegFinancePage()),
              ),
              Divider(color: c.lineSoft, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cable_rounded, color: c.brandText),
                title: const Text('اتصال درگاه و پیامک'),
                subtitle: const Text('درگاه دلخواه، سرویس پیامک، آخرین ارسال‌ها'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => _open(RegConnectPage(editor: ed)),
              ),
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
          const SizedBox(width: 8),
          Expanded(child: Text('بستن ثبت‌نام، ثبت‌شده‌ها را نگه می‌دارد. فقط ثبت‌نام تازه را متوقف می‌کند.', style: nvText(context, 12, color: c.muted, height: 1.6))),
        ]),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String v) => isEmpty ? v : this;
}
