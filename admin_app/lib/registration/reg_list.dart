// فهرست ثبت‌نام‌ها با هر شش وضعیت و بایگانی (بوم ۲۷ اندروید، ۱۶ ویندوز)، و جزئیات با تأیید، پرداخت، رد، بایگانی و حذف.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../main.dart';
import '../normalize.dart';
import '../screens/export_dialog.dart' show saveExportFile;
import 'reg_api.dart';
import 'reg_widgets.dart';

class RegListPage extends StatefulWidget {
  /// فیلتر اول: '' همه، یک وضعیت، 'attention' (منتظر تصمیم)، 'ended'، 'archived'.
  final String filter;
  final RegEditor? editor;
  const RegListPage({super.key, this.filter = '', this.editor});

  @override
  State<RegListPage> createState() => _RegListPageState();
}

class _RegListPageState extends State<RegListPage> {
  RegList? _list;
  late String _filter = widget.filter;
  final _q = TextEditingController();
  int? _sel;
  final Set<int> _picked = {};
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

  late RegEditor? _ed = widget.editor;

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = StateScope.read(context);
    _ed ??= await s.loadRegEditor();
    if (!mounted) return;
    final r = await s.loadRegistrations();
    if (!mounted) return;
    setState(() {
      _list = r ?? _list;
      _loading = false;
      _picked.removeWhere((id) => !(_list?.items.any((x) => x.id == id) ?? false));
    });
  }

  List<Registration> get _shown {
    final items = _list?.items ?? const <Registration>[];
    final q = normalizeText(_q.text);
    final digits = latinDigits(_q.text).replaceAll(RegExp(r'\D'), '');
    return items.where((r) {
      final ok = switch (_filter) {
        'archived' => r.archived,
        'attention' => !r.archived && (r.status == 'pending_approval' || r.status == 'pending_review'),
        'ended' => !r.archived && (r.status == 'rejected' || r.status == 'expired'),
        '' => !r.archived,
        _ => !r.archived && r.status == _filter,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      final key = normalizeText('${r.name} ${r.email} ${r.code} ${r.organization}');
      return key.contains(q) || (digits.length >= 4 && latinDigits(r.mobile).contains(digits));
    }).toList();
  }

  String _typeName(String code) => _ed?.typeName(code) ?? code;

  Future<void> _export() async {
    final s = StateScope.read(context);
    final r = await s.regExport();
    if (r == null) return;
    final ext = r.$1.split('.').last;
    await saveExportFile(s, r.$1.replaceAll(RegExp(r'\.[a-z]+$'), ''), ext, r.$2);
  }

  Future<void> _bulk(String action) async {
    final s = StateScope.read(context);
    final ids = _picked.toList();
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('حذف ${faDigits(ids.length)} ثبت‌نام؟'),
          content: const Text('ثبت‌نامی که پرداخت یا ورود به لیست دارد حذف نمی‌شود و فقط بایگانی می‌شود. حذف برنمی‌گردد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('نه، برگرد')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: NvColors.of(context).stop), onPressed: () => Navigator.pop(d, true), child: const Text('حذف')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await s.regBulk(ids, action);
    _picked.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = regWide(context);
    final list = _list;
    final shown = _shown;
    final c = NvColors.of(context);
    final by = list?.byStatus ?? const {};
    Widget chip(String id, String label) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id)),
        );
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('', 'همه ${faDigits(list?.active ?? 0)}'),
        chip('pending_approval', 'منتظر تأیید ${faDigits(by['pending_approval'] ?? 0)}'),
        chip('pending_review', 'بررسی پرداخت ${faDigits(by['pending_review'] ?? 0)}'),
        chip('pending_payment', 'در انتظار پرداخت ${faDigits(by['pending_payment'] ?? 0)}'),
        chip('confirmed', 'تأییدشده ${faDigits(by['confirmed'] ?? 0)}'),
        chip('ended', 'ردشده / منقضی ${faDigits((by['rejected'] ?? 0) + (by['expired'] ?? 0))}'),
        chip('archived', 'بایگانی‌شده ${faDigits(list?.archived ?? 0)}'),
      ]),
    );
    final search = NvCard(
      raised: true,
      padding: EdgeInsets.zero,
      child: TextField(
        controller: _q,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'نام، موبایل، ایمیل یا کد پیگیری', border: InputBorder.none, filled: false),
        onChanged: (_) => setState(() {}),
      ),
    );
    final bulk = _picked.isEmpty
        ? null
        : NvCard(
            child: Row(children: [
              Expanded(child: Text('${faDigits(_picked.length)} انتخاب‌شده', style: nvText(context, 14, w: FontWeight.w800))),
              TextButton(onPressed: () => _bulk(_filter == 'archived' ? 'unarchive' : 'archive'), child: Text(_filter == 'archived' ? 'برگرداندن' : 'بایگانی')),
              TextButton(style: TextButton.styleFrom(foregroundColor: c.stop), onPressed: () => _bulk('delete'), child: const Text('حذف…')),
              IconButton(tooltip: 'لغو انتخاب', onPressed: () => setState(_picked.clear), icon: const Icon(Icons.close_rounded)),
            ]),
          );
    final rows = <Widget>[
      if (_loading && list == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (!_loading && shown.isEmpty) NvEmpty(icon: Icons.how_to_reg_rounded, title: 'ثبت‌نامی نیست', hint: _q.text.isEmpty ? 'با فیلتر دیگری ببینید.' : 'جستجو نتیجه‌ای نداشت.'),
      for (final r in shown)
        _RegRow(
          r: r,
          typeName: _typeName(r.type),
          selected: wide && _sel == r.id,
          picked: _picked.contains(r.id),
          onPick: (v) => setState(() => v ? _picked.add(r.id) : _picked.remove(r.id)),
          onTap: () async {
            if (wide) return setState(() => _sel = r.id);
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegDetailPage(r: r, editor: _ed)));
            _load();
          },
        ),
      if (!wide && shown.isNotEmpty)
        Text('برای رسید و پاسخ‌ها روی نام لمس کنید. «پرداخت شد»، «تأیید»، «رد…»، «بایگانی» و «حذف…» در جزئیات است.',
            textAlign: TextAlign.center, style: nvText(context, 12, color: c.muted, height: 1.6)),
    ];
    final sel = wide ? shown.where((r) => r.id == _sel).firstOrNull ?? (shown.isNotEmpty ? shown.first : null) : null;
    return RegScaffold(
      title: 'ثبت‌نام‌ها',
      subtitle: 'ثبت‌نام آنلاین · ${faDigits(list?.active ?? 0)} نفر',
      maxWidth: wide ? 1240 : 760,
      overlap: 34,
      onRefresh: _load,
      actions: [NvRoundIcon(icon: Icons.download_rounded, label: 'خروجی اکسل', onTap: _export)],
      children: wide
          ? [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap([search, chips, if (bulk != null) bulk, ...rows]))),
                const SizedBox(width: 16),
                SizedBox(
                  width: 360,
                  child: sel == null
                      ? const NvCard(child: Text('یک ثبت‌نام را از فهرست انتخاب کنید.'))
                      : RegDetailPanel(key: ValueKey(sel.id), r: sel, typeName: _typeName(sel.type), editor: _ed, onChanged: _load),
                ),
              ]),
            ]
          : [search, chips, if (bulk != null) bulk, ...rows],
    );
  }

  static List<Widget> _gap(List<Widget> w) => [for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: 10), w[i]]];
}

