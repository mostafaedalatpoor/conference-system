import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../store.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import '../widgets/scan_input.dart';
import 'scanner.dart';
import 'walkin.dart';

/// عرض‌های چیدمان (bp-medium، bp-expanded).
const bpMedium = 600.0;
const bpExpanded = 1024.0;

/// پذیرش: جستجوی زنده ← تیک ← تحویل کارت ← نفر بعدی.
/// زیر ۱۰۲۴px باتم‌شیت؛ از ۱۰۲۴px به بالا (ویندوز) پنل جزئیات ثابت ۴۴۰px و کار با صفحه‌کلید.
class CheckinScreen extends StatefulWidget {
  /// متن جستجو بالادستی نگه داشته می‌شود تا با تعویض تب از بین نرود.
  final TextEditingController? query;
  final FocusNode? focusNode;
  const CheckinScreen({super.key, this.query, this.focusNode});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  late final TextEditingController _q = widget.query ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  int _selected = 0;

  /// پنل دسکتاپ: فردی که نمایش داده می‌شود و اینکه همین الان پذیرش شده یا نه.
  String? _paneId;
  bool _paneDone = false;

  @override
  void dispose() {
    if (widget.query == null) _q.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  /// «نفر بعدی»: جستجو پاک و دوباره فوکوس می‌شود.
  void _next() {
    setState(() {
      _q.clear();
      _selected = 0;
      _paneId = null;
      _paneDone = false;
    });
    _focus.requestFocus();
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= bpExpanded;

  void _open(Attendee a) {
    if (_wide) {
      setState(() {
        _paneId = a.id;
        _paneDone = false;
      });
      _focus.requestFocus();
    } else {
      showAttendeeSheet(context, a, onNext: _next);
    }
  }

  void _notFound(String token) {
    final store = StoreScope.read(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(store.cards.containsKey(token) ? 'این کارت رزرو هنوز به کسی وصل نشده.' : 'این کارت در لیست نیست.'),
    ));
  }

  Future<void> _scanToFind() async {
    final store = StoreScope.read(context);
    final token = await ScannerPage.scan(context);
    if (token == null || !mounted) return;
    final a = store.attendeeForToken(token);
    if (a == null) return _notFound(token);
    _open(a);
  }

  /// اسکن با بارکدخوان (ویندوز).
  bool _onWedgeScan(String raw) {
    final store = StoreScope.read(context);
    final token = tokenFromScan(raw);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این QR مال کارت کنفرانس نیست.')));
      return false;
    }
    final a = store.attendeeForToken(token);
    if (a == null) {
      _notFound(token);
      return true;
    }
    _open(a);
    return true;
  }

