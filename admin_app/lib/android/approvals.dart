// صف تأیید ثبت‌نام‌ها (طرح ۷) و جزئیات ثبت‌نام با رسید (طرح ۸).
// تأیید سریع از خود فهرست، با ۵ ثانیه «واگرد» پیش از رفتن به سرور.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../screens/registration.dart' show regStatusLabels, saveBytesAs;
import '../state.dart';
import 'jalali.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart';

/// تأییدهای در انتظار «واگرد» (شناسه‌ی ثبت‌نام ← زمان‌سنج).
final Map<int, Timer> _deferred = {};

/// کار ثبت‌نام: approve و mark_paid بعد از ۵ ثانیه انجام می‌شوند و تا آن موقع «واگرد» دارند.
void regActionWithUndo(BuildContext context, Map<String, dynamic> r, String action, {VoidCallback? onChange}) {
  final s = StateScope.read(context);
  final id = (r['id'] as num).toInt();
  final name = '${r['first_name']} ${r['last_name']}'.trim();
  final messenger = ScaffoldMessenger.of(context);
  _deferred[id]?.cancel();
  _deferred[id] = Timer(const Duration(seconds: 5), () async {
    _deferred.remove(id);
    await s.regAction(id, action);
    onChange?.call();
  });
  onChange?.call();
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 5),
    content: Text(action == 'approve' ? 'ثبت‌نام $name تأیید شد' : 'پرداخت $name تأیید شد'),
    action: SnackBarAction(
      label: 'واگرد',
      onPressed: () {
        _deferred.remove(id)?.cancel();
        onChange?.call();
      },
    ),
  ));
}

bool regPendingUndo(Map<String, dynamic> r) => _deferred.containsKey((r['id'] as num).toInt());

