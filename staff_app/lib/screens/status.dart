import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
            style: n > 0 ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
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

    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 150, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v, style: TextStyle(color: color, fontWeight: color != null ? FontWeight.w600 : null))),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        row('نیرو', store.staffName),
        row('گوشی', store.deviceLabel.isEmpty ? '—' : store.deviceLabel),
        row('رویداد', '${store.eventName} (${store.eventCode ?? ''})'),
        const Divider(),
        row('اتصال', store.online ? 'وصل' : 'آفلاین', color: store.online ? Colors.green : Colors.red),
        row('آخرین همگام‌سازی', store.lastSyncOk == null ? '—' : hm(store.lastSyncOk!)),
        row('کارهای ارسال‌نشده', faDigits(store.pending.length),
            color: store.pending.isEmpty ? null : Colors.orange),
        if (store.lastError != null) row('پیام', store.lastError!, color: theme.colorScheme.error),
        const Divider(),
        row('شرکت‌کننده‌ها', faDigits(store.attendees.length)),
        row('پذیرش‌شده', faDigits(store.checkins.length)),
        row('کارت رزرو آزاد', faDigits(store.freeReserveCards.length)),
        for (final m in store.meals)
          row(m.name, '${faDigits(store.servedCount(m.id))} از ${faDigits(store.entitledCount(m))}'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: store.syncing ? null : store.sync,
          icon: const Icon(Icons.sync),
          label: const Text('همگام‌سازی الان'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _refreshing ? null : _refresh,
          icon: const Icon(Icons.download),
          label: const Text('دریافت دوباره‌ی کل لیست'),
        ),
        if (store.rejected.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('کارهایی که سرور نپذیرفت', style: theme.textTheme.titleSmall),
          for (final r in store.rejected.reversed.take(20))
            Text('• ${r['reason']} ${r['uuid'] ?? ''}', style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 32),
        TextButton(onPressed: _logout, child: const Text('خروج از این رویداد', style: TextStyle(color: Colors.red))),
      ],
    );
  }
}
