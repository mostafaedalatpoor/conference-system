import 'package:flutter_test/flutter_test.dart';
import 'package:conference_admin/card_design.dart';
import 'package:conference_admin/state.dart';

void main() {
  group('resolveCardText', () {
    final person = CardSubject(
      isReserve: false,
      fields: {'display_name': 'دکتر مریم رضایی', 'role': ''},
      extra: {'دانشگاه': 'تهران'},
      fileRow: {'میز': '۱۲'},
    );
    const reserve = CardSubject(isReserve: true);

    test('field with prefix and suffix', () {
      final t = CardText(id: 'a', source: 'field', value: 'display_name', prefix: '« ', suffix: ' »');
      expect(resolveCardText(t, person), '« دکتر مریم رضایی »');
    });
    test('empty value is skipped', () {
      expect(resolveCardText(CardText(id: 'a', source: 'field', value: 'role'), person), isNull);
    });
    test('column and file sources', () {
      expect(resolveCardText(CardText(id: 'a', source: 'column', value: 'دانشگاه'), person), 'تهران');
      expect(resolveCardText(CardText(id: 'a', source: 'file', value: 'میز', prefix: 'میز '), person), 'میز ۱۲');
      expect(resolveCardText(CardText(id: 'a', source: 'file', value: 'نیست'), person), isNull);
    });
    test('reserve cards print only texts marked for them', () {
      expect(resolveCardText(CardText(id: 'a', value: 'همایش'), reserve), 'همایش'); // static → onReserve default true
      expect(resolveCardText(CardText(id: 'a', source: 'field', value: 'display_name'), reserve), isNull);
      expect(resolveCardText(CardText(id: 'a', value: 'همایش', onReserve: false), reserve), isNull);
    });
  });

  test('CardText json round trip and sanitizing', () {
    final t = CardText(id: 'x', side: 'back', source: 'column', value: 'میز', align: 'right', maxLines: 3, color: 'AA0000');
    final back = CardText.fromJson(t.toJson());
    expect(back.toJson(), t.toJson());
    final bad = CardText.fromJson({'source': 'evil', 'align': 'up', 'max_lines': 99, 'color': '#123456'});
    expect(bad.source, 'static');
    expect(bad.align, 'center');
    expect(bad.maxLines, 5);
    expect(bad.color, '123456');
  });

  test('matchExtraFile: email, then mobile, then name', () {
    final out = matchExtraFile(
      headers: ['ایمیل', 'موبایل', 'نام کامل', 'میز'],
      rows: [
        ['A@X.IR', '', '', '۱'],
        ['', '۰۹۱۲۰۰۰۰۰۰۲', '', '۲'],
        ['', '', 'علی  احمدی', '۳'],
        ['', '', 'ناشناس', '۴'],
      ],
      mapping: {'email': 0, 'mobile': 1, 'full_name': 2},
      personKeys: {
        'p1': ('a@x.ir', '', 'مریم'),
        'p2': ('', '09120000002', 'سارا'),
        'p3': ('', '', 'علی احمدی'),
      },
    );
    expect(out.keys.toSet(), {'p1', 'p2', 'p3'});
    expect(out['p2']!['میز'], '۲');
    expect(out['p3']!['میز'], '۳');
  });

  group('CardTemplate', () {
    test('old template migrates to editable texts', () {
      final t = CardTemplate()..load({'name_size': 18, 'show_role': false, 'show_serial': true, 'name_color': '223344'});
      final ids = t.texts.map((e) => e.value).toList();
      expect(ids, contains('display_name'));
      expect(ids, isNot(contains('role')));
      expect(ids, contains('serial'));
      final name = t.texts.firstWhere((e) => e.value == 'display_name');
      expect(name.size, 18);
      expect(name.color, '223344');
      expect(name.onReserve, isFalse);
      expect(t.setupDone, isFalse);
      expect(t.doubleSided, isTrue);
    });
    test('new template round trip; one-sided puts QR and texts on front', () {
      final t = CardTemplate()
        ..setupDone = true
        ..doubleSided = false
        ..qrSide = 'back'
        ..texts = [CardText(id: 'a', side: 'back', value: 'x'), CardText(id: 'b', value: 'y')];
      final u = CardTemplate()..load(t.toJson());
      expect(u.setupDone, isTrue);
      expect(u.effectiveQrSide, 'front');
      expect(u.textsFor('front').map((e) => e.id), ['b']);
      expect(u.textsFor('back'), isEmpty);
      expect(u.texts.length, 2);
    });
  });
}
