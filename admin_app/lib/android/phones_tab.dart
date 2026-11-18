// تب «گوشی‌ها و کارکنان» (طرح ۹ تا ۱۱): وضعیت گوشی‌های نیروها، جزئیات و لغو دسترسی،
// و کارکنان با دسترسی‌ها؛ ساخت، ویرایش و دیدن PIN در صفحه‌ی کامل «نیروها و PIN».
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../screens/staff.dart';
import 'event_tab.dart' show NvSubPage;
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart' show confirmDanger;

class PhonesTab extends StatefulWidget {
  const PhonesTab({super.key});

  @override
  State<PhonesTab> createState() => _PhonesTabState();
}

class _PhonesTabState extends State<PhonesTab> {
  bool _staff = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final s = StateScope.read(context);
    await s.loadReport();
    if (s.messageIsError) s.message = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final devices = s.deviceList;
    final active = devices.where((d) => d['revoked'] != true).length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
        NvTabHeader(line: '${faDigits(active)} گوشی · ${faDigits(s.staff.length)} نفر کارکنان', title: 'گوشی‌ها و کارکنان', bottom: 60),
        Transform.translate(
          offset: const Offset(0, -30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16), boxShadow: Nv.raised(c)),
                child: Row(children: [
                  for (final (on, label) in [(false, 'گوشی‌ها'), (true, 'کارکنان')])
                    Expanded(
                      child: Material(
                        color: _staff == on ? c.brand : Colors.transparent,
                        borderRadius: BorderRadius.circular(Nv.r12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Nv.r12),
                          onTap: () => setState(() => _staff = on),
                          child: SizedBox(
                            height: 44,
                            child: Center(child: Text(label, style: nvText(context, 14, w: FontWeight.w800, color: _staff == on ? c.onBrand : c.ink))),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              if (_staff) const _StaffList() else _DeviceList(devices: devices),
            ]),
          ),
        ),
      ]),
    );
  }
}

int? _silentMinutes(Map<String, dynamic> d) {
  final last = DateTime.tryParse('${d['last_sync_at'] ?? ''}')?.toLocal();
  return last == null ? null : DateTime.now().difference(last).inMinutes;
}

String _ago(int? mins) {
  if (mins == null) return 'هنوز وصل نشده';
  if (mins < 1) return 'الان';
  if (mins < 60) return '${faDigits(mins)} دقیقه پیش';
  if (mins < 60 * 24) return '${faDigits(mins ~/ 60)} ساعت پیش';
  return '${faDigits(mins ~/ (60 * 24))} روز پیش';
}

class _DeviceList extends StatelessWidget {
  final List<Map<String, dynamic>> devices;
  const _DeviceList({required this.devices});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    if (s.report == null) return const LinearProgressIndicator();
    final silent = devices.where((d) => d['revoked'] != true && (_silentMinutes(d) ?? 0) > 10).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in silent)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NvBanner(
            tone: NvTone.wait,
            icon: Icons.wifi_off_rounded,
            title: '«${d['label']}» ${faDigits(_silentMinutes(d)!)} دقیقه است به سرور نرسیده',
            text: (d['pending'] ?? 0) > 0
                ? 'آخرین گزارشش: ${faDigits(d['pending'])} مورد در صف ارسال. کارها روی خود گوشی امن است.'
                : 'کارهای ثبت‌شده روی خود گوشی امن است و با اینترنت می‌رسد.',
          ),
        ),
      if (devices.isEmpty)
        NvCard(child: Text('هنوز گوشی‌ای وارد نشده.', style: nvText(context, 14, color: c.muted)))
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
          child: Column(children: [
            for (var i = 0; i < devices.length; i++) _DeviceRow(d: devices[i], last: i == devices.length - 1),
          ]),
        ),
      const SizedBox(height: 14),
      NvBanner(
        tone: NvTone.info,
        icon: Icons.qr_code_2_rounded,
        text: 'برای وصل کردن گوشی تازه، در اپ نیروها کد رویداد «${s.event?.code ?? ''}» و PIN همان نیرو را وارد کنید. نیرو و PIN را در «کارکنان» بسازید.',
      ),
    ]);
  }
}

