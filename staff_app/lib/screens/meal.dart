import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../store.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

/// پذیرایی: اسکن پشت‌سرهم کارت‌ها برای وعده‌ی جاری.
/// اگر فرد حق وعده را داشته باشد و هنوز نگرفته باشد، تحویل همان لحظه ثبت می‌شود.
class MealScreen extends StatefulWidget {
  const MealScreen({super.key});

  @override
  State<MealScreen> createState() => _MealScreenState();
}

enum _Kind { ok, duplicate, notEntitled, invalid, unknown }

class _Result {
  final _Kind kind;
  final String title;
  final String detail;
  final int seq;
  _Result(this.kind, this.title, this.detail, this.seq);
}

// ---------------------------------------------------------------- روز وعده

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String get _todayIso => _iso(DateTime.now());

const _weekdays = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه', 'یکشنبه'];

String _weekday(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : _weekdays[d.weekday - 1];
}

bool _isToday(Meal m) => m.day == null || m.day!.isEmpty || m.day!.startsWith(_todayIso);

String _dayLabel(Meal m) {
  if (m.day == null || m.day!.isEmpty) return 'همه‌ی روزها';
  if (m.day!.startsWith(_todayIso)) return 'امروز';
  final tomorrow = _iso(DateTime.now().add(const Duration(days: 1)));
  if (m.day!.startsWith(tomorrow)) return 'فردا';
  return _weekday(m.day!.substring(0, m.day!.length.clamp(0, 10)));
}

