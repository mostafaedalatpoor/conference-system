// اتصال درگاه پرداخت و سرویس پیامک (بوم ۲۹ اندروید، ۱۸ ویندوز): زرین‌پال، درگاه دلخواه، پیامک دلخواه،
// پیام آزمایشی، آزمون ۱۰۰ تومانی و آخرین ارسال‌ها با «تلاش دوباره».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../main.dart';
import '../normalize.dart';
import 'reg_api.dart';
import 'reg_widgets.dart';

class RegConnectPage extends StatefulWidget {
  final RegEditor? editor;
  const RegConnectPage({super.key, this.editor});

  @override
  State<RegConnectPage> createState() => _RegConnectPageState();
}

class _RegConnectPageState extends State<RegConnectPage> {
  Map<String, dynamic>? _data;
  Map<String, dynamic> _g = {}, _s = {};
  List<Map<String, dynamic>> _msgs = [];
  final _mobile = TextEditingController();
  int _rev = 0;
  String _gwTab = 'zarinpal';

  @override
  void initState() {
    super.initState();
    _gwTab = '${(widget.editor?.config['payment'] as Map?)?['gateway'] ?? 'zarinpal'}';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = StateScope.read(context);
    final d = await s.loadConnections();
    final m = await s.loadMessages();
    if (!mounted) return;
    setState(() {
      if (d != null) {
        _data = d;
        final c = (d['connections'] as Map).cast<String, dynamic>();
        _g = (c['gateway'] as Map).cast<String, dynamic>();
        _s = (c['sms'] as Map).cast<String, dynamic>();
      }
      _msgs = m ?? _msgs;
      _rev++;
    });
  }

  Future<void> _save() async {
    final r = await StateScope.read(context).saveConnections({'gateway': _g, 'sms': _s});
    if (r != null && mounted) _load();
  }

  Future<void> _testPay() async {
    final s = StateScope.read(context);
    await s.saveConnections({'gateway': _g, 'sms': _s});
    final url = await s.testPayment();
    if (url == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    s.message = 'آدرس پرداخت آزمایشی ۱۰۰ تومانی کپی شد؛ آن را در مرورگر باز کنید و پرداخت را انجام دهید.';
    s.notify();
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final d = _data;
    final gateways = ((d?['gateways'] as List?) ?? []).cast<Map>();
    final providers = ((d?['sms_providers'] as List?) ?? []).cast<Map>();
    final callback = '${d?['callback_url'] ?? ''}';
    final gwReady = '${_g['start_url'] ?? ''}'.isNotEmpty && '${_g['redirect_field'] ?? ''}'.isNotEmpty;
    final smsReady = '${_s['url'] ?? ''}'.isNotEmpty;
    Widget pill(bool ok, String yes, String no) => Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: ok ? c.goSoft : c.waitSoft, borderRadius: BorderRadius.circular(12)),
          child: Text(ok ? yes : no, style: nvText(context, 11, w: FontWeight.w800, color: ok ? c.go : c.wait)),
        );
    Widget method(Map m, String k) => SizedBox(
          width: 110,
          child: RegSeg<String>(value: '${m[k] ?? 'POST'}', options: const [('POST', 'POST'), ('GET', 'GET')], onChanged: (v) => setState(() => m[k] = v)),
        );

