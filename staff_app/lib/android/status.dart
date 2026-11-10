// وضعیت روی اندروید: همگام‌سازی، کارهای ردشده (دیدم / خبر به مدیر)، دریافت دوباره، خروج امن.
import 'package:flutter/material.dart';

import '../brand.dart';
import '../errors.dart';
import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart' show tabularFigures;
import 'meal.dart' show nvMealLabel;
import 'nv_theme.dart';
import 'nv_widgets.dart';

class NvStatusTab extends StatefulWidget {
  const NvStatusTab({super.key});

  @override
  State<NvStatusTab> createState() => _NvStatusTabState();
}

class _NvStatusTabState extends State<NvStatusTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    final s = StoreScope.read(context);
    final m = ScaffoldMessenger.of(context);
    setState(() => _refreshing = true);
    try {
      await s.sync();
      await s.refreshSnapshot();
      m.showSnackBar(const SnackBar(content: Text('لیست به‌روز شد.')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _report(Map<String, dynamic> item) async {
    final s = StoreScope.read(context);
    final text = await showNvSheet<String>(context, (c) => _ReportSheet(item: item));
    if (text != null && text.trim().isNotEmpty && mounted) {
      s.reportToAdmin(item, text.trim());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای مدیر فرستاده شد.')));
    }
  }

  Future<void> _logout() async {
    final s = StoreScope.read(context);
    final ok = await showNvSheet<bool>(context, (c) => const _LogoutSheet());
    if (ok == true) await s.logout();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final n = s.pending.length;

    Widget info(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(child: Text(k, style: nvText(context, 14, color: c.muted))),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: nvText(context, 14, w: FontWeight.w700, color: color).copyWith(fontFeatures: tabularFigures)),
            ),
          ]),
        );

    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(t, style: nvText(context, 15, w: FontWeight.w800)),
        );

    final (IconData syncIcon, Color syncColor, String syncTitle) = s.needsLogin
        ? (Icons.lock_rounded, c.stop, 'دسترسی این گوشی باطل شد')
        : !s.online
            ? (Icons.cloud_off_rounded, c.muted, 'آفلاین')
            : n > 0
                ? (Icons.cloud_upload_rounded, c.wait, '${faDigits(n)} کار در صف')
                : (Icons.cloud_done_rounded, c.go, 'همه‌چیز ارسال شد');

    return Column(children: [
      NvHeader(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(deviceLine(s), style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
              Text('وضعیت', style: nvText(context, 22, w: FontWeight.w800, color: c.onBrand, height: 1.5)),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            NvCard(
              raised: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(syncIcon, color: syncColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: Text(syncTitle, style: nvText(context, 17, w: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                Text(
                  [
                    if (n > 0) s.pendingSummary(),
                    s.lastSyncOk == null ? 'هنوز ارسالی انجام نشده' : 'آخرین ارسال ساعت ${hm(s.lastSyncOk!)}',
                  ].join(' · '),
                  style: nvText(context, 13, color: c.muted),
                ),
                if (!s.online && !s.needsLogin)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('اپ بدون اینترنت هم کار می‌کند؛ کارها روی گوشی امن است و با اینترنت خودکار ارسال می‌شود.',
                        style: nvText(context, 13, color: c.muted)),
                  ),
                const SizedBox(height: 14),
                NvButton(
                  label: s.syncing ? 'در حال ارسال…' : 'همگام‌سازی الان',
                  icon: Icons.sync_rounded,
                  busy: s.syncing,
                  height: 54,
                  onPressed: s.syncing || s.needsLogin ? null : s.sync,
                ),
              ]),
            ),
            if (s.rejected.isNotEmpty) ...[
              title('کارهایی که سرور نپذیرفت'),
              for (final r in s.rejected.reversed.take(20).toList())
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RejectedCard(
                    item: r,
                    onDismiss: () => s.dismissRejected(r),
                    onReport: () => _report(r),
                  ),
                ),
            ],
            title('این رویداد'),
            NvCard(
              child: Column(children: [
                info('رویداد', s.eventName.isEmpty ? '—' : s.eventName),
                info('کد رویداد', s.eventCode ?? '—'),
                info('شرکت‌کننده‌ها', faDigits(s.attendees.length)),
                info('پذیرش‌شده', faDigits(s.checkins.length)),
                if (s.usesCards) info('کارت رزرو آزاد', faDigits(s.freeReserveCards.length)),
                for (final m in s.meals)
                  info(nvMealLabel(m, s.meals), '${faDigits(s.servedCount(m.id))} از ${faDigits(s.entitledCount(m))}'),
              ]),
            ),
            title('این گوشی'),
            NvCard(
              child: Column(children: [
                info('نیرو', s.staffName.isEmpty ? '—' : s.staffName),
                info('نام گوشی', s.deviceLabel.isEmpty ? '—' : s.deviceLabel),
                info('سایت', Uri.tryParse(s.server ?? '')?.host ?? '—'),
              ]),
            ),
            const SizedBox(height: 16),
            NvSoftButton(
              label: _refreshing ? 'در حال دریافت…' : 'دریافت دوباره‌ی لیست',
              icon: Icons.download_rounded,
              onPressed: _refreshing || s.needsLogin ? null : _refresh,
            ),
            const SizedBox(height: 10),
            NvSoftButton(
              label: 'خروج از رویداد',
              icon: Icons.logout_rounded,
              iconColor: c.stop,
              fg: c.stop,
              border: c.stop.withValues(alpha: .4),
              onPressed: _logout,
            ),
            const SizedBox(height: 28),
            Center(child: Text('$appName · $appVersionLabel', style: nvText(context, 12, color: c.muted))),
            Center(child: Text(makerFull, style: nvText(context, 12, color: c.muted))),
          ],
        ),
      ),
    ]);
  }
}