class _MealScreenState extends State<MealScreen> {
  /// وعده‌ی روز دیگری که نیرو در همین اجرای اپ عمداً تأیید کرده.
  static int? _confirmedOtherDay;

  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  _Result? _result;
  String? _lastToken;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _clear;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSelect());
  }

  @override
  void dispose() {
    _clear?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// وعده‌ی امروز خودکار انتخاب می‌شود؛ وعده‌ی ذخیره‌شده‌ی روز دیگر نگه داشته نمی‌شود.
  void _autoSelect() {
    if (!mounted) return;
    final store = StoreScope.read(context);
    final cur = store.selectedMeal;
    if (cur != null && (_isToday(cur) || cur.id == _confirmedOtherDay)) return;
    final today = store.meals.where((m) => m.day != null && m.day!.startsWith(_todayIso)).toList();
    store.selectMeal(today.isNotEmpty ? today.first.id : null);
  }

  Future<void> _pickMeal(Meal m) async {
    final store = StoreScope.read(context);
    if (!_isToday(m)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('وعده‌ی روز دیگر'),
          content: Text('این وعده مال ${_dayLabel(m)} است. امروز ${_weekday(_todayIso)} است. مطمئنید؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('همین وعده')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _confirmedOtherDay = m.id;
    }
    store.selectMeal(m.id);
    setState(() => _result = null);
  }

  void _show(_Kind kind, String title, String detail) {
    _clear?.cancel();
    _seq++;
    setState(() => _result = _Result(kind, title, detail, _seq));
    verdictHaptic(kind == _Kind.ok);
    _clear = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _result = null);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final store = StoreScope.read(context);
    final meal = store.selectedMeal;
    if (meal == null) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final token = tokenFromScan(raw);
      final now = DateTime.now();
      // همان کارت در چند ثانیه‌ی پشت‌سرهم دوبار حساب نشود.
      if (token != null && token == _lastToken && now.difference(_lastAt).inSeconds < 5) return;
      if (token == null && raw == _lastToken && now.difference(_lastAt).inSeconds < 5) return;
      _lastToken = token ?? raw;
      _lastAt = now;
      if (token == null) {
        _show(_Kind.unknown, 'QR ناشناخته', 'این کد مال کارت کنفرانس نیست.');
        return;
      }
      final a = store.attendeeForToken(token);
      if (a == null) {
        _show(_Kind.invalid, 'کارت نامعتبر',
            store.cards.containsKey(token) ? 'کارت رزرو به کسی وصل نشده.' : 'این کارت در لیست نیست.');
        return;
      }
      _evaluate(store, a, meal);
      return;
    }
  }

  void _evaluate(AppStore store, Attendee a, Meal meal) {
    final c = store.checkMeal(a, meal);
    switch (c.verdict) {
      case MealVerdict.ok:
        store.serveMeal(a, meal);
        _show(_Kind.ok, 'مجاز — تحویل شود', a.displayName);
      case MealVerdict.duplicate:
        _show(_Kind.duplicate, 'قبلاً گرفته', '${a.displayName}\nساعت ${hm(c.previousAt!)}');
      case MealVerdict.notEntitled:
        _show(_Kind.notEntitled, 'این وعده شامل او نیست',
            '${a.displayName}\n${store.typeName(a.registrationTypeId)}');
    }
  }

  /// جستجوی نام: لمس یک نام فقط نتیجه را نشان می‌دهد؛ ثبت با دکمه‌ی «تحویل شد».
  Future<void> _searchByName() async {
    final store = StoreScope.read(context);
    final meal = store.selectedMeal;
    if (meal == null) return;
    final a = await Navigator.of(context).push<Attendee>(MaterialPageRoute(
      builder: (_) => _PickAttendeePage(meal: meal),
    ));
    if (a == null || !mounted) return;
    _lastToken = null;
    _evaluate(store, a, meal);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final meal = store.selectedMeal;
    final x = DaftarColors.of(context);
    final today = store.meals.where(_isToday).toList();
    final others = store.meals.where((m) => !_isToday(m)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // MealPicker: چیپ‌های افقی، وعده‌های امروز اول.
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space4, vertical: DaftarSize.space2),
            children: [
              for (final m in [...today, ...others])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: DaftarSize.space2),
                  child: _MealChip(
                    meal: m,
                    selected: m.id == meal?.id,
                    faded: !_isToday(m),
                    onTap: () => _pickMeal(m),
                  ),
                ),
            ],
          ),
        ),
        if (meal != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(DaftarSize.space4, 0, DaftarSize.space4, DaftarSize.space3),
            child: Meter(
              label: 'تحویل‌شده (از دارای حق)',
              value: store.servedCount(meal.id),
              total: store.entitledCount(meal),
              format: faDigits,
            ),
          ),
        Expanded(
          child: meal == null
              ? SingleChildScrollView(
                  child: EmptyState(
                    icon: Icons.restaurant_rounded,
                    title: store.meals.isEmpty ? 'وعده‌ای تعریف نشده' : 'وعده‌ی جاری را انتخاب کنید',
                    hint: store.meals.isEmpty
                        ? 'از اپ مدیریت وعده‌ها را بسازید و از «وضعیت» لیست را دوباره بگیرید.'
                        : 'برای امروز وعده‌ای پیدا نشد؛ یکی از چیپ‌های بالا را بزنید.',
                  ),
                )
              : ColoredBox(
                  color: x.camera,
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Positioned.fill(
                          child: MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                            errorBuilder: (context, error) => _CameraError(
                              error: error,
                              onRetry: () => _controller.start(),
                            ),
                          ),
                        ),
                        // کادر هدف در نیمه‌ی بالا آزاد می‌ماند تا اسکن بعدی معطل نشود.
                        Positioned(
                          top: c.maxHeight * .08,
                          left: 0,
                          right: 0,
                          child: ValueListenableBuilder<MobileScannerState>(
                            valueListenable: _controller,
                            builder: (context, st, _) => st.error != null
                                ? const SizedBox.shrink()
                                : Center(
                                    child: Container(
                                      width: (c.maxHeight * .38).clamp(120.0, 240.0),
                                      height: (c.maxHeight * .38).clamp(120.0, 240.0),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white.withValues(alpha: .8), width: 2),
                                        borderRadius: BorderRadius.circular(DaftarSize.radiusMd),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        if (_result != null)
                          Positioned(
                            left: DaftarSize.space3,
                            right: DaftarSize.space3,
                            bottom: DaftarSize.space3,
                            child: ScanResultCard(
                              key: ValueKey(_result!.seq),
                              kind: _result!.kind.index,
                              title: _result!.title,
                              detail: _result!.detail,
                              seq: _result!.seq,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        if (meal != null)
          Padding(
            padding: const EdgeInsets.all(DaftarSize.space3),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(DaftarSize.tapLg)),
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('کارت همراهش نیست؟'),
                    onPressed: _searchByName,
                  ),
                ),
                const SizedBox(width: DaftarSize.space2),
                Tooltip(
                  message: 'چراغ‌قوه',
                  child: SizedBox.square(
                    dimension: DaftarSize.tapLg,
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, s, _) {
                        final on = s.torchState == TorchState.on;
                        return Semantics(
                          button: true,
                          toggled: on,
                          label: 'چراغ‌قوه',
                          excludeSemantics: true,
                          child: on
                              ? FilledButton(
                                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size.square(56)),
                                  onPressed: _controller.toggleTorch,
                                  child: const Icon(Icons.flashlight_on_rounded),
                                )
                              : OutlinedButton(
                                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size.square(56)),
                                  onPressed: s.isRunning ? _controller.toggleTorch : null,
                                  child: const Icon(Icons.flashlight_off_rounded),
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MealChip extends StatelessWidget {
  final Meal meal;
  final bool selected;
  final bool faded;
  final VoidCallback onTap;
  const _MealChip({required this.meal, required this.selected, required this.faded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final fg = selected ? x.onAction : (faded ? x.inkMuted : x.ink);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? x.action : x.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
          side: BorderSide(color: selected ? x.action : (faded ? x.line : x.lineStrong), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DaftarSize.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.name, style: theme.textTheme.labelLarge?.copyWith(color: fg)),
                Text(_dayLabel(meal), style: theme.textTheme.bodySmall?.copyWith(color: fg, height: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// نتیجه‌ی اسکن: پرکردگی بزرگ با آیکن، حکم درشت و نام. مجاز روشن است و رد تیره،
/// پس بدون تشخیص رنگ هم از هم جدا می‌شوند. ۴ ثانیه می‌ماند و نوار پایین زمان باقی‌مانده را نشان می‌دهد.
class ScanResultCard extends StatelessWidget {
  /// ۰ مجاز، ۱ قبلاً گرفته، ۲ شامل نیست، ۳ کارت نامعتبر، ۴ QR ناشناخته.
  final int kind;
  final String title;
  final String detail;
  final int seq;
  const ScanResultCard({super.key, required this.kind, required this.title, required this.detail, required this.seq});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final (bg, fg, icon) = switch (kind) {
      0 => (x.goFill, x.onGo, Icons.check_circle_rounded),
      1 => (x.stopFill, x.onStop, Icons.history_rounded),
      2 => (x.stopFill, x.onStop, Icons.do_not_disturb_on_rounded),
      3 => (x.stopFill, x.onStop, Icons.close_rounded),
      _ => (x.idleFill, x.onIdle, Icons.help_rounded),
    };

    final card = Semantics(
      liveRegion: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(DaftarSize.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DaftarSize.space4, DaftarSize.space4, DaftarSize.space4, DaftarSize.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: fg, size: 56),
                  const SizedBox(width: DaftarSize.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: theme.textTheme.displayMedium?.copyWith(color: fg)),
                        Text(detail, style: theme.textTheme.titleMedium?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                  Text('#${faDigits(seq)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: fg, fontFeatures: tabularFigures)),
                ],
              ),
            ),
            if (reduceMotion)
              Container(height: 4, color: fg.withValues(alpha: .35))
            else
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(seconds: 4),
                builder: (context, v, _) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: v,
                    child: Container(height: 4, color: fg.withValues(alpha: .55)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (reduceMotion) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .96, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: card,
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;
  const _CameraError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: DaftarColors.of(context).paper,
      child: Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: Icons.no_photography_rounded,
            title: denied ? 'برای اسکن، اجازه‌ی دوربین لازم است' : 'دوربین باز نشد',
            hint: denied
                ? 'اگر پنجره‌ی اجازه نیامد، از تنظیمات گوشی اجازه‌ی دوربین را برای این اپ روشن کنید.'
                : 'اپ را ببندید و دوباره باز کنید. تا آن موقع از «کارت همراهش نیست؟» استفاده کنید.',
            action: FilledButton(onPressed: onRetry, child: Text(denied ? 'اجازه بده' : 'دوباره امتحان کن')),
          ),
        ),
      ),
    );
  }
}

/// جستجوی تمام‌صفحه‌ی نام در پذیرایی. هر ردیف وضعیت آن فرد را برای این وعده نشان می‌دهد
/// و لمس، پیش از ثبت، تأیید «تحویل شد» می‌خواهد.
class _PickAttendeePage extends StatefulWidget {
  final Meal meal;
  const _PickAttendeePage({required this.meal});

  @override
  State<_PickAttendeePage> createState() => _PickAttendeePageState();
}

class _PickAttendeePageState extends State<_PickAttendeePage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _confirm(Attendee a) async {
    final store = StoreScope.read(context);
    final c = store.checkMeal(a, widget.meal);
    if (c.verdict != MealVerdict.ok) {
      Navigator.of(context).pop(a);
      return;
    }
    final x = DaftarColors.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(DaftarSize.space5, 0, DaftarSize.space5, DaftarSize.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(a.displayName, style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: DaftarSize.space1),
            Text('${widget.meal.name} · ${store.typeName(a.registrationTypeId)}',
                style: Theme.of(c).textTheme.bodyMedium?.copyWith(color: x.inkMuted)),
            const SizedBox(height: DaftarSize.space3),
            const Notice(tone: NoticeTone.go, text: 'مجاز است و هنوز نگرفته.'),
            const SizedBox(height: DaftarSize.space5),
            FilledButton.icon(
              style: daftarGoStyle(c),
              icon: const Icon(Icons.check_rounded),
              label: const Text('تحویل شد'),
              onPressed: () => Navigator.pop(c, true),
            ),
            const SizedBox(height: DaftarSize.space2),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop(a);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final results = _q.text.trim().isEmpty ? <Attendee>[] : store.search(_q.text, limit: 30);
    return Scaffold(
      appBar: AppBar(title: Text('جستجوی نام — ${widget.meal.name}')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(DaftarSize.space4),
            child: TextField(
              controller: _q,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'نام، نام خانوادگی یا موبایل',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Divider(color: x.line),
          Expanded(
            child: _q.text.trim().isEmpty
                ? const EmptyState(icon: Icons.search_rounded, title: 'چند حرف از نام یا موبایل را بنویسید')
                : results.isEmpty
                    ? EmptyState(icon: Icons.person_search_rounded, title: 'کسی با «${_q.text.trim()}» پیدا نشد')
                    : ListView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          for (final a in results)
                            Builder(builder: (context) {
                              final c = store.checkMeal(a, widget.meal);
                              final (label, color, icon) = switch (c.verdict) {
                                MealVerdict.ok => ('مجاز', x.go, Icons.check_circle_rounded),
                                MealVerdict.duplicate =>
                                  ('گرفته، ${hm(c.previousAt!)}', x.stop, Icons.history_rounded),
                                MealVerdict.notEntitled => ('شامل نیست', x.stop, Icons.do_not_disturb_on_rounded),
                              };
                              return Material(
                                color: x.surface,
                                child: InkWell(
                                  onTap: () => _confirm(a),
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: DaftarSize.tapXl),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: DaftarSize.space4, vertical: DaftarSize.space2),
                                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(a.displayName, style: theme.textTheme.titleMedium),
                                            Text(store.typeName(a.registrationTypeId),
                                                style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                                          ],
                                        ),
                                      ),
                                      Icon(icon, size: 18, color: color),
                                      const SizedBox(width: DaftarSize.space1),
                                      Text(label,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
