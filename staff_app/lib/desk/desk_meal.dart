// پذیرایی در ویندوز (طرح ۷ تا ۱۰): یک نوار برای اسکن کارت یا تایپ نام، کارت نتیجه‌ی درشت،
// اسکن‌های اخیر در کنار، و مجوز شفاهی (F9) در پنل کناری.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../store.dart';
import '../theme/widgets.dart' show verdictHaptic;
import 'scan_field.dart';

const _weekdays = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه', 'یکشنبه'];
String _two(int n) => n.toString().padLeft(2, '0');
String _today() {
  final n = DateTime.now();
  return '${n.year}-${_two(n.month)}-${_two(n.day)}';
}

bool _isToday(Meal m) => m.day == null || m.day!.isEmpty || m.day!.startsWith(_today());
String _weekday(Meal m) {
  final d = DateTime.tryParse(m.day ?? '');
  return d == null ? 'همه‌ی روزها' : _weekdays[d.weekday - 1];
}

enum _K { ok, duplicate, notEntitled, invalid }

class _Verdict {
  final _K kind;
  final String title, name, detail, short;
  final Attendee? a;
  final int seq;
  final DateTime at = DateTime.now();
  _Verdict(this.kind, this.title, this.name, this.detail, this.short, this.seq, [this.a]);
}

/// اسکن‌های اخیر همین اجرا (با تعویض تب از بین نمی‌رود).
final List<_Verdict> _recent = [];
int _seqAll = 0;
int? _confirmedOtherDay;

class DeskMealTab extends StatefulWidget {
  final bool wide;
  const DeskMealTab({super.key, required this.wide});

  @override
  State<DeskMealTab> createState() => _DeskMealTabState();
}

