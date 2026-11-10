// تب «امروز» (طرح ۴): «نیاز به توجه» که هر مورد به صفحه‌ی خودش می‌رود، آمار، پذیرایی و نوع‌ها.
// هر ۳۰ ثانیه خودکار و با پایین‌کشیدن تازه می‌شود.
import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import 'approvals.dart';
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart';

class TodayTab extends StatefulWidget {
  final ValueChanged<int> onGo;
  const TodayTab({super.key, required this.onGo});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Timer? _timer;
  DateTime? _at;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (!mounted) return;
    final s = StateScope.read(context);
    await s.loadReport();
    final ok = !s.messageIsError;
    if (ok) {
      try {
        await s.loadRegistrations();
      } catch (_) {
        // افزونه‌ی بدون صفحه‌ی ثبت‌نام: صف تأیید خالی می‌ماند.
      }
    } else if (quiet) {
      // خطای به‌روزرسانی خودکار پیام نمی‌دهد؛ نوار «آفلاین» کافی است.
      s.message = null;
    }
    if (mounted) {
      setState(() {
        _failed = !ok;
        if (ok) _at = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final r = s.report;
    final header = NvTabHeader(
      line: todayLine(),
      title: s.event?.name ?? '',
      trailing: NvHeaderPill(
        icon: _failed ? Icons.cloud_off_rounded : Icons.sync_rounded,
        text: _failed ? 'آفلاین' : 'زنده',
        onTap: () => _refresh(),
      ),
    );
    if (r == null) {
      return Column(children: [
        header,
        Expanded(
          child: _failed
              ? NvErrorState(onRetry: () => _refresh())
              : const NvSkeletonList(),
        ),
      ]);
    }
    final totals = (r['totals'] as Map).cast<String, dynamic>();
    final items = _attention(context, s, r);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
        header,
        Transform.translate(
          offset: const Offset(0, -30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NvBanner(
                    tone: NvTone.neutral,
                    icon: Icons.cloud_off_rounded,
                    text: 'به سرور نرسیدیم؛ داده‌ی ساعت ${faDigits(hm(_at ?? DateTime.now()))} نشان داده می‌شود.',
                  ),
                ),
              _AttentionCard(items: items),
              const SizedBox(height: 14),
              _Stats(totals: totals),
              const SizedBox(height: 14),
              ..._meals(context, s, r),
              const SizedBox(height: 14),
              NvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('بر اساس نوع ثبت‌نام', style: nvText(context, 15, w: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final t in (r['by_registration_type'] as List).cast<Map>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text('${t['name']}', style: nvText(context, 14))),
                        Text('${faDigits(t['checked_in'])} از ${faDigits(t['total'])}', style: nvText(context, 14, w: FontWeight.w700)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Text(
                '${_at == null ? '' : 'آخرین به‌روزرسانی ${faDigits(hm(_at!))}، '}هر ۳۰ ثانیه خودکار؛ برای تازه‌سازی پایین بکشید',
                textAlign: TextAlign.center,
                style: nvText(context, 12, color: c.muted),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// «نیاز به توجه»: فقط موردهایی که کاری می‌خواهند.
  List<_Item> _attention(BuildContext context, AdminState s, Map<String, dynamic> r) {
    final c = NvColors.of(context);
    final out = <_Item>[];
    final waiting = (s.regByStatus['pending_approval'] ?? 0) + (s.regByStatus['pending_review'] ?? 0);
    if (waiting > 0) {
      out.add(_Item(Icons.how_to_reg_rounded, c.waitSoft, c.wait, '${faDigits(waiting)} ثبت‌نام منتظر تصمیم',
          'تأیید یا رد از صف تأیید', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApprovalsPage()))));
    }
    for (final f in s.flaggedList.where((f) => f['resolved_at'] == null).take(6)) {
      final flag = '${f['flag']}';
      final (IconData icon, bool red) = switch (flag) {
        'meal_override' => (Icons.flag_rounded, true),
        'duplicate_meal' => (Icons.repeat_rounded, false),
        'not_entitled' => (Icons.block_rounded, true),
        'staff_note' => (Icons.campaign_rounded, false),
        _ => (Icons.warning_rounded, false),
      };
      final at = DateTime.tryParse('${f['device_time']}')?.toLocal();
      final sub = [
        if ('${f['name'] ?? ''}'.isNotEmpty) '${f['name']}',
        if ('${f['detail'] ?? ''}'.isNotEmpty) '${f['detail']}',
        if (at != null) faDigits(hm(at)),
        if ('${f['staff'] ?? ''}'.isNotEmpty) '${f['staff']}',
      ].join('، ');
      final aid = f['attendee_id']?.toString();
      final person = aid == null ? null : s.people[aid];
      out.add(_Item(icon, red ? c.stopSoft : c.waitSoft, red ? c.stop : c.wait, '${f['flag_label']}', sub, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => person != null ? PersonPage(person: person) : FlagPage(flag: f),
        ));
      }));
    }
    final open = s.flaggedList.where((f) => f['resolved_at'] == null).length;
    if (open > 6) {
      out.add(_Item(Icons.more_horiz_rounded, c.chip, c.muted, 'و ${faDigits(open - 6)} مورد مشکوک دیگر', 'همه‌ی موردها',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FlagsPage()))));
    }
    for (final d in s.deviceList) {
      if (d['revoked'] == true) continue;
      final last = DateTime.tryParse('${d['last_sync_at'] ?? ''}')?.toLocal();
      if (last == null) continue;
      final mins = DateTime.now().difference(last).inMinutes;
      if (mins <= 10) continue;
      out.add(_Item(Icons.phonelink_off_rounded, c.waitSoft, c.wait, '«${d['label']}» بی‌خبر است',
          ['${faDigits(mins)} دقیقه', if ('${d['staff'] ?? ''}'.isNotEmpty) '${d['staff']}', if ((d['pending'] ?? 0) > 0) '${faDigits(d['pending'])} در صف'].join('، '),
          () => widget.onGo(2)));
    }
    final incomplete = s.people.values.where((p) => p.missingName).length;
    if (incomplete > 0) {
      out.add(_Item(Icons.edit_note_rounded, c.waitSoft, c.wait, '${faDigits(incomplete)} نفر اطلاعات ناقص دارند', 'نام یا نام خانوادگی خالی است',
          () => widget.onGo(1)));
    }
    final free = (r['totals'] as Map)['reserve_cards_free'] as num? ?? 0;
    if (s.settings.usesCards && free < 3) {
      out.add(_Item(Icons.style_rounded, c.chip, c.muted, 'کارت رزرو رو به اتمام', '${faDigits(free)} کارت آزاد مانده', () => widget.onGo(3)));
    }
    return out;
  }