class _RegRow extends StatelessWidget {
  final Registration r;
  final String typeName;
  final bool selected, picked;
  final ValueChanged<bool> onPick;
  final VoidCallback onTap;
  const _RegRow({required this.r, required this.typeName, required this.selected, required this.picked, required this.onPick, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final (Color bg, Color fg) = switch (r.archived ? 'x' : r.status) {
      'confirmed' => (c.goSoft, c.go),
      'pending_approval' || 'pending_review' => (c.waitSoft, c.wait),
      'rejected' => (c.stopSoft, c.stop),
      _ => (c.field, c.muted),
    };
    final hold = r.holdUntil;
    final line = [
      typeName,
      if (r.amountOnline > 0) regMoney(r.amountOnline, unit: false),
      if (r.status == 'rejected' && r.rejectReason.isNotEmpty) 'رد شد: ${r.rejectReason}'
      else if (r.status == 'pending_review' && (r.hasReceipt || r.payTracking.isNotEmpty)) 'رسید دارد'
      else if (r.status == 'pending_payment' && hold != null) 'تا ${faDigits(hold.difference(DateTime.now()).inHours.clamp(0, 9999))} ساعت دیگر'
      else regPayMethods[r.payMethod] ?? '',
    ].where((e) => e.isNotEmpty).join(' · ');
    return Opacity(
      opacity: r.archived || r.status == 'expired' ? .7 : 1,
      child: Material(
        color: selected ? c.brandSoft : c.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: () => onPick(!picked),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: selected ? BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: c.brand, width: 2)) : null,
            child: Row(children: [
              Checkbox(value: picked, onChanged: (v) => onPick(v ?? false)),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: Text(r.name.isEmpty ? '؟' : String.fromCharCode(r.name.runes.first), style: nvText(context, 16, w: FontWeight.w800, color: fg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: nvText(context, 15, w: FontWeight.w800)),
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: nvText(context, 12, color: c.muted)),
                ]),
              ),
              RegStatusPill(r),
            ]),
          ),
        ),
      ),
    );
  }
}