    final gatewayCard = RegCard(
      title: 'درگاه پرداخت',
      raised: true,
      trailing: pill(_gwTab != 'custom' || gwReady, 'وصل است', 'کامل نیست'),
      children: d == null
          ? [const Center(child: CircularProgressIndicator())]
          : [
              RegSeg<String>(
                value: _gwTab == 'zarinpal' || _gwTab == 'custom' ? _gwTab : 'other',
                options: const [('zarinpal', 'زرین‌پال'), ('custom', 'درگاه دلخواه'), ('other', 'ماژول‌های نصب‌شده')],
                onChanged: (v) => setState(() => _gwTab = v),
              ),
              if (_gwTab == 'zarinpal')
                Text('کد مرچنت و حالت آزمایشی زرین‌پال در «راه‌اندازی ثبت‌نام ← گام ۵ پرداخت» است.', style: nvText(context, 12, color: c.muted, height: 1.6)),
              if (_gwTab != 'zarinpal' && _gwTab != 'custom')
                Text(
                    'درگاه‌هایی که برنامه‌نویس اضافه کرده خودکار اینجا می‌آیند: ${gateways.where((g) => g['id'] != 'zarinpal' && g['id'] != 'custom').map((g) => g['name']).join('، ').ifEmpty('هنوز چیزی نصب نشده')}.',
                    style: nvText(context, 12, color: c.muted, height: 1.6)),
              NvField(
                label: 'آدرس برگشت (به درگاه بدهید)',
                child: Row(children: [
                  Expanded(child: Text(callback, textDirection: TextDirection.ltr, style: nvText(context, 12))),
                  RegCopy(callback, label: ''),
                ]),
              ),
              if (_gwTab == 'custom') ...[
                const NvBanner(tone: NvTone.info, text: 'آدرس شروع، آدرس تأیید، هدر و بدنه را با متغیرهای {amount} {callback} {code} {mobile} {authority} بنویسید. هدرها و بدنه رمزشده ذخیره می‌شوند.'),
                RegText('نام درگاه', _g, 'name', hint: 'مثلاً پرداخت سازمان'),
                Text('واحد مبلغ', style: nvText(context, 13, w: FontWeight.w700)),
                RegSeg<String>(value: '${_g['unit'] ?? 'toman'}', options: const [('toman', 'تومان'), ('rial', 'ریال')], onChanged: (v) => setState(() => _g['unit'] = v)),
                Text('شروع پرداخت', style: nvText(context, 14, w: FontWeight.w800)),
                Row(children: [method(_g, 'start_method'), const SizedBox(width: 8), Expanded(child: RegText('', _g, 'start_url', ltr: true, hint: 'https://api.gateway.example/start'))]),
                RegText('هدرها (هر خط Name: value)', _g, 'start_headers', ltr: true, lines: 2, hint: 'Authorization: Bearer …'),
                RegText('بدنه', _g, 'start_body', ltr: true, lines: 3, hint: '{"amount": {amount}, "callback": "{callback}"}'),
                Row(children: [
                  Expanded(child: RegText('فیلد آدرس درگاه در پاسخ', _g, 'redirect_field', ltr: true, hint: 'data.url')),
                  const SizedBox(width: 8),
                  Expanded(child: RegText('فیلد شناسه‌ی تراکنش', _g, 'authority_field', ltr: true, optional: true, hint: 'data.id')),
                ]),
                Text('تأیید پرداخت', style: nvText(context, 14, w: FontWeight.w800)),
                Row(children: [method(_g, 'verify_method'), const SizedBox(width: 8), Expanded(child: RegText('', _g, 'verify_url', ltr: true, hint: 'https://api.gateway.example/verify'))]),
                RegText('هدرها', _g, 'verify_headers', ltr: true, lines: 2, optional: true),
                RegText('بدنه', _g, 'verify_body', ltr: true, lines: 2, optional: true, hint: '{"id": "{authority}", "amount": {amount}}'),
                Row(children: [
                  Expanded(child: RegText('فیلد نتیجه در پاسخ', _g, 'verify_field', ltr: true, optional: true, hint: 'status')),
                  const SizedBox(width: 8),
                  Expanded(child: RegText('پارامتر برگشت', _g, 'callback_param', ltr: true, optional: true, hint: 'Status')),
                ]),
                RegText('مقدار موفق', _g, 'success_value', ltr: true, hint: 'OK'),
                RegToggle(title: 'حالت آزمایشی', value: _g['test_mode'] == true, onChanged: (v) => setState(() => _g['test_mode'] = v)),
              ],
              Row(children: [
                Expanded(child: NvButton(label: 'ذخیره', height: 48, onPressed: _save)),
                const SizedBox(width: 8),
                Expanded(child: NvSoftButton(label: 'آزمون با ۱۰۰ تومان', icon: Icons.science_rounded, onPressed: _testPay)),
              ]),
            ],
    );

