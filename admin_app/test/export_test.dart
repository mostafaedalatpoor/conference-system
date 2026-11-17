import 'dart:convert';

import 'package:conference_admin/export.dart';
import 'package:conference_admin/screens/people_desk.dart';
import 'package:conference_admin/state.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('خروجی (گروه ۴)', () {
    test('safeCell: = + - @ و تب امن می‌شوند', () {
      expect(safeCell('=SUM(A1)'), "'=SUM(A1)");
      expect(safeCell('+98912'), "'+98912");
      expect(safeCell('-5'), "'-5");
      expect(safeCell('@x'), "'@x");
      expect(safeCell('\tx'), "'\tx");
      expect(safeCell('علی'), 'علی');
      expect(safeCell(''), '');
    });

    final rows = [
      {
        'first_name': '=cmd',
        'last_name': 'رضایی',
        'card': 21,
        'first_checkin': '2026-11-20T06:00:00Z',
        'last_checkin': '2026-11-20T07:10:00Z',
        'checkin_by': 'سینا',
        'source': 'walkin',
        'meals': {'l1': 2},
      },
    ];
    final meals = [
      {'code': 'l1', 'name': 'ناهار'},
    ];

    test('exportTable: سرستون، وعده، منبع و کارت', () {
      final t = exportTable(rows, ['first_name', 'card', 'source', 'meal:l1', 'checkin_by'], meals, jalali: false);
      expect(t.first, ['نام', 'کارت', 'منبع', 'ناهار', 'پذیرش توسط']);
      expect(t[1], ['=cmd', '21', 'ثبت در محل', '2', 'سینا']);
    });

    test('exportTime شمسی و میلادی', () {
      final local = DateTime.utc(2026, 11, 20, 6).toLocal();
      final hm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      expect(exportTime('2026-11-20T06:00:00Z', jalali: false), startsWith('2026-11-'));
      expect(exportTime('2026-11-20T06:00:00Z', jalali: true), endsWith(hm));
      expect(exportTime('2026-11-20T06:00:00Z', jalali: true), startsWith('1405/08/'));
      expect(exportTime(null, jalali: true), '');
    });

    test('CSV: BOM، نقل‌قول و سلول امن', () {
      final bytes = toCsv([
        ['نام', 'سازمان'],
        ['=cmd', 'الف, ب'],
      ]);
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.sublist(3));
      expect(text, "نام,سازمان\r\n'=cmd,\"الف, ب\"\r\n");
    });

    test('xlsx: یک برگه‌ی راست‌به‌چپ با سلول امن', () {
      final ex = Excel.decodeBytes(toXlsx([
        ['نام'],
        ['=cmd'],
      ]));
      final sheet = ex.tables.values.first;
      expect(sheet.rows[1].first?.value.toString(), "'=cmd");
    });
  });

  group('فیلتر تب افراد (۱۷)', () {
    Person p({String status = 'active', String mobile = '0912', String email = ''}) =>
        Person(id: 'x', firstName: 'a', lastName: 'b', typeCode: 't', status: status, mobile: mobile, email: email);
    test('آمده، نیامده، ناقص، غیرفعال', () {
      expect(peopleFilterMatch(PeopleFilter.arrived, p(), {'checked_in': true}), isTrue);
      expect(peopleFilterMatch(PeopleFilter.notArrived, p(), {'checked_in': true}), isFalse);
      expect(peopleFilterMatch(PeopleFilter.notArrived, p(), null), isTrue);
      expect(peopleFilterMatch(PeopleFilter.incomplete, p(mobile: ''), null), isTrue);
      expect(peopleFilterMatch(PeopleFilter.incomplete, p(mobile: '', email: 'e@x'), null), isFalse);
      expect(peopleFilterMatch(PeopleFilter.all, p(status: 'inactive'), null), isFalse);
      expect(peopleFilterMatch(PeopleFilter.inactive, p(status: 'inactive'), null), isTrue);
    });
  });
}