  List<Widget> _meals(BuildContext context, AdminState s, Map<String, dynamic> r) {
    final c = NvColors.of(context);
    final meals = (r['meals'] as List).cast<Map>();
    if (meals.isEmpty) return const [];
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final nowHm = '${two(now.hour)}:${two(now.minute)}';
    String timeOf(Map m) {
      final i = s.mealIds.indexOf((m['id'] as num?)?.toInt() ?? -1);
      return i >= 0 && i < s.meals.length ? s.meals[i].time : '';
    }

    final todays = meals.where((m) => '${m['day'] ?? ''}'.startsWith(today)).toList()
      ..sort((a, b) => (timeOf(a).isEmpty ? '99' : timeOf(a)).compareTo(timeOf(b).isEmpty ? '99' : timeOf(b)));
    final shown = todays.isNotEmpty ? todays : meals;
    final started = shown.where((m) => timeOf(m).isNotEmpty && timeOf(m).compareTo(nowHm) <= 0).toList();
    final current = started.isNotEmpty ? started.last : (todays.isNotEmpty ? todays.first : null);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text(todays.isNotEmpty ? 'پذیرایی امروز' : 'پذیرایی', style: nvText(context, 15, w: FontWeight.w800)),
      ),
      for (final m in shown)
        Builder(builder: (context) {
          final isNow = identical(m, current);
          final past = !isNow && todays.contains(m) && started.contains(m);
          final entitled = (m['entitled'] as num? ?? 0).toInt();
          final served = (m['served'] as num? ?? 0).toInt();
          final dup = (m['duplicates'] as num? ?? 0).toInt();
          final not = (m['not_entitled'] as num? ?? 0).toInt();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Opacity(
              opacity: past ? .85 : 1,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Nv.r22),
                  border: isNow ? Border.all(color: c.brand, width: 2) : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text('${m['name']}', style: nvText(context, 16, w: FontWeight.w800)),
                    if (isNow) ...[
                      const SizedBox(width: 8),
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(11)),
                        child: Text('الان', style: nvText(context, 11, w: FontWeight.w800, color: c.onBrand)),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      [if (timeOf(m).isNotEmpty) 'ساعت ${faDigits(timeOf(m))}', if (past) 'گذشته'].join('، '),
                      style: nvText(context, 12, color: c.muted),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text('تحویل‌شده', style: nvText(context, 13, color: c.muted))),
                    Text('${faDigits(served)} از ${faDigits(entitled)}', style: nvText(context, 13, w: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entitled == 0 ? 0 : (served / entitled).clamp(0, 1),
                      minHeight: 8,
                      color: past ? c.go : c.brand,
                      backgroundColor: c.field,
                    ),
                  ),
                  if (dup > 0 || not > 0) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      if (dup > 0) NvStatusChip(text: '${faDigits(dup)} تکراری', icon: Icons.repeat_rounded, bg: c.waitSoft, fg: c.wait),
                      if (not > 0) NvStatusChip(text: '${faDigits(not)} بدون حق', icon: Icons.block_rounded, bg: c.stopSoft, fg: c.stop),
                    ]),
                  ],
                ]),
              ),
            ),
          );
        }),
    ];
  }
}