    final smsCard = RegCard(
      title: 'سرویس پیامک',
      trailing: pill(smsReady, 'وصل است', 'انتخاب نشده'),
      children: d == null
          ? const []
          : [
              if (providers.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: providers.any((p) => p['id'] == _s['provider']) ? '${_s['provider']}' : null,
                  items: [for (final p in providers) DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']}'))],
                  onChanged: (v) => setState(() => _s['provider'] = v),
                ),
              Text('اتصال دلخواه (HTTP)', style: nvText(context, 14, w: FontWeight.w800)),
              Row(children: [method(_s, 'method'), const SizedBox(width: 8), Expanded(child: RegText('', _s, 'url', ltr: true, hint: 'https://api.sms.example/send'))]),
              RegText('هدرها', _s, 'headers', ltr: true, lines: 2, hint: 'X-API-KEY: …'),
              RegText('بدنه', _s, 'body', ltr: true, lines: 3, hint: '{"to": "{mobile}", "from": "{sender}", "text": "{text}"}'),
              RegText('شماره‌ی فرستنده', _s, 'sender', ltr: true, optional: true),
              Text('قاعده‌ی موفقیت', style: nvText(context, 13, w: FontWeight.w700)),
              RegSeg<String>(value: '${_s['success'] ?? 'http200'}', options: const [('http200', 'HTTP ۲۰۰'), ('text', 'متن در پاسخ')], onChanged: (v) => setState(() => _s['success'] = v)),
              if (_s['success'] == 'text') RegText('متن موفقیت', _s, 'success_text', ltr: true),
              Row(children: [
                Expanded(child: NvButton(label: 'ذخیره', height: 48, onPressed: _save)),
                const SizedBox(width: 8),
                Expanded(
                  child: NvSoftButton(
                    label: 'پیام آزمایشی',
                    icon: Icons.send_rounded,
                    onPressed: () async {
                      final mobile = await showDialog<String>(
                        context: context,
                        builder: (dc) => AlertDialog(
                          title: const Text('پیام آزمایشی به موبایل'),
                          content: TextField(controller: _mobile, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: '0912…')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dc), child: const Text('انصراف')),
                            FilledButton(onPressed: () => Navigator.pop(dc, _mobile.text), child: const Text('بفرست')),
                          ],
                        ),
                      );
                      if (mobile == null || mobile.trim().isEmpty || !context.mounted) return;
                      final s = StateScope.read(context);
                      await s.saveConnections({'gateway': _g, 'sms': _s});
                      await s.testSms(mobile.trim());
                      _load();
                    },
                  ),
                ),
              ]),
            ],
    );

    final sendsCard = RegCard(title: 'آخرین ارسال‌ها', children: [
      if (_msgs.isEmpty) Text('هنوز پیامی فرستاده نشده.', style: nvText(context, 13, color: c.muted)),
      for (final m in _msgs.take(15))
        Row(children: [
          Icon(m['ok'] == true ? Icons.check_circle_rounded : Icons.error_rounded, size: 18, color: m['ok'] == true ? c.go : c.stop),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                '${m['recipient']}',
                m['trigger'] == 'test' ? 'آزمایشی' : (regTriggers[m['trigger']] ?? '${m['trigger']}'),
                if (m['channel'] == 'email') 'ایمیل',
                if (m['ok'] != true) '${m['response']}'.split('·').first.trim(),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nvText(context, 13),
            ),
          ),
          if (m['ok'] != true)
            TextButton(
              onPressed: () async {
                await StateScope.read(context).retryMessage((m['id'] as num).toInt());
                _load();
              },
              child: const Text('تلاش دوباره'),
            ),
          Text(faDigits(hm(DateTime.tryParse('${m['at']}')?.toLocal() ?? DateTime.now())), style: nvText(context, 12, color: c.muted)),
        ]),
    ]);

    return RegScaffold(
      title: 'اتصال درگاه و پیامک',
      subtitle: 'ثبت‌نام آنلاین · برای همه‌ی رویدادهای این سایت',
      maxWidth: regWide(context) ? 1240 : 760,
      overlap: 34,
      onRefresh: _load,
      children: [
        KeyedSubtree(
          key: ValueKey(_rev),
          child: regWide(context)
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: gatewayCard),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: [smsCard, const SizedBox(height: 12), sendsCard])),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [gatewayCard, const SizedBox(height: 12), smsCard, const SizedBox(height: 12), sendsCard]),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String v) => isEmpty ? v : this;
}
