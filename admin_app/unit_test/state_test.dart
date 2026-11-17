// آزمون‌های واحد منطق خالص. پوشه‌ی test/ در CI بعد از flutter create پاک می‌شود، پس این‌ها اینجاست:
// flutter test unit_test
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
}
