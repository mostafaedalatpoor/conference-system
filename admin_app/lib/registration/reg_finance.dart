// گزارش مالی ثبت‌نام (بوم ۲۸ اندروید و ویندوز).
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../export.dart' show toXlsx;
import '../main.dart';
import '../normalize.dart';
import '../screens/export_dialog.dart' show saveExportFile;
import 'reg_api.dart';
import 'reg_widgets.dart';

class RegFinancePage extends StatefulWidget {
  const RegFinancePage({super.key});

  @override
  State<RegFinancePage> createState() => _RegFinancePageState();
}

class _RegFinancePageState extends State<RegFinancePage> {
  Map<String, dynamic>? _f;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await StateScope.read(context).loadFinance();
    if (mounted && r != null) setState(() => _f = r);
  }

  int _t(String k) => ((_f?['totals'] as Map?)?[k] as num?)?.toInt() ?? 0;

  Future<void> _export() async {
    final f = _f;
    if (f == null) return;
    final rows = <List<String>>[
      ['بخش', 'شرح', 'تعداد', 'مبلغ (تومان)'],
      ['دریافت‌شده', 'آنلاین (تأییدشده)', '${_t('paid_count')}', '${_t('paid_online')}'],
      ['دریافت‌شده', 'درگاه', '', '${_t('paid_gateway')}'],
      ['دریافت‌شده', 'کارت‌به‌کارت', '', '${_t('paid_card')}'],
      ['دریافت‌شده', 'لینک بیرونی', '', '${_t('paid_link')}'],
      ['در جریان', 'در انتظار پرداخت', '${_t('awaiting_payment_count')}', '${_t('awaiting_payment')}'],
      ['در جریان', 'بررسی پرداخت', '${_t('awaiting_review_count')}', '${_t('awaiting_review')}'],
      ['در جریان', 'منتظر تأیید مدیر', '${_t('awaiting_approval_count')}', '${_t('awaiting_approval')}'],
      for (final x in ((f['by_type'] as List?) ?? []).cast<Map>()) ['بر اساس نوع', '${x['name']}', '${x['count']}', '${x['amount']}'],
      for (final x in ((f['by_addon'] as List?) ?? []).cast<Map>()) ['گزینه‌ی اضافه', '${x['title']}', '${x['count']}', '${x['amount']}'],
      ['روز اجرا', 'باید در محل پرداخت شود', '', '${_t('onsite_due')}'],
      ['روز اجرا', 'تسویه‌شده', '', '${_t('onsite_settled')}'],
      ['روز اجرا', 'باقی‌مانده', '${_t('onsite_open')}', '${_t('onsite_due') - _t('onsite_settled')}'],
      if (_t('rejected_paid') > 0) ['برگرداندنی', 'پرداخت‌شده ولی ردشده', '', '${_t('rejected_paid')}'],
    ];
    final s = StateScope.read(context);
    final Uint8List bytes = toXlsx(rows);
    await saveExportFile(s, 'finance-${s.eventCode ?? ''}', 'xlsx', bytes);
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final f = _f;
    final expected = _t('expected_total');
    final paid = _t('paid_online');
    final onsiteDue = _t('onsite_due');
    final onsiteSettled = _t('onsite_settled');
    return RegScaffold(
      title: 'گزارش مالی',
      subtitle: 'ثبت‌نام آنلاین',
      overlap: 44,
      onRefresh: _load,
      actions: [NvRoundIcon(icon: Icons.download_rounded, label: 'خروجی اکسل', onTap: _export)],
      children: f == null
          ? [const NvCard(raised: true, child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())))]
          : [
              RegCard(raised: true, children: [
                Text('دریافت‌شده‌ی آنلاین (تأییدشده)', style: nvText(context, 12, color: c.muted)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: regMoney(paid, unit: false), style: nvText(context, 30, w: FontWeight.w800, color: c.go)),
                  TextSpan(text: ' تومان', style: nvText(context, 15, color: c.muted)),
                ])),
                RegBar(expected == 0 ? 0 : paid / expected),
                Text(expected == 0 ? 'هنوز مبلغی نیست.' : '${faDigits((paid * 100 / expected).round())}٪ از مبلغ کل ثبت‌نام‌های غیر ردشده',
                    style: nvText(context, 12, color: c.muted)),
                if (_t('paid_gateway') > 0) RegKv('درگاه', regMoney(_t('paid_gateway'), unit: false)),
                if (_t('paid_card') > 0) RegKv('کارت‌به‌کارت', regMoney(_t('paid_card'), unit: false)),
                if (_t('paid_link') > 0) RegKv('لینک بیرونی', regMoney(_t('paid_link'), unit: false)),
              ]),
              RegCard(title: 'در جریان', children: [
                RegKv('در انتظار پرداخت · ${faDigits(_t('awaiting_payment_count'))} نفر', regMoney(_t('awaiting_payment'), unit: false)),
                RegKv('بررسی پرداخت · ${faDigits(_t('awaiting_review_count'))} نفر', regMoney(_t('awaiting_review'), unit: false)),
                RegKv('منتظر تأیید مدیر · ${faDigits(_t('awaiting_approval_count'))} نفر', regMoney(_t('awaiting_approval'), unit: false)),
              ]),
              RegCard(title: 'بر اساس نوع', children: [
                if (((f['by_type'] as List?) ?? []).isEmpty) Text('هنوز پرداختی نیست.', style: nvText(context, 13, color: c.muted)),
                for (final x in ((f['by_type'] as List?) ?? []).cast<Map>())
                  RegKv('${x['name']} · ${faDigits(x['count'])} نفر', regMoney((x['amount'] as num?) ?? 0, unit: false)),
              ]),
              if (((f['by_addon'] as List?) ?? []).isNotEmpty)
                RegCard(title: 'گزینه‌های اضافه', children: [
                  for (final x in ((f['by_addon'] as List?) ?? []).cast<Map>())
                    RegKv('${x['title']} · آنلاین · ${faDigits(x['count'])} نفر', regMoney((x['amount'] as num?) ?? 0, unit: false)),
                ]),
              RegCard(title: 'تسویه‌ی روز اجرا', children: [
                RegKv('باید در محل پرداخت شود', regMoney(onsiteDue, unit: false)),
                RegKv('تسویه‌شده تا الان', regMoney(onsiteSettled, unit: false), color: c.go),
                RegKv('باقی‌مانده · ${faDigits(_t('onsite_open'))} نفر', regMoney(onsiteDue - onsiteSettled, unit: false), color: c.wait),
                RegBar(onsiteDue == 0 ? 0 : onsiteSettled / onsiteDue),
              ]),
              if (_t('rejected_paid') > 0)
                NvBanner(tone: NvTone.wait, title: 'برگرداندنی', text: '${regMoney(_t('rejected_paid'))} پرداخت شده ولی ثبت‌نامش رد شده؛ باید برگردانده شود.'),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('مبلغ‌ها به تومان‌اند و فقط ثبت‌نام‌های غیر ردشده و غیر منقضی را می‌شمارند. «خروجی» همین گزارش را به اکسل می‌دهد.',
                      style: nvText(context, 12, color: c.muted, height: 1.6)),
                ),
              ]),
            ],
    );
  }
}
