// پذیرش در ویندوز (طرح ۱ تا ۶ و ۱۳): جستجو و نتایج در یک ستون، پنل فرد در کنار؛
// Enter پذیرش یا نفر بعدی، ↑↓ انتخاب، Esc پاک کردن، Ctrl+Z برگرداندن، Ctrl+N ثبت‌نام در محل.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/checkin.dart';
import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../android/walkin.dart';
import '../brand.dart';
import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../android/attendee_dialogs.dart' show batchLetter;
import '../store.dart';
import 'scan_field.dart';

class DeskCheckinTab extends StatefulWidget {
  final TextEditingController query;
  final bool wide;
  final bool walkin;
  final VoidCallback onWalkin;
  final VoidCallback onCloseWalkin;
  const DeskCheckinTab({
    super.key,
    required this.query,
    required this.wide,
    required this.walkin,
    required this.onWalkin,
    required this.onCloseWalkin,
  });

  @override
  State<DeskCheckinTab> createState() => _DeskCheckinTabState();
}

class _DeskCheckinTabState extends State<DeskCheckinTab> {
  final _focus = FocusNode();
  int _sel = 0;

  /// فردی که پنل روی او ثابت مانده (اسکن، یا بعد از پذیرش تا «نفر بعدی»).
  String? _pinned;
  GlobalKey<NvCheckinPanelState> _panelKey = GlobalKey();
  String? _panelFor;