  void _walkin() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WalkinScreen(initialName: _q.text.trim()),
      ));

  /// نتایج جستجو؛ شماره‌ی کارت («۲۱۳» یا «R5001») هم پیدا می‌شود.
  List<Attendee> _results(AppStore store) {
    final out = store.search(_q.text);
    final n = int.tryParse(latinDigits(_q.text.trim()).replaceFirst(RegExp(r'^[Rrر]\s*'), ''));
    if (n != null && store.usesCards) {
      for (final c in store.cards.values) {
        if (c.serial != n) continue;
        final a = store.attendeeForToken(c.token);
        if (a != null && !out.contains(a)) out.insert(0, a);
      }
    }
    return out;
  }

  /// Enter در دسکتاپ: تیک پذیرش نفر انتخاب‌شده؛ در حالت «انجام شد»، نفر بعدی.
  void _enter(AppStore store, List<Attendee> results) {
    if (!_wide) {
      if (results.length == 1) _open(results.first);
      return;
    }
    final a = _paneId != null ? store.attendees[_paneId] : (results.isEmpty ? null : results[_selected.clamp(0, results.length - 1)]);
    if (a == null) return;
    if (_paneDone || store.checkins[a.id] != null && _paneId == a.id) return _next();
    if (store.checkins[a.id] != null) {
      setState(() => _paneId = a.id);
      return;
    }
    store.checkin(a);
    HapticFeedback.lightImpact();
    setState(() {
      _paneId = a.id;
      _paneDone = true;
    });
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, List<Attendee> results) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _next();
      return KeyEventResult.handled;
    }
    if (!_wide || results.isEmpty) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown || e.logicalKey == LogicalKeyboardKey.arrowUp) {
      final d = e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        _selected = (_selected + d).clamp(0, results.length - 1);
        _paneId = null;
        _paneDone = false;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final q = _q.text.trim();
    final results = _results(store);
    final x = DaftarColors.of(context);
    final wide = _wide;
    final desk = !AppStore.hasCamera;
    final selected = results.isEmpty ? null : results[_selected.clamp(0, results.length - 1)];
    final paneAttendee = _paneId != null ? store.attendees[_paneId] : (q.isEmpty ? null : selected);

    final search = Padding(
      padding: const EdgeInsets.fromLTRB(DaftarSize.space4, DaftarSize.space3, DaftarSize.space4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ScanInputField(
              controller: _q,
              focusNode: _focus,
              scanEnabled: store.scanEnabled && desk,
              hint: store.usesCards ? 'نام، موبایل یا شماره‌ی کارت' : 'نام، نام خانوادگی یا موبایل',
              onChanged: (_) => setState(() {
                _selected = 0;
                if (!_paneDone) _paneId = null;
              }),
              onSubmitted: (_) => _enter(store, results),
              onScan: _onWedgeScan,
            ),
          ),
          if (store.cameraScan) ...[
            const SizedBox(width: DaftarSize.space2),
            Tooltip(
              message: 'اسکن کارت',
              child: SizedBox.square(
                dimension: DaftarSize.tapLg,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size.square(56)),
                  onPressed: _scanToFind,
                  child: const Icon(Icons.qr_code_scanner_rounded, semanticLabel: 'اسکن کارت'),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final list = q.isEmpty
        ? _Recent(onOpen: _open)
        : results.isEmpty
            ? SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'کسی با «$q» پیدا نشد',
                  hint: 'املای دیگر یا شماره‌ی موبایل را امتحان کنید.',
                  action: OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('ثبت‌نام در محل'),
                    onPressed: _walkin,
                  ),
                ),
              )
            : ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  for (var i = 0; i < results.length; i++)
                    AttendeeRow(
                      a: results[i],
                      query: q,
                      selected: wide && (paneAttendee?.id == results[i].id),
                      onTap: () {
                        setState(() => _selected = i);
                        _open(results[i]);
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.all(DaftarSize.space4),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text('پیدا نشد؟ ثبت‌نام در محل'),
                      onPressed: _walkin,
                    ),
                  ),
                ],
              );

    final column = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (n, e) => _onKey(n, e, results),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          Padding(
            padding: const EdgeInsets.fromLTRB(DaftarSize.space4, DaftarSize.space3, DaftarSize.space4, DaftarSize.space2),
            child: Meter(
              label: 'پذیرش‌شده',
              value: store.checkins.length,
              total: store.attendees.length,
              format: faDigits,
            ),
          ),
          Divider(color: x.line),
          Expanded(child: list),
          if (wide)
            Container(
              padding: const EdgeInsets.all(DaftarSize.space3),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: x.line))),
              child: KeyHints([
                ('Enter', 'تیک پذیرش / نفر بعدی'),
                ('↑ ↓', 'انتخاب'),
                ('Esc', 'پاک کردن'),
                ('Ctrl+N', 'ثبت‌نام در محل'),
                if (store.scanEnabled && desk) ('F4', 'ورودی اسکن'),
              ]),
            ),
        ],
      ),
    );

    if (!wide) return column;
    return Row(children: [
      Expanded(child: column),
      Container(
        width: 440,
        decoration: BoxDecoration(
          color: x.surface,
          border: BorderDirectional(start: BorderSide(color: x.line)),
        ),
        child: paneAttendee == null
            ? const Center(
                child: EmptyState(
                  icon: Icons.badge_rounded,
                  title: 'کسی انتخاب نشده',
                  hint: 'نام را بنویسید یا کارت را اسکن کنید؛ Enter تیک پذیرش می‌زند.',
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.only(top: DaftarSize.space5),
                child: AttendeePanel(
                  key: ValueKey(paneAttendee.id),
                  attendeeId: paneAttendee.id,
                  done: _paneDone,
                  onCheckin: () => _enter(store, results),
                  onNext: _next,
                  enterHints: true,
                ),
              ),
      ),
    ]);
  }
}

