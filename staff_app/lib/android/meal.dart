// پذیرایی روی اندروید (طرح ۱۲ تا ۱۸): دوربین با کارت نتیجه، مجوز شفاهی، جستجوی نام، انتخاب وعده، اجازه‌ی دوربین.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../store.dart';
import '../theme/widgets.dart' show verdictHaptic;
import 'checkin.dart' show NvCornersPainter;
import 'nv_theme.dart';
import 'nv_widgets.dart';

const _weekdays = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه', 'یکشنبه'];
String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
bool _isToday(Meal m) => m.day == null || m.day!.isEmpty || m.day!.startsWith(_iso(DateTime.now()));
String _weekday(Meal m) {
  final d = DateTime.tryParse(m.day ?? '');
  return d == null ? 'همه‌ی روزها' : _weekdays[d.weekday - 1];
}

/// نام وعده برای فهرست‌ها؛ اگر هم‌نام دیگری هست، روز هفته کنارش می‌آید.
String nvMealLabel(Meal m, List<Meal> all) =>
    all.where((o) => o.name == m.name).length > 1 && m.day != null ? '${m.name} ${_weekday(m)}' : m.name;

enum _V { ok, duplicate, notEntitled, invalid }

class _Verdict {
  final _V kind;
  final String title, name, detail;
  final Attendee? a;
  final int seq;
  _Verdict(this.kind, this.title, this.name, this.detail, this.seq, [this.a]);
}

class NvMealTab extends StatefulWidget {
  final VoidCallback onOpenStatus;
  const NvMealTab({super.key, required this.onOpenStatus});

  @override
  State<NvMealTab> createState() => _NvMealTabState();
}

