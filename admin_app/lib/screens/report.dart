import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../export.dart';
import '../main.dart';
import 'export_dialog.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

class ReportScreen extends StatefulWidget {
  /// روی موبایل («امروز») گزارش خودکار هر ۳۰ ثانیه به‌روز می‌شود.
  final bool autoRefresh;
  final String title;
  const ReportScreen({super.key, this.autoRefresh = false, this.title = 'گزارش زنده'});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StateScope.read(context).loadReport();
      if (widget.autoRefresh) _setAuto(true);
    });
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
    return PageBody(title: widget.title, children: [
      Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: s.busy ? null : s.loadReport,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('به‌روزرسانی'),
        ),
        const SizedBox(width: DaftarSize.space4),
        Switch(value: _auto, onChanged: _setAuto),
        const SizedBox(width: DaftarSize.space2),
        const Text('هر ۳۰ ثانیه'),
        const SizedBox(width: DaftarSize.space4),
        OutlinedButton.icon(
          onPressed: r == null ? null : () => showExportDialog(context),
          icon: const Icon(Icons.download_rounded),
          label: const Text('خروجی اکسل…'),
        ),
        const SizedBox(width: DaftarSize.space4),
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
        // حضور روزانه یا رویداد چندروزه: «همه» و هر روز.
        if (r['daily_attendance'] == true && ((r['by_day'] as List?) ?? const []).isNotEmpty) ...[
          const SizedBox(height: DaftarSize.space3),
          Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
            ChoiceChip(label: const Text('همه'), selected: s.reportDay == null, onSelected: (_) => s.setReportDay(null)),
            for (final d in (r['by_day'] as List).cast<Map>())
              ChoiceChip(
                label: Text('${s.dayName('${d['day']}')} · ${faDigits(d['checked_in'])}'),
                selected: s.reportDay == d['day'],
                onSelected: (_) => s.setReportDay('${d['day']}'),
              ),
          ]),
        ],
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
          DataColumn(label: Text('')),
        ], rows: [
          for (final m in r['meals'] as List)
            DataRow(cells: [
              DataCell(Text('${m['name']}')),
              DataCell(Text(faDigits(m['entitled']))),
              DataCell(Text(faDigits(m['served']))),
              DataCell(Text(faDigits(m['duplicates']))),
              DataCell(Text(faDigits(m['not_entitled']))),
              DataCell(TextButton(
                onPressed: () {
                  final code = s.meals.where((x) => x.id == m['id']).map((x) => x.code).firstOrNull;
                  if (code == null) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MealPeoplePage(code: code, name: '${m['name']}'),
                  ));
                },
                child: const Text('دیدن فهرست'),
              )),
            ]),
        ]),
        Text('حق دارند: فقط افراد فعال؛ غیرفعال‌ها شمرده نمی‌شوند.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: x.inkMuted)),
        const SectionTitle('موارد مشکوک'),
        if ((r['flagged'] as List).isEmpty) const Hint('موردی نیست.'),
        for (final f in r['flagged'] as List)
          ListTile(
            dense: true,
            leading: f['rejected'] == true
                ? Icon(Icons.gpp_bad_rounded, color: x.stop)
                : Icon(Icons.warning_rounded, color: x.wait),
            title: Text('${f['flag_label']} — ${(f['name'] as String?)?.isNotEmpty == true ? f['name'] : 'بدون نام'}'),
            subtitle: Text('ساعت ${_time(f['device_time'] as String?)}${f['staff'] != null ? '، ${f['staff']}' : ''}'),
          ),
        if (((r['hourly'] as List?) ?? const []).isNotEmpty) ...[
          SectionTitle('ورود ساعت‌به‌ساعت · ${s.dayName('${r['hourly_day']}')}'),
          _HourlyBars(hours: (r['hourly'] as List).cast<Map>()),
        ],
        if (((r['staff_activity'] as List?) ?? const []).isNotEmpty) ...[
          const SectionTitle('نیروها'),
          DataTable(columns: const [
            DataColumn(label: Text('نام')),
            DataColumn(label: Text('پذیرش'), numeric: true),
            DataColumn(label: Text('تحویل'), numeric: true),
            DataColumn(label: Text('آخرین فعالیت')),
          ], rows: [
            for (final st in (r['staff_activity'] as List).cast<Map>())
              DataRow(cells: [
                DataCell(Text('${st['name']}${st['active'] == false ? ' (غیرفعال)' : ''}')),
                DataCell(Text(st['checkins'] == 0 ? '—' : faDigits(st['checkins']))),
                DataCell(Text(st['meals'] == 0 ? '—' : faDigits(st['meals']))),
                DataCell(Text(DateTime.tryParse('${st['last_at']}') == null
                    ? '—'
                    : relativeTime(DateTime.parse('${st['last_at']}')))),
              ]),
          ]),
        ],
        const SectionTitle('خروجی‌ها'),
        _ExportCards(report: r),
        const SectionTitle('گوشی‌ها'),
        for (final d in r['devices'] as List) DeviceRow(device: (d as Map).cast<String, dynamic>()),
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


/// زمان نسبی فارسی: «همین الان»، «۲ دقیقه پیش»، «۳ ساعت پیش».
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'همین الان';
  if (d.inMinutes < 60) return '${faDigits(d.inMinutes)} دقیقه پیش';
  if (d.inHours < 24) return '${faDigits(d.inHours)} ساعت پیش';
  return '${faDigits(d.inDays)} روز پیش';
}