/// جستجوی خالی: راهنما و ۵ پذیرش آخر همین گوشی برای بررسی سریع.
class _Recent extends StatelessWidget {
  final void Function(Attendee) onOpen;
  const _Recent({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final x = DaftarColors.of(context);
    final mine = store.checkins.entries
        .where((e) => store.staffId != null && e.value.staffId == store.staffId && store.attendees[e.key] != null)
        .toList()
      ..sort((p, q) => q.value.at.compareTo(p.value.at));
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        EmptyState(
          icon: Icons.search_rounded,
          title: 'چند حرف از نام یا موبایل را بنویسید',
          hint: store.cameraScan
              ? 'یا کارت را با دکمه‌ی کنار جستجو اسکن کنید.'
              : (store.scanEnabled ? 'اگر بارکدخوان وصل است، کارت را اسکن کنید.' : null),
        ),
        if (mine.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(DaftarSize.space4, DaftarSize.space2, DaftarSize.space4, DaftarSize.space1),
            child: Text('پذیرش‌های آخر این گوشی', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
          ),
          for (final e in mine.take(5))
            AttendeeRow(a: store.attendees[e.key]!, onTap: () => onOpen(store.attendees[e.key]!)),
        ],
      ],
    );
  }
}

/// حرف دسته: حرف اول نام خانوادگی، چون کارت‌های چاپی به ترتیب نام خانوادگی چیده شده‌اند.
String batchLetter(Attendee a) {
  final s = (a.lastName.trim().isNotEmpty ? a.lastName : a.firstName).trim();
  if (s.isEmpty) return '؟';
  final ch = String.fromCharCode(s.runes.first);
  return ch == 'آ' ? 'ا' : ch;
}

/// ردیف نتیجه‌ی جستجو: ۶۴px، با حرف دسته در ابتدا و چیپ ساعت پذیرش در انتها.
class AttendeeRow extends StatelessWidget {
  final Attendee a;
  final String query;
  final VoidCallback onTap;
  final bool selected;
  const AttendeeRow({super.key, required this.a, required this.onTap, this.query = '', this.selected = false});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final state = store.checkins[a.id];
    final parts = [
      store.typeName(a.registrationTypeId),
      store.roleName(a.roleId),
      a.organization,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: selected ? x.stampSoft : x.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: DaftarSize.tapXl),
          padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space4, vertical: DaftarSize.space2),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
          child: Row(
            children: [
              if (store.usesCards) ...[
                _LetterBox(letter: batchLetter(a), done: state != null),
                const SizedBox(width: DaftarSize.space3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Highlighted(text: a.displayName, query: query, style: theme.textTheme.titleMedium),
                    if (parts.isNotEmpty)
                      Text(parts,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                  ],
                ),
              ),
              if (state != null) ...[
                const SizedBox(width: DaftarSize.space2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: x.goSoft,
                    borderRadius: BorderRadius.circular(DaftarSize.radiusPill),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_rounded, size: 16, color: x.go),
                    const SizedBox(width: DaftarSize.space1),
                    Text(hm(state.at),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: x.go, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LetterBox extends StatelessWidget {
  final String letter;
  final bool done;
  const _LetterBox({required this.letter, required this.done});
  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? x.goSoft : x.surface,
        borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
        border: Border.all(color: done ? x.goSoft : x.lineStrong, width: 1.5),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: size * .45,
              fontWeight: FontWeight.w800,
              color: done ? x.go : x.ink,
              height: 1.2,
            ),
      ),
    );
  }
}

