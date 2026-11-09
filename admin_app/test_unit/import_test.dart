import 'package:flutter_test/flutter_test.dart';
import 'package:conference_admin/cards_pdf.dart' show personFields;
import 'package:conference_admin/excel_import.dart';
import 'package:conference_admin/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final headers = ['نام', 'نام خانوادگی', 'ایمیل', 'موبایل', 'سازمان'];
  final mapping = {'first_name': 0, 'last_name': 1, 'email': 2, 'mobile': 3, 'organization': 4};
  AdminState state() => AdminState()..types = [CodeName('p', 'ارائه‌دهنده')];

  test('everyone in the sheet is imported; problems are warnings', () {
    final s = state();
    final r = s.buildImport(
      SheetTable('s', headers, [
        ['مریم', 'رضایی', 'm@x.ir', '', ''], // 2 ok
        ['سارا', '', '', '09120000001', ''], // 3 no last name
        ['', '', 'only@x.ir', '', ''], // 4 no name at all
        ['', '', '', '', 'فقط سازمان'], // 5 nothing to identify
        ['مریم', 'رضایی', 'm@x.ir', '', ''], // 6 identical to row 2
        ['علی', 'احمدی', 'co@x.ir', '', ''], // 7
        ['رضا', 'نوری', 'co@x.ir', '', ''], // 8 shared email, other name
      ]),
      mapping,
      'p',
    );
    expect(r.people.length, 6);
    expect(r.incomplete, 3);
    expect(r.problems.where((p) => p.contains('یک بار وارد شد')).length, 1);
    expect(r.problems.any((p) => p.contains('«علی احمدی»') && p.contains('جدا وارد شد')), isTrue);
    expect(r.problems.any((p) => p.contains('؛ رد شد')), isFalse);
    final ids = r.people.map((p) => p.id).toSet();
    expect(ids.length, 6, reason: 'shared email gets distinct ids');
    final nameless = r.people.firstWhere((p) => p.organization == 'فقط سازمان');
    expect(nameless.placeholderName, isTrue);
    expect(nameless.missingName, isTrue);
    expect(personFields(s, nameless)['display_name'], '', reason: 'placeholder never printed on the card');
    expect(r.people.firstWhere((p) => p.email == 'only@x.ir').listName, 'بی‌نام (only@x.ir)');
  });

  test('re-import keeps ids and never erases a completed name', () {
    final s = state();
    final rows = [
      ['سارا', '', '', '09120000001', ''],
      ['علی', 'احمدی', 'co@x.ir', '', ''],
      ['رضا', 'نوری', 'co@x.ir', '', ''],
    ];
    final first = s.buildImport(SheetTable('s', headers, rows), mapping, 'p');
    for (final p in first.people) {
      s.people[p.id] = p;
    }
    s.people.values.firstWhere((p) => p.firstName == 'سارا').lastName = 'کریمی'; // completed on the day
    final again = s.buildImport(SheetTable('s', headers, rows), mapping, 'p');
    expect(again.people.map((p) => p.id).toSet(), first.people.map((p) => p.id).toSet());
    expect(again.people.firstWhere((p) => p.firstName == 'سارا').lastName, 'کریمی');
    expect(again.incomplete, 0);
    expect(again.updated, 3);
  });

  test('card order: by last name, else first name; nameless last', () {
    final s = state();
    Person p(String id, String f, String l) => Person(id: id, firstName: f, lastName: l, typeCode: 'p', token: 't$id');
    for (final x in [p('1', 'زهرا', 'احمدی'), p('2', 'بهار', ''), p('3', '${namelessPrefix}۹)', ''), p('4', 'نیما', 'تهرانی')]) {
      s.people[x.id] = x;
    }
    expect(s.sortedPeople.map((x) => x.id), ['1', '2', '4', '3']);
  });
}