class _NvMealTabState extends State<NvMealTab> with SingleTickerProviderStateMixin {
  static int? _confirmedOtherDay;
  MobileScannerController? _cam;
  MobileScannerController get _controller => _cam ??= MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  late final AnimationController _life = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  _Verdict? _v;
  int _seq = 0;
  String? _lastToken;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) setState(() => _v = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSelect());
  }

  @override
  void dispose() {
    _life.dispose();
    _cam?.dispose();
    super.dispose();
  }

  /// وعده‌ی «الان» امروز خودکار انتخاب می‌شود؛ وعده‌ی مانده از روز دیگر با پرسش عوض می‌شود.
  Future<void> _autoSelect() async {
    if (!mounted) return;
    final s = StoreScope.read(context);
    final cur = s.selectedMeal;
    if (cur != null && (_isToday(cur) || cur.id == _confirmedOtherDay)) return;
    final now = s.currentMealFor(DateTime.now());
    if (cur == null && now != null) {
      s.selectMeal(now.id);
      return;
    }
    if (s.meals.isEmpty) return;
    await _openPicker(stale: cur != null);
  }

  Future<void> _openPicker({bool stale = false}) async {
    final s = StoreScope.read(context);
    final picked = await showNvSheet<Meal>(context, (c) => _MealPicker(stale: stale, current: s.selectedMeal));
    if (picked == null || !mounted) return;
    if (!_isToday(picked)) _confirmedOtherDay = picked.id;
    s.selectMeal(picked.id);
    setState(() => _v = null);
  }

  void _show(_Verdict v) {
    setState(() => _v = v);
    verdictHaptic(v.kind == _V.ok);
    _life.duration = Duration(seconds: v.kind == _V.notEntitled ? 8 : 4);
    _life.forward(from: 0);
  }

  void _evaluate(AppStore s, Attendee a, Meal m, {String? overrideBy}) {
    _seq++;
    final c = s.checkMeal(a, m);
    final role = [s.roleName(a.roleId), if (s.cardOf(a.id) != null) 'کارت ${faDigits(s.cardOf(a.id)!.serial)}'].where((e) => e.isNotEmpty).join(' · ');
    if (overrideBy != null) {
      s.serveMeal(a, m, overrideBy: overrideBy);
      _show(_Verdict(_V.ok, 'تحویل با مجوز شفاهی', a.displayName, 'اجازه: $overrideBy', _seq, a));
      return;
    }
    switch (c.verdict) {
      case MealVerdict.ok:
        s.serveMeal(a, m);
        _show(_Verdict(_V.ok, 'مجاز · تحویل شود', a.displayName, role, _seq, a));
      case MealVerdict.duplicate:
        final by = _servedBy(s, a, m);
        _show(_Verdict(_V.duplicate, 'قبلاً گرفته', a.displayName, ['ساعت ${faDigits(hm(c.previousAt!))}', if (by != null) by].join(' · '), _seq, a));
      case MealVerdict.notEntitled:
        _show(_Verdict(_V.notEntitled, 'این وعده شامل او نیست', a.displayName, '${s.typeName(a.registrationTypeId)} · ${_rule(s, m)}', _seq, a));
    }
  }

  String? _servedBy(AppStore s, Attendee a, Meal m) {
    for (final e in [...s.serverLog, ...s.pending]) {
      if (e.kind == 'meal_served' && e.attendeeId == a.id && e.mealId == m.id) {
        return e.staffId == null ? null : s.staffNames[e.staffId];
      }
    }
    return null;
  }

  String _rule(AppStore s, Meal m) {
    final names = [for (final t in s.types) if (m.typeIds.contains(t.id)) t.name, for (final r in s.roles) if (m.roleIds.contains(r.id)) r.name];
    return names.isEmpty ? '${m.name} برای گروه خاصی است' : '${m.name} فقط برای ${names.join(' و ')}';
  }

  void _onDetect(BarcodeCapture cap) {
    final s = StoreScope.read(context);
    final m = s.selectedMeal;
    if (m == null) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final token = tokenFromScan(raw);
      final now = DateTime.now();
      if ((token ?? raw) == _lastToken && now.difference(_lastAt).inSeconds < 5) return;
      _lastToken = token ?? raw;
      _lastAt = now;
      if (token == null) {
        _seq++;
        _show(_Verdict(_V.invalid, 'QR ناشناخته', 'این کد مال کارت کنفرانس نیست.', '', _seq));
        return;
      }
      final a = s.attendeeForToken(token);
      if (a == null) {
        _seq++;
        _show(_Verdict(_V.invalid, 'کارت نامعتبر', s.cards.containsKey(token) ? 'کارت رزرو به کسی وصل نشده.' : 'این کارت در لیست نیست.', '', _seq));
        return;
      }
      _evaluate(s, a, m);
      return;
    }
  }

  Future<void> _override(Attendee a, Meal m) async {
    _life.stop();
    final by = await showNvSheet<String>(context, (c) => _OverrideSheet(a: a, meal: m));
    if (!mounted) return;
    if (by == null || by.trim().isEmpty) {
      _life.forward();
      return;
    }
    _evaluate(StoreScope.read(context), a, m, overrideBy: by.trim());
  }

  Future<void> _byName(Meal m) async {
    final r = await Navigator.of(context).push<(Attendee, String?)>(MaterialPageRoute(builder: (_) => NvMealByNamePage(meal: m)));
    if (r == null || !mounted) return;
    _lastToken = null;
    _evaluate(StoreScope.read(context), r.$1, m, overrideBy: r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final m = s.selectedMeal;
    final served = m == null ? 0 : s.servedCount(m.id);
    final entitled = m == null ? 0 : s.entitledCount(m);

    final header = NvHeader(
      radius: 28,
      bottom: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: s.meals.isEmpty ? null : () => _openPicker(),
              child: Row(children: [
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m == null ? 'وعده انتخاب نشده' : 'وعده‌ی جاری · ${_isToday(m) ? 'امروز' : _weekday(m)}',
                        style: nvText(context, 12, color: Colors.white.withValues(alpha: .85))),
                    Text(m?.name ?? 'پذیرایی', maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 24, w: FontWeight.w800, color: Colors.white, height: 1.4)),
                  ]),
                ),
                if (s.meals.isNotEmpty) const Icon(Icons.expand_more_rounded, size: 24, color: Colors.white),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          NvSyncPill(onOpenStatus: widget.onOpenStatus),
        ]),
        if (m != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('تحویل‌شده', style: nvText(context, 13, w: FontWeight.w600, color: Colors.white.withValues(alpha: .9)))),
            Text('${faDigits(served)} از ${faDigits(entitled)}', style: nvText(context, 13, w: FontWeight.w600, color: Colors.white)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: entitled == 0 ? 0 : (served / entitled).clamp(0, 1),
              minHeight: 8,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .22),
            ),
          ),
        ],
      ]),
    );

    if (s.meals.isEmpty || m == null) {
      return Column(children: [
        header,
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
            NvEmpty(
              icon: Icons.restaurant_rounded,
              title: s.meals.isEmpty ? 'وعده‌ای تعریف نشده' : 'وعده را انتخاب کنید',
              hint: s.meals.isEmpty ? 'مدیر باید در اپ مدیریت وعده‌ها را بسازد.' : null,
            ),
            if (s.meals.isNotEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: NvButton(label: 'انتخاب وعده', onPressed: () => _openPicker())),
          ]),
        ),
      ]);
    }

    if (!s.cameraScan) {
      return Column(children: [
        header,
        Expanded(child: NvMealByNameBody(meal: m, onDeliver: (a, by) => _evaluate(s, a, m, overrideBy: by), verdict: _v == null ? null : _VerdictCard(v: _v!, life: _life, onOverride: _v!.a == null ? null : () => _override(_v!.a!, m)))),
      ]);
    }

    return Column(children: [
      header,
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Nv.r28),
            child: Container(
              color: c.camera,
              child: Stack(children: [
                Positioned.fill(
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => NvCameraPermission(onRetry: () => _controller.start(), onByName: () => _byName(m), dark: true),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(child: Align(alignment: Alignment(0, -.35), child: SizedBox.square(dimension: 200, child: CustomPaint(painter: NvCornersPainter())))),
                ),
                if (_v != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _VerdictCard(v: _v!, life: _life, onOverride: _v!.kind == _V.notEntitled && _v!.a != null ? () => _override(_v!.a!, m) : null),
                  ),
              ]),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Row(children: [
          Expanded(child: NvSoftButton(label: 'کارت همراهش نیست؟', icon: Icons.person_search_rounded, border: c.surface, onPressed: () => _byName(m))),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'چراغ قوه',
            excludeSemantics: true,
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(Nv.r18),
              child: InkWell(
                borderRadius: BorderRadius.circular(Nv.r18),
                onTap: () => _controller.toggleTorch(),
                child: SizedBox.square(dimension: 52, child: Icon(Icons.flashlight_on_rounded, size: 24, color: c.ink)),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// کارت نتیجه‌ی اسکن: سبز «مجاز»، قرمز «قبلاً گرفته» یا «شامل نیست»، با شماره و نوار زمان.
class _VerdictCard extends StatelessWidget {
  final _Verdict v;
  final AnimationController life;
  final VoidCallback? onOverride;
  const _VerdictCard({required this.v, required this.life, this.onOverride});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final ok = v.kind == _V.ok;
    final bg = ok ? c.verdictOk : c.verdictBad;
    final fg = ok ? c.onVerdictOk : Colors.white;
    final icon = switch (v.kind) {
      _V.ok => Icons.check_rounded,
      _V.duplicate => Icons.history_rounded,
      _V.notEntitled => Icons.do_not_disturb_on_rounded,
      _V.invalid => Icons.error_outline_rounded,
    };
    return Semantics(
      liveRegion: true,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Nv.r22)),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Row(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: (ok ? c.onVerdictOk : Colors.white).withValues(alpha: ok ? .12 : .16), shape: BoxShape.circle),
                  child: Icon(icon, size: 42, color: fg),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.title, style: nvText(context, 24, w: FontWeight.w800, color: fg, height: 1.4)),
                    Text(v.name, style: nvText(context, 17, w: FontWeight.w700, color: fg)),
                    if (v.detail.isNotEmpty) Text(v.detail, style: nvText(context, 13, w: FontWeight.w600, color: fg.withValues(alpha: .85))),
                  ]),
                ),
              ]),
            ),
            Positioned(top: 8, left: 14, child: Text('#${faDigits(v.seq)}', style: nvText(context, 12, w: FontWeight.w700, color: fg.withValues(alpha: .7)))),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: life,
                builder: (context, _) => LinearProgressIndicator(
                  value: 1 - life.value,
                  minHeight: 6,
                  color: fg.withValues(alpha: .45),
                  backgroundColor: fg.withValues(alpha: .15),
                ),
              ),
            ),
          ]),
        ),
        if (onOverride != null) ...[
          const SizedBox(height: 8),
          NvSoftButton(label: 'تحویل با مجوز شفاهی مدیر', icon: Icons.verified_user_rounded, iconColor: c.wait, border: c.surface, onPressed: onOverride),
        ],
      ]),
    );
  }
}

