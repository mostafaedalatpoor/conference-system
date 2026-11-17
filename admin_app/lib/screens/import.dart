import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../excel_import.dart';
import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

/// ورود افراد از اکسل در سه گام (طراحی ویندوز ۰۶-Import، مورد ۱۸):
/// ۱ فایل، ۲ نگاشت ستون‌ها و تطبیق مقدار نوع و نقش، ۳ بررسی تکراری‌ها و ورود.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  int _step = 0;
  String? _fileName;
  List<SheetTable> _tables = [];
  SheetTable? _table;
  Map<String, int> _mapping = {};
  Set<String> _guessed = {};

  /// نوع: true = از ستون فایل (با جدول تطبیق)، false = یک نوع برای همه.
  bool _typeFromColumn = false;
  String? _typeCode;
  final Map<String, String> _typeByValue = {};

  /// نقش: مقدار ستون → کد نقش (null = بدون نقش).
  final Map<String, String?> _roleByValue = {};

  /// تصمیم ردیف‌های هم‌تماس با فرد فعلی: merge / new / skip.
  final Map<int, String> _resolutions = {};
  String? _error;

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    try {
      final tables = await readTables(f.name, f.bytes!);
      setState(() {
        _fileName = f.name;
        _tables = tables;
        _error = tables.isEmpty ? 'فایل خالی است.' : null;
        _selectTable(tables.isEmpty ? null : tables.first);
      });
    } catch (e) {
      setState(() => _error = 'خواندن فایل ناموفق بود: $e\nاگر فایل .xls قدیمی است، در اکسل با فرمت .xlsx ذخیره‌اش کنید.');
    }
  }

  void _selectTable(SheetTable? t) {
    _table = t;
    _mapping = t == null ? {} : guessMapping(t.headers);
    _guessed = _mapping.keys.toSet();
    _typeFromColumn = _mapping.containsKey('type');
    _typeByValue.clear();
    _roleByValue.clear();
    _resolutions.clear();
  }

  /// تطبیق خودکار مقدارها با نوع‌ها و نقش‌های تعریف‌شده (فقط جاهایی که هنوز انتخاب نشده).
  void _autoMatch(AdminState s) {
    final t = _table;
    if (t == null) return;
    autoMatchValues(distinctValues(t, _mapping['type']), s.types.map((x) => (x.code, x.name)))
        .forEach((k, v) => _typeByValue.putIfAbsent(k, () => v));
    autoMatchValues(distinctValues(t, _mapping['role']), s.roles.map((x) => (x.code, x.name)))
        .forEach((k, v) => _roleByValue.putIfAbsent(k, () => v));
  }

  ImportResult? _result(AdminState s) {
    final t = _table;
    if (t == null) return null;
    if (_typeFromColumn ? !_mapping.containsKey('type') : _typeCode == null) return null;
    return s.buildImport(
      t,
      _mapping,
      _typeFromColumn ? null : _typeCode,
      typeByValue: _typeFromColumn ? _typeByValue : null,
      roleByValue: _mapping.containsKey('role') ? _roleByValue : null,
      resolutions: _resolutions,
    );
  }

  bool get _namesMapped =>
      _mapping.containsKey('full_name') || (_mapping.containsKey('first_name') && _mapping.containsKey('last_name'));

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    if (_table != null) _autoMatch(s);
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    const steps = ['انتخاب فایل', 'نگاشت ستون‌ها', 'بررسی و ورود'];

    final header = Row(children: [
      for (var i = 0; i < steps.length; i++) ...[
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 6, decoration: BoxDecoration(color: i <= _step ? x.stamp : x.line, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: DaftarSize.space1),
            Text('${faDigits(i + 1)} · ${steps[i]}',
                style: theme.textTheme.bodySmall?.copyWith(color: i == _step ? x.ink : x.inkMuted, fontWeight: i == _step ? FontWeight.w800 : null)),
          ]),
        ),
        if (i < steps.length - 1) const SizedBox(width: DaftarSize.space2),
      ],
    ]);

    return PageBody(title: 'ورود افراد از اکسل', children: [
      header,
      const SizedBox(height: DaftarSize.space4),
      ...switch (_step) {
        0 => _fileStep(s),
        1 => _mappingStep(s),
        _ => _reviewStep(s),
      },
    ]);
  }

  // ---------------------------------------------------------------- گام ۱

  List<Widget> _fileStep(AdminState s) {
    final byType = <String, int>{};
    for (final p in s.people.values.where((p) => p.isActive)) {
      byType[p.typeCode] = (byType[p.typeCode] ?? 0) + 1;
    }
    return [
      Text(s.people.isEmpty
          ? 'هنوز کسی وارد نشده.'
          : 'روی سرور: ${[for (final e in byType.entries) '${s.typeName(e.key)}: ${faDigits(e.value)}'].join('   ·   ')}'),
      const SizedBox(height: DaftarSize.space3),
      Row(children: [
        OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open_rounded), label: const Text('انتخاب فایل (xlsx یا csv)')),
        const SizedBox(width: 12),
        if (_fileName != null)
          Expanded(child: Text('$_fileName · ${faDigits(_table?.rows.length ?? 0)} ردیف', overflow: TextOverflow.ellipsis)),
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(tone: NoticeTone.stop, text: _error!)),
      if (_tables.length > 1) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<SheetTable>(
          initialValue: _table,
          decoration: const InputDecoration(labelText: 'برگه'),
          items: [for (final t in _tables) DropdownMenuItem(value: t, child: Text('${t.name} (${faDigits(t.rows.length)} ردیف)'))],
          onChanged: (t) => setState(() => _selectTable(t)),
        ),
      ],
      const SizedBox(height: DaftarSize.space3),
      const Hint(
        'ورود دوباره‌ی همان فایل کسی را تکراری نمی‌کند و کارت چاپ‌شده‌اش را عوض نمی‌کند؛ شناسه‌ی هر نفر از ایمیل، '
        'یا اگر نبود موبایل، یا اگر نبود نام ساخته می‌شود.',
      ),
      if (s.imports.isNotEmpty) ...[
        const SectionTitle('ورودی‌های قبلی'),
        for (final b in s.imports)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(Icons.description_rounded, size: 20, color: DaftarColors.of(context).inkMuted),
              const SizedBox(width: DaftarSize.space2),
              Expanded(
                child: Text([
                  b.fileName.isEmpty ? 'بدون نام' : b.fileName,
                  '${faDigits(b.people)} نفر',
                  if (DateTime.tryParse(b.createdAt ?? '') != null) hm(DateTime.parse(b.createdAt!)),
                ].join(' · ')),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: DaftarColors.of(context).stop),
                onPressed: s.busy || b.people == 0 ? null : () => _deleteImport(s, b),
                child: const Text('حذف این ورودی…'),
              ),
            ]),
          ),
      ],
      const SizedBox(height: DaftarSize.space5),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton(onPressed: _table == null ? null : () => setState(() => _step = 1), child: const Text('بعدی: نگاشت ستون‌ها')),
      ),
    ];
  }

  Future<void> _deleteImport(AdminState s, ImportBatch b) async {
    final del = b.people - b.withActivity;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف ورودی «${b.fileName}»؟'),
        content: Text('${faDigits(del)} نفر حذف می‌شود.'
            '${b.withActivity > 0 ? ' ${faDigits(b.withActivity)} نفر چون پذیرش یا وعده دارند می‌مانند.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه، برگرد')),
          FilledButton(
            style: daftarDangerStyle(c),
            onPressed: del > 0 ? () => Navigator.pop(c, true) : null,
            child: Text('حذف ${faDigits(del)} نفر'),
          ),
        ],
      ),
    );
    if (ok == true) await s.deleteImport(b);
  }

  // ---------------------------------------------------------------- گام ۲

  Widget _pill(String text, bool ok) {
    final x = DaftarColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: ok ? x.goSoft : x.waitSoft, borderRadius: BorderRadius.circular(DaftarSize.radiusPill)),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ok ? x.go : x.wait, fontWeight: FontWeight.w700)),
    );
  }

  /// جدول «مقدار فایل ← نوع/نقش».
  Widget _valueTable(AdminState s, {required bool role}) {
    final t = _table!;
    final values = distinctValues(t, _mapping[role ? 'role' : 'type']);
    final items = role ? s.roles : s.types;
    if (values.isEmpty) return const Hint('این ستون مقداری ندارد.');
    return Column(children: [
      for (final v in values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
            const Icon(Icons.arrow_back_rounded, size: 18),
            const SizedBox(width: DaftarSize.space2),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('${role ? 'r' : 't'}:$v:${items.length}'),
                initialValue: role ? _roleByValue[normalizeText(v)] : _typeByValue[normalizeText(v)],
                isDense: true,
                decoration: const InputDecoration(isDense: true, hintText: 'انتخاب کنید'),
                items: [
                  if (role) const DropdownMenuItem<String?>(value: null, child: Text('بدون نقش')),
                  for (final i in items) DropdownMenuItem<String?>(value: i.code, child: Text(i.name)),
                ],
                onChanged: (c) => setState(() {
                  if (role) {
                    _roleByValue[normalizeText(v)] = c;
                  } else if (c != null) {
                    _typeByValue[normalizeText(v)] = c;
                  }
                }),
              ),
            ),
            const SizedBox(width: DaftarSize.space2),
            SizedBox(
              width: 120,
              child: (role ? _roleByValue.containsKey(normalizeText(v)) : _typeByValue.containsKey(normalizeText(v)))
                  ? _pill('تطبیق شد', true)
                  : TextButton(
                      onPressed: s.busy
                          ? null
                          : () async {
                              final c = await s.createTypeOrRole(role: role, name: v);
                              if (c != null && mounted) {
                                setState(() => role ? _roleByValue[normalizeText(v)] = c : _typeByValue[normalizeText(v)] = c);
                              }
                            },
                      child: Text(role ? 'ساخت نقش تازه' : 'ساخت نوع تازه'),
                    ),
            ),
          ]),
        ),
    ]);
  }

  List<Widget> _mappingStep(AdminState s) {
    final t = _table!;
    final typeValues = _typeFromColumn ? distinctValues(t, _mapping['type']) : const <String>[];
    final unmatchedTypes = typeValues.where((v) => !_typeByValue.containsKey(normalizeText(v))).length;
    final ready = _namesMapped && (_typeFromColumn ? _mapping.containsKey('type') && unmatchedTypes == 0 : _typeCode != null);
    return [
      Text('هر ستون اکسل کدام ویژگی است؟', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: DaftarSize.space2),
      for (final f in fieldLabels.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 220, child: Text(f.value)),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('map:${f.key}:${_mapping[f.key]}'),
                initialValue: _mapping[f.key] ?? -1,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  const DropdownMenuItem<int>(value: -1, child: Text('— نادیده بگیر —')),
                  for (var i = 0; i < t.headers.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${t.headers[i].isEmpty ? 'ستون ${faDigits(i + 1)}' : t.headers[i]}'
                        '${t.rows.isNotEmpty ? '  (مثلاً: ${t.rows.first[i]})' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _guessed.remove(f.key);
                  if (v == null || v < 0) {
                    _mapping.remove(f.key);
                  } else {
                    _mapping[f.key] = v;
                  }
                  if (f.key == 'type') _typeByValue.clear();
                  if (f.key == 'role') _roleByValue.clear();
                }),
              ),
            ),
            const SizedBox(width: DaftarSize.space2),
            SizedBox(
              width: 110,
              child: _guessed.contains(f.key) && _mapping.containsKey(f.key)
                  ? _pill('خودکار', true)
                  : (const ['first_name', 'last_name'].contains(f.key) && !_namesMapped ? _pill('نیاز به انتخاب', false) : null),
            ),
          ]),
        ),
      const SectionTitle('نوع ثبت‌نام'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('از ستون فایل')),
          ButtonSegment(value: false, label: Text('یک نوع برای همه')),
        ],
        selected: {_typeFromColumn},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _typeFromColumn = v.first),
      ),
      const SizedBox(height: DaftarSize.space3),
      if (!_typeFromColumn)
        SizedBox(
          width: 300,
          child: DropdownButtonFormField<String>(
            initialValue: _typeCode,
            decoration: const InputDecoration(labelText: 'نوع ثبت‌نام همه‌ی این فایل'),
            items: [for (final t in s.types) DropdownMenuItem(value: t.code, child: Text(t.name))],
            onChanged: (v) => setState(() => _typeCode = v),
          ),
        )
      else if (!_mapping.containsKey('type'))
        const Notice(tone: NoticeTone.wait, text: 'ستون «نوع ثبت‌نام» را در فهرست بالا انتخاب کنید.')
      else
        _valueTable(s, role: false),
      if (_mapping.containsKey('role')) ...[
        const SectionTitle('نقش'),
        const Hint('هر مقدار ستون نقش به کدام نقش؟ مقداری که تطبیق نشود، بدون نقش وارد می‌شود.'),
        const SizedBox(height: DaftarSize.space2),
        _valueTable(s, role: true),
      ],
      if (s.types.isEmpty && !_typeFromColumn)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Notice(tone: NoticeTone.wait, text: 'اول در «پیکربندی» انواع ثبت‌نام را بسازید، یا «از ستون فایل» را انتخاب کنید.'),
        ),
      const SizedBox(height: DaftarSize.space5),
      Row(children: [
        OutlinedButton(onPressed: () => setState(() => _step = 0), child: const Text('بازگشت')),
        const SizedBox(width: DaftarSize.space3),
        FilledButton(
          onPressed: ready ? () => setState(() => _step = 2) : null,
          child: Text(!_namesMapped
              ? 'ستون نام را انتخاب کنید'
              : unmatchedTypes > 0
                  ? '${faDigits(unmatchedTypes)} مقدار نوع تطبیق نشده'
                  : 'بعدی: بررسی'),
        ),
      ]),
    ];
  }

  // ---------------------------------------------------------------- گام ۳

  List<Widget> _reviewStep(AdminState s) {
    final r = _result(s);
    if (r == null) return [const Notice(tone: NoticeTone.wait, text: 'نگاشت کامل نیست.')];
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    Widget stat(int n, String label, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(faDigits(n), style: theme.textTheme.headlineSmall?.copyWith(color: c, fontWeight: FontWeight.w800)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
          ]),
        );
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(DaftarSize.space4),
          child: Row(children: [
            stat(r.people.length - r.incomplete, 'کامل و آماده', x.go),
            stat(r.incomplete, 'ناقص (بدون موبایل) · وارد می‌شوند', x.wait),
            stat(r.conflicts.length, 'تکراری با افراد فعلی · ادغام یا رد', x.stop),
          ]),
        ),
      ),
      Text('${faDigits(r.created)} نفر جدید، ${faDigits(r.updated)} به‌روزرسانی'
          '${r.possibleDuplicates > 0 ? '، ${faDigits(r.possibleDuplicates)} احتمال تکراری درون فایل' : ''}.'),
      for (final c in r.conflicts) _conflictCard(s, c),
      if (r.problems.isNotEmpty) ...[
        const SectionTitle('ردیف‌هایی که توجه می‌خواهند'),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(color: x.waitSoft, borderRadius: BorderRadius.circular(DaftarSize.radiusXs)),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(DaftarSize.space3), children: [
            for (final p in r.problems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_rounded, size: 16, color: x.wait),
                  const SizedBox(width: DaftarSize.space2),
                  Expanded(child: Text(p, style: theme.textTheme.bodySmall)),
                ]),
              ),
          ]),
        ),
      ],
      const SectionTitle('پیش‌نمایش'),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('کارت')),
            DataColumn(label: Text('نام')),
            DataColumn(label: Text('موبایل')),
            DataColumn(label: Text('سازمان')),
            DataColumn(label: Text('نوع')),
            DataColumn(label: Text('نقش')),
          ],
          rows: [
            for (final p in r.people.take(30))
              DataRow(
                color: p.mobile.isEmpty ? WidgetStatePropertyAll(x.waitSoft) : null,
                cells: [
                  DataCell(Text(faDigits(p.serial ?? ''))),
                  DataCell(Text(p.displayName)),
                  DataCell(Text(p.mobile.isEmpty ? 'خالی' : p.mobile)),
                  DataCell(Text(p.organization)),
                  DataCell(Text(s.typeName(p.typeCode))),
                  DataCell(Text(s.roleName(p.roleCode))),
                ],
              ),
          ],
        ),
      ),
      if (r.people.length > 30) Text('… و ${faDigits(r.people.length - 30)} نفر دیگر'),
      const SizedBox(height: DaftarSize.space4),
      Text('افراد فعلی دست نمی‌خورند؛ ردیف تکراری فقط پس از تأیید شما ادغام می‌شود.',
          style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
      const SizedBox(height: DaftarSize.space3),
      Row(children: [
        OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('بازگشت')),
        const SizedBox(width: DaftarSize.space3),
        FilledButton.icon(
          icon: const Icon(Icons.cloud_upload_rounded),
          onPressed: s.busy || r.people.isEmpty
              ? null
              : () async {
                  await s.uploadPeople(r.people, fileName: _fileName);
                  if (mounted && !s.messageIsError) {
                    setState(() {
                      _step = 0;
                      _table = null;
                      _tables = [];
                      _fileName = null;
                    });
                  }
                },
          label: Text('ورود ${faDigits(r.people.length)} ردیف'),
        ),
      ]),
    ];
  }

  /// کارت «فرد فعلی ↔ ردیف جدید» با «ادغام»، «فرد جدید بساز»، «رد».
  Widget _conflictCard(AdminState s, ImportConflict c) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    final choice = _resolutions[c.row] ?? 'new';
    Widget side(String tag, Person p) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(DaftarSize.space3),
            decoration: BoxDecoration(color: x.sunken, borderRadius: BorderRadius.circular(DaftarSize.radiusSm)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tag, style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
              Text(p.displayName, style: theme.textTheme.titleSmall),
              if (p.mobile.isNotEmpty) Text('موبایل: ${p.mobile}', style: theme.textTheme.bodySmall),
              if (p.email.isNotEmpty) Text('ایمیل: ${p.email}', style: theme.textTheme.bodySmall),
              if (p.organization.isNotEmpty) Text('سازمان: ${p.organization}', style: theme.textTheme.bodySmall),
            ]),
          ),
        );
    return Card(
      margin: const EdgeInsets.only(top: DaftarSize.space3),
      child: Padding(
        padding: const EdgeInsets.all(DaftarSize.space3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ردیف ${faDigits(c.row + 2)} · ${normalizeMobile(c.existing.mobile) == normalizeMobile(c.incoming.mobile) && c.incoming.mobile.isNotEmpty ? 'موبایل یکسان' : 'ایمیل یکسان'}',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: DaftarSize.space2),
          Row(children: [side('فرد فعلی', c.existing), const SizedBox(width: DaftarSize.space2), side('ردیف جدید', c.incoming)]),
          const SizedBox(height: DaftarSize.space2),
          Wrap(spacing: DaftarSize.space2, children: [
            for (final (v, label) in const [('merge', 'ادغام'), ('new', 'فرد جدید بساز'), ('skip', 'رد')])
              ChoiceChip(label: Text(label), selected: choice == v, onSelected: (_) => setState(() => _resolutions[c.row] = v)),
          ]),
        ]),
      ),
    );
  }
}