/// بخش مطابق جستجو با پس‌زمینه‌ی stamp-soft برجسته می‌شود.
class _Highlighted extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  const _Highlighted({required this.text, required this.query, this.style});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final q = query.trim();
    final i = q.isEmpty ? -1 : text.toLowerCase().indexOf(q.toLowerCase());
    if (i < 0) return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(text: text.substring(i, i + q.length), style: TextStyle(backgroundColor: x.stampSoft)),
        TextSpan(text: text.substring(i + q.length)),
      ]),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String presentationLabel(String k) => switch (k) {
      'poster' => 'ارائه‌ی پوستری',
      'oral' => 'ارائه‌ی شفاهی',
      _ => '',
    };

Future<void> showAttendeeSheet(BuildContext context, Attendee a, {VoidCallback? onNext}) async {
  final next = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _AttendeeSheet(attendeeId: a.id),
  );
  if (next == true) onNext?.call();
}

/// باتم‌شیت پذیرش یک نفر: آماده ← انجام شد (شماره‌ی کارت می‌ماند) ← نفر بعدی.
class _AttendeeSheet extends StatefulWidget {
  final String attendeeId;
  const _AttendeeSheet({required this.attendeeId});

  @override
  State<_AttendeeSheet> createState() => _AttendeeSheetState();
}

class _AttendeeSheetState extends State<_AttendeeSheet> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AttendeePanel(
        attendeeId: widget.attendeeId,
        done: _done,
        onCheckin: () {
          final store = StoreScope.read(context);
          final a = store.attendees[widget.attendeeId];
          if (a == null) return;
          store.checkin(a);
          HapticFeedback.lightImpact();
          setState(() => _done = true);
        },
        onNext: () => Navigator.of(context).pop(true),
      ),
    );
  }
}

/// محتوای پذیرش یک نفر؛ در موبایل داخل باتم‌شیت و در ویندوز در پنل ثابت کنار فهرست.
class AttendeePanel extends StatelessWidget {
  final String attendeeId;
  final bool done;
  final VoidCallback onCheckin;
  final VoidCallback onNext;

  /// در ویندوز کنار دکمه‌ها نوشته می‌شود که Enter همان کار را می‌کند.
  final bool enterHints;
  const AttendeePanel({
    super.key,
    required this.attendeeId,
    required this.done,
    required this.onCheckin,
    required this.onNext,
    this.enterHints = false,
  });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final a = store.attendees[attendeeId];
    if (a == null) return const SizedBox.shrink();
    final state = store.checkins[a.id];
    final cards = store.usesCards;
    final card = cards ? store.cardOf(a.id) : null;
    final theme = Theme.of(context);
    final x = DaftarColors.of(context);
    final letter = batchLetter(a);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enter = enterHints ? ' (Enter)' : '';

    final tags = [
      store.typeName(a.registrationTypeId),
      store.roleName(a.roleId),
      presentationLabel(a.presentationKind),
      if (a.source == 'walkin') 'ثبت‌نام در محل',
    ].where((s) => s.isNotEmpty).toList();

    final details = <(String, String, bool)>[
      ('سازمان', a.organization, false),
      ('موبایل', a.mobile, true),
    ].where((d) => d.$2.isNotEmpty);

