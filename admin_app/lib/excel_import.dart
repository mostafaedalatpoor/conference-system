import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'normalize.dart';

/// یک جدول خوانده‌شده از فایل: سرستون‌ها و ردیف‌ها، همه به شکل متن.
class SheetTable {
  final String name;
  final List<String> headers;
  final List<List<String>> rows;
  SheetTable(this.name, this.headers, this.rows);
}

/// فیلدهایی که از هر ستون می‌شود پر کرد.
const Map<String, String> fieldLabels = {
  'title': 'عنوان (دکتر، مهندس…)',
  'first_name': 'نام',
  'last_name': 'نام خانوادگی',
  'full_name': 'نام کامل (در یک ستون)',
  'email': 'ایمیل',
  'mobile': 'موبایل',
  'organization': 'سازمان',
  'country': 'کشور',
  'presentation_kind': 'نوع ارائه (پوستر/شفاهی)',
  'role': 'نقش',
  'share_contact': 'اشتراک اطلاعات تماس (بله/خیر)',
  'website': 'صفحه‌ی شخصی (لینک)',
};

const Map<String, List<String>> _synonyms = {
  'title': ['title', 'عنوان', 'لقب', 'پیشوند'],
  'first_name': ['first name', 'firstname', 'first_name', 'name', 'given name', 'نام'],
  'last_name': ['last name', 'lastname', 'last_name', 'family', 'family name', 'surname', 'نام خانوادگی', 'فامیلی', 'نام‌خانوادگی'],
  'full_name': ['full name', 'fullname', 'نام و نام خانوادگی', 'نام کامل'],
  'email': ['email', 'e-mail', 'mail', 'ایمیل', 'پست الکترونیک'],
  'mobile': ['mobile', 'phone', 'cell', 'tel', 'موبایل', 'شماره موبایل', 'تلفن همراه', 'شماره تماس', 'تلفن', 'همراه'],
  'organization': ['organization', 'organisation', 'affiliation', 'company', 'university', 'سازمان', 'دانشگاه', 'محل کار', 'وابستگی'],
  'country': ['country', 'کشور'],
  'presentation_kind': ['presentation', 'presentation type', 'نوع ارائه', 'ارائه'],
  'role': ['role', 'نقش'],
  'share_contact': ['share contact', 'اشتراک اطلاعات تماس', 'اشتراک تماس'],
  'website': ['website', 'homepage', 'url', 'وب‌سایت', 'وبسایت', 'صفحه شخصی', 'صفحه‌ی شخصی'],
};

/// «بله/خیر» ستون اشتراک اطلاعات تماس؛ خالی یا نامفهوم = طبق تنظیم رویداد.
bool? shareFrom(String v) {
  final s = v.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (['بله', 'آره', 'yes', 'y', 'true', '1', 'دارد'].contains(s)) return true;
  if (['خیر', 'نه', 'no', 'n', 'false', '0', 'ندارد'].contains(s)) return false;
  return null;
}

Future<List<SheetTable>> readTables(String fileName, Uint8List bytes) async {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.csv') || lower.endsWith('.txt') || lower.endsWith('.tsv')) {
    return [_readCsv(fileName, bytes)];
  }
  final excel = Excel.decodeBytes(bytes);
  final out = <SheetTable>[];
  for (final entry in excel.tables.entries) {
    final rows = entry.value.rows
        .map((r) => r.map(_cellText).toList())
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) continue;
    final width = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    final padded = rows.map((r) => [...r, for (var i = r.length; i < width; i++) '']).toList();
    out.add(SheetTable(entry.key, padded.first.map((h) => h.trim()).toList(), padded.sublist(1)));
  }
  return out;
}

String _cellText(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) {
    final x = v.value;
    return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
  }
  return v.toString().trim();
}

SheetTable _readCsv(String name, Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final delim = ['\t', ';', ','].firstWhere((d) => firstLine.contains(d), orElse: () => ',');
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delim) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
  if (rows.isEmpty) return SheetTable(name, [], []);
  final width = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
  final padded = rows.map((r) => [...r.map((c) => c.trim()), for (var i = r.length; i < width; i++) '']).toList();
  return SheetTable(name, padded.first, padded.sublist(1));
}

/// حدس اولیه‌ی نگاشت: فیلد → شماره‌ی ستون.
Map<String, int> guessMapping(List<String> headers) {
  final out = <String, int>{};
  final norm = headers.map((h) => normalizeText(h).replaceAll('_', ' ')).toList();
  // اول تطابق کامل، بعد شامل‌بودن؛ «نام خانوادگی» نباید به «نام» بخورد.
  for (final exact in [true, false]) {
    for (final f in _synonyms.keys) {
      if (out.containsKey(f)) continue;
      for (var i = 0; i < norm.length; i++) {
        if (out.containsValue(i)) continue;
        final hit = _synonyms[f]!.any((s) {
          final ns = normalizeText(s);
          return exact ? norm[i] == ns : (ns.length > 3 && norm[i].contains(ns));
        });
        if (hit) {
          out[f] = i;
          break;
        }
      }
    }
  }
  if (out.containsKey('first_name') && out.containsKey('last_name')) out.remove('full_name');
  return out;
}

String presentationKindFrom(String raw) {
  final s = normalizeText(raw);
  if (s.isEmpty) return '';
  if (s.contains('پوستر') || s.contains('poster')) return 'poster';
  if (s.contains('شفاهی') || s.contains('oral') || s.contains('سخنرانی') || s.contains('lecture')) return 'oral';
  return '';
}