Future<String?> askRejectReason(BuildContext context, String name) {
  final t = TextEditingController();
  final c = NvColors.of(context);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('رد ثبت‌نام $name؟'),
      content: TextField(
        controller: t,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'دلیل (برای خود ثبت‌نام‌کننده نوشته می‌شود)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('نه، برگرد')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: c.stop), onPressed: () => Navigator.pop(d, t.text.trim()), child: const Text('رد شود')),
      ],
    ),
  );
}

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  final _q = TextEditingController();
  String _filter = 'pending_approval';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = StateScope.read(context);
    try {
      await s.loadRegistrations();
      if (s.regEditor == null) await s.loadRegPage();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      // اگر چیزی منتظر تأیید مدیر نیست ولی پرداخت منتظر بررسی هست، همان اول باز شود.
      if ((s.regByStatus['pending_approval'] ?? 0) == 0 && (s.regByStatus['pending_review'] ?? 0) > 0) _filter = 'pending_review';
    });
  }

  Future<void> _export() async {
    final s = StateScope.read(context);
    final r = await s.run<(String, Uint8List)>('', s.exportRegistrations);
    if (r != null) await saveBytesAs(s, r.$1, 'xlsx', r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final q = normalizeText(_q.text);
    final list = s.registrations.where((r) {
      final st = '${r['status']}';
      final inFilter = _filter == 'other' ? const ['pending_payment', 'expired'].contains(st) : st == _filter;
      if (!inFilter) return false;
      if (q.isEmpty) return true;
      return normalizeText('${r['first_name']} ${r['last_name']} ${r['mobile']} ${r['code']} ${r['organization']}').contains(q);
    }).toList();
    int n(String k) => s.regByStatus[k] ?? 0;

    Widget chip(String id, String label, int count) {
      final on = _filter == id;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Material(
          color: on ? c.brand : c.surface,
          shape: StadiumBorder(side: on ? BorderSide.none : BorderSide(color: c.lineSoft)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _filter = id),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text(count > 0 ? '$label ${faDigits(count)}' : label, style: nvText(context, 12, w: FontWeight.w700, color: on ? c.onBrand : c.ink)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          NvPageHeader(
            title: 'ثبت‌نام‌ها',
            subtitle: 'ثبت‌نام آنلاین',
            bottom: 56,
            action: IconButton(
              tooltip: 'خروجی اکسل',
              style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .16), foregroundColor: Colors.white),
              onPressed: s.busy ? null : _export,
              icon: const Icon(Icons.download_rounded),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(Nv.r18), boxShadow: Nv.raised(c)),
                  child: TextField(
                    controller: _q,
                    decoration: InputDecoration(
                      hintText: 'نام، موبایل یا کد ثبت‌نام',
                      prefixIcon: Icon(Icons.search_rounded, color: c.brandText),
                      filled: true,
                      fillColor: c.surface,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    chip('pending_approval', 'منتظر تأیید', n('pending_approval')),
                    chip('pending_review', 'بررسی پرداخت', n('pending_review')),
                    chip('confirmed', 'تأییدشده', n('confirmed')),
                    chip('rejected', 'ردشده', n('rejected')),
                    chip('other', 'پرداخت‌نشده', n('pending_payment') + n('expired')),
                  ]),
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const LinearProgressIndicator()
                else if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Center(child: Text('ثبت‌نامی در این بخش نیست.', style: nvText(context, 15, color: c.muted))),
                  )
                else
                  for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: _RegCard(r: r, onChange: () => setState(() {}))),
                if (!_loading && (_filter == 'pending_approval' || _filter == 'pending_review'))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('تأیید یا رد سریع از همین فهرست. برای رسید و پاسخ‌ها، روی نام بزنید.',
                        textAlign: TextAlign.center, style: nvText(context, 12, color: c.muted)),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RegCard extends StatelessWidget {
  final Map<String, dynamic> r;
  final VoidCallback onChange;
  const _RegCard({required this.r, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final st = '${r['status']}';
    final name = '${r['first_name']} ${r['last_name']}'.trim();
    final type = s.types.where((t) => t.code == r['type']).firstOrNull?.name ?? '${r['type']}';
    final amount = (r['amount_online'] as num? ?? 0).toInt();
    final at = DateTime.tryParse('${r['created_at']}')?.toLocal();
    final undo = regPendingUndo(r);
    final canQuick = st == 'pending_approval' || st == 'pending_review';
    final addons = ((s.regEditor?['page'] as Map?)?['addons'] as List? ?? const []).cast<Map>();
    final chosen = [for (final id in (r['addons'] as List? ?? const [])) addons.where((a) => a['id'] == id).firstOrNull?['title'] ?? '$id'];
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Nv.r22),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegDetailPage(r: r))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.waitSoft, borderRadius: BorderRadius.circular(Nv.r14)),
                child: Text(name.isEmpty ? '؟' : String.fromCharCode(name.runes.first), style: nvText(context, 16, w: FontWeight.w800, color: c.wait)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: nvText(context, 15, w: FontWeight.w800)),
                  Text(
                    [type, amount > 0 ? moneyFa(amount) : 'بدون پرداخت', if (at != null) _when(at)].join(' · '),
                    style: nvText(context, 12, color: c.muted),
                  ),
                ]),
              ),
              Icon(Icons.chevron_left_rounded, color: c.muted),
            ]),
          ),
        ),
        if (r['has_receipt'] == true || chosen.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (r['has_receipt'] == true) NvStatusChip(text: 'رسید دارد', icon: Icons.receipt_long_rounded, bg: c.field, fg: c.muted),
              for (final a in chosen) NvTag('$a'),
            ]),
          ),
        if (!canQuick)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(regStatusLabels[st] ?? st, style: nvText(context, 12, w: FontWeight.w700, color: st == 'confirmed' ? c.go : c.muted)),
          )
        else if (undo)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text('در حال تأیید… (از پیام پایین می‌شود واگرد کرد)', style: nvText(context, 12, w: FontWeight.w700, color: c.go)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c.go, minimumSize: const Size.fromHeight(44)),
                  onPressed: s.busy ? null : () => regActionWithUndo(context, r, st == 'pending_review' ? 'mark_paid' : 'approve', onChange: onChange),
                  child: Text(st == 'pending_review' ? 'تأیید پرداخت' : 'تأیید'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: c.stop, minimumSize: const Size.fromHeight(44)),
                  onPressed: s.busy
                      ? null
                      : () async {
                          final why = await askRejectReason(context, name);
                          if (why != null) await s.regAction((r['id'] as num).toInt(), 'reject', reason: why);
                        },
                  child: const Text('رد…'),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

