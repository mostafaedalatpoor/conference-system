import 'package:flutter/material.dart';

import '../errors.dart';
import '../brand.dart';
import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    final store = StoreScope.read(context);
    setState(() => _refreshing = true);
    try {
      await store.sync();
      await store.refreshSnapshot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لیست به‌روز شد.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    final store = StoreScope.read(context);
    final n = store.pending.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('خروج از رویداد'),
        content: Text(n > 0
            ? '${faDigits(n)} کار هنوز به سرور نرسیده و با خروج از بین می‌رود. اول اینترنت را وصل کنید و همگام‌سازی کنید.'
            : 'داده‌ی رویداد از این گوشی پاک می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(
            style: n > 0 ? daftarDangerStyle(c) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(n > 0 ? 'با این حال خارج شو' : 'خروج'),
          ),
        ],
      ),
    );
    if (ok == true) await store.logout();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final x = DaftarColors.of(context);
    final n = store.pending.length;

    Widget row(String k, String v, {Color? color, IconData? icon}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 150, child: Text(k, style: theme.textTheme.bodyMedium?.copyWith(color: x.inkMuted))),
            if (icon != null) ...[Icon(icon, size: 18, color: color ?? x.ink), const SizedBox(width: 6)],
            Expanded(
              child: Text(
                v,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: color != null ? FontWeight.w600 : null,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ]),
        );

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: DaftarSize.space4),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(DaftarSize.space4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: DaftarSize.space2),
                ...children,
              ]),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(DaftarSize.space4),
      children: [
        // آفلاین خطا نیست: پیام اصلی خنثی است و فقط باطل‌شدن دسترسی قرمز است.
        if (store.needsLogin)
          const Padding(
            padding: EdgeInsets.only(bottom: DaftarSize.space4),
            child: Notice(tone: NoticeTone.stop, text: 'دسترسی این گوشی باطل شده. دوباره وارد شوید.'),
          )
        else if (!store.online)
          Padding(
            padding: const EdgeInsets.only(bottom: DaftarSize.space4),
            child: Notice(
              tone: NoticeTone.neutral,
              icon: Icons.cloud_off_rounded,
              title: 'آفلاین',
              text: n > 0
                  ? 'اپ بدون اینترنت هم کار می‌کند. ${faDigits(n)} کار روی گوشی امن است و با اینترنت خودکار ارسال می‌شود.'
                  : 'اپ بدون اینترنت هم کار می‌کند.',
            ),
          )
        else if (n > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: DaftarSize.space4),
            child: Notice(
              tone: NoticeTone.wait,
              icon: Icons.cloud_upload_rounded,
              text: '${faDigits(n)} کار در صف؛ با اینترنت خودکار ارسال می‌شود.',
            ),
          ),
        section('همگام‌سازی', [
          row('اتصال', store.online ? 'وصل' : 'آفلاین',
              icon: store.online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: store.online ? x.go : x.ink),
          row('آخرین همگام‌سازی', store.lastSyncOk == null ? '—' : hm(store.lastSyncOk!)),
          row('کارهای ارسال‌نشده', faDigits(n), color: n == 0 ? null : x.wait),
          if (store.lastError != null && !store.needsLogin)
            Padding(
              padding: const EdgeInsets.only(top: DaftarSize.space1),
              child: Text(store.lastError!, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
            ),
          const SizedBox(height: DaftarSize.space3),
          FilledButton.icon(
            style: daftarWideStyle(context),
            onPressed: store.syncing ? null : store.sync,
            icon: const Icon(Icons.sync_rounded),
            label: Text(store.syncing ? 'در حال ارسال…' : 'همگام‌سازی الان'),
          ),
          const SizedBox(height: DaftarSize.space2),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(DaftarSize.tapLg)),
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.download_rounded),
            label: Text(_refreshing ? 'در حال دریافت…' : 'دریافت دوباره‌ی کل لیست'),
          ),
        ]),
        section('آمار این رویداد', [
          row('شرکت‌کننده‌ها', faDigits(store.attendees.length)),
          row('پذیرش‌شده', faDigits(store.checkins.length)),
          row('کارت رزرو آزاد', faDigits(store.freeReserveCards.length)),
          for (final m in store.meals)
            row(m.name, '${faDigits(store.servedCount(m.id))} از ${faDigits(store.entitledCount(m))}'),
        ]),
        section('این گوشی', [
          row('نیرو', store.staffName),
          row('گوشی', store.deviceLabel.isEmpty ? '—' : store.deviceLabel),
          row('رویداد', '${store.eventName} (${store.eventCode ?? ''})'),
        ]),
        if (store.rejected.isNotEmpty)
          section('کارهایی که سرور نپذیرفت', [
            for (final r in store.rejected.reversed.take(20))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DaftarSize.space1),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_rounded, size: 18, color: x.wait),
                  const SizedBox(width: DaftarSize.space2),
                  Expanded(
                    child: Text(
                      [
                        '${r['reason'] ?? 'دلیل نامشخص'}',
                        if (r['at'] != null && DateTime.tryParse('${r['at']}') != null)
                          'ساعت ${hm(DateTime.parse('${r['at']}'))}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ]),
              ),
          ]),
        const SizedBox(height: DaftarSize.space3),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: x.stop),
          onPressed: _logout,
          child: const Text('خروج از این رویداد'),
        ),
        const SizedBox(height: DaftarSize.space4),
        const AboutCard(
          appName: appName,
          appNameLatin: appNameLatin,
          version: appVersionLabel,
          maker: makerFull,
          website: makerWebsite,
        ),
      ],
    );
  }
}
