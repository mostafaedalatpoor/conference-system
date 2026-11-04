import 'package:flutter/material.dart';

import '../main.dart';
import 'checkin.dart';
import 'meal.dart';
import 'status.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tabs = <({Widget page, NavigationDestination dest})>[
      if (store.canCheckin)
        (page: const CheckinScreen(), dest: const NavigationDestination(icon: Icon(Icons.how_to_reg), label: 'پذیرش')),
      if (store.canServe)
        (page: const MealScreen(), dest: const NavigationDestination(icon: Icon(Icons.restaurant), label: 'پذیرایی')),
      (page: const StatusScreen(), dest: const NavigationDestination(icon: Icon(Icons.sync), label: 'وضعیت')),
    ];
    final i = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(store.eventName.isEmpty ? 'کنفرانس' : store.eventName, overflow: TextOverflow.ellipsis),
        actions: const [SyncBadge(), SizedBox(width: 8)],
      ),
      // فقط صفحه‌ی فعال ساخته می‌شود تا دوربین پذیرایی در پس‌زمینه روشن نماند.
      body: KeyedSubtree(key: ValueKey(i), child: tabs[i].page),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: [for (final t in tabs) t.dest],
      ),
    );
  }
}

/// نشانگر کوچک وضعیت شبکه و تعداد کارهای ارسال‌نشده.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final n = store.pending.length;
    final color = store.online ? (n == 0 ? Colors.green : Colors.orange) : scheme.error;
    final icon = store.syncing
        ? Icons.sync
        : (store.online ? (n == 0 ? Icons.cloud_done : Icons.cloud_upload) : Icons.cloud_off);
    return InkWell(
      onTap: store.sync,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            if (n > 0) ...[
              const SizedBox(width: 4),
              Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}
