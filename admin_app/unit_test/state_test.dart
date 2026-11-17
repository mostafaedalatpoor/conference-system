// آزمون‌های واحد منطق خالص. پوشه‌ی test/ در CI بعد از flutter create پاک می‌شود، پس این‌ها اینجاست:
// flutter test unit_test
import 'package:conference_admin/excel_import.dart';
import 'package:conference_admin/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isCheckedInFromTimeline', () {
    test('empty → not checked in', () => expect(isCheckedInFromTimeline([]), isFalse));
    test('checkin then undo → not checked in', () {
      expect(
          isCheckedInFromTimeline([
            {'seq': 1, 'kind': 'checkin'},
            {'seq': 2, 'kind': 'checkin_undo'},
          ]),
          isFalse);
    });
    test('order by seq, not list order', () {
      expect(
          isCheckedInFromTimeline([
            {'seq': 3, 'kind': 'checkin'},
            {'seq': 2, 'kind': 'checkin_undo'},
            {'seq': 1, 'kind': 'checkin'},
          ]),
          isTrue);
    });
    test('meals do not change check-in', () {
      expect(
          isCheckedInFromTimeline([
            {'seq': 1, 'kind': 'checkin'},
            {'seq': 2, 'kind': 'meal_served'},
          ]),
          isTrue);
    });
  });

  group('StaffDef', () {
    test('fromJson reads server fields; missing active means active (old plugin)', () {
      final s = StaffDef.fromJson({'id': 4, 'name': 'سینا', 'can_serve': false, 'has_pin': true});
      expect(s.id, 4);
      expect(s.active, isTrue);
      expect(s.canServe, isFalse);
      expect(s.hasPin, isTrue);
      expect(StaffDef.fromJson({'name': 'x', 'active': false}).active, isFalse);
    });
    test('toUpload sends id, updated_at and explicit active; pin only when new', () {
      final s = StaffDef('امید', id: 7, updatedAt: '2026-11-17T10:42:00+00:00', active: false);
      final u = s.toUpload();
      expect(u['id'], 7);
      expect(u['active'], isFalse);
      expect(u['updated_at'], '2026-11-17T10:42:00+00:00');
      expect(u.containsKey('pin'), isFalse);
      s.newPin = '۱۲۳۴';
      expect(s.toUpload()['pin'], '1234');
    });
    test('new staff has no id and no updated_at', () {
      final u = StaffDef('نگار').toUpload();
      expect(u.containsKey('id'), isFalse);
      expect(u.containsKey('updated_at'), isFalse);
      expect(u['active'], isTrue);
    });
  });

  test('EventInfo reads archived; old plugin without it → not archived', () {
    expect(EventInfo.fromJson({'code': 'a', 'archived': true}).archived, isTrue);
    expect(EventInfo.fromJson({'code': 'a'}).archived, isFalse);
  });

  test('MealDef sends active', () {
    final m = MealDef('l1', 'ناهار', '', {}, {}, active: false);
    expect(m.toJson()['active'], isFalse);
  });

  group('group 2', () {
    test('daily: check-in only for that day', () {
      final ev = [
        {'seq': 1, 'kind': 'checkin', 'day': '2026-11-20'},
        {'seq': 2, 'kind': 'checkin', 'day': '2026-11-21'},
        {'seq': 3, 'kind': 'checkin_undo', 'day': '2026-11-21'},
      ];
      expect(isCheckedInFromTimeline(ev, day: '2026-11-20'), isTrue);
      expect(isCheckedInFromTimeline(ev, day: '2026-11-21'), isFalse);
      expect(isCheckedInFromTimeline(ev), isFalse);
    });

    test('meal counts subtract undo', () {
      final c = mealCountsFromTimeline([
        {'kind': 'meal_served', 'meal_id': 5},
        {'kind': 'meal_served', 'meal_id': 5},
        {'kind': 'meal_undo', 'meal_id': 5},
        {'kind': 'meal_undo', 'meal_id': 6},
        {'kind': 'checkin'},
      ]);
      expect(c[5], 1);
      expect(c[6], 0);
    });

    test('possible duplicates: same mobile or email, active only, not self', () {
      final a = Person(id: '1', firstName: 'مریم', lastName: 'رضایی', typeCode: 't', mobile: '09121234567');
      final b = Person(id: '2', firstName: 'دکتر مریم', lastName: 'رضایی‌نژاد', typeCode: 't', mobile: '+98 912 123 4567');
      final c = Person(id: '3', firstName: 'x', lastName: 'y', typeCode: 't', email: 'M@x.ir');
      final d = Person(id: '4', firstName: 'z', lastName: 'w', typeCode: 't', email: 'm@x.ir', status: 'inactive');
      final e = Person(id: '5', firstName: 'q', lastName: 'r', typeCode: 't', email: 'm@x.ir');
      expect(findPossibleDuplicates(a, [a, b, c]).map((p) => p.id), ['2']);
      expect(findPossibleDuplicates(e, [c, d, e]).map((p) => p.id), ['3']);
    });

    test('excel import: shared contact with another name is kept, not dropped', () {
      final s = AdminState()..eventCode = 'ev';
      final t = SheetTable('s', ['first', 'last', 'mobile'], [
        ['علی', 'محمدی', '09120000000'],
        ['زهرا', 'احمدی', '09120000000'],
        ['علی', 'محمدی', '09120000000'],
      ]);
      final r = s.buildImport(t, {'first_name': 0, 'last_name': 1, 'mobile': 2}, 'p');
      expect(r.people.length, 2);
      expect(r.possibleDuplicates, 1);
      expect(r.people.map((p) => p.id).toSet().length, 2);
      // ورود دوباره همان شناسه‌ها را می‌دهد.
      final again = s.buildImport(t, {'first_name': 0, 'last_name': 1, 'mobile': 2}, 'p');
      expect(again.people.map((p) => p.id).toSet(), r.people.map((p) => p.id).toSet());
    });

    test('todayIso', () => expect(todayIso(DateTime(2026, 1, 5)), '2026-01-05'));
  });
}