/// «کدام وعده؟»: امروز با ساعت و «الان»، روزهای دیگر جمع‌شده.
class _MealPicker extends StatefulWidget {
  final bool stale;
  final Meal? current;
  const _MealPicker({required this.stale, this.current});

  @override
  State<_MealPicker> createState() => _MealPickerState();
}

class _MealPickerState extends State<_MealPicker> {
  int? _sel;
  bool _others = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final now = DateTime.now();
    final cur = s.currentMealFor(now);
    final today = s.meals.where(_isToday).toList()..sort((a, b) => a.time.compareTo(b.time));
    final others = s.meals.where((m) => !_isToday(m)).toList();
    _sel ??= (widget.current != null && _isToday(widget.current!)) ? widget.current!.id : (cur?.id ?? (today.isNotEmpty ? today.first.id : null));
    final selected = s.meals.where((m) => m.id == _sel).firstOrNull;
    if (today.isEmpty) _others = true;

    Widget row(Meal m) {
      final on = m.id == _sel;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? c.brandSoft : c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16), side: BorderSide(color: on ? c.brand : c.line, width: on ? 2 : 1.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(Nv.r16),
            onTap: () => setState(() => _sel = m.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name, style: nvText(context, 16, w: on ? FontWeight.w800 : FontWeight.w700)),
                      Text(
                        [
                          if (!_isToday(m)) _weekday(m),
                          if (m.time.isNotEmpty) faDigits(m.time),
                          if (cur?.id == m.id) 'الان',
                        ].join(' · '),
                        style: nvText(context, 12, w: on ? FontWeight.w700 : FontWeight.w400, color: on ? c.brandText : c.muted),
                      ),
                    ]),
                  ),
                  Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 24, color: on ? c.brandText : c.line),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('کدام وعده؟', style: nvText(context, 22, w: FontWeight.w800)),
      const SizedBox(height: 12),
      if (widget.stale) ...[
        NvBanner(
          tone: NvTone.wait,
          icon: Icons.today_rounded,
          text: 'وعده‌ی روز دیگری روی این گوشی مانده بود. امروز ${_weekdays[now.weekday - 1]} است؛ وعده‌ی درست را انتخاب کنید.',
        ),
        const SizedBox(height: 12),
      ],
      if (today.isNotEmpty) ...[
        Text('امروز · ${_weekdays[now.weekday - 1]}', style: nvText(context, 13, w: FontWeight.w700, color: c.muted)),
        const SizedBox(height: 8),
        for (final m in today) row(m),
      ],
      if (others.isNotEmpty) ...[
        InkWell(
          onTap: today.isEmpty ? null : () => setState(() => _others = !_others),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Expanded(child: Text('وعده‌های روزهای دیگر', style: nvText(context, 13, color: c.muted))),
              if (today.isNotEmpty) Icon(_others ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.muted),
            ]),
          ),
        ),
        if (_others) for (final m in others) row(m),
      ],
      const SizedBox(height: 8),
      NvButton(
        label: selected == null ? 'یک وعده انتخاب کنید' : 'شروع پذیرایی ${selected.name}',
        onPressed: selected == null ? null : () => Navigator.of(context).pop(selected),
      ),
    ]);
  }
}