  @override
  void didUpdateWidget(DeskCheckinTab old) {
    super.didUpdateWidget(old);
    if (old.walkin && !widget.walkin) _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// نتایج جستجو؛ شماره‌ی کارت («۲۱۳» یا «R5001») هم پیدا می‌شود.
  List<Attendee> _results(AppStore s) {
    final out = s.search(widget.query.text);
    final n = int.tryParse(latinDigits(widget.query.text.trim()).replaceFirst(RegExp(r'^[Rrر]\s*'), ''));
    if (n != null && s.usesCards) {
      for (final c in s.cards.values) {
        if (c.serial != n) continue;
        final a = s.attendeeForToken(c.token);
        if (a != null && !out.contains(a)) out.insert(0, a);
      }
    }
    return out;
  }

  void _next() {
    setState(() {
      _pinned = null;
      _sel = 0;
    });
    widget.query.clear();
    _focus.requestFocus();
  }

  bool _onScan(String raw) {
    final s = StoreScope.read(context);
    final token = tokenFromScan(raw);
    final m = ScaffoldMessenger.of(context);
    if (token == null) {
      m.showSnackBar(const SnackBar(content: Text('این QR مال کارت کنفرانس نیست.')));
      return false;
    }
    final a = s.attendeeForToken(token);
    if (a == null) {
      m.showSnackBar(SnackBar(content: Text(s.cards.containsKey(token) ? 'این کارت رزرو هنوز به کسی وصل نشده.' : 'این کارت در لیست نیست.')));
      return true;
    }
    setState(() => _pinned = a.id);
    return true;
  }

  void _enter(List<Attendee> results) {
    final st = _panelKey.currentState;
    if (st != null) {
      st.primary();
      return;
    }
    if (!widget.wide && results.isNotEmpty) _openSheet(results[_sel.clamp(0, results.length - 1)]);
  }

  Future<void> _openSheet(Attendee a) async {
    final next = await showCheckinSheet(context, a.id);
    if (next == true && mounted) _next();
    _focus.requestFocus();
  }

  KeyEventResult _onKey(KeyEvent e, int count) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.arrowDown && count > 0) {
      setState(() {
        _pinned = null;
        _sel = (_sel + 1).clamp(0, count - 1);
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && count > 0) {
      setState(() {
        _pinned = null;
        _sel = (_sel - 1).clamp(0, count - 1);
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _next();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      return (_panelKey.currentState?.undo() ?? false) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final q = widget.query.text.trim();
    final results = q.isEmpty ? const <Attendee>[] : _results(s);
    if (_sel >= results.length) _sel = results.isEmpty ? 0 : results.length - 1;
    final paneId = _pinned ?? (results.isEmpty ? null : results[_sel].id);
    if (paneId != _panelFor) {
      _panelFor = paneId;
      _panelKey = GlobalKey();
    }
    final doneOrPinned = _pinned != null && q.isEmpty;

    final search = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _onKey(e, results.length),
      child: NvScanField(
        controller: widget.query,
        focusNode: _focus,
        scanEnabled: s.scanEnabled,
        hint: _pinned != null && q.isEmpty
            ? 'نفر بعدی را بنویسید یا اسکن کنید'
            : (s.usesCards ? 'نام، موبایل یا شماره‌ی کارت را بنویسید' : 'نام، نام خانوادگی یا موبایل را بنویسید'),
        onChanged: (_) => setState(() {
          _sel = 0;
          _pinned = null;
        }),
        onSubmitted: (_) => _enter(results),
        onScan: _onScan,
      ),
    );

    final total = s.attendees.length;
    final done = s.checkins.length;
    final left = Padding(
      padding: EdgeInsets.fromLTRB(widget.wide ? 24 : 16, 20, widget.wide ? 24 : 16, widget.wide ? 16 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        search,
        const SizedBox(height: 14),
        if (q.isEmpty)
          Expanded(child: Opacity(opacity: doneOrPinned && widget.wide ? .55 : 1, child: _StartView(onPick: (a) => setState(() => _pinned = a.id))))
        else ...[
          Row(children: [
            Text(results.isEmpty ? 'نتیجه‌ای نیست' : '${faDigits(results.length)} نتیجه', style: nvText(context, 13, w: FontWeight.w700, color: c.muted)),
            const SizedBox(width: 16),
            if (widget.wide) ...[
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 6, color: c.brand, backgroundColor: c.lineSoft),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text('پذیرش‌شده ${faDigits(done)} از ${faDigits(total)}', style: nvText(context, 13, w: FontWeight.w700)),
            ],
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16)),
              child: ListView(padding: EdgeInsets.zero, children: [
                for (var i = 0; i < results.length; i++)
                  _DeskRow(
                    a: results[i],
                    query: q,
                    selected: i == _sel && _pinned == null,
                    first: i == 0,
                    onTap: () {
                      setState(() {
                        _sel = i;
                        _pinned = null;
                      });
                      if (!widget.wide) _openSheet(results[i]);
                      _focus.requestFocus();
                    },
                  ),
                if (s.canCheckin)
                  InkWell(
                    onTap: widget.onWalkin,
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.person_add_rounded, color: c.brandText),
                        const SizedBox(width: 8),
                        Text('پیدا نشد؟ ثبت‌نام «$q» در محل', style: nvText(context, 15, w: FontWeight.w700, color: c.brandText)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ],
        if (widget.wide) ...[
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink,
                  side: BorderSide(color: c.line, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r14)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: widget.onWalkin,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_add_rounded, size: 22, color: c.brand),
                  const SizedBox(width: 8),
                  Text('ثبت‌نام در محل', style: nvText(context, 14, w: FontWeight.w700)),
                  const SizedBox(width: 8),
                  const NvKbd('Ctrl+N'),
                ]),
              ),
            ),
            const Spacer(),
            const Wrap(spacing: 14, children: [
              NvKeyHint(['↑', '↓'], 'انتخاب'),
              NvKeyHint(['Esc'], 'پاک کن'),
              NvKeyHint(['Ctrl+Z'], 'اشتباه زدم'),
            ]),
          ]),
        ],
      ]),
    );

    if (!widget.wide) {
      final sel = paneId == null ? null : s.attendees[paneId];
      return Column(children: [
        Expanded(child: left),
        if (sel != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
            child: NvButton(
              label: s.checkins[sel.id] != null ? 'قبلاً پذیرش شده · ${sel.firstName}' : 'تیک پذیرش ${sel.firstName}',
              icon: s.checkins[sel.id] != null ? Icons.history_rounded : Icons.check_rounded,
              color: s.checkins[sel.id] != null ? c.brand : c.go,
              height: 60,
              onPressed: () => _openSheet(sel),
            ),
          ),
      ]);
    }

    final Widget panel;
    if (widget.walkin) {
      panel = NvWalkinScreen(key: const ValueKey('walkin'), panel: true, initialName: q, onClose: widget.onCloseWalkin);
    } else if (paneId != null) {
      panel = NvCheckinPanel(
        key: _panelKey,
        attendeeId: paneId,
        desk: true,
        onNext: _next,
        onCheckedIn: () {
          setState(() => _pinned = paneId);
          widget.query.clear();
          _focus.requestFocus();
        },
        footer: const _MakerLine(),
      );
    } else {
      panel = const _EmptyPanel();
    }

    return Row(children: [
      Expanded(
        child: IgnorePointer(
          ignoring: widget.walkin,
          child: Opacity(opacity: widget.walkin ? .5 : 1, child: left),
        ),
      ),
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.walkin ? 560 : 430,
        decoration: BoxDecoration(
          color: c.surface,
          border: BorderDirectional(start: BorderSide(color: c.lineSoft)),
          boxShadow: widget.walkin ? [BoxShadow(color: c.ink.withValues(alpha: .08), blurRadius: 30, offset: const Offset(-12, 0))] : null,
        ),
        padding: const EdgeInsets.all(24),
        child: panel,
      ),
    ]);
  }
}