/// جزئیات یک ثبت‌نام در صفحه‌ی جدا (اندروید).
class RegDetailPage extends StatelessWidget {
  final Registration r;
  final RegEditor? editor;
  const RegDetailPage({super.key, required this.r, this.editor});

  @override
  Widget build(BuildContext context) => RegScaffold(
        title: r.name,
        subtitle: 'کد ${r.code}',
        overlap: 30,
        children: [RegDetailPanel(r: r, typeName: editor?.typeName(r.type) ?? r.type, editor: editor, onChanged: () async {}, page: true)],
      );
}

/// جزئیات، رسید و کارها (بوم ۰۸-ApprovalDetail؛ در ویندوز پنل کنار فهرست).
class RegDetailPanel extends StatefulWidget {
  final Registration r;
  final String typeName;
  final RegEditor? editor;
  final Future<void> Function() onChanged;
  final bool page;
  const RegDetailPanel({super.key, required this.r, required this.typeName, this.editor, required this.onChanged, this.page = false});

  @override
  State<RegDetailPanel> createState() => _RegDetailPanelState();
}

class _RegDetailPanelState extends State<RegDetailPanel> {
  late Registration r = widget.r;
  Uint8List? _receipt;
  bool _receiptTried = false;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _act(String action, {String confirm = ''}) async {
    final s = StateScope.read(context);
    final res = await s.regAction(r.id, action, reason: _reason.text.trim(), confirmCode: confirm);
    if (res == null || !mounted) return;
    final j = res['registration'];
    if (j is Map) {
      setState(() => r = Registration(j.cast<String, dynamic>()));
    } else if (action == 'delete' && widget.page) {
      Navigator.of(context).maybePop();
    }
    await widget.onChanged();
  }