/// «تحویل با مجوز شفاهی»: نام کسی که اجازه داد.
class _OverrideSheet extends StatefulWidget {
  final Attendee a;
  final Meal meal;
  const _OverrideSheet({required this.a, required this.meal});

  @override
  State<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends State<_OverrideSheet> {
  final _who = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _who.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('${widget.meal.name}${widget.meal.day == null ? '' : ' ${_weekday(widget.meal)}'}', style: nvText(context, 13, w: FontWeight.w600, color: c.muted)),
      Text(widget.a.displayName, style: nvText(context, 24, w: FontWeight.w800, height: 1.4)),
      Text('${s.typeName(widget.a.registrationTypeId)} · طبق قانون ${widget.meal.name} شامل او نیست', style: nvText(context, 14, color: c.muted)),
      const SizedBox(height: 14),
      const NvBanner(
        tone: NvTone.wait,
        icon: Icons.flag_rounded,
        title: 'این تحویل «مجوز شفاهی» ثبت می‌شود',
        text: 'در گزارش مدیر با علامت مشکوک و نام اجازه‌دهنده می‌آید. فقط وقتی بزنید که مدیر همین‌جا اجازه داده باشد.',
      ),
      const SizedBox(height: 14),
      NvField(
        label: 'چه کسی اجازه داد؟',
        error: _error,
        child: TextField(controller: _who, autofocus: true, decoration: const InputDecoration(hintText: 'مثلاً خانم احمدی (مدیر اجرایی)')),
      ),
      if (s.approvers.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in s.approvers)
            ActionChip(
              label: Text(n, style: nvText(context, 12, w: FontWeight.w600)),
              backgroundColor: c.chip,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              onPressed: () => setState(() => _who.text = n),
            ),
        ]),
      ],
      const SizedBox(height: 14),
      NvButton(
        label: 'تحویل با مجوز شفاهی',
        icon: Icons.verified_user_rounded,
        color: c.wait,
        onPressed: () {
          if (_who.text.trim().isEmpty) {
            setState(() => _error = 'نام کسی که اجازه داد را بنویسید.');
            return;
          }
          Navigator.of(context).pop(_who.text.trim());
        },
      ),
      const SizedBox(height: 10),
      NvSoftButton(label: 'انصراف، تحویل نشود', onPressed: () => Navigator.of(context).pop()),
    ]);
  }
}

