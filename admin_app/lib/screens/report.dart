import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Timer? _timer;
  bool _auto = false;
  Object? _seenReport;
  DateTime? _updatedAt;

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
    final x = DaftarColors.of(context);
    if (!identical(r, _seenReport)) {
      _seenReport = r;
      _updatedAt = r == null ? null : DateTime.now();
    }
    final flagged = r == null ? 0 : (r['flagged'] as List).length;
    return PageBody(title: 'گزارش زنده', children: [
      Row(children: [
        OutlinedButton.icon(
          onPressed: s.busy ? null : s.loadReport,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('به‌روزرسانی'),
        ),
        const SizedBox(width: DaftarSize.space4),
        Switch(value: _auto, onChanged: _setAuto),
        const SizedBox(width: DaftarSize.space2),
        const Text('هر ۳۰ ثانیه'),
        const Spacer(),
        if (_updatedAt != null)
          Text('آخرین به‌روزرسانی ${hm(_updatedAt!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: x.inkMuted, fontFeatures: tabularFigures)),
      ]),
      if (r == null)
        EmptyState(
          icon: Icons.insights_rounded,
          title: 'گزارشی گرفته نشده',
          action: FilledButton(onPressed: s.busy ? null : s.loadReport, child: const Text('به‌روزرسانی')),
        )
      else ...[
        const SectionTitle('خلاصه'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 760 ? 4 : 2;
          final w = (c.maxWidth - DaftarSize.space3 * (cols - 1)) / cols;
          return Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
            StatTile(
              width: w,
              label: 'پذیرش‌شده',
              value: faDigits(r['totals']['checked_in']),
              of: faDigits(r['totals']['attendees']),
            ),
            StatTile(width: w, label: 'ثبت‌نام در محل', value: faDigits(r['totals']['walkins'])),
            StatTile(width: w, label: 'کارت رزرو آزاد', value: faDigits(r['totals']['reserve_cards_free'])),
            StatTile(
              width: w,
              label: 'موارد مشکوک',
              value: faDigits(flagged),
              attention: flagged > 0,
              line: flagged > 0 ? 'فهرست در پایین صفحه' : 'موردی نیست',
            ),
          ]);
        }),
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
        if ((r['flagged'] as List).isEmpty) const Hint('موردی نیست.'),
        for (final f in r['flagged'] as List)
          ListTile(
            dense: true,
            leading: Icon(Icons.warning_rounded, color: x.wait),
            title: Text('${f['flag_label']} — ${(f['name'] as String?)?.isNotEmpty == true ? f['name'] : 'بدون نام'}'),
            subtitle: Text('ساعت ${_time(f['device_time'] as String?)}${f['staff'] != null ? '، ${f['staff']}' : ''}'),
          ),
        const SectionTitle('گوشی‌ها'),
        for (final d in r['devices'] as List)
          ListTile(
            dense: true,
            leading: Icon(d['revoked'] == true ? Icons.phonelink_erase_rounded : Icons.smartphone_rounded),
            title: Text('${d['staff'] ?? ''} — ${d['label'] ?? ''}'),
            subtitle: Text('آخرین همگام‌سازی: ${_time(d['last_sync_at'] as String?)}${d['revoked'] == true ? ' (باطل‌شده)' : ''}'),
          ),
      ],
    ]);
  }
}

/// کاشی عدد: برچسب کوچک، عدد درشت td-display و خط توضیح.
/// «موارد مشکوک» وقتی بیش از صفر است پس‌زمینه‌ی wait-soft می‌گیرد.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? of;
  final String? line;
  final bool attention;
  final double width;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.width,
    this.of,
    this.line,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(DaftarSize.space4),
      decoration: BoxDecoration(
        color: attention ? x.waitSoft : x.surface,
        border: Border.all(color: attention ? x.waitSoft : x.line),
        borderRadius: BorderRadius.circular(DaftarSize.radiusMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (attention) ...[Icon(Icons.warning_rounded, size: 16, color: x.wait), const SizedBox(width: 4)],
          Text(label, style: theme.textTheme.labelLarge?.copyWith(color: attention ? x.ink : x.inkMuted)),
        ]),
        const SizedBox(height: DaftarSize.space1),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: value),
            if (of != null)
              TextSpan(
                text: ' از $of',
                style: theme.textTheme.titleMedium?.copyWith(color: x.inkMuted, fontWeight: FontWeight.w600),
              ),
          ]),
          style: theme.textTheme.displaySmall,
        ),
        if (line != null) Text(line!, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
      ]),
    );
  }
}