/// ردیف یک گوشی یا رایانه‌ی نیرو. بیش از ۱۰ دقیقه بی‌خبر = احتمالاً آفلاین و کارهایش هنوز نرسیده.
class DeviceRow extends StatelessWidget {
  final Map<String, dynamic> device;
  const DeviceRow({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final revoked = device['revoked'] == true;
    final last = DateTime.tryParse('${device['last_sync_at'] ?? ''}');
    final silent = last == null ? null : DateTime.now().difference(last.toLocal()).inMinutes;
    final stale = !revoked && silent != null && silent > 10;
    final label = '${device['label'] ?? ''}'.trim();
    final staff = '${device['staff'] ?? ''}'.trim();
    final line2 = [
      if (staff.isNotEmpty) staff,
      last == null ? 'هنوز همگام نشده' : (stale ? '${faDigits(silent)} دقیقه بی‌خبر' : relativeTime(last)),
    ].join('، ');
    return Opacity(
      opacity: revoked ? .55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: DaftarSize.space2),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
        child: Row(children: [
          Icon(revoked ? Icons.phonelink_erase_rounded : Icons.smartphone_rounded, color: x.inkMuted),
          const SizedBox(width: DaftarSize.space3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.isEmpty ? 'دستگاه بی‌نام' : label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Row(children: [
                if (stale) ...[Icon(Icons.warning_rounded, size: 14, color: x.wait), const SizedBox(width: 4)],
                Flexible(
                  child: Text(line2,
                      style: theme.textTheme.bodySmall?.copyWith(color: stale ? x.wait : x.inkMuted, fontFeatures: tabularFigures)),
                ),
              ]),
            ]),
          ),
          if (revoked)
            const DaftarTag('باطل‌شده', kind: TagKind.outline)
          else if (device['id'] is int)
            OutlinedButton(
              onPressed: () async {
                final s = StateScope.read(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('باطل کردن دستگاه'),
                    content: Text('دسترسی «${label.isEmpty ? 'این دستگاه' : label}» باطل شود؟ '
                        'کارهای ارسال‌نشده‌ی آن دستگاه تا ورود دوباره با PIN روی همان دستگاه می‌ماند.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
                      FilledButton(
                        style: daftarDangerStyle(c),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('باطل کن'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await s.revokeDevice(device['id'] as int);
              },
              child: const Text('باطل کن'),
            ),
        ]),
      ),
    );
  }
}

/// «دیدن فهرست» یک وعده: افراد فعال دارای حق و هر کس تحویل گرفته، با فیلتر.
class MealPeoplePage extends StatefulWidget {
  final String code;
  final String name;
  const MealPeoplePage({super.key, required this.code, required this.name});

