import 'package:flutter_test/flutter_test.dart';
import 'package:conference_admin/screens/registration.dart';
void main() {
  test('jalali', () {
    expect(gregorianToJalali(2026, 11, 11), (1405, 8, 20));
    expect(gregorianToJalali(2026, 3, 21), (1405, 1, 1));
    expect(gregorianToJalali(2025, 3, 20), (1403, 12, 30));
    expect(jalaliDeadline('2026-11-05 23:59'), '۱۴۰۵-۰۸-۱۴ ۲۳:۵۹');
  });
}
