import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import 'checkin.dart';
import 'meal.dart';
import 'status.dart';
import 'walkin.dart';
import '../widgets/scan_input.dart';

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
    final theme = Theme.of(context);
    final attention = store.pending.isNotEmpty || store.rejected.isNotEmpty;
    final statusIcon = Badge(
      isLabelVisible: attention,
      smallSize: 8,
      backgroundColor: x.wait,
      child: const Icon(Icons.insights_rounded),
    );
    final tabs = <({Widget page, String label, Widget icon, String? title})>[
      if (store.canCheckin)
        (
          page: CheckinScreen(query: _checkinQuery),
          label: 'پذیرش',
          icon: const Icon(Icons.how_to_reg_rounded),
          title: null,
        ),
      if (store.canServe)
        (
          page: const MealScreen(),
          label: 'پذیرایی',
          icon: const Icon(Icons.restaurant_rounded),
          // نام وعده‌ی جاری همیشه در نوار بالا دیده می‌شود.
          title: store.selectedMeal == null ? 'پذیرایی' : 'پذیرایی — ${store.selectedMeal!.name}',
        ),
      (page: const StatusScreen(), label: 'وضعیت', icon: statusIcon, title: 'وضعیت'),
    ];
    final i = _index.clamp(0, tabs.length - 1);
    final statusIndex = tabs.length - 1;
    final title = tabs[i].title ?? (store.eventName.isEmpty ? appName : store.eventName);
    // از ۶۰۰px به بالا (ویندوز، تبلت): ناوبری سه‌گزینه‌ای بالا با F1 تا F3 به‌جای نوار پایین.
    final wide = MediaQuery.sizeOf(context).width >= 600;
    // اگر نیرو فقط یک تب کاری دارد، نوار پایین حذف می‌شود و «وضعیت» از نشانگر همگام‌سازی باز می‌شود.
    final showNav = tabs.length > 2;
    void go(int v) {
      if (v < tabs.length) setState(() => _index = v);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => go(0),
        const SingleActivator(LogicalKeyboardKey.f2): () => go(1),
        const SingleActivator(LogicalKeyboardKey.f3): () => go(2),
        const SingleActivator(LogicalKeyboardKey.f4): () => ScanFocus.request(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (!store.canCheckin) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WalkinScreen(initialName: _checkinQuery.text.trim()),
          ));
        },
      },
      child: Scaffold(
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
          bottom: wide && showNav
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(DaftarSize.space4, 0, DaftarSize.space4, DaftarSize.space2),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          for (var k = 0; k < tabs.length; k++)
                            ButtonSegment(
                              value: k,
                              icon: tabs[k].icon,
                              label: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(tabs[k].label),
                                const SizedBox(width: DaftarSize.space2),
                                Text('F${k + 1}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: k == i ? x.onAction.withValues(alpha: .7) : x.inkMuted,
                                    )),
                              ]),
                            ),
                        ],
                        selected: {i},
                        onSelectionChanged: (v) => go(v.first),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        // فقط صفحه‌ی فعال ساخته می‌شود تا دوربین پذیرایی در پس‌زمینه روشن نماند.
        body: KeyedSubtree(key: ValueKey(i), child: tabs[i].page),
        bottomNavigationBar: showNav && !wide
            ? NavigationBar(
                selectedIndex: i,
                onDestinationSelected: go,
                destinations: [for (final t in tabs) NavigationDestination(icon: t.icon, label: t.label)],
              )
            : null,
      ),
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
