// پذیرش روی اندروید (طرح ۴ تا ۸): شروع، جستجو، شیت فرد، «پذیرش شد» با برگرداندن ۸ ثانیه‌ای، تکراری، و اسکن.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../screens/checkin.dart' show batchLetter, showCompleteInfo, showLinkCard;
import '../store.dart';
import '../theme/widgets.dart' show verdictHaptic;
import 'meal.dart' show NvCameraPermission;
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'walkin.dart';

class NvCheckinTab extends StatefulWidget {
  final TextEditingController query;
  final VoidCallback onOpenStatus;
  const NvCheckinTab({super.key, required this.query, required this.onOpenStatus});

  @override
  State<NvCheckinTab> createState() => _NvCheckinTabState();
}

class _NvCheckinTabState extends State<NvCheckinTab> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(Attendee a) async {
    FocusScope.of(context).unfocus();
    final next = await showCheckinSheet(context, a.id);
    if (next == true && mounted) {
      widget.query.clear();
      setState(() {});
      _focus.requestFocus();
    }
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NvScanCheckinPage()));
    if (mounted) setState(() {});
  }

  void _walkin() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NvWalkinScreen(initialName: widget.query.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final q = widget.query.text.trim();
    final results = q.isEmpty ? <Attendee>[] : s.search(q);
    final total = s.attendees.length;
    final done = s.checkins.length;

    final header = NvHeader(
      bottom: q.isEmpty ? 76 : 70,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(deviceLine(s), style: nvText(context, 13, w: FontWeight.w500, color: Colors.white.withValues(alpha: .85))),
            Text(s.eventName.isEmpty ? 'پذیرش' : s.eventName,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 22, w: FontWeight.w800, color: Colors.white, height: 1.45)),
          ]),
        ),
        const SizedBox(width: 12),
        NvSyncPill(onOpenStatus: widget.onOpenStatus),
      ]),
    );

    final search = Row(children: [
      Expanded(
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Nv.r18),
            border: Border.all(color: c.brand, width: 2),
            boxShadow: q.isEmpty ? null : Nv.raised(c),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 22, color: c.brandText),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.query,
                focusNode: _focus,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.search,
                style: nvText(context, 17, w: q.isEmpty ? FontWeight.w400 : FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: 'نام، نام خانوادگی یا موبایل',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (results.length == 1) _open(results.first);
                },
              ),
            ),
            if (q.isNotEmpty)
              IconButton(
                tooltip: 'پاک کردن',
                icon: Icon(Icons.close_rounded, size: 20, color: c.faint),
                onPressed: () => setState(widget.query.clear),
              ),
          ]),
        ),
      ),
      if (s.cameraScan) ...[
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'اسکن کارت',
          excludeSemantics: true,
          child: Material(
            color: c.brand,
            borderRadius: BorderRadius.circular(Nv.r18),
            child: InkWell(
              borderRadius: BorderRadius.circular(Nv.r18),
              onTap: _scan,
              child: const SizedBox.square(dimension: 56, child: Icon(Icons.qr_code_scanner_rounded, size: 26, color: Colors.white)),
            ),
          ),
        ),
      ],
    ]);

    final mine = s.checkins.entries
        .where((e) => s.staffId != null && e.value.staffId == s.staffId && s.attendees[e.key] != null)
        .toList()
      ..sort((p, r) => r.value.at.compareTo(p.value.at));

    return Stack(children: [
      ListView(
        padding: const EdgeInsets.only(bottom: 110),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          header,
          Transform.translate(
            offset: Offset(0, q.isEmpty ? -60 : -32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Nv.gutter),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (q.isEmpty) ...[
                  NvCard(
                    raised: true,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: Row(children: [
                      NvRing(value: total == 0 ? 0 : done / total),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('پذیرش‌شده', style: nvText(context, 13, color: c.muted)),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${faDigits(done)} '),
                              TextSpan(text: 'از ${faDigits(total)} نفر', style: nvText(context, 15, w: FontWeight.w600, color: c.muted)),
                            ]),
                            style: nvText(context, 24, w: FontWeight.w800, height: 1.35),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                search,
                const SizedBox(height: 14),
                if (q.isEmpty) ...[
                  if (mine.isEmpty)
                    NvEmpty(
                      icon: Icons.search_rounded,
                      title: 'چند حرف از نام یا موبایل را بنویسید',
                      hint: s.cameraScan ? 'یا کارت را با دکمه‌ی کنار جستجو اسکن کنید.' : null,
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                      child: Row(children: [
                        Expanded(child: Text('آخرین پذیرش‌های این گوشی', style: nvText(context, 15, w: FontWeight.w700))),
                        Text('برای بررسی سریع', style: nvText(context, 12, color: c.muted)),
                      ]),
                    ),
                    NvCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final (i, e) in mine.take(5).indexed)
                          _RecentRow(a: s.attendees[e.key]!, at: e.value.at, last: i == mine.take(5).length - 1, onTap: () => _open(s.attendees[e.key]!)),
                      ]),
                    ),
                  ],
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('${faDigits(results.length)} نتیجه · ${faDigits(done)} از ${faDigits(total)} پذیرش شده',
                        style: nvText(context, 13, w: FontWeight.w600, color: c.muted)),
                  ),
                  const SizedBox(height: 10),
                  for (final a in results) ...[
                    NvAttendeeRow(a: a, query: q, onTap: () => _open(a)),
                    const SizedBox(height: 10),
                  ],
                  if (results.isEmpty) NvEmpty(icon: Icons.person_search_rounded, title: 'کسی با «$q» پیدا نشد'),
                  _DashedButton(label: 'پیدا نشد؟ ثبت‌نام «$q» در محل', icon: Icons.person_add_rounded, onTap: _walkin),
                ],
              ]),
            ),
          ),
        ],
      ),
    ]);
  }
}

