import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Timer? _timer;
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => StateScope.read(context).loadReport());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setAuto(bool v) {
    setState(() => _auto = v);
    _timer?.cancel();
    if (v) _timer = Timer.periodic(const Duration(seconds: 30), (_) => StateScope.read(context).loadReport());
  }

  String _time(String? iso) {
    if (iso == null) return '—';
    final t = DateTime.tryParse(iso);
    return t == null ? '—' : hm(t);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final r = s.report;
    return PageBody(children: [
      Row(children: [
        FilledButton.tonalIcon(onPressed: s.busy ? null : s.loadReport, icon: const Icon(Icons.refresh), label: const Text('به‌روزرسانی')),
        const SizedBox(width: 16),
        Switch(value: _auto, onChanged: _setAuto),
        const Text('هر ۳۰ ثانیه'),
      ]),
      if (r == null)
        const Padding(padding: EdgeInsets.all(24), child: Text('گزارشی گرفته نشده.'))
      else ...[
        const SectionTitle('خلاصه'),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Tile('پذیرش‌شده', '${faDigits(r['totals']['checked_in'])} از ${faDigits(r['totals']['attendees'])}'),
          _Tile('ثبت‌نام در محل', faDigits(r['totals']['walkins'])),
          _Tile('کارت رزرو آزاد', faDigits(r['totals']['reserve_cards_free'])),
          _Tile('موارد مشکوک', faDigits((r['flagged'] as List).length)),
        ]),
        const SectionTitle('بر اساس نوع ثبت‌نام'),
        DataTable(columns: const [
          DataColumn(label: Text('نوع')),
          DataColumn(label: Text('کل')),
          DataColumn(label: Text('پذیرش‌شده')),
        ], rows: [
          for (final t in r['by_registration_type'] as List)
            DataRow(cells: [
              DataCell(Text('${t['name']}')),
              DataCell(Text(faDigits(t['total']))),
              DataCell(Text(faDigits(t['checked_in']))),
            ]),
        ]),
        const SectionTitle('پذیرایی'),
        DataTable(columns: const [
          DataColumn(label: Text('وعده')),
          DataColumn(label: Text('حق دارند')),
          DataColumn(label: Text('تحویل‌شده')),
          DataColumn(label: Text('تکراری')),
          DataColumn(label: Text('بدون حق')),
        ], rows: [
          for (final m in r['meals'] as List)
            DataRow(cells: [
              DataCell(Text('${m['name']}')),
              DataCell(Text(faDigits(m['entitled']))),
              DataCell(Text(faDigits(m['served']))),
              DataCell(Text(faDigits(m['duplicates']))),
              DataCell(Text(faDigits(m['not_entitled']))),
            ]),
        ]),
        const SectionTitle('موارد مشکوک'),
        if ((r['flagged'] as List).isEmpty) const Text('موردی نیست.'),
        for (final f in r['flagged'] as List)
          ListTile(
            dense: true,
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: Text('${f['flag_label']} — ${(f['name'] as String?)?.isNotEmpty == true ? f['name'] : 'بدون نام'}'),
            subtitle: Text('ساعت ${_time(f['device_time'] as String?)}${f['staff'] != null ? ' · ${f['staff']}' : ''}'),
          ),
        const SectionTitle('گوشی‌ها'),
        for (final d in r['devices'] as List)
          ListTile(
            dense: true,
            leading: Icon(d['revoked'] == true ? Icons.phonelink_erase : Icons.smartphone),
            title: Text('${d['staff'] ?? ''} — ${d['label'] ?? ''}'),
            subtitle: Text('آخرین همگام‌سازی: ${_time(d['last_sync_at'] as String?)}${d['revoked'] == true ? ' (باطل‌شده)' : ''}'),
          ),
      ],
    ]);
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  const _Tile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ]),
      );
}