  @override
  State<MealPeoplePage> createState() => _MealPeoplePageState();
}

class _MealPeoplePageState extends State<MealPeoplePage> {
  late Future<List<Map<String, dynamic>>> _people;
  String _filter = 'waiting';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _people = StateScope.read(context).mealPeople(widget.code);
  }

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _people,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          if (snap.hasError) {
            return const Padding(
              padding: EdgeInsets.all(DaftarSize.space4),
              child: Notice(tone: NoticeTone.neutral, text: 'این فهرست از سرور نیامد. افزونه‌ی سایت باید به‌روز شود.'),
            );
          }
          final all = snap.data!;
          bool match(Map<String, dynamic> p, String f) => switch (f) {
                'waiting' => p['entitled'] == true && (p['served'] as int? ?? 0) == 0,
                'served' => (p['served'] as int? ?? 0) > 0,
                'not_entitled' => p['entitled'] != true,
                _ => true,
              };
          int count(String f) => all.where((p) => match(p, f)).length;
          final list = all.where((p) => match(p, _filter)).toList();
          return ListView(padding: const EdgeInsets.all(DaftarSize.space4), children: [
            Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
              for (final (f, label) in const [
                ('waiting', 'حق دارند، نگرفته'),
                ('served', 'گرفته'),
                ('not_entitled', 'بدون حق، گرفته'),
                ('all', 'همه'),
              ])
                ChoiceChip(
                  label: Text('$label ${faDigits(count(f))}'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ]),
            const SizedBox(height: DaftarSize.space3),
            if (list.isEmpty) const Hint('کسی نیست.'),
            for (final p in list)
              Container(
                padding: const EdgeInsets.symmetric(vertical: DaftarSize.space2),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.line))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p['name']}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if ('${p['organization'] ?? ''}'.isNotEmpty)
                        Text('${p['organization']}', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                    ]),
                  ),
                  if ((p['served'] as int? ?? 0) > 0)
                    Text(
                      DateTime.tryParse('${p['served_at']}') != null ? 'گرفته ${hm(DateTime.parse('${p['served_at']}'))}' : 'گرفته',
                      style: theme.textTheme.bodySmall?.copyWith(color: x.go),
                    )
                  else
                    Text('هنوز نه', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

/// «ورود ساعت‌به‌ساعت»: ستون برای هر ساعت، عدد بالای ستون و ساعت زیرش.
class _HourlyBars extends StatelessWidget {
  final List<Map> hours;
  const _HourlyBars({required this.hours});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final max = hours.fold<int>(1, (m, h) => (h['count'] as int) > m ? h['count'] as int : m);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final h in hours)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DaftarSize.space1),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(faDigits(h['count']), style: theme.textTheme.labelMedium?.copyWith(fontFeatures: tabularFigures)),
                const SizedBox(height: DaftarSize.space1),
                Container(
                  height: (h['count'] as int) == 0 ? 3 : 100 * (h['count'] as int) / max,
                  decoration: BoxDecoration(
                    color: (h['count'] as int) == 0 ? x.line : x.stamp,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(DaftarSize.radiusXs)),
                  ),
                ),
                const SizedBox(height: DaftarSize.space1),
                Text(faDigits('${h['hour']}'.padLeft(2, '0')),
                    style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted, fontFeatures: tabularFigures)),
              ]),
            ),
          ),
      ]),
    );
  }
}

const _kinds = {
  'checkin': 'پذیرش',
  'checkin_undo': 'لغو پذیرش',
  'walkin_register': 'ثبت‌نام در محل',
  'meal_served': 'تحویل وعده',
  'meal_undo': 'برگرداندن وعده',
};