class _RecentRow extends StatelessWidget {
  final Attendee a;
  final DateTime at;
  final bool last;
  final VoidCallback onTap;
  const _RecentRow({required this.a, required this.at, required this.last, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final card = s.usesCards ? s.cardOf(a.id) : null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.goSoft, borderRadius: BorderRadius.circular(Nv.r12)),
            child: Icon(Icons.check_circle_rounded, size: 22, color: c.go),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 15, w: FontWeight.w700)),
              if (card != null) Text('کارت ${faDigits(card.serial)}', style: nvText(context, 12, color: c.muted)),
            ]),
          ),
          Text(faDigits(hm(at)), style: nvText(context, 13, w: FontWeight.w700, color: c.go)),
        ]),
      ),
    );
  }
}

class _DashedButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DashedButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(Nv.r18),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashPainter(c.line),
        child: SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 22, color: c.brandText),
            const SizedBox(width: 8),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: nvText(context, 15, w: FontWeight.w700, color: c.brandText))),
          ]),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Nv.r18)));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// ردیف نتیجه: مربع حرف دسته (یا تیک سبز اگر پذیرش شده)، نام با بخش پیداشده، و چیپ کارت یا ساعت پذیرش.
class NvAttendeeRow extends StatelessWidget {
  final Attendee a;
  final String query;
  final VoidCallback onTap;
  const NvAttendeeRow({super.key, required this.a, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final state = s.checkins[a.id];
    final card = s.usesCards ? s.cardOf(a.id) : null;
    final sub = [s.roleName(a.roleId).isNotEmpty ? s.roleName(a.roleId) : s.typeName(a.registrationTypeId), a.organization]
        .where((e) => e.isNotEmpty)
        .join(' · ');
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Nv.r18),
      child: InkWell(
        borderRadius: BorderRadius.circular(Nv.r18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Nv.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: state != null ? c.goSoft : c.brandSoft, borderRadius: BorderRadius.circular(Nv.r14)),
                child: state != null
                    ? Icon(Icons.check_circle_rounded, size: 24, color: c.go)
                    : Text(s.usesCards ? batchLetter(a) : (a.displayName.isEmpty ? '؟' : a.displayName.characters.first),
                        style: nvText(context, 18, w: FontWeight.w800, color: c.brandText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Highlighted(text: a.displayName, query: query, style: nvText(context, 16, w: FontWeight.w700, height: 1.5)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 13, color: c.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              if (state != null)
                _Pill(text: 'پذیرش ${faDigits(hm(state.at))}', bg: c.goSoft, fg: c.go)
              else if (card != null)
                _Pill(text: 'کارت ${faDigits(card.serial)}', bg: c.field, fg: c.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: nvText(context, 12, w: FontWeight.w700, color: fg)),
      );
}

class _Highlighted extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  const _Highlighted({required this.text, required this.query, required this.style});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final q = query.trim();
    final i = q.isEmpty ? -1 : text.indexOf(q);
    if (i < 0) return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(text: text.substring(i, i + q.length), style: TextStyle(backgroundColor: c.brand.withValues(alpha: .22))),
        TextSpan(text: text.substring(i + q.length)),
      ]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

// ---------------------------------------------------------------- شیت فرد

/// شیت پذیرش یک نفر. true یعنی «نفر بعدی».
Future<bool?> showCheckinSheet(BuildContext context, String attendeeId) =>
    showNvSheet<bool>(context, (c) => NvCheckinPanel(attendeeId: attendeeId, onNext: () => Navigator.of(c).pop(true)));

/// محتوای شیت پذیرش: آماده، «پذیرش شد» با برگرداندن، یا «قبلاً پذیرش شده».
class NvCheckinPanel extends StatefulWidget {
  final String attendeeId;
  final VoidCallback onNext;
  final Widget? footer;
  const NvCheckinPanel({super.key, required this.attendeeId, required this.onNext, this.footer});

  @override
  State<NvCheckinPanel> createState() => _NvCheckinPanelState();
}

class _NvCheckinPanelState extends State<NvCheckinPanel> {
  bool _done = false;
  DateTime? _doneAt;
  Timer? _undoTimer;
  static const _undoSeconds = 8;
  int _left = _undoSeconds;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _checkin(AppStore s, Attendee a) {
    s.checkin(a);
    verdictHaptic(true);
    setState(() {
      _done = true;
      _doneAt = DateTime.now();
      _left = _undoSeconds;
    });
    _undoTimer?.cancel();
    _undoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  void _undo(AppStore s, Attendee a) {
    _undoTimer?.cancel();
    s.undoCheckin(a);
    setState(() {
      _done = false;
      _left = 0;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('پذیرش ${a.fullName} برگردانده شد.')));
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final a = s.attendees[widget.attendeeId];
    if (a == null) return const SizedBox.shrink();
    final state = s.checkins[a.id];
    final card = s.usesCards ? s.cardOf(a.id) : null;
    final letter = batchLetter(a);
    final tags = [
      s.typeName(a.registrationTypeId),
      s.roleName(a.roleId),
      if (a.presentationKind == 'oral') 'ارائه‌ی شفاهی',
      if (a.presentationKind == 'poster') 'ارائه‌ی پوستری',
      if (a.source == 'walkin') 'ثبت‌نام در محل',
      if (a.source == 'register') 'ثبت‌نام سایت',
    ].where((e) => e.isNotEmpty).toList();

    if (_done) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.goSoft, borderRadius: BorderRadius.circular(Nv.r18)),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.go, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('پذیرش شد', style: nvText(context, 20, w: FontWeight.w800, color: c.goInk)),
                Text('${a.displayName} · ${faDigits(hm(_doneAt!))}', style: nvText(context, 14, color: c.goInk)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (s.usesCards) ...[
          Text(card == null ? 'این فرد کارت ندارد؛ پذیرایی‌اش با جستجوی نام انجام می‌شود.' : 'کارت چاپی را تحویل بدهید',
              textAlign: TextAlign.center, style: nvText(context, 15, w: FontWeight.w600, color: c.muted)),
          if (card != null) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              NvLetter(letter, size: 84),
              const SizedBox(width: 12),
              Container(
                height: 84,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Nv.r18), border: Border.all(color: c.ink, width: 3)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('کارت', style: nvText(context, 12, w: FontWeight.w600, color: c.muted)),
                  Text(faDigits(card.serial), style: nvText(context, 40, w: FontWeight.w800, height: 1.1)),
                ]),
              ),
            ]),
          ],
          const SizedBox(height: 16),
        ],
        NvButton(label: 'نفر بعدی', height: Nv.buttonXl, onPressed: widget.onNext),
        if (_left > 0) ...[
          const SizedBox(height: 12),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r16)),
            child: Row(children: [
              Icon(Icons.undo_rounded, size: 20, color: c.muted),
              const SizedBox(width: 8),
              Expanded(child: Text('اشتباه زدم؟', style: nvText(context, 14, color: c.muted))),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () => _undo(s, a),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'برگردان '),
                  TextSpan(text: '${faDigits(_left)} ثانیه', style: nvText(context, 13, color: c.muted)),
                ])),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: _left / _undoSeconds, minHeight: 4, color: c.line, backgroundColor: c.lineSoft),
          ),
        ],
      ]);
    }

    final children = <Widget>[
      Text(a.displayName, style: nvText(context, 28, w: FontWeight.w800, height: 1.4)),
      if (tags.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) NvTag(t, outline: t.startsWith('ارائه') || t.startsWith('ثبت‌نام'))]),
      ],
      if (a.organization.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(a.organization, style: nvText(context, 15, color: c.muted)),
      ],
      ..._warnings(context, s, a),
    ];

    if (state != null) {
      final by = state.staffId != null ? s.staffNames[state.staffId] : null;
      children.addAll([
        const SizedBox(height: 14),
        NvBanner(
          tone: NvTone.wait,
          icon: Icons.history_rounded,
          title: 'قبلاً پذیرش شده',
          text: ['ساعت ${faDigits(hm(state.at))}', if (by != null) 'نیرو: $by'].join(' · '),
        ),
        if (card != null) ...[
          const SizedBox(height: 14),
          NvPlateRow(letter: letter, title: 'کارت ${faDigits(card.serial)}', hint: 'کارت گم‌شده دوباره صادر نمی‌شود'),
        ],
        const SizedBox(height: 14),
        NvButton(label: 'باشه، نفر بعدی', onPressed: widget.onNext),
        const SizedBox(height: 12),
        if (s.isAdmin)
          NvSoftButton(
            label: 'لغو پذیرش (مدیر)',
            icon: Icons.admin_panel_settings_rounded,
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('لغو پذیرش'),
                  content: Text('پذیرش ${a.fullName} لغو شود؟ در گزارش ثبت می‌شود.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: c.stop), onPressed: () => Navigator.pop(d, true), child: const Text('لغو پذیرش')),
                  ],
                ),
              );
              if (ok == true) s.undoCheckin(a);
            },
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r16)),
            child: Row(children: [
              Icon(Icons.admin_panel_settings_rounded, size: 20, color: c.muted),
              const SizedBox(width: 10),
              Expanded(child: Text('لغو پذیرش فقط برای نیروی «مدیر» است و در گزارش ثبت می‌شود.', style: nvText(context, 13, color: c.muted, height: 1.5))),
            ]),
          ),
      ]);
    } else {
      children.addAll([
        if (card != null) ...[
          const SizedBox(height: 14),
          NvPlateRow(letter: letter, title: 'دسته‌ی «$letter» · کارت ${faDigits(card.serial)}', hint: 'کارت چاپی را از این دسته بردارید'),
        ],
        const SizedBox(height: 14),
        NvButton(label: 'تیک پذیرش', icon: Icons.check_rounded, color: c.go, height: 64, onPressed: () => _checkin(s, a)),
      ]);
    }
    if (widget.footer != null) children.addAll([const SizedBox(height: 12), widget.footer!]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  /// اطلاعات ناقص، تماس مشترک، تسویه در روز اجرا، بدون کارت.
  List<Widget> _warnings(BuildContext context, AppStore s, Attendee a) {
    final out = <Widget>[];
    void add(Widget w) => out.addAll([const SizedBox(height: 12), w]);
    final noFirst = a.firstName.trim().isEmpty || a.firstName.startsWith('بی‌نام (ردیف ');
    final missing = [if (noFirst) 'نام', if (a.lastName.trim().isEmpty) 'نام خانوادگی'];
    if (missing.isNotEmpty) {
      add(NvBanner(
        tone: NvTone.wait,
        title: 'اطلاعات ناقص',
        text: '${missing.join(' و ')} این فرد در ثبت‌نام وارد نشده؛ از خود اوست، نه از اپ. پذیرش مشکلی ندارد؛ از خودش بپرسید و تکمیل کنید.',
        action: OutlinedButton.icon(onPressed: () => showCompleteInfo(context, a), icon: const Icon(Icons.edit_rounded), label: const Text('تکمیل اطلاعات')),
      ));
    }
    final shared = s.sharingContact(a);
    if (shared.isNotEmpty) {
      add(NvBanner(
        tone: NvTone.info,
        title: 'ایمیل یا موبایل مشترک',
        text: 'ایمیل یا موبایل این فرد با ${shared.take(3).map((o) => '«${o.displayName}»').join('، ')} یکی است. مطمئن شوید همین شخص است.',
      ));
    }
    if (a.onsiteDue > 0) {
      final owed = s.onsiteOwed(a);
      final what = a.onsiteNote.isEmpty ? '' : ' برای ${a.onsiteNote}';
      if (owed > 0) {
        add(NvBanner(
          tone: NvTone.wait,
          icon: Icons.payments_rounded,
          title: 'تسویه در روز اجرا',
          text: '${moneyFa(a.onsiteDue)}$what تسویه نشده است. مبلغ را بگیرید و «تسویه شد» را بزنید.',
          action: OutlinedButton.icon(
            icon: const Icon(Icons.payments_rounded),
            label: const Text('تسویه شد'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('تسویه شد؟'),
                  content: Text('${moneyFa(a.onsiteDue)}$what از ${a.fullName} گرفته شد؟ در گزارش ثبت می‌شود.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تسویه شد')),
                  ],
                ),
              );
              if (ok == true) s.settleOnsite(a);
            },
          ),
        ));
      } else {
        add(NvBanner(tone: NvTone.go, text: '${moneyFa(a.onsiteDue)}$what تسویه شده است.'));
      }
    }
    if (s.usesCards && s.cardOf(a.id) == null) {
      add(NvBanner(
        tone: NvTone.neutral,
        icon: Icons.credit_card_off_rounded,
        title: 'بدون کارت',
        text: 'این فرد کارت ندارد (هنگام ثبت‌نام کارت رزرو تمام شده بود).',
        action: OutlinedButton.icon(
          onPressed: s.freeReserveCards.isEmpty ? null : () => showLinkCard(context, a),
          icon: const Icon(Icons.add_card_rounded),
          label: Text(s.freeReserveCards.isEmpty ? 'کارت رزرو آزادی نیست' : 'وصل‌کردن کارت رزرو'),
        ),
      ));
    }
    return out;
  }
}