class _Item {
  final IconData icon;
  final Color bg, fg;
  final String title, sub;
  final VoidCallback onTap;
  _Item(this.icon, this.bg, this.fg, this.title, this.sub, this.onTap);
}

class _AttentionCard extends StatelessWidget {
  final List<_Item> items;
  const _AttentionCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22), boxShadow: Nv.raised(c)),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: c.go),
                const SizedBox(width: 10),
                Expanded(child: Text('همه‌چیز رو به راه است', style: nvText(context, 15, w: FontWeight.w700))),
              ]),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                child: Row(children: [
                  Expanded(child: Text('نیاز به توجه', style: nvText(context, 15, w: FontWeight.w800))),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.waitSoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(faDigits(items.length), style: nvText(context, 13, w: FontWeight.w800, color: c.wait)),
                  ),
                ]),
              ),
              for (var i = 0; i < items.length; i++)
                InkWell(
                  onTap: items[i].onTap,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: i == items.length - 1 ? null : Border(bottom: BorderSide(color: c.lineSoft))),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: items[i].bg, borderRadius: BorderRadius.circular(Nv.r12)),
                        child: Icon(items[i].icon, size: 22, color: items[i].fg),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(items[i].title, style: nvText(context, 14, w: FontWeight.w800)),
                          if (items[i].sub.isNotEmpty)
                            Text(items[i].sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: nvText(context, 12, color: c.muted)),
                        ]),
                      ),
                      Icon(Icons.chevron_left_rounded, color: c.muted),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

class _Stats extends StatelessWidget {
  final Map<String, dynamic> totals;
  const _Stats({required this.totals});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    int n(String k) => (totals[k] as num? ?? 0).toInt();
    final total = n('attendees'), done = n('checked_in');
    Widget tile(String label, String value, String foot, {Color? footColor}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: nvText(context, 12, w: FontWeight.w600, color: c.muted)),
              Text(value, style: nvText(context, 26, w: FontWeight.w800, height: 1.3)),
              Text(foot, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 11, w: footColor == null ? FontWeight.w400 : FontWeight.w700, color: footColor ?? c.muted)),
            ]),
          ),
        );
    final free = n('reserve_cards_free');
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
        child: Row(children: [
          SizedBox.square(dimension: 64, child: NvRing(value: total == 0 ? 0 : done / total)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('پذیرش‌شده', style: nvText(context, 12, w: FontWeight.w600, color: c.muted)),
            Text.rich(TextSpan(children: [
              TextSpan(text: faDigits(done), style: nvText(context, 30, w: FontWeight.w800, height: 1.25)),
              TextSpan(text: ' از ${faDigits(total)}', style: nvText(context, 15, color: c.muted)),
            ])),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        tile('در محل', faDigits(n('walkins')), n('walkins_no_card') > 0 ? '${faDigits(n('walkins_no_card'))} بدون کارت' : 'ثبت‌نام در محل'),
        if (s.settings.usesCards) ...[
          const SizedBox(width: 10),
          tile('رزرو آزاد', faDigits(free), free < 3 ? 'کم است' : 'کارت رزرو', footColor: free < 3 ? c.wait : null),
        ],
      ]),
      if (n('onsite_due') > 0) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
          child: Row(children: [
            Icon(Icons.payments_rounded, color: c.brandText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تسویه‌ی روز اجرا', style: nvText(context, 12, w: FontWeight.w600, color: c.muted)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: moneyFa(n('onsite_settled')).replaceAll(' تومان', ''), style: nvText(context, 16, w: FontWeight.w800)),
                  TextSpan(text: ' از ${moneyFa(n('onsite_due'))}', style: nvText(context, 12, color: c.muted)),
                ])),
              ]),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// چند ردیف خاکستری به‌جای چرخان تنها، تا شکل صفحه پیش از رسیدن داده دیده شود.
class NvSkeletonList extends StatelessWidget {
  final int rows;
  const NvSkeletonList({super.key, this.rows = 5});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (var i = 0; i < rows; i++)
        Container(
          height: 64,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r18)),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r12))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(height: 12, width: 160, decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 10, width: 100, decoration: BoxDecoration(color: c.lineSoft, borderRadius: BorderRadius.circular(5))),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// خطا با «تلاش دوباره».
class NvErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String title;
  final String hint;
  const NvErrorState({super.key, required this.onRetry, this.title = 'به سرور نرسیدیم', this.hint = 'آدرس سایت یا اینترنت را بررسی کنید.'});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_rounded, size: 48, color: c.stop),
          const SizedBox(height: 10),
          Text(title, style: nvText(context, 18, w: FontWeight.w800)),
          Text(hint, textAlign: TextAlign.center, style: nvText(context, 14, color: c.muted)),
          const SizedBox(height: 14),
          NvSoftButton(label: 'تلاش دوباره', icon: Icons.refresh_rounded, onPressed: onRetry),
        ]),
      ),
    );
  }
}