class _DeviceRow extends StatelessWidget {
  final Map<String, dynamic> d;
  final bool last;
  const _DeviceRow({required this.d, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final revoked = d['revoked'] == true;
    final mins = _silentMinutes(d);
    final online = !revoked && mins != null && mins <= 10;
    final roles = ((d['roles'] as List?) ?? const []).join('، ');
    return Opacity(
      opacity: revoked ? .55 : 1,
      child: InkWell(
        onTap: () => showNvSheet<void>(context, (_) => _DeviceSheet(d: d)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
              child: Icon(revoked ? Icons.phonelink_erase_rounded : Icons.smartphone_rounded, color: c.brandText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['label'] ?? 'گوشی بی‌نام'}', style: nvText(context, 15, w: FontWeight.w800)),
                Text(
                  revoked
                      ? 'لغو شده · ${_ago(mins)}'
                      : [if ('${d['staff'] ?? ''}'.isNotEmpty) '${d['staff']}', if (roles.isNotEmpty) roles, 'آخرین ارتباط: ${_ago(mins)}'].join(' · '),
                  style: nvText(context, 12, color: c.muted),
                ),
              ]),
            ),
            if (!revoked)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                online
                    ? NvStatusChip(text: 'آنلاین', icon: Icons.check_circle_rounded, bg: c.goSoft, fg: c.go)
                    : NvStatusChip(text: 'آفلاین', icon: Icons.wifi_off_rounded, bg: c.waitSoft, fg: c.wait),
                const SizedBox(height: 4),
                Text(
                  (d['pending'] ?? 0) > 0 && !online ? '${faDigits(d['pending'])} در صف' : '${faDigits(d['today_count'] ?? 0)} ثبت امروز',
                  style: nvText(context, 11, color: c.muted),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _DeviceSheet extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DeviceSheet({required this.d});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final revoked = d['revoked'] == true;
    final mins = _silentMinutes(d);
    final online = !revoked && mins != null && mins <= 10;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(k, style: nvText(context, 14, color: c.muted))),
            Text(v, style: nvText(context, 14, w: FontWeight.w700)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
            child: Icon(Icons.smartphone_rounded, color: c.brandText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['label']}', style: nvText(context, 18, w: FontWeight.w800)),
              Text(['${d['staff'] ?? ''}', if (((d['roles'] as List?) ?? const []).isNotEmpty) 'نقش: ${(d['roles'] as List).join('، ')}'].where((e) => e.isNotEmpty).join(' · '),
                  style: nvText(context, 13, color: c.muted)),
            ]),
          ),
          if (revoked)
            NvStatusChip(text: 'لغو شده', icon: Icons.block_rounded, bg: c.field, fg: c.muted)
          else
            online
                ? NvStatusChip(text: 'آنلاین', icon: Icons.check_circle_rounded, bg: c.goSoft, fg: c.go)
                : NvStatusChip(text: 'آفلاین', icon: Icons.wifi_off_rounded, bg: c.waitSoft, fg: c.wait),
        ]),
        const SizedBox(height: 10),
        kv('آخرین ارتباط', _ago(mins)),
        kv('در صف ارسال (آخرین گزارش)', '${faDigits(d['pending'] ?? 0)} مورد'),
        kv('ثبت‌شده امروز', faDigits(d['today_count'] ?? 0)),
        kv('نسخه‌ی اپ', '${d['app_version'] ?? ''}'.isEmpty ? 'گزارش نشده' : faDigits(d['app_version'])),
        if (!revoked) ...[
          const SizedBox(height: 10),
          const NvBanner(
            tone: NvTone.info,
            text: 'اگر گوشی گم شد یا دست فرد نامطمئنی افتاد، دسترسی را لغو کنید. کارهای ثبت‌شده‌ی قبلی می‌ماند و کارهای ارسال‌نشده تا ورود دوباره با PIN روی همان گوشی می‌ماند.',
          ),
          const SizedBox(height: 14),
          NvSoftButton(
            label: 'لغو دسترسی این گوشی…',
            icon: Icons.block_rounded,
            iconColor: c.stop,
            fg: c.stop,
            border: c.stop.withValues(alpha: .4),
            onPressed: s.busy
                ? null
                : () async {
                    final ok = await confirmDanger(context,
                        title: 'لغو دسترسی «${d['label']}»؟', text: 'این گوشی تا ورود دوباره با PIN نمی‌تواند چیزی ثبت کند.', confirm: 'لغو دسترسی');
                    if (ok == true) {
                      await s.revokeDevice((d['id'] as num).toInt());
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
          ),
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ]),
    );
  }
}

class _StaffList extends StatelessWidget {
  const _StaffList();

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    String desk(StaffDef st) {
      final d = s.deviceList.where((d) => d['staff'] == st.name && d['revoked'] != true).firstOrNull;
      return d == null ? '' : '${d['label']}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.staff.isEmpty) NvCard(child: Text('هنوز نیرویی نساخته‌اید.', style: nvText(context, 14, color: c.muted))),
      if (s.staff.isNotEmpty)
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
          child: Column(children: [
            for (var i = 0; i < s.staff.length; i++)
              InkWell(
                onTap: () => _openStaff(context),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: i == s.staff.length - 1 ? null : Border(bottom: BorderSide(color: c.lineSoft))),
                  child: Row(children: [
                    NvLetter(s.staff[i].name.isEmpty ? '؟' : String.fromCharCode(s.staff[i].name.runes.first), size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.staff[i].name, style: nvText(context, 15, w: FontWeight.w800)),
                        Text(
                          [
                            _roles(s.staff[i]),
                            if (desk(s.staff[i]).isNotEmpty) desk(s.staff[i]),
                            if (!s.staff[i].active) 'غیرفعال',
                            if (!s.staff[i].hasPin) 'بدون PIN',
                          ].join(' · '),
                          style: nvText(context, 12, color: s.staff[i].hasPin ? c.muted : c.wait),
                        ),
                      ]),
                    ),
                    Icon(Icons.edit_rounded, color: c.muted),
                  ]),
                ),
              ),
          ]),
        ),
      const SizedBox(height: 12),
      NvButton(label: 'نیروی تازه یا دیدن PIN', icon: Icons.person_add_rounded, onPressed: () => _openStaff(context)),
    ]);
  }
}

String _roles(StaffDef st) => [if (st.canCheckin) 'پذیرش', if (st.canServe) 'پذیرایی', if (st.isAdmin) 'مدیر'].join('، ').ifEmpty('بدون دسترسی');

extension on String {
  String ifEmpty(String v) => isEmpty ? v : this;
}

/// صفحه‌ی کامل نیروها (۲٫۰): PIN با آیکن چشم و کپی، غیرفعال‌سازی، تعارض ذخیره.
void _openStaff(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NvSubPage(title: 'نیروها و PIN', subtitle: StateScope.read(context).event?.name, child: const StaffScreen()),
    ));
