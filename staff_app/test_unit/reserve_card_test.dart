// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter_test/flutter_test.dart';
import 'package:conference_staff/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppStore store({required bool freeCard}) => AppStore()
    ..loadForTest({
      'types': [
        {'id': 1, 'code': 'participant', 'name': 'شرکت‌کننده'},
      ],
      'attendees': [],
      'cards': [
        {'token': 'usedreservecard0001', 'attendee_id': 'x', 'serial': 5001, 'is_reserve': true},
        if (freeCard) {'token': 'freereservecard0002', 'attendee_id': null, 'serial': 5002, 'is_reserve': true},
      ],
      'settings': {'identify_mode': 'scan'},
    });

  test('walk-in without a card when reserve cards ran out; link one later', () {
    final s = store(freeCard: false);
    expect(s.freeReserveCards, isEmpty);
    final a = s.walkin(firstName: 'نیما', lastName: 'تهرانی', mobile: '', email: '', registrationTypeId: 1, card: null);
    expect(s.checkins.containsKey(a.id), isTrue, reason: 'checked in without a card');
    expect(s.cardOf(a.id), isNull);
    expect(s.pending.map((e) => e.kind), ['walkin_register', 'checkin']);
    expect(s.pending.first.toPush().containsKey('card_token'), isFalse);

    // a new reserve card arrives later (fresh snapshot keeps the queue)
    final t = store(freeCard: true);
    final w = t.walkin(firstName: 'نیما', lastName: 'تهرانی', mobile: '', email: '', registrationTypeId: 1, card: null);
    final (card, err) = t.reserveCardFrom('R۵۰۰۲');
    expect(err, isNull);
    t.linkCard(w, card!);
    expect(t.cardOf(w.id)?.serial, 5002);
    expect(t.attendeeForToken('freereservecard0002')?.id, w.id);
    expect(t.freeReserveCards, isEmpty);
    expect(t.pending.last.toPush(), containsPair('card_token', 'freereservecard0002'));
  });

  test('reserve card lookup errors', () {
    final s = store(freeCard: true);
    expect(s.reserveCardFrom('5001').$2, contains('قبلاً'));
    expect(s.reserveCardFrom('9999').$2, contains('پیدا نشد'));
    expect(s.reserveCardFrom('abc').$2, contains('شماره'));
    expect(s.reserveCardFrom('ر5002').$1?.serial, 5002);
  });
}