class _DeskMealTabState extends State<DeskMealTab> with SingleTickerProviderStateMixin {
  final _q = TextEditingController();
  final _focus = FocusNode();
  final _approver = TextEditingController();
  late final AnimationController _life = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  _Verdict? _v;
  int _sel = 0;
  Attendee? _overrideFor;
  String? _lastToken;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted && _overrideFor == null) setState(() => _v = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = StoreScope.read(context);
      final cur = s.selectedMeal;
      if (cur != null && (_isToday(cur) || cur.id == _confirmedOtherDay)) return;
      final now = s.currentMealFor(DateTime.now());
      if (now != null) s.selectMeal(now.id);
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _q.dispose();
    _focus.dispose();
    _approver.dispose();
    super.dispose();
  }

  void _show(_Verdict v) {
    _recent.insert(0, v);
    if (_recent.length > 30) _recent.removeLast();
    setState(() => _v = v);
    verdictHaptic(v.kind == _K.ok);
    _life.duration = Duration(seconds: v.kind == _K.notEntitled ? 8 : 4);
    _life.forward(from: 0);
  }

  String _rule(AppStore s, Meal m) {
    final names = [for (final t in s.types) if (m.typeIds.contains(t.id)) t.name, for (final r in s.roles) if (m.roleIds.contains(r.id)) r.name];
    return names.isEmpty ? '${m.name} برای گروه خاصی است' : '${m.name} فقط برای ${names.join(' و ')}';
  }

  String? _servedBy(AppStore s, Attendee a, Meal m) {
    for (final e in [...s.serverLog, ...s.pending]) {
      if (e.kind == 'meal_served' && e.attendeeId == a.id && e.mealId == m.id) {
        return e.staffId == null ? null : s.staffNames[e.staffId];
      }
    }
    return null;
  }

  void _evaluate(AppStore s, Attendee a, Meal m, {String? overrideBy}) {
    final seq = ++_seqAll;
    final c = s.checkMeal(a, m);
    final card = s.cardOf(a.id);
    final role = [s.roleName(a.roleId), if (card != null) 'کارت ${faDigits(card.serial)}'].where((e) => e.isNotEmpty).join(' · ');
    if (overrideBy != null) {
      s.serveMeal(a, m, overrideBy: overrideBy);
      _show(_Verdict(_K.ok, 'تحویل با مجوز شفاهی', a.displayName, 'اجازه: $overrideBy', 'مجوز شفاهی', seq, a));
      return;
    }
    switch (c.verdict) {
      case MealVerdict.ok:
        s.serveMeal(a, m);
        _show(_Verdict(_K.ok, 'مجاز · تحویل شود', a.displayName, role, 'مجاز', seq, a));
      case MealVerdict.duplicate:
        final by = _servedBy(s, a, m);
        final t = faDigits(hm(c.previousAt!));
        _show(_Verdict(_K.duplicate, 'قبلاً گرفته', a.displayName, ['ساعت $t', if (by != null) by].join(' · '), 'قبلاً گرفته، ساعت $t', seq, a));
      case MealVerdict.notEntitled:
        _show(_Verdict(_K.notEntitled, 'این وعده شامل او نیست', a.displayName, '${s.typeName(a.registrationTypeId)} · ${_rule(s, m)}', 'شامل او نیست', seq, a));
    }
  }

  bool _onScan(String raw) {
    final s = StoreScope.read(context);
    final m = s.selectedMeal;
    if (m == null) return false;
    final token = tokenFromScan(raw);
    final now = DateTime.now();
    if ((token ?? raw) == _lastToken && now.difference(_lastAt).inSeconds < 3) return true;
    _lastToken = token ?? raw;
    _lastAt = now;
    setState(() => _overrideFor = null);
    if (token == null) {
      _show(_Verdict(_K.invalid, 'QR ناشناخته', 'این کد مال کارت کنفرانس نیست.', '', 'مال کارت کنفرانس نیست', ++_seqAll));
      return false;
    }
    final a = s.attendeeForToken(token);
    if (a == null) {
      final why = s.cards.containsKey(token) ? 'کارت رزرو به کسی وصل نشده.' : 'این کارت در لیست نیست.';
      _show(_Verdict(_K.invalid, 'کارت نامعتبر', why, '', why, ++_seqAll));
      return true;
    }
    _evaluate(s, a, m);
    return true;
  }

  void _clear() {
    _q.clear();
    setState(() {
      _sel = 0;
      _overrideFor = null;
    });
    _focus.requestFocus();
  }

  /// Enter روی نام انتخاب‌شده: مجاز ← تحویل؛ بقیه فقط در پنل دیده می‌شوند.
  Future<void> _pick(AppStore s, Meal m, Attendee a) async {
    final v = s.checkMeal(a, m).verdict;
    if (v != MealVerdict.ok) {
      if (!widget.wide) {
        _q.clear();
        _evaluate(s, a, m);
      }
      return;
    }
    if (!widget.wide) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('${m.name} برای ${a.displayName}'),
          content: const Text('تحویل شد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تحویل شد')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _q.clear();
    _lastToken = null;
    _evaluate(s, a, m);
    setState(() => _sel = 0);
    _focus.requestFocus();
  }

  void _startOverride(Attendee a) {
    _life.stop();
    _approver.clear();
    setState(() => _overrideFor = a);
  }

  void _submitOverride(AppStore s, Meal m) {
    final by = _approver.text.trim();
    final a = _overrideFor;
    if (by.isEmpty || a == null) return;
    _q.clear();
    setState(() => _overrideFor = null);
    _evaluate(s, a, m, overrideBy: by);
    _focus.requestFocus();
  }

  Attendee? _overrideCandidate(AppStore s, Meal? m, List<Attendee> results) {
    if (m == null) return null;
    if (_q.text.trim().isNotEmpty && results.isNotEmpty) {
      final a = results[_sel.clamp(0, results.length - 1)];
      return s.checkMeal(a, m).verdict == MealVerdict.notEntitled ? a : null;
    }
    return _v?.kind == _K.notEntitled ? _v!.a : null;
  }

  KeyEventResult _onKey(KeyEvent e, AppStore s, Meal? m, List<Attendee> results) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown && results.isNotEmpty) {
      setState(() => _sel = (_sel + 1).clamp(0, results.length - 1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && results.isNotEmpty) {
      setState(() => _sel = (_sel - 1).clamp(0, results.length - 1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _clear();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f9) {
      final a = _overrideCandidate(s, m, results);
      if (a != null) _startOverride(a);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickOtherDay(AppStore s, Meal m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('وعده‌ی روز دیگر'),
        content: Text('«${m.name}» مال ${_weekday(m)} است، نه امروز. مطمئنید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('بله، همین وعده')),
        ],
      ),
    );
    if (ok != true) return;
    _confirmedOtherDay = m.id;
    s.selectMeal(m.id);
    setState(() => _v = null);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final m = s.selectedMeal;
    final q = _q.text.trim();
    final results = q.isEmpty ? const <Attendee>[] : s.search(q);
    if (_sel >= results.length) _sel = results.isEmpty ? 0 : results.length - 1;
    final candidate = _overrideCandidate(s, m, results);

    if (s.meals.isEmpty) {
      return const Center(child: NvEmpty(icon: Icons.restaurant_rounded, title: 'وعده‌ای تعریف نشده', hint: 'مدیر باید در اپ مدیریت وعده‌ها را تعریف کند.'));
    }

    final todays = s.meals.where(_isToday).toList()..sort((a, b) => (a.time.isEmpty ? '99' : a.time).compareTo(b.time.isEmpty ? '99' : b.time));
    final others = s.meals.where((x) => !_isToday(x)).toList();
    final now = s.currentMealFor(DateTime.now());

    Widget chip(Meal x) {
      final on = x.id == m?.id;
      final small = [if (x.time.isNotEmpty) 'ساعت ${faDigits(x.time)}', if (x.id == now?.id) 'الان', if (!_isToday(x)) _weekday(x)].join('، ');
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Material(
          color: on ? c.ink : c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r14), side: on ? BorderSide.none : BorderSide(color: c.line, width: 1.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(Nv.r14),
            onTap: () {
              if (_isToday(x)) {
                s.selectMeal(x.id);
                setState(() => _v = null);
                _focus.requestFocus();
              } else {
                _pickOtherDay(s, x);
              }
            },
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.name, style: nvText(context, 15, w: on ? FontWeight.w800 : FontWeight.w700, color: on ? c.bg : c.ink)),
                if (small.isNotEmpty) Text(small, style: nvText(context, 11, w: FontWeight.w500, color: on ? c.bg.withValues(alpha: .8) : c.muted)),
              ]),
            ),
          ),
        ),
      );
    }

    final served = m == null ? 0 : s.servedCount(m.id);
    final entitled = m == null ? 0 : s.entitledCount(m);
    final top = Row(children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final x in todays) chip(x),
            if (m != null && !_isToday(m)) chip(m),
            if (others.isNotEmpty)
              PopupMenuButton<Meal>(
                tooltip: 'وعده‌های روزهای دیگر',
                onSelected: (x) => _pickOtherDay(s, x),
                itemBuilder: (_) => [for (final x in others) PopupMenuItem(value: x, child: Text('${x.name} · ${_weekday(x)}${x.time.isEmpty ? '' : ' ${faDigits(x.time)}'}'))],
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: Row(children: [
                    Text('روزهای دیگر', style: nvText(context, 14, w: FontWeight.w600, color: c.muted)),
                    Icon(Icons.expand_more_rounded, color: c.muted),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      if (m != null) ...[
        const SizedBox(width: 16),
        SizedBox(
          width: widget.wide ? 260 : 150,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('تحویل‌شده', style: nvText(context, 13, w: FontWeight.w700, color: c.muted))),
              Text('${faDigits(served)} از ${faDigits(entitled)}', style: nvText(context, 13, w: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: entitled == 0 ? 0 : (served / entitled).clamp(0, 1), minHeight: 8, color: c.brand, backgroundColor: c.lineSoft),
            ),
          ]),
        ),
      ],
    ]);

    final Widget main;
    if (m == null) {
      main = _Idle(title: 'وعده را انتخاب کنید', hint: todays.isEmpty ? 'امروز وعده‌ای نیست؛ از «روزهای دیگر» انتخاب کنید.' : 'بالای صفحه وعده‌ی درست را بزنید.');
    } else if (q.isNotEmpty) {
      main = _NameResults(
        results: results,
        meal: m,
        sel: _sel,
        onTap: (i) {
          setState(() => _sel = i);
          if (!widget.wide) _pick(s, m, results[i]);
          _focus.requestFocus();
        },
      );
    } else if (_v != null) {
      main = _VerdictCard(v: _v!, life: _life);
    } else {
      main = _Idle(
        title: 'آماده‌ی اسکن',
        hint: s.scanEnabled ? 'کارت را با بارکدخوان اسکن کنید، یا اگر همراهش نیست نام را بنویسید.' : 'نام را بنویسید و Enter بزنید.',
        meal: m,
      );
    }

    final scanBar = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _onKey(e, s, m, results),
      child: NvScanField(
        controller: _q,
        focusNode: _focus,
        look: NvScanLook.bar,
        scanEnabled: s.scanEnabled,
        hint: s.scanEnabled ? 'آماده‌ی اسکن کارت بعدی' : 'نام را بنویسید',
        hintMore: s.scanEnabled ? 'کارت همراهش نیست؟ نام را تایپ کنید' : null,
        onChanged: (_) => setState(() {
          _sel = 0;
          _overrideFor = null;
        }),
        onSubmitted: (_) {
          if (m != null && results.isNotEmpty) _pick(s, m, results[_sel]);
        },
        onScan: _onScan,
      ),
    );

    final left = Padding(
      padding: EdgeInsets.fromLTRB(widget.wide ? 24 : 16, 20, widget.wide ? 24 : 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        top,
        const SizedBox(height: 14),
        Expanded(child: main),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: scanBar),
          if (candidate != null && m != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 64,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink,
                  backgroundColor: c.surface,
                  side: BorderSide(color: c.wait, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16)),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                onPressed: () => _startOverride(candidate),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_user_rounded, color: c.wait),
                  const SizedBox(width: 8),
                  Text('تحویل با مجوز شفاهی', style: nvText(context, 16, w: FontWeight.w800)),
                  if (widget.wide) ...[const SizedBox(width: 8), const NvKbd('F9')],
                ]),
              ),
            ),
          ],
        ]),
      ]),
    );

    if (!widget.wide) {
      if (_overrideFor != null && m != null) {
        return Padding(padding: const EdgeInsets.all(16), child: _overridePanel(s, m, _overrideFor!));
      }
      return left;
    }

    final Widget side;
    final double width;
    if (_overrideFor != null && m != null) {
      side = _overridePanel(s, m, _overrideFor!);
      width = 430;
    } else if (q.isNotEmpty && results.isNotEmpty && m != null) {
      side = _PersonPanel(a: results[_sel], meal: m, onServe: () => _pick(s, m, results[_sel]), onOverride: () => _startOverride(results[_sel]));
      width = 430;
    } else {
      side = const _RecentPanel();
      width = 340;
    }

    return Row(children: [
      Expanded(child: left),
      Container(
        width: width,
        padding: EdgeInsets.all(width == 430 ? 24 : 20),
        decoration: BoxDecoration(
          color: c.surface,
          border: BorderDirectional(start: BorderSide(color: c.lineSoft)),
          boxShadow: _overrideFor != null ? [BoxShadow(color: c.ink.withValues(alpha: .08), blurRadius: 30, offset: const Offset(-12, 0))] : null,
        ),
        child: side,
      ),
    ]);
  }

  Widget _overridePanel(AppStore s, Meal m, Attendee a) {
    final c = NvColors.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          setState(() => _overrideFor = null);
          _focus.requestFocus();
        },
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            Text('${m.name} ${_weekday(m)}', style: nvText(context, 13, w: FontWeight.w600, color: c.muted)),
            Text(a.displayName, style: nvText(context, 26, w: FontWeight.w800, height: 1.4)),
            Text('طبق قانون، ${m.name} شامل او نیست', style: nvText(context, 14, color: c.muted)),
            const SizedBox(height: 14),
            const NvBanner(
              tone: NvTone.wait,
              icon: Icons.flag_rounded,
              title: '«مجوز شفاهی» ثبت می‌شود',
              text: 'در گزارش مدیر با نام اجازه‌دهنده و علامت «مشکوک» می‌آید. فقط وقتی بزنید که مدیر همین‌جا اجازه داده باشد.',
            ),
            const SizedBox(height: 14),
            Text('چه کسی اجازه داد؟', style: nvText(context, 14, w: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _approver,
              autofocus: true,
              style: nvText(context, 16),
              decoration: const InputDecoration(hintText: 'مثلاً خانم احمدی (مدیر اجرایی)'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitOverride(s, m),
            ),
            if (s.approvers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final n in s.approvers)
                  ActionChip(
                    label: Text(n),
                    onPressed: () => setState(() => _approver.text = n),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.wait,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r18)),
              textStyle: nvText(context, 18, w: FontWeight.w800),
            ),
            onPressed: _approver.text.trim().isEmpty ? null : () => _submitOverride(s, m),
            icon: const Icon(Icons.verified_user_rounded, size: 26),
            label: const Text('تحویل با مجوز شفاهی'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: TextButton(
            style: TextButton.styleFrom(backgroundColor: c.field, foregroundColor: c.ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16))),
            onPressed: () {
              setState(() => _overrideFor = null);
              _focus.requestFocus();
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('انصراف، تحویل نشود', style: nvText(context, 16, w: FontWeight.w700)),
              if (widget.wide) ...[const SizedBox(width: 8), const NvKbd('Esc')],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Idle extends StatelessWidget {
  final String title, hint;
  final Meal? meal;
  const _Idle({required this.title, required this.hint, this.meal});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22)),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
          child: Icon(Icons.qr_code_scanner_rounded, size: 64, color: c.brandText),
        ),
        const SizedBox(height: 18),
        Text(title, style: nvText(context, 30, w: FontWeight.w800)),
        if (meal != null) Text(meal!.name, style: nvText(context, 18, w: FontWeight.w700, color: c.brandText)),
        const SizedBox(height: 6),
        Text(hint, textAlign: TextAlign.center, style: nvText(context, 15, color: c.muted, height: 1.6)),
      ]),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final _Verdict v;
  final AnimationController life;
  const _VerdictCard({required this.v, required this.life});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final (Color bg, Color fg, IconData icon) = switch (v.kind) {
      _K.ok => (c.verdictOk, c.onVerdictOk, Icons.check_rounded),
      _K.duplicate => (c.verdictBad, Colors.white, Icons.history_rounded),
      _K.notEntitled => (c.verdictBad, Colors.white, Icons.do_not_disturb_on_rounded),
      _K.invalid => (c.chip, c.ink, Icons.help_rounded),
    };
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxWidth < 640;
      final title = v.kind == _K.notEntitled ? 46.0 : 52.0;
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
        child: Stack(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Flex(
                direction: compact ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: compact ? 104 : 148,
                    height: compact ? 104 : 148,
                    decoration: BoxDecoration(color: fg.withValues(alpha: .14), shape: BoxShape.circle),
                    child: Icon(icon, size: compact ? 72 : 100, color: fg),
                  ),
                  SizedBox(width: compact ? 0 : 32, height: compact ? 16 : 0),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                      children: [
                        Text(v.title, textAlign: compact ? TextAlign.center : null, style: nvText(context, compact ? title * .66 : title, w: FontWeight.w800, color: fg, height: 1.25)),
                        const SizedBox(height: 6),
                        Text(v.name, textAlign: compact ? TextAlign.center : null, style: nvText(context, compact ? 22 : 30, w: FontWeight.w700, color: fg, height: 1.4)),
                        if (v.detail.isNotEmpty)
                          Text(v.detail, textAlign: compact ? TextAlign.center : null, style: nvText(context, 17, w: FontWeight.w600, color: fg.withValues(alpha: .85))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: 16,
            end: 22,
            child: Text('#${faDigits(v.seq)}', style: nvText(context, 14, w: FontWeight.w700, color: fg.withValues(alpha: .75))),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: life,
              builder: (context, _) => LinearProgressIndicator(
                value: 1 - life.value,
                minHeight: 8,
                color: fg.withValues(alpha: .45),
                backgroundColor: fg.withValues(alpha: .15),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

class _NameResults extends StatelessWidget {
  final List<Attendee> results;
  final Meal meal;
  final int sel;
  final ValueChanged<int> onTap;
  const _NameResults({required this.results, required this.meal, required this.sel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    if (results.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16)),
        alignment: Alignment.center,
        child: Text('کسی با این نام پیدا نشد.', style: nvText(context, 16, color: c.muted)),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16)),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: results.length,
        itemBuilder: (context, i) {
          final a = results[i];
          final check = s.checkMeal(a, meal);
          final on = i == sel;
          final (Color pbg, Color pfg, IconData icon, String label) = switch (check.verdict) {
            MealVerdict.ok => (c.goSoft, c.goInk, Icons.check_circle_rounded, 'مجاز'),
            MealVerdict.duplicate => (c.stopSoft, c.stopInk, Icons.history_rounded, 'گرفته ${faDigits(hm(check.previousAt!))}'),
            MealVerdict.notEntitled => (c.tag, c.muted, Icons.block_rounded, 'شامل نیست'),
          };
          final sub = [s.roleName(a.roleId), s.typeName(a.registrationTypeId), a.organization].where((e) => e.isNotEmpty).join(' · ');
          return Material(
            color: on ? Color.alphaBlend(c.brand.withValues(alpha: .10), c.surface) : c.surface,
            child: InkWell(
              onTap: () => onTap(i),
              child: Container(
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    top: i == 0 ? BorderSide.none : BorderSide(color: c.lineSoft),
                    start: on ? BorderSide(color: c.brand, width: 4) : BorderSide.none,
                  ),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 17, w: FontWeight.w700)),
                      if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 13, color: c.muted)),
                    ]),
                  ),
                  NvStatusChip(text: label, icon: icon, bg: pbg, fg: pfg),
                  if (on && check.verdict == MealVerdict.ok) ...[const SizedBox(width: 10), const NvKbd('Enter')],
                  if (on && check.verdict == MealVerdict.notEntitled) ...[const SizedBox(width: 10), const NvKbd('F9')],
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PersonPanel extends StatelessWidget {
  final Attendee a;
  final Meal meal;
  final VoidCallback onServe;
  final VoidCallback onOverride;
  const _PersonPanel({required this.a, required this.meal, required this.onServe, required this.onOverride});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final check = s.checkMeal(a, meal);
    final tags = [s.typeName(a.registrationTypeId), s.roleName(a.roleId)].where((e) => e.isNotEmpty).toList();
    final mealName = '${meal.name} ${_weekday(meal)}';
    final banner = switch (check.verdict) {
      MealVerdict.ok => NvBanner(tone: NvTone.go, icon: Icons.check_circle_rounded, title: '$mealName شامل اوست', text: 'هنوز نگرفته'),
      MealVerdict.duplicate => NvBanner(tone: NvTone.stop, icon: Icons.history_rounded, title: 'قبلاً گرفته', text: 'ساعت ${faDigits(hm(check.previousAt!))}'),
      MealVerdict.notEntitled => NvBanner(tone: NvTone.neutral, icon: Icons.block_rounded, title: '$mealName شامل او نیست', text: s.typeName(a.registrationTypeId)),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          Text(a.displayName, style: nvText(context, 30, w: FontWeight.w800, height: 1.4)),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) NvTag(t)]),
          ],
          const SizedBox(height: 14),
          banner,
        ]),
      ),
      if (check.verdict == MealVerdict.ok)
        SizedBox(
          height: 68,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.go,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r18)),
              textStyle: nvText(context, 20, w: FontWeight.w800),
            ),
            onPressed: onServe,
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_rounded, size: 30),
              SizedBox(width: 10),
              Text('تحویل شد'),
              SizedBox(width: 10),
              NvKbd('Enter', onBrand: true),
            ]),
          ),
        )
      else if (check.verdict == MealVerdict.notEntitled)
        SizedBox(
          height: 60,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink,
              side: BorderSide(color: c.wait, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16)),
            ),
            onPressed: onOverride,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.verified_user_rounded, color: c.wait),
              const SizedBox(width: 8),
              Text('تحویل با مجوز شفاهی', style: nvText(context, 16, w: FontWeight.w800)),
              const SizedBox(width: 8),
              const NvKbd('F9'),
            ]),
          ),
        ),
    ]);
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel();

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('اسکن‌های اخیر', style: nvText(context, 16, w: FontWeight.w800))),
        Text('این دستگاه', style: nvText(context, 12, color: c.muted)),
      ]),
      const SizedBox(height: 6),
      Expanded(
        child: _recent.isEmpty
            ? Center(child: Text('هنوز اسکنی نشده.', style: nvText(context, 14, color: c.muted)))
            : ListView(padding: EdgeInsets.zero, children: [
                for (var i = 0; i < _recent.length; i++)
                  Builder(builder: (context) {
                    final v = _recent[i];
                    final bad = v.kind == _K.duplicate || v.kind == _K.notEntitled;
                    final (IconData icon, Color color) = switch (v.kind) {
                      _K.ok => (Icons.check_circle_rounded, c.go),
                      _K.duplicate => (Icons.history_rounded, c.verdictBad),
                      _K.notEntitled => (Icons.block_rounded, c.verdictBad),
                      _K.invalid => (Icons.help_rounded, c.muted),
                    };
                    return Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      decoration: BoxDecoration(
                        color: i == 0 && bad ? c.stopSoft : null,
                        borderRadius: i == 0 && bad ? BorderRadius.circular(10) : null,
                        border: i == 0 && bad ? null : Border(bottom: BorderSide(color: c.lineSoft)),
                      ),
                      child: Row(children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(v.a?.displayName ?? v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 14, w: FontWeight.w600)),
                            Text(v.short, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 12, color: c.muted)),
                          ]),
                        ),
                        Text(faDigits(hm(v.at)), style: nvText(context, 12, w: FontWeight.w600, color: c.muted)),
                      ]),
                    );
                  }),
              ]),
      ),
    ]);
  }
}