class _MakerLine extends StatelessWidget {
  const _MakerLine();

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'ساخته‌ی '),
        TextSpan(text: makerTeam, style: nvText(context, 12, w: FontWeight.w700)),
        const TextSpan(text: ' · '),
        const TextSpan(text: makerEmail),
      ]),
      textAlign: TextAlign.center,
      style: nvText(context, 12, color: c.muted, height: 1.6),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StoreScope.of(context);
    return Column(children: [
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
              child: Icon(Icons.person_search_rounded, size: 44, color: c.brandText),
            ),
            const SizedBox(height: 14),
            Text('نفر را پیدا کنید', style: nvText(context, 20, w: FontWeight.w800)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                s.scanEnabled
                    ? 'چند حرف از نام یا موبایل را بنویسید. اگر بارکدخوان دارید، کارت را اسکن کنید.'
                    : 'چند حرف از نام یا موبایل را بنویسید.',
                textAlign: TextAlign.center,
                style: nvText(context, 14, color: c.muted, height: 1.6),
              ),
            ),
            if (s.canCheckin) ...[
              const SizedBox(height: 14),
              const NvKeyHint(['Ctrl+N'], 'ثبت‌نام در محل'),
            ],
          ]),
        ),
      ),
      const _MakerLine(),
    ]);
  }
}

/// وقتی جستجو خالی است: آمار و آخرین پذیرش‌های این میز.
class _StartView extends StatelessWidget {
  final ValueChanged<Attendee> onPick;
  const _StartView({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final total = s.attendees.length;
    final done = s.checkins.length;
    final walkins = s.attendees.values.where((a) => a.source == 'walkin').length;
    final (deskCount, deskFirst) = s.deskCheckinsToday();
    final recent = [
      for (final e in [...s.serverLog, ...s.pending].reversed)
        if (e.kind == 'checkin' && s.deskStaffIds.contains(e.staffId) && e.attendeeId != null && s.checkins.containsKey(e.attendeeId)) e,
    ];
    final seen = <String>{};
    final rows = recent.where((e) => seen.add(e.attendeeId!)).take(6).toList();

    Widget stat(String label, Widget value, Widget foot) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: nvText(context, 13, w: FontWeight.w600, color: c.muted)),
              const SizedBox(height: 4),
              value,
              const SizedBox(height: 4),
              foot,
            ]),
          ),
        );

    return ListView(padding: EdgeInsets.zero, children: [
      Row(children: [
        stat(
          'پذیرش‌شده',
          Text.rich(TextSpan(children: [
            TextSpan(text: faDigits(done), style: nvText(context, 32, w: FontWeight.w800, height: 1.25)),
            TextSpan(text: ' از ${faDigits(total)}', style: nvText(context, 15, w: FontWeight.w600, color: c.muted)),
          ])),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 6, color: c.brand, backgroundColor: c.lineSoft),
          ),
        ),
        const SizedBox(width: 12),
        stat(
          'ثبت‌نام در محل',
          Text(faDigits(walkins), style: nvText(context, 32, w: FontWeight.w800, height: 1.25)),
          Text(s.usesCards ? '${faDigits(s.freeReserveCards.length)} کارت رزرو آزاد' : 'بدون کارت', style: nvText(context, 12, color: c.muted)),
        ),
        const SizedBox(width: 12),
        stat(
          'این میز امروز',
          Text(faDigits(deskCount), style: nvText(context, 32, w: FontWeight.w800, height: 1.25)),
          Text(deskFirst == null ? 'هنوز پذیرشی نیست' : 'از ساعت ${faDigits(hm(deskFirst))}', style: nvText(context, 12, color: c.muted)),
        ),
      ]),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Expanded(child: Text('آخرین پذیرش‌های این میز', style: nvText(context, 16, w: FontWeight.w800))),
          Text('برای بررسی سریع', style: nvText(context, 12, color: c.muted)),
        ]),
      ),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16)),
          child: Text('هنوز پذیرشی روی این دستگاه نیست.', style: nvText(context, 14, color: c.muted)),
        )
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16)),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++)
              Builder(builder: (context) {
                final a = s.attendees[rows[i].attendeeId];
                if (a == null) return const SizedBox.shrink();
                final card = s.usesCards ? s.cardOf(a.id) : null;
                return InkWell(
                  onTap: () => onPick(a),
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.lineSoft))),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded, size: 24, color: c.go),
                      const SizedBox(width: 14),
                      Expanded(child: Text(a.displayName, style: nvText(context, 16, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                      if (card != null) Text('کارت ${faDigits(card.serial)}', style: nvText(context, 13, color: c.muted)),
                      SizedBox(
                        width: 60,
                        child: Text(faDigits(hm(s.checkins[a.id]!.at)),
                            textAlign: TextAlign.left, style: nvText(context, 13, w: FontWeight.w700, color: c.go)),
                      ),
                    ]),
                  ),
                );
              }),
          ]),
        ),
    ]);
  }
}