/// پذیرایی با جستجوی نام: هر ردیف وضعیتش برای این وعده را دارد؛ انتخاب و بعد «تحویل شد».
class NvMealByNamePage extends StatelessWidget {
  final Meal meal;
  const NvMealByNamePage({super.key, required this.meal});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return Scaffold(
      body: Column(children: [
        NvBackHeader(title: 'جستجوی نام', subtitle: '${meal.name} · تحویل‌شده ${faDigits(s.servedCount(meal.id))} از ${faDigits(s.entitledCount(meal))}'),
        Expanded(
          child: NvMealByNameBody(meal: meal, onDeliver: (a, by) => Navigator.of(context).pop((a, by)), bottomPad: 0),
        ),
      ]),
    );
  }
}

class NvMealByNameBody extends StatefulWidget {
  final Meal meal;
  final void Function(Attendee a, String? overrideBy) onDeliver;
  final Widget? verdict;
  final double bottomPad;
  const NvMealByNameBody({super.key, required this.meal, required this.onDeliver, this.verdict, this.bottomPad = 92});

  @override
  State<NvMealByNameBody> createState() => _NvMealByNameBodyState();
}

class _NvMealByNameBodyState extends State<NvMealByNameBody> {
  final _q = TextEditingController();
  String? _sel;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final q = _q.text.trim();
    final results = q.isEmpty ? <Attendee>[] : s.search(q, limit: 40);
    final selected = _sel == null ? null : s.attendees[_sel];
    final verdict = selected == null ? null : s.checkMeal(selected, widget.meal).verdict;