class _RejectedCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDismiss, onReport;
  const _RejectedCard({required this.item, required this.onDismiss, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StoreScope.of(context);
    final at = DateTime.tryParse('${item['at'] ?? ''}');
    final who = s.attendees[item['attendee_id']?.toString()];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.waitSoft, borderRadius: BorderRadius.circular(Nv.r16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_rounded, color: c.wait, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item['reason'] ?? 'دلیل نامشخص'}', style: nvText(context, 14, w: FontWeight.w700, color: c.waitInk)),
              Text(
                [if (who != null) who.fullName, if (at != null) 'ساعت ${hm(at)}'].join(' · '),
                style: nvText(context, 12, color: c.waitInk),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: c.waitInk, minimumSize: const Size.fromHeight(44)),
              onPressed: onDismiss,
              child: const Text('دیدم، پاک کن'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.wait,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: onReport,
              icon: const Icon(Icons.campaign_rounded, size: 18),
              label: const Text('خبر به مدیر'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ReportSheet({required this.item});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('خبر به مدیر', style: nvText(context, 20, w: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('«${widget.item['reason'] ?? ''}» — چه شد؟ متن در گزارش مدیر دیده می‌شود.',
            style: nvText(context, 13, color: c.muted)),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
          decoration: const InputDecoration(hintText: 'مثلاً: کارت را اشتباه به نفر دیگری دادیم'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        NvButton(
          label: 'بفرست',
          icon: Icons.send_rounded,
          onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text),
        ),
      ]),
    );
  }
}

class _LogoutSheet extends StatelessWidget {
  const _LogoutSheet();

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final n = s.pending.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('خروج از رویداد', style: nvText(context, 20, w: FontWeight.w800)),
        const SizedBox(height: 12),
        if (n == 0)
          Text('همه‌ی کارها ارسال شده. داده‌ی رویداد از این گوشی پاک می‌شود.', style: nvText(context, 14, color: c.muted))
        else ...[
          NvBanner(
            tone: NvTone.stop,
            title: '${faDigits(n)} کار هنوز به سرور نرسیده',
            text: '${s.pendingSummary()}. با خروج این کارها برای همیشه از بین می‌روند.',
          ),
          if (!s.online) ...[
            const SizedBox(height: 10),
            const NvBanner(
              tone: NvTone.neutral,
              icon: Icons.cloud_off_rounded,
              text: 'گوشی آفلاین است. اول اینترنت را وصل کنید تا کارها ارسال شوند.',
            ),
          ],
        ],
        const SizedBox(height: 18),
        if (n > 0) ...[
          NvButton(
            label: 'برگرد و همگام‌سازی کن',
            icon: Icons.sync_rounded,
            onPressed: () {
              s.sync();
              Navigator.pop(context, false);
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.stop, minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('با این حال خارج شو و ${faDigits(n)} کار را از دست بده'),
          ),
        ] else ...[
          NvButton(label: 'خروج', icon: Icons.logout_rounded, color: c.stop, onPressed: () => Navigator.pop(context, true)),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
        ],
      ]),
    );
  }
}
