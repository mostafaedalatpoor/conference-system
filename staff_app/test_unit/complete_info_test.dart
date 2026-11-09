// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter_test/flutter_test.dart';
import 'package:conference_staff/models.dart';
import 'package:conference_staff/screens/checkin.dart' show batchLetter;
import 'package:conference_staff/store.dart';

Map<String, dynamic> att(String id, String first, String last, {String email = '', String mobile = ''}) => {
      'id': id,
      'first_name': first,
      'last_name': last,
      'email': email,
      'mobile': mobile,
      'registration_type_id': 1,
    };

const a1 = '11111111-1111-4111-8111-111111111111';
const a2 = '22222222-2222-4222-8222-222222222222';
const a3 = '33333333-3333-4333-8333-333333333333';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('display name falls back for nameless people', () {
    final a = Attendee.fromJson(att(a1, '', '', email: 'x@y.ir'));
    expect(a.missingName, isTrue);
    expect(a.displayName, 'بی‌نام (x@y.ir)');
    expect(Attendee.fromJson(att(a1, 'مریم', 'رضایی')).missingName, isFalse);
  });

  test('completion fills blanks, warning clears, batch letter keeps printed name', () {
    final s = AppStore()
      ..loadForTest({
        'attendees': [
          att(a1, 'سارا', '', email: 'co@x.ir'),
          att(a2, 'علی', 'احمدی', email: 'co@x.ir'),
          att(a3, 'بی‌نام (ردیف ۹)', ''),
        ],
      });
    final a = s.attendees[a1]!;
    expect(a.missingName, isTrue);
    expect(batchLetter(a), 'س'); // بدون نام خانوادگی، با نام
    expect(s.sharingContact(a).map((o) => o.id), [a2]);

    s.completeInfo(a, lastName: 'کریمی', mobile: '۰۹۱۲ ۱۲۳ ۴۵۶۷', firstName: '');
    final b = s.attendees[a1]!;
    expect(b.lastName, 'کریمی');
    expect(b.firstName, 'سارا');
    expect(b.mobile, '09121234567');
    expect(b.missingName, isFalse);
    expect(batchLetter(b), 'س', reason: 'card was printed under س');
    expect(s.search('کریمی').map((x) => x.id), [a1]);
    expect(s.pending.single.kind, 'attendee_update');
    expect(s.pending.single.toPush()['payload']['fields'], {'last_name': 'کریمی', 'mobile': '09121234567'});

    // placeholder name: letter «؟», and completion replaces the placeholder
    final c = s.attendees[a3]!;
    expect(batchLetter(c), '؟');
    s.completeInfo(c, firstName: 'نرگس', lastName: 'نوری');
    expect(s.attendees[a3]!.displayName, 'نرگس نوری');
    expect(batchLetter(s.attendees[a3]!), '؟');
  });

  test('update from another device (server log) applies after snapshot', () {
    final s = AppStore()
      ..loadForTest({
        // snapshot already has the completed name; the log keeps the "before"
        'attendees': [att(a1, 'سارا', 'کریمی')],
        'log': [
          {
            'uuid': '44444444-4444-4444-8444-444444444444',
            'kind': 'attendee_update',
            'attendee_id': a1,
            'payload': {
              'fields': {'last_name': 'کریمی'},
              'before': {'first_name': 'سارا', 'last_name': ''},
            },
            'device_time': '2026-11-11T08:00:00Z',
            'seq': 5,
          },
        ],
      });
    final a = s.attendees[a1]!;
    expect(a.lastName, 'کریمی');
    expect(batchLetter(a), 'س');
  });
}
