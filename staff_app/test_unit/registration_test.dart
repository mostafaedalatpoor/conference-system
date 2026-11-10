// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter_test/flutter_test.dart';
import 'package:conference_staff/models.dart';
import 'package:conference_staff/store.dart';

const a1 = '11111111-1111-4111-8111-111111111111';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registration-page attendee: meal from add-on, on-site payment, search by code', () {
    final s = AppStore()
      ..loadForTest({
        'types': [
          {'id': 1, 'code': 'participant', 'name': 'شرکت‌کننده'},
        ],
        'meals': [
          {'id': 5, 'code': 'lunch1', 'name': 'ناهار', 'day': '2026-11-11', 'rules': {'registration_type_ids': [], 'role_ids': []}},
          {'id': 6, 'code': 'lunch2', 'name': 'ناهار دوم', 'day': '2026-11-12', 'rules': {'registration_type_ids': [], 'role_ids': []}},
        ],
        'attendees': [
          {'id': a1, 'first_name': 'مریم', 'last_name': 'رضایی', 'registration_type_id': 1, 'source': 'register',
            'extra_meals': ['lunch1'], 'onsite_due': 250000, 'onsite_note': 'ناهار روز اول', 'reg_code': 'RY-7K2M9P'},
        ],
      });
    final a = s.attendees[a1]!;
    expect(s.checkMeal(a, s.meals[0]).verdict, MealVerdict.ok);
    expect(s.checkMeal(a, s.meals[1]).verdict, MealVerdict.notEntitled);
    expect(s.search('ry-7k2m9p').map((x) => x.id), [a1]);
    expect(s.onsiteOwed(a), 250000);
    s.settleOnsite(a);
    expect(s.onsiteOwed(s.attendees[a1]!), 0);
    expect(s.pending.last.kind, 'onsite_settled');
    expect(s.pending.last.toPush()['payload'], {'amount': 250000, 'note': 'ناهار روز اول'});
    // completing info keeps the registration fields
    s.completeInfo(a, email: 'm@x.ir');
    expect(s.attendees[a1]!.extraMeals, ['lunch1']);
    expect(s.attendees[a1]!.regCode, 'RY-7K2M9P');
  });
}
