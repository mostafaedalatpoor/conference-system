import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../excel_import.dart';
import '../main.dart';
import '../theme/widgets.dart';
import '../theme/daftar.dart';
import '../normalize.dart';
import '../state.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _fileName;
  List<SheetTable> _tables = [];
  SheetTable? _table;
  Map<String, int> _mapping = {};
  String? _typeCode;
  ImportResult? _preview;
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
    _preview = null;
  }

  void _buildPreview(AdminState s) {
    if (_table == null || _typeCode == null) return;
    setState(() => _preview = s.buildImport(_table!, _mapping, _typeCode!));
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final byType = <String, int>{};
    for (final p in s.people.values) {
      byType[p.typeCode] = (byType[p.typeCode] ?? 0) + 1;
    }

    return PageBody(title: 'شرکت‌کننده‌ها', children: [
      const SectionTitle('شرکت‌کننده‌های فعلی روی سرور'),
      Text(s.people.isEmpty
          ? 'هنوز کسی وارد نشده.'
          : [for (final e in byType.entries) '${s.typeName(e.key)}: ${faDigits(e.value)}'].join('   ·   ')),
      const SectionTitle('ورود از اکسل'),
      const Hint(
        'هر فایل یک نوع ثبت‌نام دارد (مثلاً خروجی سایت ثبت‌نام = ارائه‌دهنده، فرم شنونده‌ها = شرکت‌کننده). '
        'ورود دوباره‌ی همان فایل کسی را تکراری نمی‌کند و کارت چاپ‌شده‌اش را عوض نمی‌کند؛ شناسه‌ی هر نفر از ایمیل، '
        'یا اگر نبود موبایل، یا اگر نبود نام ساخته می‌شود.',
      ),
      const SizedBox(height: 12),
      Row(children: [
        OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open_rounded), label: const Text('انتخاب فایل (xlsx یا csv)')),
        const SizedBox(width: 12),
        if (_fileName != null) Expanded(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(tone: NoticeTone.stop, text: _error!)),
      if (_tables.length > 1) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<SheetTable>(
          value: _table,
          decoration: const InputDecoration(labelText: 'برگه'),
          items: [for (final t in _tables) DropdownMenuItem(value: t, child: Text('${t.name} (${faDigits(t.rows.length)} ردیف)'))],
          onChanged: (t) => setState(() => _selectTable(t)),
        ),
      ],
      if (_table != null) ...[
        const SectionTitle('کدام ستون چیست؟'),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final f in fieldLabels.entries)
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<int>(
                value: _mapping[f.key],
                isExpanded: true,
                decoration: InputDecoration(labelText: f.value, isDense: true),
                items: [
                  const DropdownMenuItem<int>(value: -1, child: Text('— ندارد —')),
                  for (var i = 0; i < _table!.headers.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${_table!.headers[i].isEmpty ? 'ستون ${faDigits(i + 1)}' : _table!.headers[i]}'
                        '${_table!.rows.isNotEmpty ? '  (مثلاً: ${_table!.rows.first[i]})' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  if (v == null || v < 0) {
                    _mapping.remove(f.key);
                  } else {
                    _mapping[f.key] = v;
                  }
                  _preview = null;
                }),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: 300,
          child: DropdownButtonFormField<String>(
            value: _typeCode,
            decoration: const InputDecoration(labelText: 'نوع ثبت‌نام همه‌ی این فایل'),
            items: [for (final t in s.types) DropdownMenuItem(value: t.code, child: Text(t.name))],
            onChanged: (v) => setState(() {
              _typeCode = v;
              _preview = null;
            }),
          ),
        ),
        if (s.types.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Notice(tone: NoticeTone.wait, text: 'اول در «پیکربندی» انواع ثبت‌نام را بسازید و ذخیره کنید.'),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: _typeCode == null ? null : () => _buildPreview(s),
            child: const Text('پیش‌نمایش'),
          ),
        ),
      ],
      if (_preview != null) ...[
        const SectionTitle('پیش‌نمایش'),
        Text('${faDigits(_preview!.people.length)} نفر: ${faDigits(_preview!.created)} جدید، '
            '${faDigits(_preview!.updated)} به‌روزرسانی. ${faDigits(_preview!.problems.length)} مورد مشکل.'),
        const SizedBox(height: 8),
        if (_preview!.problems.isNotEmpty)
          // ردیف‌های مشکل‌دار: پس‌زمینه‌ی wait-soft با آیکن هشدار.
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: DaftarColors.of(context).waitSoft,
              borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
            ),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(DaftarSize.space3), children: [
              for (final p in _preview!.problems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_rounded, size: 16, color: DaftarColors.of(context).wait),
                    const SizedBox(width: DaftarSize.space2),
                    Expanded(child: Text(p, style: Theme.of(context).textTheme.bodySmall)),
                  ]),
                ),
            ]),
          ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('کارت')),
              DataColumn(label: Text('عنوان')),
              DataColumn(label: Text('نام')),
              DataColumn(label: Text('نام خانوادگی')),
              DataColumn(label: Text('موبایل')),
              DataColumn(label: Text('ایمیل')),
              DataColumn(label: Text('سازمان')),
              DataColumn(label: Text('ارائه')),
              DataColumn(label: Text('نقش')),
            ],
            rows: [
              for (final p in _preview!.people.take(30))
                DataRow(cells: [
                  DataCell(Text(faDigits(p.serial ?? ''))),
                  DataCell(Text(p.title)),
                  DataCell(Text(p.firstName)),
                  DataCell(Text(p.lastName)),
                  DataCell(Text(p.mobile)),
                  DataCell(Text(p.email)),
                  DataCell(Text(p.organization)),
                  DataCell(Text(p.presentationKind == 'poster' ? 'پوستر' : (p.presentationKind == 'oral' ? 'شفاهی' : ''))),
                  DataCell(Text(s.roleName(p.roleCode))),
                ]),
            ],
          ),
        ),
        if (_preview!.people.length > 30) Text('… و ${faDigits(_preview!.people.length - 30)} نفر دیگر'),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_rounded),
            onPressed: s.busy || _preview!.people.isEmpty
                ? null
                : () async {
                    await s.uploadPeople(_preview!.people);
                    if (mounted && !s.messageIsError) setState(() => _preview = null);
                  },
            label: Text('ارسال ${faDigits(_preview!.people.length)} نفر به سرور'),
          ),
        ),
      ],
    ]);
  }
}