/// ردیف نتیجه: حرف دسته (یا تیک سبز برای پذیرش‌شده)، نام با بخش پیداشده، کارت یا ساعت پذیرش.
class _DeskRow extends StatelessWidget {
  final Attendee a;
  final String query;
  final bool selected;
  final bool first;
  final VoidCallback onTap;
  const _DeskRow({required this.a, required this.query, required this.selected, required this.first, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final state = s.checkins[a.id];
    final card = s.usesCards ? s.cardOf(a.id) : null;
    final sub = [s.roleName(a.roleId), s.typeName(a.registrationTypeId), a.organization].where((e) => e.isNotEmpty).join(' · ');
    return Material(
      color: selected ? Color.alphaBlend(c.brand.withValues(alpha: .10), c.surface) : c.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: BorderDirectional(
              top: first ? BorderSide.none : BorderSide(color: c.lineSoft),
              start: selected ? BorderSide(color: c.brand, width: 4) : BorderSide.none,
            ),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state != null ? c.goSoft : (selected ? c.surface : c.chip),
                borderRadius: BorderRadius.circular(Nv.r12),
                border: selected && state == null ? Border.all(color: c.brand, width: 1.5) : null,
              ),
              child: state != null
                  ? Icon(Icons.check_circle_rounded, size: 26, color: c.go)
                  : Text(batchLetter(a), style: nvText(context, 19, w: FontWeight.w800, color: c.brandText)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(_marked(context, a.displayName, query, nvText(context, 17, w: FontWeight.w700)), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty)
                  Text.rich(_marked(context, sub, query, nvText(context, 13, color: c.muted)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (state != null) ...[
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: c.goSoft, borderRadius: BorderRadius.circular(15)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: c.goInk),
                  const SizedBox(width: 4),
                  Text('پذیرش ${faDigits(hm(state.at))}', style: nvText(context, 13, w: FontWeight.w700, color: c.goInk)),
                ]),
              ),
              const SizedBox(width: 10),
            ],
            if (card != null)
              Text(state != null ? faDigits(card.serial) : 'کارت ${faDigits(card.serial)}', style: nvText(context, 13, w: FontWeight.w700, color: c.muted)),
            if (selected) ...[const SizedBox(width: 10), const NvKbd('Enter')],
          ]),
        ),
      ),
    );
  }

  /// بخش‌هایی از متن که با کلمه‌های جستجو جور است، با پس‌زمینه‌ی کم‌رنگ برند.
  TextSpan _marked(BuildContext context, String text, String query, TextStyle style) {
    final c = NvColors.of(context);
    final words = query.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (words.isEmpty) return TextSpan(text: text, style: style);
    final hits = List<bool>.filled(text.length, false);
    for (final w in words) {
      var i = text.indexOf(w);
      while (i >= 0) {
        for (var k = i; k < i + w.length && k < text.length; k++) {
          hits[k] = true;
        }
        i = text.indexOf(w, i + w.length);
      }
    }
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      if (i == text.length || hits[i] != hits[start]) {
        spans.add(TextSpan(
          text: text.substring(start, i),
          style: hits[start] ? style.copyWith(backgroundColor: c.brand.withValues(alpha: .25)) : null,
        ));
        start = i;
      }
    }
    return TextSpan(style: style, children: spans);
  }
}
