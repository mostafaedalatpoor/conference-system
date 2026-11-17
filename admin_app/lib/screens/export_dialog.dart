import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cards_pdf.dart' show PdfFonts;
import '../export.dart';
import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import 'cards.dart' show isMobilePlatform;

/// ذخیره‌ی فایل خروجی: روی گوشی انتخاب‌گر سیستم، روی ویندوز «ذخیره در مسیر». مسیر یا null.
Future<String?> saveExportFile(AdminState s, String name, String ext, Uint8List bytes) async {
  try {
    String? path;
    if (isMobilePlatform) {
      path = await FilePicker.platform.saveFile(
          dialogTitle: 'ذخیره‌ی خروجی', fileName: name, type: FileType.custom, allowedExtensions: [ext], bytes: bytes);
    } else {
      path = await FilePicker.platform
          .saveFile(dialogTitle: 'ذخیره‌ی خروجی', fileName: name, type: FileType.custom, allowedExtensions: [ext]);
      if (path != null) {
        path = path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';
        await File(path).writeAsBytes(bytes);
      }
    }
    if (path == null) return null;
    s.message = 'ذخیره شد: $path';
    s.messageIsError = false;
    s.notify();
    return path;
  } catch (e) {
    s.message = 'فایل ذخیره نشد: $e';
    s.messageIsError = true;
    s.notify();
    return null;
  }
}

/// ساخت بایت‌های یک جدول در قالب خواسته‌شده.
Future<Uint8List> encodeTable(List<List<String>> table, ExportFormat f, {required String title}) async => switch (f) {
      ExportFormat.csv => toCsv(table),
      ExportFormat.xlsx => toXlsx(table),
      ExportFormat.pdf => await toPdf(table, fonts: await PdfFonts.load(), title: title),
    };

/// پنجره‌ی «خروجی فهرست حضور» (طراحی ۱۰-Reports و ۱۸-States حالت ۱۴).
Future<void> showExportDialog(BuildContext context, {ExportFormat format = ExportFormat.xlsx}) =>
    showDialog<void>(context: context, builder: (_) => _ExportDialog(format: format));

class _ExportDialog extends StatefulWidget {
  final ExportFormat format;
  const _ExportDialog({required this.format});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  String _who = 'all';
  String? _type;
  String? _role;
  String? _day;
  late ExportFormat _format = widget.format;
  bool _jalali = true;
  final List<String> _cols = [...defaultExportColumns];
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await StateScope.read(context).exportRows(who: _who, type: _type, role: _role, day: _day);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _rows =>
      ((_data?['rows'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  List<Map<String, dynamic>> get _meals =>
      ((_data?['meals'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  Future<void> _build(AdminState s) async {
    final table = exportTable(_rows, _cols, _meals, jalali: _jalali);
    final title = 'فهرست حضور — ${s.event?.name ?? ''} — ${exportWho[_who]}';
    final bytes = await s.run('', () => encodeTable(table, _format, title: title));
    if (bytes == null || !mounted) return;
    final path = await saveExportFile(s, 'attendance-${s.eventCode}-$_who.${_format.ext}', _format.ext, bytes);
    if (path != null && mounted) Navigator.pop(context);
  }

  Widget _chips<T>(Map<T, String> items, bool Function(T) selected, void Function(T) onTap) => Wrap(
        spacing: DaftarSize.space2,
        runSpacing: DaftarSize.space2,
        children: [
          for (final e in items.entries)
            ChoiceChip(label: Text(e.value), selected: selected(e.key), onSelected: (_) => onTap(e.key)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final theme = Theme.of(context);
    final x = DaftarColors.of(context);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: DaftarSize.space3, bottom: DaftarSize.space2),
          child: Text(t, style: theme.textTheme.labelLarge?.copyWith(color: x.inkMuted)),
        );
    final days = [...{for (final r in _rows) ...((r['days'] as List?) ?? const []).map((e) => '$e')}]..sort();
    final allCols = {...exportColumns, for (final m in _meals) 'meal:${m['code']}': '${m['name']}'};
    return AlertDialog(
      title: const Text('خروجی فهرست حضور'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('چه کسانی'),
            _chips(exportWho, (k) => _who == k, (k) {
              _who = k;
              _load();
            }),
            const SizedBox(height: DaftarSize.space2),
            Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space2, children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  initialValue: _type,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'نوع', isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                    for (final t in s.types) DropdownMenuItem<String?>(value: t.code, child: Text(t.name)),
                  ],
                  onChanged: (v) {
                    _type = v;
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  initialValue: _role,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'نقش', isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                    for (final r in s.roles) DropdownMenuItem<String?>(value: r.code, child: Text(r.name)),
                  ],
                  onChanged: (v) {
                    _role = v;
                    _load();
                  },
                ),
              ),
              if (_data?['daily_attendance'] == true)
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _day,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'روز', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('همه‌ی روزها')),
                      for (final d in {...days, if (_day != null) _day!})
                        DropdownMenuItem<String?>(value: d, child: Text(s.dayName(d))),
                    ],
                    onChanged: (v) {
                      _day = v;
                      _load();
                    },
                  ),
                ),
            ]),
            label('ستون‌ها'),
            Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, children: [
              for (final e in allCols.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _cols.contains(e.key),
                  onSelected: (v) => setState(() {
                    if (v) {
                      // ترتیب ستون‌ها همان ترتیب فهرست بالا.
                      _cols
                        ..add(e.key)
                        ..sort((a, b) => allCols.keys.toList().indexOf(a).compareTo(allCols.keys.toList().indexOf(b)));
                    } else {
                      _cols.remove(e.key);
                    }
                  }),
                ),
            ]),
            Wrap(spacing: DaftarSize.space6, runSpacing: DaftarSize.space2, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                label('قالب'),
                _chips({for (final f in ExportFormat.values) f: f.label}, (f) => _format == f, (f) => setState(() => _format = f)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                label('تاریخ'),
                _chips({true: 'شمسی', false: 'میلادی'}, (v) => _jalali == v, (v) => setState(() => _jalali = v)),
              ]),
            ]),
            const SizedBox(height: DaftarSize.space3),
            const Hint('سلول‌هایی که با علامت ریاضی شروع می‌شوند، با یک نشانه امن ذخیره می‌شوند.'),
            if (_error != null) ...[
              const SizedBox(height: DaftarSize.space2),
              Notice(tone: NoticeTone.stop, text: 'ردیف‌ها از سرور نیامد: $_error'),
            ],
          ]),
        ),
      ),
      actions: [
        Text(
          _loading ? 'در حال خواندن…' : '${faDigits(_rows.length)} نفر · ${faDigits(_cols.length)} ستون',
          style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: _loading || _data == null || _cols.isEmpty || s.busy ? null : () => _build(s),
          child: const Text('ساخت خروجی'),
        ),
      ],
    );
  }
}
