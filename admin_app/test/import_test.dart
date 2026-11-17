import 'package:conference_admin/excel_import.dart';
import 'package:conference_admin/normalize.dart';
import 'package:conference_admin/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final table = SheetTable('s', ['نام', 'نام خانوادگی', 'موبایل', 'نوع', 'نقش'], [
    ['علی', 'محمدی', '09121111111', 'ارائه‌دهنده', 'سخنران'],
    ['زهرا', 'احمدی', '', 'شرکت کننده', ''],
    ['مریم', 'رضایی', '09122222222', 'مهمان ویژه', 'داور'],
  ]);

  group('جدول تطبیق مقدار (۱۸)', () {
    test('distinctValues بدون خالی و تکرار', () {
      final t = SheetTable('s', ['x'], [
        ['الف'],
        [''],
        ['الف '],
        ['ب'],
      ]);
      expect(distinctValues(t, 0), ['الف', 'ب']);
      expect(distinctValues(t, null), isEmpty);
    });

    test('autoMatchValues با نام نرمال‌شده یا کد', () {
      final m = autoMatchValues(['ارائه‌دهنده', 'شرکت كننده', 'guest', 'نامعلوم'], [
        ('presenter', 'ارائه دهنده'),
        ('participant', 'شرکت کننده'),
        ('guest', 'مهمان'),
      ]);
      expect(m.length, 3);
      expect(m.values, containsAll(['presenter', 'participant', 'guest']));
    });

    test('guessMapping ستون نوع را می‌شناسد', () {
      expect(guessMapping(table.headers)['type'], 3);
    });
  });

  group('buildImport با نوع و نقش از ستون', () {
    AdminState state() => AdminState()
      ..eventCode = 'ev'
      ..types = [CodeName('p', 'ارائه‌دهنده'), CodeName('a', 'شرکت کننده')]
      ..roles = [CodeName('sp', 'سخنران')];
    final mapping = {'first_name': 0, 'last_name': 1, 'mobile': 2, 'type': 3, 'role': 4};

    test('مقدار تطبیق‌نشده‌ی نوع رد و گزارش می‌شود؛ نقش از جدول', () {
      final s = state();
      final r = s.buildImport(table, mapping, null,
          typeByValue: {normalizeText('ارائه‌دهنده'): 'p', normalizeText('شرکت کننده'): 'a'},
          roleByValue: {normalizeText('سخنران'): 'sp', normalizeText('داور'): null});
      expect(r.people.map((p) => p.typeCode).toList(), ['p', 'a']);
      expect(r.people.first.roleCode, 'sp');
      expect(r.problems.single, contains('مهمان ویژه'));
      expect(r.incomplete, 1);
    });

    test('یک نوع برای همه همان رفتار قبلی است', () {
      final r = state().buildImport(table, mapping, 'a');
      expect(r.people.length, 3);
      expect(r.people.every((p) => p.typeCode == 'a'), isTrue);
    });

    test('تماس مشترک با فرد فعلی: new، merge، skip', () {
      final s = state();
      s.people = {
        'old': Person(id: 'old', firstName: 'علی', lastName: 'م', typeCode: 'p', mobile: '09121111111', token: 'tok', serial: 7),
      };
      final t = SheetTable('s', ['نام', 'نام خانوادگی', 'ایمیل', 'موبایل'], [
        ['دکتر علی', 'محمدی', 'ali@x.ir', '09121111111'],
      ]);
      final m = {'first_name': 0, 'last_name': 1, 'email': 2, 'mobile': 3};
      final asNew = s.buildImport(t, m, 'p');
      expect(asNew.conflicts.length, 1);
      expect(asNew.people.single.id, isNot('old'));
      final merged = s.buildImport(t, m, 'p', resolutions: {0: 'merge'});
      expect(merged.people.single.id, 'old');
      expect(merged.people.single.serial, 7);
      expect(merged.updated, 1);
      final skipped = s.buildImport(t, m, 'p', resolutions: {0: 'skip'});
      expect(skipped.people, isEmpty);
      expect(skipped.conflicts.length, 1, reason: 'کارت تصمیم می‌ماند تا «رد» برگشت‌پذیر باشد');
    });
  });
}
