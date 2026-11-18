// پوسته‌ی ویندوز: سربرگ رنگی با تب‌ها (F1 تا F3) و نشانگر همگام‌سازی؛
// در پنجره‌ی باریک (طرح ۱۳) ناوبری پایین می‌آید.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../android/walkin.dart';
import '../main.dart';
import 'desk_checkin.dart';
import 'desk_meal.dart';
import 'desk_status.dart';
import 'scan_field.dart';

/// زیر این عرض، چیدمان باریک (یک ستون و ناوبری پایین).
const deskWideBreakpoint = 900.0;

class NvDeskShell extends StatefulWidget {
  const NvDeskShell({super.key});

  @override
  State<NvDeskShell> createState() => _NvDeskShellState();
}

class _NvDeskShellState extends State<NvDeskShell> {
  int _index = 0;
  bool _walkin = false;
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
    final wide = MediaQuery.sizeOf(context).width >= deskWideBreakpoint;
    final tabs = <(IconData, String, String)>[
      if (s.canCheckin) (Icons.how_to_reg_rounded, 'پذیرش', 'checkin'),
      if (s.canServe) (Icons.restaurant_rounded, 'پذیرایی', 'meal'),
      (Icons.insights_rounded, 'وضعیت', 'status'),
    ];
    final i = _index.clamp(0, tabs.length - 1);
    final kind = tabs[i].$3;
    final walkin = _walkin && kind == 'checkin';
    final attention = s.pending.isNotEmpty || s.rejected.isNotEmpty;

    void go(int v) {
      if (v >= tabs.length) return;
      setState(() {
        _index = v;
        _walkin = false;
      });
    }

    void openWalkin() {
      if (!s.canCheckin) return;
      if (!wide) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _NarrowWalkin(initialName: _query.text.trim())));
        return;
      }
      setState(() {
        _index = 0;
        _walkin = true;
      });
    }

    final page = switch (kind) {
      'checkin' => DeskCheckinTab(
          query: _query,
          wide: wide,
          walkin: walkin,
          onWalkin: openWalkin,
          onCloseWalkin: () => setState(() => _walkin = false),
        ),
      'meal' => DeskMealTab(wide: wide),
      _ => DeskStatusTab(wide: wide),
    };

    final header = wide
        ? Container(
            height: 68,
            color: c.brand,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 240),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(deviceLine(s), style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
                  Text(walkin ? 'ثبت‌نام در محل' : (s.eventName.isEmpty ? (s.eventCode ?? '') : s.eventName),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 19, w: FontWeight.w800, color: c.onBrand, height: 1.35)),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: walkin
                    ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        const NvKbd('Esc', onBrand: true),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() => _walkin = false),
                          child: Text('برگشت به پذیرش', style: nvText(context, 13, color: c.onBrand)),
                        ),
                      ])
                    : Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(Nv.r14)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            for (var k = 0; k < tabs.length; k++) ...[
                              if (k > 0) const SizedBox(width: 4),
                              _Tab(
                                icon: tabs[k].$1,
                                label: tabs[k].$2,
                                keyLabel: 'F${k + 1}',
                                selected: k == i,
                                badge: tabs[k].$3 == 'status' && attention && k != i,
                                onTap: () => go(k),
                              ),
                            ],
                          ]),
                        ),
                      ),
              ),
              if (!walkin) ...[const SizedBox(width: 20), NvSyncPill(showTime: true, onOpenStatus: () => go(tabs.length - 1))],
            ]),
          )
        : NvHeader(
            radius: 0,
            bottom: 14,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(deviceLine(s), style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
                  Text(s.eventName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 19, w: FontWeight.w800, color: c.onBrand)),
                ]),
              ),
              NvSyncPill(onOpenStatus: () => go(tabs.length - 1)),
            ]),
          );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => go(0),
        const SingleActivator(LogicalKeyboardKey.f2): () => go(1),
        const SingleActivator(LogicalKeyboardKey.f3): () => go(2),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): openWalkin,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => s.sync(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.bg,
          body: Column(children: [
            header,
            Expanded(child: KeyedSubtree(key: ValueKey(kind), child: page)),
          ]),
          bottomNavigationBar: wide
              ? null
              : Container(
                  decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                  child: SizedBox(
                    height: 60,
                    child: Row(children: [
                      for (var k = 0; k < tabs.length; k++)
                        Expanded(
                          child: InkWell(
                            onTap: () => go(k),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Badge(
                                isLabelVisible: tabs[k].$3 == 'status' && attention,
                                smallSize: 8,
                                backgroundColor: c.wait,
                                child: Icon(tabs[k].$1, size: 24, color: k == i ? c.brandText : c.muted),
                              ),
                              const SizedBox(height: 2),
                              Text(tabs[k].$2,
                                  style: nvText(context, 12, w: k == i ? FontWeight.w700 : FontWeight.w600, color: k == i ? c.brandText : c.muted)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final String keyLabel;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;
  const _Tab({required this.icon, required this.label, required this.keyLabel, required this.selected, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label ($keyLabel)',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Badge(
                isLabelVisible: badge,
                smallSize: 8,
                backgroundColor: c.waitSoft,
                child: Icon(icon, size: 22, color: selected ? c.brandText : c.onBrand),
              ),
              const SizedBox(width: 8),
              Text(label, style: nvText(context, 15, w: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? c.brandText : c.onBrand)),
              const SizedBox(width: 8),
              NvKbd(keyLabel, onBrand: !selected),
            ]),
          ),
        ),
      ),
    );
  }
}

/// ثبت‌نام در محل در پنجره‌ی باریک: صفحه‌ی کامل با همان پنل.
class _NarrowWalkin extends StatelessWidget {
  final String initialName;
  const _NarrowWalkin({required this.initialName});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(children: [
        const NvBackHeader(title: 'ثبت‌نام در محل'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NvWalkinScreen(panel: true, initialName: initialName, onClose: () => Navigator.of(context).maybePop()),
          ),
        ),
      ]),
    );
  }
}