    Widget chip(Attendee a) {
      final r = s.checkMeal(a, widget.meal);
      return switch (r.verdict) {
        MealVerdict.ok => NvStatusChip(text: 'مجاز', icon: Icons.check_circle_rounded, bg: c.goSoft, fg: c.go),
        MealVerdict.duplicate => NvStatusChip(text: 'گرفته ${faDigits(hm(r.previousAt!))}', icon: Icons.history_rounded, bg: c.stopSoft, fg: c.stop),
        MealVerdict.notEntitled => NvStatusChip(text: 'شامل نیست', icon: Icons.block_rounded, bg: c.neutralSoft, fg: c.muted),
      };
    }

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
          if (widget.verdict != null) ...[widget.verdict!, const SizedBox(height: 12)],
          TextField(
            controller: _q,
            autofocus: widget.verdict == null,
            style: nvText(context, 17, w: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'نام، نام خانوادگی یا موبایل',
              prefixIcon: Icon(Icons.search_rounded, color: c.brandText),
              fillColor: c.surface,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Nv.r18), borderSide: BorderSide(color: c.brand, width: 2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Nv.r18), borderSide: BorderSide(color: c.brand, width: 2)),
              suffixIcon: q.isEmpty ? null : IconButton(icon: Icon(Icons.close_rounded, color: c.faint), onPressed: () => setState(() {
                    _q.clear();
                    _sel = null;
                  })),
            ),
            onChanged: (_) => setState(() => _sel = null),
          ),
          const SizedBox(height: 8),
          Text('وضعیت هر نفر برای «${widget.meal.name}» کنار نامش نوشته شده است', style: nvText(context, 12, color: c.muted)),
          const SizedBox(height: 10),
          if (q.isNotEmpty && results.isEmpty) NvEmpty(icon: Icons.person_search_rounded, title: 'کسی با «$q» پیدا نشد'),
          for (final a in results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: a.id == _sel ? c.brandSoft : c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Nv.r18),
                  side: a.id == _sel ? BorderSide(color: c.brand, width: 2) : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Nv.r18),
                  onTap: () => setState(() => _sel = a.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 68),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.displayName, style: nvText(context, 16, w: FontWeight.w700, height: 1.5)),
                            Text([s.roleName(a.roleId).isNotEmpty ? s.roleName(a.roleId) : s.typeName(a.registrationTypeId), a.organization].where((e) => e.isNotEmpty).join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 13, color: c.muted)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        chip(a),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      if (selected != null)
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + widget.bottomPad + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(selected.displayName, style: nvText(context, 15, w: FontWeight.w700))),
              Text('انتخاب‌شده', style: nvText(context, 12, color: c.muted)),
            ]),
            const SizedBox(height: 8),
            switch (verdict!) {
              MealVerdict.ok => NvButton(
                  label: 'تحویل شد',
                  icon: Icons.check_rounded,
                  color: c.go,
                  height: Nv.buttonXl,
                  onPressed: () {
                    widget.onDeliver(selected, null);
                    setState(() {
                      _q.clear();
                      _sel = null;
                    });
                  },
                ),
              MealVerdict.duplicate => NvBanner(tone: NvTone.stop, icon: Icons.history_rounded, text: 'این نفر «${widget.meal.name}» را گرفته است؛ دوباره تحویل نمی‌شود.'),
              MealVerdict.notEntitled => NvSoftButton(
                  label: 'شامل نیست · تحویل با مجوز شفاهی',
                  icon: Icons.verified_user_rounded,
                  iconColor: c.wait,
                  onPressed: () async {
                    final by = await showNvSheet<String>(context, (_) => _OverrideSheet(a: selected, meal: widget.meal));
                    if (by == null || !mounted) return;
                    widget.onDeliver(selected, by);
                    setState(() {
                      _q.clear();
                      _sel = null;
                    });
                  },
                ),
            },
          ]),
        ),
    ]);
  }
}

/// دوربین اجازه ندارد: «اجازه بده» یا «جستجوی نام».
class NvCameraPermission extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onByName;
  final String byNameLabel;
  final bool dark;
  const NvCameraPermission({super.key, required this.onRetry, required this.onByName, this.byNameLabel = 'جستجوی نام', this.dark = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      color: c.bg,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
            child: Icon(Icons.no_photography_rounded, size: 48, color: c.muted),
          ),
          const SizedBox(height: 12),
          Text('برای اسکن، اجازه‌ی دوربین لازم است', textAlign: TextAlign.center, style: nvText(context, 20, w: FontWeight.w800, height: 1.5)),
          const SizedBox(height: 6),
          Text('بدون اجازه هم می‌توانید کار کنید: نام را جستجو کنید.', textAlign: TextAlign.center, style: nvText(context, 15, color: c.muted, height: 1.6)),
          const SizedBox(height: 16),
          NvButton(label: 'اجازه بده', onPressed: onRetry),
          const SizedBox(height: 10),
          NvSoftButton(label: byNameLabel, icon: Icons.person_search_rounded, border: c.line, onPressed: onByName),
          const SizedBox(height: 10),
          Text('اگر قبلاً «نه» زده‌اید: تنظیمات گوشی ← برنامه‌ها ← رویدادیار ← دوربین', textAlign: TextAlign.center, style: nvText(context, 12, color: c.muted, height: 1.6)),
        ]),
      ),
    );
  }
}
