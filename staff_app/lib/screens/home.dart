import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
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
  // متن جستجوی پذیرش اینجا نگه داشته می‌شود تا با تعویض تب از بین نرود.
  final _checkinQuery = TextEditingController();

  @override
  void dispose() {
    _checkinQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final x = DaftarColors.of(context);
    final attention = store.pending.isNotEmpty || store.rejected.isNotEmpty;
    final statusIcon = Badge(
      isLabelVisible: attention,
      smallSize: 8,
      backgroundColor: x.wait,
      child: const Icon(Icons.insights_rounded),
    );
    final tabs = <({Widget page, NavigationDestination dest, String? title})>[
      if (store.canCheckin)
        (
          page: CheckinScreen(query: _checkinQuery),
          dest: const NavigationDestination(icon: Icon(Icons.how_to_reg_rounded), label: 'پذیرش'),
          title: null,
        ),
      if (store.canServe)
        (
          page: const MealScreen(),
          dest: const NavigationDestination(icon: Icon(Icons.restaurant_rounded), label: 'پذیرایی'),
          // نام وعده‌ی جاری همیشه در نوار بالا دیده می‌شود.
          title: store.selectedMeal == null ? 'پذیرایی' : 'پذیرایی — ${store.selectedMeal!.name}',
        ),
      (
        page: const StatusScreen(),
        dest: NavigationDestination(icon: statusIcon, label: 'وضعیت'),
        title: 'وضعیت',
      ),
    ];
    final i = _index.clamp(0, tabs.length - 1);
    final statusIndex = tabs.length - 1;
    final title = tabs[i].title ?? (store.eventName.isEmpty ? 'کنفرانس' : store.eventName);
    // اگر نیرو فقط یک تب کاری دارد، نوار پایین حذف می‌شود و «وضعیت» از نشانگر همگام‌سازی باز می‌شود.
    final showNav = tabs.length > 2;

    return Scaffold(
      appBar: AppBar(
        leading: i == statusIndex && tabs.length == 2
            ? IconButton(
                tooltip: 'برگشت',
                icon: const BackButtonIcon(),
                onPressed: () => setState(() => _index = 0),
              )
            : null,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          SyncPill(onOpenStatus: () => setState(() => _index = statusIndex)),
          const SizedBox(width: DaftarSize.space2),
        ],
      ),
      // فقط صفحه‌ی فعال ساخته می‌شود تا دوربین پذیرایی در پس‌زمینه روشن نماند.
      body: KeyedSubtree(key: ValueKey(i), child: tabs[i].page),
      bottomNavigationBar: showNav
          ? NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => _index = v),
              destinations: [for (final t in tabs) t.dest],
            )
          : null,
    );
  }
}

/// نشانگر همگام‌سازی: همیشه دیده می‌شود و با متن می‌گوید چه خبر است.
/// آفلاین خطا نیست و خنثی نمایش داده می‌شود؛ قرمز فقط برای «دسترسی باطل شد».
class SyncPill extends StatefulWidget {
  final VoidCallback? onOpenStatus;
  const SyncPill({super.key, this.onOpenStatus});

  @override
  State<SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<SyncPill> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _syncNow() async {
    final store = StoreScope.read(context);
    final before = store.pending.length;
    await store.sync();
    if (!mounted) return;
    final after = store.pending.length;
    final String msg;
    if (store.needsLogin) {
      msg = 'دسترسی این گوشی باطل شده. دوباره وارد شوید.';
    } else if (!store.online) {
      msg = 'اینترنت وصل نیست؛ کارها روی گوشی امن است.';
    } else if (after > 0) {
      msg = '${faDigits(after)} کار هنوز در صف است.';
    } else if (before > 0) {
      msg = '${faDigits(before)} کار ارسال شد.';
    } else {
      msg = 'همه‌چیز ارسال شده است.';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final n = store.pending.length;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (store.syncing && !reduceMotion) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }

    final IconData icon;
    final String label;
    final Color bg, fg, iconColor;
    final String semantics;
    if (store.needsLogin) {
      (icon, label, bg, fg, iconColor) = (Icons.lock_rounded, 'دسترسی باطل شد', x.stopSoft, x.stop, x.stop);
      semantics = 'دسترسی این گوشی باطل شده';
    } else if (store.syncing) {
      (icon, label, bg, fg, iconColor) = (Icons.sync_rounded, 'در حال ارسال…', x.surface, x.ink, x.stamp);
      semantics = 'در حال همگام‌سازی';
    } else if (!store.online) {
      (icon, label, bg, fg, iconColor) =
          (Icons.cloud_off_rounded, n > 0 ? 'آفلاین، ${faDigits(n)} در صف' : 'آفلاین', x.sunken, x.ink, x.ink);
      semantics = n > 0 ? 'آفلاین، ${faDigits(n)} کار در صف' : 'آفلاین';
    } else if (n > 0) {
      (icon, label, bg, fg, iconColor) = (Icons.cloud_upload_rounded, '${faDigits(n)} در صف', x.waitSoft, x.wait, x.wait);
      semantics = '${faDigits(n)} کار در صف';
    } else {
      final last = store.lastSyncOk;
      final ago = last == null ? null : DateTime.now().difference(last);
      final text = last == null
          ? 'ارسال شد'
          : (ago!.inMinutes >= 5 ? 'آخرین ارسال ${faDigits(ago.inMinutes)} دقیقه پیش' : 'ارسال شد، ${hm(last)}');
      (icon, label, bg, fg, iconColor) = (Icons.cloud_done_rounded, text, x.surface, x.ink, x.go);
      semantics = text;
    }

    return Semantics(
      button: true,
      label: '$semantics. برای همگام‌سازی لمس کنید',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: bg == x.surface ? x.line : bg)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: store.syncing ? widget.onOpenStatus : _syncNow,
          onLongPress: widget.onOpenStatus,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RotationTransition(
                    turns: _spin,
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