    final Widget body;
    if (done) {
      body = Column(
        key: const ValueKey('done'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Notice(
            tone: NoticeTone.go,
            title: 'پذیرش شد',
            text: !cards
                ? 'خوش آمدید.'
                : (card == null ? 'کارت این نفر در لیست نیست.' : 'کارت را از دسته‌ی «$letter» بدهید.'),
          ),
          if (cards) ...[
            const SizedBox(height: DaftarSize.space4),
            _CardPlate(letter: letter, serial: card?.serial, large: true),
          ],
          const SizedBox(height: DaftarSize.space5),
          FilledButton.icon(
            style: daftarWideStyle(context, xl: true),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text('نفر بعدی$enter'),
            onPressed: onNext,
          ),
        ],
      );
    } else if (state != null) {
      final by = state.staffId != null ? store.staffNames[state.staffId] : null;
      body = Column(
        key: const ValueKey('already'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Notice(
            tone: NoticeTone.wait,
            icon: Icons.history_rounded,
            title: 'قبلاً پذیرش شده',
            text: ['ساعت ${hm(state.at)}', if (by != null) 'نیرو: $by'].join('، '),
          ),
          if (cards) ...[
            const SizedBox(height: DaftarSize.space2),
            Text('کارت گم‌شده دوباره صادر نمی‌شود.', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
            const SizedBox(height: DaftarSize.space4),
            _CardPlate(letter: letter, serial: card?.serial),
          ],
          const SizedBox(height: DaftarSize.space5),
          FilledButton(
            style: daftarWideStyle(context),
            onPressed: onNext,
            child: Text('نفر بعدی$enter'),
          ),
          if (store.isAdmin) ...[
            const SizedBox(height: DaftarSize.space2),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(DaftarSize.tapLg)),
              onPressed: () async {
                final ok = await _confirmDanger(
                  context,
                  title: 'لغو پذیرش',
                  text: 'پذیرش ${a.fullName} لغو شود؟ در گزارش ثبت می‌شود.',
                  confirm: 'لغو پذیرش',
                );
                if (ok == true) store.undoCheckin(a);
              },
              child: const Text('لغو پذیرش'),
            ),
          ],
        ],
      );
    } else {
      body = Column(
        key: const ValueKey('ready'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cards) ...[
            _CardPlate(letter: letter, serial: card?.serial),
            const SizedBox(height: DaftarSize.space5),
          ],
          FilledButton.icon(
            style: daftarGoStyle(context),
            icon: const Icon(Icons.check_rounded),
            label: Text('تیک پذیرش$enter'),
            onPressed: onCheckin,
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(DaftarSize.space5, 0, DaftarSize.space5, DaftarSize.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(a.displayName, style: theme.textTheme.headlineSmall),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: DaftarSize.space2),
            Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
              for (final t in tags) DaftarTag(t, kind: t == 'ثبت‌نام در محل' ? TagKind.outline : TagKind.plain),
            ]),
          ],
          if (details.isNotEmpty) const SizedBox(height: DaftarSize.space3),
          for (final d in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                  width: 88,
                  child: Text(d.$1, style: theme.textTheme.bodyMedium?.copyWith(color: x.inkMuted)),
                ),
                Expanded(
                  child: Text(
                    d.$3 ? faDigits(d.$2) : d.$2,
                    style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: d.$3 ? tabularFigures : null),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: DaftarSize.space4),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
            child: body,
          ),
        ],
      ),
    );
  }
}

/// صفحه‌ی «دسته و شماره‌ی کارت»: نیرو هم‌زمان با تیک می‌داند دستش را سمت کدام دسته ببرد.
class _CardPlate extends StatelessWidget {
  final String letter;
  final int? serial;
  final bool large;
  const _CardPlate({required this.letter, required this.serial, this.large = false});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    Widget cell(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
            Text(
              value,
              style: (large ? theme.textTheme.displayLarge : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(DaftarSize.space4),
      decoration: BoxDecoration(
        color: x.sunken,
        borderRadius: BorderRadius.circular(DaftarSize.radiusMd),
      ),
      child: Row(children: [
        cell('دسته', letter),
        Container(width: 1, height: large ? 56 : 40, color: x.line),
        const SizedBox(width: DaftarSize.space4),
        cell('شماره‌ی کارت', serial == null ? '—' : faDigits(serial!)),
      ]),
    );
  }
}

Future<bool?> _confirmDanger(BuildContext context,
        {required String title, required String text, required String confirm}) =>
    showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(
            style: daftarDangerStyle(c),
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