// ---------------------------------------------------------------- اسکن پذیرش

/// اسکن کارت با دوربین؛ با خواندن کارت، شیت فرد روی همان دوربین باز می‌شود (طرح ۶).
class NvScanCheckinPage extends StatefulWidget {
  const NvScanCheckinPage({super.key});

  @override
  State<NvScanCheckinPage> createState() => _NvScanCheckinPageState();
}

class _NvScanCheckinPageState extends State<NvScanCheckinPage> {
  final _cam = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  String? _attendeeId;
  String? _problem;
  int _rev = 0;

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_attendeeId != null) return;
    final s = StoreScope.read(context);
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final token = tokenFromScan(raw);
      if (token == null) {
        setState(() => _problem = 'این QR مال کارت کنفرانس نیست.');
        return;
      }
      final a = s.attendeeForToken(token);
      if (a == null) {
        setState(() => _problem = s.cards.containsKey(token) ? 'این کارت رزرو هنوز به کسی وصل نشده.' : 'این کارت در لیست نیست.');
        verdictHaptic(false);
        return;
      }
      setState(() {
        _attendeeId = a.id;
        _problem = null;
        _rev++;
      });
      return;
    }
  }

  void _reset() => setState(() {
        _attendeeId = null;
        _problem = null;
      });

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _cam,
            onDetect: _onDetect,
            errorBuilder: (context, error) => NvCameraPermission(
              onRetry: () => _cam.start(),
              onByName: () => Navigator.of(context).pop(),
              byNameLabel: 'برگشت به جستجوی نام',
            ),
          ),
        ),
        const Positioned.fill(child: IgnorePointer(child: _Frame(top: .3))),
        Positioned(
          top: top + 12,
          left: 16,
          right: 16,
          child: Row(children: [
            NvRoundIcon(icon: Icons.close_rounded, label: 'بستن اسکن', onTap: () => Navigator.of(context).pop()),
            Expanded(child: Text('اسکن کارت', textAlign: TextAlign.center, style: nvText(context, 16, w: FontWeight.w700, color: Colors.white))),
            NvRoundIcon(icon: Icons.flashlight_on_rounded, label: 'چراغ قوه', onTap: () => _cam.toggleTorch()),
          ]),
        ),
        if (_attendeeId != null || _problem != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .78),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Nv.r28)),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 30, offset: Offset(0, -8))],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + MediaQuery.paddingOf(context).bottom),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NvHandle(),
                  const SizedBox(height: 10),
                  if (_problem != null) ...[
                    NvBanner(tone: NvTone.stop, title: 'کارت شناخته نشد', text: _problem!),
                    const SizedBox(height: 12),
                    NvButton(label: 'دوباره اسکن کن', icon: Icons.qr_code_scanner_rounded, onPressed: _reset),
                  ] else ...[
                    Row(children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 18, color: c.brandText),
                      const SizedBox(width: 8),
                      Text('کارت خوانده شد', style: nvText(context, 13, w: FontWeight.w700, color: c.brandText)),
                    ]),
                    const SizedBox(height: 8),
                    NvCheckinPanel(
                      key: ValueKey(_rev),
                      attendeeId: _attendeeId!,
                      onNext: _reset,
                      footer: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'کارت مال این شخص نیست؟ '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: InkWell(
                              onTap: _reset,
                              child: Text('برگرد و دوباره اسکن کن', style: nvText(context, 13, w: FontWeight.w700, color: c.brandText)),
                            ),
                          ),
                        ]),
                        textAlign: TextAlign.center,
                        style: nvText(context, 13, color: c.muted),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// کادر چهارگوشه‌ی سفید روی دوربین.
class _Frame extends StatelessWidget {
  final double top;
  const _Frame({required this.top});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, k) {
        const size = 220.0;
        return Stack(children: [
          Positioned(
            left: (k.maxWidth - size) / 2,
            top: k.maxHeight * top - size / 2,
            child: const SizedBox.square(dimension: size, child: CustomPaint(painter: NvCornersPainter())),
          ),
        ]);
      });
}

class NvCornersPainter extends CustomPainter {
  const NvCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 42.0, r = 14.0;
    final w = size.width, h = size.height;
    void corner(Offset o, double sx, double sy) {
      final path = Path()
        ..moveTo(o.dx, o.dy + sy * l)
        ..lineTo(o.dx, o.dy + sy * r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + sx * r, o.dy)
        ..lineTo(o.dx + sx * l, o.dy);
      canvas.drawPath(path, p);
    }

    corner(Offset.zero, 1, 1);
    corner(Offset(w, 0), -1, 1);
    corner(Offset(0, h), 1, -1);
    corner(Offset(w, h), -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
