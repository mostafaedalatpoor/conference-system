// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conference_staff/main.dart';
import 'package:conference_staff/models.dart';
import 'package:conference_staff/store.dart';

const a1 = '11111111-1111-4111-8111-111111111111';
const a2 = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> meal(int id, String name, String day, [String time = '']) => {
      'id': id,
      'code': 'm$id',
      'name': name,
      'day': day,
      'time': time,
      'rules': {'registration_type_ids': [2], 'role_ids': []},
    };

Map<String, dynamic> base({bool loggedIn = true, bool canCheckin = true, bool canServe = true}) => {
      if (loggedIn) 'server': 'https://example.test',
      if (loggedIn) 'token': 't',
      'event_code': 'conf',
      'device_label': 'میز ۱',
      'staff_name': 'سارا',
      'can_checkin': canCheckin,
      'can_serve': canServe,
      'event_name': 'همایش آزمایشی',
      'types': [
        {'id': 1, 'code': 'g', 'name': 'عادی'},
        {'id': 2, 'code': 'v', 'name': 'ویژه'},
      ],
      'meals': [
        meal(5, 'صبحانه', '2026-11-11', '08:00'),
        meal(6, 'ناهار', '2026-11-11', '12:30'),
        meal(7, 'شام', '2026-11-11'),
        meal(8, 'ناهار دوم', '2026-11-12', '12:30'),
      ],
      'attendees': [
        {'id': a1, 'first_name': 'مریم', 'last_name': 'رضایی', 'registration_type_id': 2},
        {'id': a2, 'first_name': 'علی', 'last_name': 'احمدی', 'registration_type_id': 1},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('meal time round-trips and current meal follows the clock', () {
    final s = AppStore()..loadForTest(base());
    expect(s.meals.firstWhere((m) => m.id == 6).time, '12:30');
    expect(s.currentMealFor(DateTime(2026, 11, 11, 7, 0))?.id, 5, reason: 'nothing started yet → first of today');
    expect(s.currentMealFor(DateTime(2026, 11, 11, 9, 0))?.id, 5);
    expect(s.currentMealFor(DateTime(2026, 11, 11, 13, 0))?.id, 6);
    expect(s.currentMealFor(DateTime(2026, 11, 12, 13, 0))?.id, 8);
    expect(s.currentMealFor(DateTime(2026, 11, 13, 13, 0)), isNull);
  });

  test('verbal-approval meal records override_by and remembers approvers', () {
    final s = AppStore()..loadForTest(base());
    final lunch = s.meals.firstWhere((m) => m.id == 6);
    final ali = s.attendees[a2]!;
    expect(s.checkMeal(ali, lunch).verdict, MealVerdict.notEntitled);
    s.serveMeal(ali, lunch, overrideBy: ' آقای کریمی ');
    final e = s.pending.single.toPush();
    expect(e['kind'], 'meal_served');
    expect(e['payload'], {'override_by': 'آقای کریمی'});
    expect(s.approvers, ['آقای کریمی']);
    expect(s.servedCount(6), 1);

    // ordinary delivery has no payload
    s.serveMeal(s.attendees[a1]!, lunch);
    expect(s.pending.last.toPush()['payload'], anyOf(isNull, isEmpty));
    expect(s.pendingSummary(), '۲ تحویل ناهار');
  });

  test('report to admin queues staff_note and dismisses the rejected item', () {
    final s = AppStore()
      ..loadForTest({
        ...base(),
        'rejected': [
          {'uuid': 'u1', 'reason': 'قبلاً تحویل شده', 'attendee_id': a1},
        ],
      });
    s.reportToAdmin(s.rejected.first, 'دو بار اسکن شد');
    expect(s.rejected, isEmpty);
    final e = s.pending.single.toPush();
    expect(e['kind'], 'staff_note');
    expect(e['payload']['text'], 'دو بار اسکن شد');
    expect(e['payload']['uuid'], 'u1');
  });

  Future<AppStore> pump(WidgetTester t, Map<String, dynamic> data) async {
    await t.binding.setSurfaceSize(const Size(400, 860));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = AppStore()..loadForTest(data);
    await t.pumpWidget(StoreScope(store: s, child: const StaffApp(android: true)));
    await t.pump();
    return s;
  }

  testWidgets('android login screen', (t) async {
    await pump(t, base(loggedIn: false));
    expect(find.text('کد رویداد'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('android shell: tabs, search, sheet, status', (t) async {
    await pump(t, base());
    expect(find.text('پذیرش'), findsWidgets);
    expect(find.text('پذیرایی'), findsOneWidget);
    expect(find.text('وضعیت'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'مریم');
    await t.pump();
    expect(find.text('مریم رضایی'), findsWidgets);

    await t.tap(find.text('پذیرایی'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // امروز وعده‌ای نیست: انتخاب وعده خودکار باز می‌شود.
    expect(find.text('یک وعده انتخاب کنید'), findsOneWidget);
    await t.tapAt(const Offset(200, 20));
    await t.pumpAndSettle();

    await t.tap(find.text('وضعیت'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('خروج از رویداد'), 300, scrollable: find.byType(Scrollable).last);
    // تا ته فهرست تا دکمه زیر ناوبری شناور نماند.
    await t.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await t.pumpAndSettle();
    expect(find.text('خروج از رویداد'), findsOneWidget);
    await t.tap(find.text('خروج از رویداد'));
    await t.pumpAndSettle();
    expect(find.textContaining('همه‌ی کارها ارسال شده'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('android revoked screen keeps data', (t) async {
    final s = await pump(t, base());
    s.needsLogin = true;
    s.notifyListeners();
    await t.pump();
    expect(find.byType(TextField), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