/// کارت‌های «گزارش‌ها» (طراحی ۱۰-Reports): فهرست حضور، پذیرایی، موارد بررسی، تاریخچه و پشتیبان کامل.
class _ExportCards extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ExportCards({required this.report});

  Future<void> _table(BuildContext context, String name, String title, List<List<String>> table, ExportFormat f) async {
    final s = StateScope.read(context);
    final bytes = await s.run('', () => encodeTable(table, f, title: title));
    if (bytes != null) await saveExportFile(s, '$name-${s.eventCode}.${f.ext}', f.ext, bytes);
  }

  List<List<String>> _meals() => [
        ['وعده', 'روز', 'حق دارند', 'تحویل‌شده', 'تکراری', 'بدون حق'],
        for (final m in (report['meals'] as List).cast<Map>())
          ['${m['name']}', '${m['day'] ?? ''}', '${m['entitled']}', '${m['served']}', '${m['duplicates']}', '${m['not_entitled']}'],
      ];

  List<List<String>> _flagged() => [
        ['زمان', 'کار', 'فرد', 'مشکل', 'نیرو', 'رد شد'],
        for (final f in (report['flagged'] as List).cast<Map>())
          [
            exportTime(f['device_time']?.toString(), jalali: true),
            _kinds[f['kind']] ?? '${f['kind']}',
            '${f['name'] ?? ''}',
            '${f['flag_label']}',
            '${f['staff'] ?? ''}',
            f['rejected'] == true ? 'بله' : '',
          ],
      ];

  /// تاریخچه‌ی همه‌ی رخدادها از دفتر، با نام فرد، نیرو و وعده.
  Future<void> _history(BuildContext context) async {
    final s = StateScope.read(context);
    final snap = await s.run('', s.fullSnapshot);
    if (snap == null || !context.mounted) return;
    final people = {for (final a in (snap['attendees'] as List).cast<Map>()) '${a['id']}': '${a['first_name']} ${a['last_name']}'};
    final staff = {for (final x in (snap['staff'] as List).cast<Map>()) x['id']: '${x['name']}'};
    final meals = {for (final m in (snap['meals'] as List).cast<Map>()) m['id']: '${m['name']}'};
    final table = [
      ['ردیف', 'زمان', 'کار', 'فرد', 'وعده', 'نیرو', 'پرچم', 'دلیل'],
      for (final e in (snap['log'] as List).cast<Map>())
        [
          '${e['seq']}',
          exportTime(e['device_time']?.toString(), jalali: true),
          _kinds[e['kind']] ?? '${e['kind']}',
          people[e['attendee_id']] ?? '',
          meals[e['meal_id']] ?? '',
          staff[e['staff_id']] ?? (e['staff_id'] == null ? 'اپ مدیریت' : ''),
          '${e['flag'] ?? ''}',
          '${(e['payload'] as Map?)?['reason'] ?? ''}',
        ],
    ];
    if (context.mounted) await _table(context, 'history', 'تاریخچه‌ی رویدادها', table, ExportFormat.xlsx);
  }

  Future<void> _backup(BuildContext context) async {
    final s = StateScope.read(context);
    final snap = await s.run('', s.fullSnapshot);
    if (snap == null) return;
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(snap)));
    await saveExportFile(s, 'backup-${s.eventCode}-${DateTime.now().toIso8601String().substring(0, 10)}.json', 'json', bytes);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final busy = s.busy;
    Widget card(IconData icon, String title, String text, List<(String, VoidCallback)> actions) => SizedBox(
          width: 320,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(DaftarSize.space4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: DaftarColors.of(context).stamp),
                const SizedBox(height: DaftarSize.space2),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DaftarColors.of(context).inkMuted)),
                const SizedBox(height: DaftarSize.space3),
                Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
                  for (final (label, onTap) in actions) OutlinedButton(onPressed: busy ? null : onTap, child: Text(label)),
                ]),
              ]),
            ),
          ),
        );
    return Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
      card(Icons.groups_rounded, 'فهرست حضور', 'افراد با اولین و آخرین پذیرش و پذیرش‌کننده.', [
        ('اکسل', () => showExportDialog(context)),
        ('PDF', () => showExportDialog(context, format: ExportFormat.pdf)),
      ]),
      card(Icons.restaurant_rounded, 'گزارش پذیرایی', 'تعداد هر وعده، تکراری‌ها و بدون حق.', [
        ('اکسل', () => _table(context, 'meals', 'گزارش پذیرایی', _meals(), ExportFormat.xlsx)),
        ('PDF', () => _table(context, 'meals', 'گزارش پذیرایی', _meals(), ExportFormat.pdf)),
      ]),
      card(Icons.flag_rounded, 'موارد نیازمند بررسی', 'پرچم‌ها و کارهایی که سرور نپذیرفت.', [
        ('اکسل', () => _table(context, 'flagged', 'موارد نیازمند بررسی', _flagged(), ExportFormat.xlsx)),
      ]),
      card(Icons.history_rounded, 'تاریخچه‌ی رویدادها', 'همه‌ی ثبت‌ها و لغوها به‌ترتیب زمان.', [
        ('اکسل', () => _history(context)),
      ]),
      card(Icons.backup_rounded, 'پشتیبان کامل رویداد', 'یک فایل از همه‌ی داده‌ها برای نگهداری پس از رویداد.', [
        ('ساخت پشتیبان', () => _backup(context)),
      ]),
    ]);
  }
}