  Future<void> _delete() async {
    final c = NvColors.of(context);
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('حذف ثبت‌نام ${r.name}؟'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(r.canDelete
                ? 'حذف برنمی‌گردد. برای تأیید، کد پیگیری «${r.code}» را بنویسید.'
                : 'این ثبت‌نام پرداخت یا ورود به لیست دارد؛ حذف نمی‌شود و به‌جایش بایگانی می‌شود. کد پیگیری «${r.code}» را بنویسید.'),
            const SizedBox(height: 10),
            TextField(controller: code, textDirection: TextDirection.ltr, autofocus: true, onChanged: (_) => set(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('نه، برگرد')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.stop),
              onPressed: code.text.trim().toUpperCase() == r.code.toUpperCase() ? () => Navigator.pop(d, true) : null,
              child: Text(r.canDelete ? 'حذف' : 'بایگانی'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _act('delete', confirm: code.text.trim());
  }

  Future<void> _loadReceipt() async {
    final b = await StateScope.read(context).regReceipt(r.id);
    if (mounted) setState(() {
      _receipt = b;
      _receiptTried = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final ed = widget.editor;
    final created = r.createdAt;
    final addons = ((ed?.config['addons'] as List?) ?? []).cast<Map>().where((a) => r.addons.contains(a['id'])).toList();
    final fields = ((ed?.config['custom_fields'] as List?) ?? []).cast<Map>();
    final s = r.status;
    String answer(Map f) {
      final v = r.answers['${f['id']}'];
      if (v == null) return '';
      final opts = ((f['options'] as List?) ?? []).cast<Map>();
      String label(dynamic id) => '${opts.where((o) => o['id'] == id).firstOrNull?['label'] ?? id}';
      return v is List ? v.map(label).join('، ') : (f['kind'] == 'text' ? '$v' : label(v));
    }

    return NvCard(
      raised: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.page) ...[
          Text(r.name, style: nvText(context, 18, w: FontWeight.w800)),
          Text('کد ${r.code}${created != null ? ' · ${faDigits(hm(created))}' : ''}', style: nvText(context, 12, color: c.muted)),
          const SizedBox(height: 8),
        ],
        Align(alignment: AlignmentDirectional.centerStart, child: RegStatusPill(r)),
        const SizedBox(height: 8),
        RegKv('موبایل', faDigits(r.mobile), ltr: true),
        if (r.email.isNotEmpty) RegKv('ایمیل', r.email, ltr: true),
        if (r.organization.isNotEmpty) RegKv('سازمان', r.organization),
        RegKv('نوع', widget.typeName),
        for (final f in fields)
          if (answer(f).isNotEmpty) RegKv('${f['label']}', answer(f)),
        for (final a in addons)
          RegKv('${a['title']}${a['price_mode'] == 'onsite' ? ' · در محل' : ''}', (a['price'] as num? ?? 0) > 0 ? regMoney(a['price'] as num, unit: false) : '✓'),
        RegKv('مبلغ آنلاین', regMoney(r.amountOnline)),
        if (r.amountOnsite > 0) RegKv('در محل', regMoney(r.amountOnsite)),
        RegKv('روش', regPayMethods[r.payMethod] ?? r.payMethod),
        if (r.payRef.isNotEmpty) RegKv('شماره‌ی بانک', r.payRef, ltr: true),
        if (r.payTracking.isNotEmpty) RegKv('شماره‌ی پیگیری', faDigits(r.payTracking), ltr: true),
        if (r.hasReceipt) ...[
          const SizedBox(height: 8),
          if (_receipt != null)
            ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_receipt!, height: 220, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('رسید PDF است؛ از پیشخوان وردپرس باز کنید.')))
          else
            NvSoftButton(label: _receiptTried ? 'رسید باز نشد؛ دوباره' : 'دیدن رسید (فقط برای مدیر)', icon: Icons.receipt_long_rounded, onPressed: _loadReceipt),
        ],
        if (r.rejectReason.isNotEmpty) ...[const SizedBox(height: 8), NvBanner(tone: NvTone.stop, text: 'دلیل رد: ${r.rejectReason}')],
        const SizedBox(height: 12),
        if (s != 'rejected' && s != 'confirmed') ...[
          TextField(controller: _reason, decoration: const InputDecoration(hintText: 'دلیل رد (فقط برای «رد…»؛ به فرد نشان داده می‌شود)')),
          const SizedBox(height: 8),
        ],
        Row(children: [
          if (s != 'rejected' && s != 'confirmed')
            Expanded(child: NvSoftButton(label: 'رد…', fg: c.stop, border: c.stop, onPressed: () => _act('reject'))),
          if (s == 'pending_payment' || s == 'pending_review' || s == 'expired') ...[
            const SizedBox(width: 8),
            Expanded(child: NvSoftButton(label: 'پرداخت شد', onPressed: () => _act('mark_paid'))),
          ],
          if (s == 'pending_approval') ...[
            const SizedBox(width: 8),
            Expanded(flex: 13, child: NvButton(label: 'تأیید ثبت‌نام', color: c.go, height: 48, onPressed: () => _act('approve'))),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: NvSoftButton(label: r.archived ? 'برگرداندن از بایگانی' : 'بایگانی', icon: Icons.inventory_2_outlined, onPressed: () => _act(r.archived ? 'unarchive' : 'archive'))),
          const SizedBox(width: 8),
          Expanded(child: NvSoftButton(label: 'حذف…', fg: c.stop, border: c.stop, onPressed: _delete)),
        ]),
        const SizedBox(height: 8),
        Text('بایگانی: از فهرست اصلی کنار می‌رود ولی در گزارش می‌ماند. حذف دو مرحله‌ای است؛ ثبت‌نامی که پرداخت یا ورود به لیست دارد فقط بایگانی می‌شود.',
            style: nvText(context, 12, color: c.muted, height: 1.6)),
      ]),
    );
  }
}