String _when(DateTime t) {
  final now = DateTime.now();
  final same = t.year == now.year && t.month == now.month && t.day == now.day;
  return same ? 'امروز ${faDigits(hm(t))}' : '${jalaliLabel(isoDate(t), year: false)} ${faDigits(hm(t))}';
}

class RegDetailPage extends StatefulWidget {
  final Map<String, dynamic> r;
  const RegDetailPage({super.key, required this.r});

  @override
  State<RegDetailPage> createState() => _RegDetailPageState();
}

class _RegDetailPageState extends State<RegDetailPage> {
  Future<(String, Uint8List)?>? _receipt;

  @override
  void initState() {
    super.initState();
    if (widget.r['has_receipt'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final s = StateScope.read(context);
        setState(() => _receipt = s.loadReceipt((widget.r['id'] as num).toInt()).then<(String, Uint8List)?>((v) => v).catchError((_) => null));
      });
    }
  }

  String _answer(AdminState s, String fid, dynamic v) {
    final fields = ((s.regEditor?['page'] as Map?)?['custom_fields'] as List? ?? const []).cast<Map>();
    final f = fields.where((e) => e['id'] == fid).firstOrNull;
    final opts = ((f?['options'] as List?) ?? const []).cast<Map>();
    String label(dynamic id) => opts.where((o) => o['id'] == id).firstOrNull?['label']?.toString() ?? '$id';
    return v is List ? v.map(label).join('، ') : (opts.isEmpty ? '$v' : label(v));
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final r = s.registrations.where((x) => x['id'] == widget.r['id']).firstOrNull ?? widget.r;
    final st = '${r['status']}';
    final name = '${r['first_name']} ${r['last_name']}'.trim();
    final page = (s.regEditor?['page'] as Map?) ?? const {};
    final fields = ((page['custom_fields'] as List?) ?? const []).cast<Map>();
    final addons = ((page['addons'] as List?) ?? const []).cast<Map>();
    final types = ((page['types'] as List?) ?? const []).cast<Map>();
    final typePrice = (types.where((t) => t['code'] == r['type']).firstOrNull?['price'] as num? ?? 0).toInt();
    final chosen = [for (final id in (r['addons'] as List? ?? const [])) addons.where((a) => a['id'] == id).firstOrNull ?? {'title': '$id'}];
    final online = (r['amount_online'] as num? ?? 0).toInt();
    final onsite = (r['amount_onsite'] as num? ?? 0).toInt();
    final method = switch ('${r['pay_method'] ?? ''}') {
      'gateway' => 'درگاه',
      'card' => 'کارت‌به‌کارت',
      'link' => 'لینک بیرونی',
      _ => '',
    };

    Widget kv(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: nvText(context, 14, color: c.muted))),
            Expanded(child: SelectableText(v, style: nvText(context, 14, w: bold ? FontWeight.w800 : FontWeight.w600))),
          ]),
        );

    final canApprove = st == 'pending_approval';
    final canPaid = const ['pending_payment', 'pending_review', 'expired'].contains(st);
    final canReject = st != 'rejected' && !(st == 'confirmed' && r['attendee_id'] != null);
    final undo = regPendingUndo(r);

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        NvPageHeader(title: name, subtitle: regStatusLabels[st] ?? st),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            NvCard(
              child: Column(children: [
                kv('نوع', s.types.where((t) => t.code == r['type']).firstOrNull?.name ?? '${r['type']}'),
                kv('کد ثبت‌نام', '${r['code']}'),
                kv('موبایل', faDigits(r['mobile'] ?? '')),
                if ('${r['email'] ?? ''}'.isNotEmpty) kv('ایمیل', '${r['email']}'),
                if ('${r['organization'] ?? ''}'.isNotEmpty) kv('سازمان', '${r['organization']}'),
                if (chosen.isNotEmpty) kv('گزینه‌ها', chosen.map((a) => a['title']).join('، ')),
                for (final e in ((r['answers'] as Map?) ?? const {}).entries)
                  kv(fields.where((f) => f['id'] == e.key).firstOrNull?['label']?.toString() ?? '${e.key}', _answer(s, '${e.key}', e.value)),
                if ('${r['reject_reason'] ?? ''}'.isNotEmpty) kv('دلیل رد', '${r['reject_reason']}'),
              ]),
            ),
            if (online > 0 || onsite > 0) ...[
              const SizedBox(height: 12),
              NvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(method.isEmpty ? 'پرداخت' : 'پرداخت: $method', style: nvText(context, 15, w: FontWeight.w800)),
                  const SizedBox(height: 4),
                  if (typePrice > 0) kv('ثبت‌نام', moneyFa(typePrice)),
                  for (final a in chosen)
                    if ((a['price'] as num? ?? 0) > 0)
                      kv('${a['title']}${a['price_mode'] == 'onsite' ? ' (روز اجرا)' : ''}', moneyFa((a['price'] as num).toInt())),
                  if (online > 0) kv('جمع آنلاین', moneyFa(online), bold: true),
                  if (onsite > 0) kv('تسویه در روز اجرا', moneyFa(onsite), bold: true),
                  if ('${r['pay_tracking'] ?? ''}'.isNotEmpty) kv('کد پیگیری', faDigits(r['pay_tracking'])),
                  if ('${r['pay_ref'] ?? ''}'.isNotEmpty) kv('پیگیری بانک', '${r['pay_ref']}'),
                ]),
              ),
            ],
            if (r['has_receipt'] == true) ...[
              const SizedBox(height: 12),
              Text('رسید کارت‌به‌کارت', style: nvText(context, 15, w: FontWeight.w800)),
              const SizedBox(height: 8),
              FutureBuilder<(String, Uint8List)?>(
                future: _receipt,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  final v = snap.data;
                  if (v == null) return const NvBanner(tone: NvTone.neutral, text: 'رسید از سرور نرسید.');
                  if (v.$1 == 'application/pdf') {
                    return NvSoftButton(label: 'ذخیره‌ی رسید (PDF)', icon: Icons.download_rounded, onPressed: () => saveBytesAs(s, 'receipt-${r['code']}.pdf', 'pdf', v.$2));
                  }
                  return InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('رسید ${r['code']}')),
                        body: Center(child: InteractiveViewer(maxScale: 6, child: Image.memory(v.$2))),
                      ),
                    )),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Nv.r18),
                      child: Stack(children: [
                        Image.memory(v.$2, height: 220, width: double.infinity, fit: BoxFit.cover),
                        PositionedDirectional(
                          bottom: 8,
                          end: 8,
                          child: NvStatusChip(text: 'بزرگ‌نمایی', icon: Icons.zoom_in_rounded, bg: c.surface, fg: c.ink),
                        ),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text('برای بزرگ‌نمایی لمس کنید؛ با دو انگشت زوم کنید.', style: nvText(context, 12, color: c.muted)),
            ],
            if (r['attendee_id'] != null && s.people[r['attendee_id']] != null) ...[
              const SizedBox(height: 12),
              NvSoftButton(
                label: 'صفحه‌ی این نفر',
                icon: Icons.person_rounded,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonPage(person: s.people[r['attendee_id']]!))),
              ),
            ],
          ]),
        ),
        if ((canApprove || canPaid || canReject) && !undo)
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.chip))),
            child: Row(children: [
              if (canReject)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: c.stop, minimumSize: const Size.fromHeight(Nv.button)),
                    onPressed: s.busy
                        ? null
                        : () async {
                            final why = await askRejectReason(context, name);
                            if (why != null) await s.regAction((r['id'] as num).toInt(), 'reject', reason: why);
                          },
                    child: const Text('رد…'),
                  ),
                ),
              if (canReject && (canApprove || canPaid)) const SizedBox(width: 10),
              if (canApprove || canPaid)
                Expanded(
                  flex: 2,
                  child: NvButton(
                    label: canApprove ? 'تأیید ثبت‌نام' : 'پرداخت تأیید شد',
                    color: c.go,
                    onPressed: s.busy
                        ? null
                        : () {
                            regActionWithUndo(context, r, canApprove ? 'approve' : 'mark_paid', onChange: () {
                              if (mounted) setState(() {});
                            });
                          },
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
