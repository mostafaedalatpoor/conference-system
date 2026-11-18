// آزمون‌های واحد منطق خالص. پوشه‌ی test/ در CI بعد از flutter create پاک می‌شود، پس این‌ها اینجاست:
// flutter test unit_test
import 'package:conference_staff/models.dart';
import 'package:conference_staff/store.dart';
import 'package:flutter_test/flutter_test.dart';

LogEvent ev(String kind, String aid, DateTime t, {String? day, int? meal, int seq = 0}) => LogEvent(
      uuid: 'u$seq-$kind',
      kind: kind,
      attendeeId: aid,
      mealId: meal,
      deviceTime: t,
      day: day,
      seq: seq,
    );

void main() {
  final d1 = DateTime(2026, 11, 20, 9);
  final d2 = DateTime(2026, 11, 21, 9);

  AppStore store({required bool daily, required DateTime today}) {
    final s = AppStore()
      ..dailyAttendance = daily
      ..eventStart = '2026-11-20'
      ..eventEnd = '2026-11-22';
    s.now = () => today;
    return s;
  }

  test('daily off: check-in from yesterday still counts (old behavior)', () {
    final s = store(daily: false, today: d2)..serverLog = [ev('checkin', 'a', d1, day: '2026-11-20', seq: 1)];
    s.recomputeForTest();
    expect(s.checkins.containsKey('a'), isTrue);
  });

  test('daily on: only today counts; other days listed', () {
    final s = store(daily: true, today: d2)..serverLog = [ev('checkin', 'a', d1, day: '2026-11-20', seq: 1)];
    s.recomputeForTest();
    expect(s.checkins.containsKey('a'), isFalse);
    expect(s.checkinDays['a'], {'2026-11-20'});
    expect(s.dayName('2026-11-20'), 'روز ۱');
  });

  test('daily on: event without day uses local date of device time', () {
    final s = store(daily: true, today: d1)..serverLog = [ev('checkin', 'a', d1, seq: 1)];
    s.recomputeForTest();
    expect(s.checkins.containsKey('a'), isTrue);
  });

  test('undo of another day does not cancel today', () {
    final s = store(daily: true, today: d2)
      ..serverLog = [
        ev('checkin', 'a', d1, day: '2026-11-20', seq: 1),
        ev('checkin', 'a', d2, day: '2026-11-21', seq: 2),
        ev('checkin_undo', 'a', d2, day: '2026-11-20', seq: 3),
      ];
    s.recomputeForTest();
    expect(s.checkins.containsKey('a'), isTrue);
    expect(s.checkinDays['a'], {'2026-11-21'});
  });

  test('meal_undo removes one delivery', () {
    final s = store(daily: false, today: d1)
      ..serverLog = [
        ev('meal_served', 'a', d1, meal: 5, seq: 1),
        ev('meal_served', 'a', d1, meal: 5, seq: 2),
        ev('meal_undo', 'a', d1, meal: 5, seq: 3),
      ];
    s.recomputeForTest();
    expect(s.mealsServed['a']![5]!.length, 1);
  });

  test('event day label', () {
    expect(store(daily: true, today: d2).eventDayOf, (2, 3));
    expect(store(daily: true, today: DateTime(2026, 12, 1)).eventDayOf, isNull);
    final one = store(daily: true, today: d1)..eventEnd = '2026-11-20';
    expect(one.eventDayOf, isNull);
  });

  test('LogEvent sends day and reads it back', () {
    final e = ev('checkin', 'a', d1, day: '2026-11-20');
    expect(e.toPush()['day'], '2026-11-20');
    expect(LogEvent.fromJson(e.toJson()).day, '2026-11-20');
    expect(ev('checkin', 'a', d1).toPush().containsKey('day'), isFalse);
  });

  test('unknown card message: revoked, unowned reserve, unknown', () {
    final s = AppStore()
      ..revokedCards = {'old'}
      ..cards = {'res': PassCard('res', null, 5001, true)};
    expect(s.unknownCardMessage('old'), contains('باطل'));
    expect(s.unknownCardMessage('res'), contains('رزرو'));
    expect(s.unknownCardMessage('zzz'), contains('در لیست نیست'));
  });

  test('addon meal entitles; onsite settled from log', () {
    final m = Meal(1, 'lunch', 'ناهار', '2026-11-20', {9}, {});
    final a = Attendee(id: 'a', firstName: 'x', lastName: 'y', registrationTypeId: 1, extraMeals: {'lunch'}, onsiteDue: 150000);
    expect(m.entitles(a), isTrue);
    expect(m.entitles(Attendee(id: 'b', firstName: 'x', lastName: 'y', registrationTypeId: 1)), isFalse);
    final s = store(daily: false, today: d1)..serverLog = [ev('onsite_settled', 'a', d1, seq: 1)];
    s.recomputeForTest();
    expect(s.onsiteSettled.containsKey('a'), isTrue);
    expect(s.onsiteOwed(a), 0);
    final s2 = store(daily: false, today: d1);
    s2.recomputeForTest();
    expect(s2.onsiteOwed(a), 150000);
  });
}
