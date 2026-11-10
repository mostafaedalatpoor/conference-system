// ریشه‌ی ظاهر تازه‌ی اندروید: ورود، دسترسی باطل‌شده، و پوسته با ناوبری شناور.
import 'package:flutter/material.dart';

import '../main.dart';
import 'checkin.dart';
import 'login.dart';
import 'meal.dart';
import 'nv_theme.dart';
import 'status.dart';
import 'nv_widgets.dart';

class NvRoot extends StatelessWidget {
  const NvRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    if (!s.loaded) {
      return Scaffold(
        backgroundColor: NvColors.of(context).brand,
        body: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!s.loggedIn) return const NvLoginScreen();
    // توکن باطل شده ولی داده و صف روی گوشی هست: فقط PIN دوباره.
    if (s.needsLogin) return const NvRevokedScreen();
    return const NvShell();
  }
}

class NvShell extends StatefulWidget {
  const NvShell({super.key});

  @override
  State<NvShell> createState() => _NvShellState();
}

class _NvShellState extends State<NvShell> {
  int _index = 0;
  // متن جستجوی پذیرش با تعویض تب از بین نمی‌رود.
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    void openStatus(int i) => setState(() => _index = i);
    final tabs = <(IconData, String, Widget Function(int statusIndex))>[
      if (s.canCheckin)
        (Icons.how_to_reg_rounded, 'پذیرش', (si) => NvCheckinTab(query: _query, onOpenStatus: () => openStatus(si))),
      if (s.canServe) (Icons.restaurant_rounded, 'پذیرایی', (si) => NvMealTab(onOpenStatus: () => openStatus(si))),
      (Icons.insights_rounded, 'وضعیت', (_) => const NvStatusTab()),
    ];
    final statusIndex = tabs.length - 1;
    final i = _index.clamp(0, statusIndex);
    final attention = s.pending.isNotEmpty || s.rejected.isNotEmpty;

    return PopScope(
      // دکمه‌ی برگشت از تب‌های دیگر اول به تب کاری اول برمی‌گردد.
      canPop: i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        extendBody: true,
        // فقط تب فعال ساخته می‌شود تا دوربین پذیرایی در پس‌زمینه روشن نماند.
        body: KeyedSubtree(key: ValueKey(i), child: tabs[i].$3(statusIndex)),
        bottomNavigationBar: NvNavBar(
          index: i,
          onTap: (v) => setState(() => _index = v),
          items: [
            for (var k = 0; k < tabs.length; k++) (tabs[k].$1, tabs[k].$2, k == statusIndex && attention),
          ],
        ),
      ),
    );
  }
}
