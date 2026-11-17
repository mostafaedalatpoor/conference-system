import 'package:conference_admin/card_logic.dart';
import 'package:flutter_test/flutter_test.dart';

CardTemplate _t(String id, {Set<String>? roles, Set<String>? types, bool isDefault = false}) =>
    CardTemplate(id: id, name: id, isDefault: isDefault, roles: roles, types: types);

void main() {
  group('اعتبارسنجی مشخصات (۳۰)', () {
    test('عدد با ارقام فارسی و عربی و ممیز فارسی', () {
      expect(parseDecimal('۸۵'), 85);
      expect(parseDecimal('٨٥'), 85);
      expect(parseDecimal('۸۵٫۵'), 85.5);
      expect(parseDecimal('85/5'), 85.5);
      expect(parseDecimal(' 90 '), 90);
      expect(parseDecimal('.5'), 0.5);
    });

    test('ورودی نامعتبر عدد نیست', () {
      for (final bad in ['', 'abc', '-5', '1e3', '8 5', '۸۵٫۵٫۱', 'NaN', 'Infinity']) {
        expect(parseDecimal(bad), isNull, reason: bad);
      }
    });

    test('عرض و ارتفاع بین ۳۰ تا ۳۰۰', () {
      expect(cardSizeError('۲۰', 'عرض'), 'عرض باید بین ۳۰ تا ۳۰۰ میلی‌متر باشد');
      expect(cardSizeError('۳۰۰٫۱', 'ارتفاع'), 'ارتفاع باید بین ۳۰ تا ۳۰۰ میلی‌متر باشد');
      expect(cardSizeError('۳۰', 'عرض'), isNull);
      expect(cardSizeError('300', 'عرض'), isNull);
      expect(cardSizeError('۸۵٫۵', 'عرض'), isNull);
      expect(cardSizeError('', 'عرض'), 'عرض را بنویسید');
      expect(cardSizeError('x', 'عرض'), 'عرض باید عدد باشد');
    });

    test('حاشیه‌ی برش ۰ تا ۱۰', () {
      expect(bleedError('0'), isNull);
      expect(bleedError('۳'), isNull);
      expect(bleedError('۱۰'), isNull);
      expect(bleedError('۱۱'), isNotNull);
      expect(bleedError('-1'), isNotNull);
      expect(bleedError(''), isNotNull);
    });

    test('رنگ hex شش‌رقمی', () {
      expect(normalizeHex('#10141a'), '10141A');
      expect(normalizeHex('۱۰۱۴۱a'), '10141A');
      expect(normalizeHex('12345'), isNull);
      expect(normalizeHex('GGGGGG'), isNull);
      expect(normalizeHex('#1234567'), isNull);
      expect(hexColorError('0B7A7B'), isNull);
      expect(hexColorError('0B7A7'), isNotNull);
      expect(hexColorError(''), isNotNull);
    });

    test('نمایش میلی‌متر', () {
      expect(fmtMm(85), '۸۵');
      expect(fmtMm(85.5), '۸۵٫۵');
      expect(fmtMm(85.04), '۸۵');
    });
  });

  group('تصمیم قالب هر فرد (۲۷)', () {
    CardTemplateSet set() => CardTemplateSet()
      ..separate = true
      ..templates = [
        _t('default', isDefault: true),
        _t('guest', types: {'guest'}),
        _t('speaker', roles: {'speaker', 'judge'}),
        _t('judge', roles: {'judge'}),
      ];

    test('قاعده‌ی نقش بر قاعده‌ی نوع اولویت دارد، حتی اگر قالب نوع زودتر بیاید', () {
      expect(templateFor(set(), typeCode: 'guest', roleCode: 'speaker').id, 'speaker');
    });

    test('بین چند قالب نقش، اولی در فهرست', () {
      expect(templateFor(set(), typeCode: 'x', roleCode: 'judge').id, 'speaker');
    });

    test('بدون نقش جور، قاعده‌ی نوع', () {
      expect(templateFor(set(), typeCode: 'guest', roleCode: 'volunteer').id, 'guest');
      expect(templateFor(set(), typeCode: 'guest').id, 'guest');
      expect(templateFor(set(), typeCode: 'guest', roleCode: '').id, 'guest');
    });

    test('هیچ قاعده‌ای نخورد: پیش‌فرض', () {
      expect(templateFor(set(), typeCode: 'student', roleCode: null).id, 'default');
    });

    test('قالب جدا خاموش: همه پیش‌فرض', () {
      final s = set()..separate = false;
      expect(templateFor(s, typeCode: 'guest', roleCode: 'speaker').id, 'default');
      expect(s.activeTemplates.map((t) => t.id), ['default']);
    });

    test('هر قالب یک فایل: گروه‌ها به ترتیب قالب‌ها و ترتیب افراد حفظ می‌شود', () {
      final people = [
        ('علی', 'guest', null),
        ('مریم', 'student', 'speaker'),
        ('رضا', 'student', null),
        ('سارا', 'guest', 'judge'),
      ];
      final g = groupByTemplate(set(), people, typeOf: (p) => p.$2, roleOf: (p) => p.$3);
      expect(g.map((e) => e.$1.id), ['default', 'guest', 'speaker']);
      expect(g[2].$2.map((p) => p.$1), ['مریم', 'سارا']);
      expect(g[0].$2.map((p) => p.$1), ['رضا']);
    });

    test('قالب رزرو حذف‌شده یا قالب‌های جدا خاموش: پیش‌فرض', () {
      final s = set()..reserveTemplateId = 'gone';
      expect(s.reserveTemplate.id, 'default');
      s.reserveTemplateId = 'guest';
      expect(s.reserveTemplate.id, 'guest');
      s.separate = false;
      expect(s.reserveTemplate.id, 'default');
    });
  });

  group('ذخیره‌ی قالب‌ها (نسخه‌ی ۲)', () {
    test('قالب تکی قدیمی یک قالب «پیش‌فرض» می‌شود', () {
      final s = CardTemplateSet()
        ..load({
          'width_mm': 90,
          'height_mm': 130,
          'name_x': 40,
          'name_color': '#112233',
          'show_role': false,
          'qr_size_mm': 25,
          'front_image': r'C:\a\front.png',
        });
      expect(s.templates, hasLength(1));
      final d = s.defaultTemplate;
      expect(d.id, defaultTemplateId);
      expect(d.name, 'پیش‌فرض');
      expect(d.isDefault, isTrue);
      expect(d.nameX, 40);
      expect(d.nameColor, '112233');
      expect(d.showRole, isFalse);
      expect(d.qrSizeMm, 25);
      expect(d.frontImage, r'C:\a\front.png');
      expect(s.widthMm, 90);
      expect(s.heightMm, 130);
      expect(s.bleedMm, defaultBleedMm);
      expect(s.separate, isFalse);
    });

    test('رفت و برگشت نسخه‌ی ۲ و کلیدهای قدیمی برای اپ قدیمی', () {
      final a = CardTemplateSet()
        ..widthMm = 90
        ..heightMm = 130
        ..bleedMm = 2
        ..cropMarks = true
        ..separate = true;
      a.defaultTemplate
        ..nameX = 33
        ..frontImage = 'f.png';
      final sp = a.duplicate(a.defaultTemplate)
        ..name = 'سخنران'
        ..roles = {'speaker'}
        ..nameSize = 20;
      a.reserveTemplateId = sp.id;

      final server = a.toJson();
      expect(server['version'], 2);
      expect(server['name_x'], 33, reason: 'اپ قدیمی قالب پیش‌فرض را از کلیدهای سطح بالا می‌خواند');
      expect(server.containsKey('front_image'), isFalse);
      expect((server['templates'] as List).first.containsKey('front_image'), isFalse);

      final b = CardTemplateSet()..load(server);
      expect(b.toJson(), server);
      expect(b.templates.map((t) => t.name), ['پیش‌فرض', 'سخنران']);
      expect(b.byId(sp.id)!.roles, {'speaker'});
      expect(b.byId(sp.id)!.nameSize, 20);
      expect(b.reserveTemplate.id, sp.id);
      expect(b.cropMarks, isTrue);
      expect(b.defaultTemplate.frontImage, isEmpty);

      // تصویرها فقط محلی‌اند و بعد از خواندن از سرور برمی‌گردند.
      b.restoreImages(a.images());
      expect(b.defaultTemplate.frontImage, 'f.png');
      expect(b.byId(sp.id)!.frontImage, 'f.png');

      final local = CardTemplateSet()..load(a.toJson(images: true));
      expect(local.defaultTemplate.frontImage, 'f.png');
    });

    test('بدون علامت پیش‌فرض اولی پیش‌فرض می‌شود؛ شناسه‌ی تکراری و رنگ نامعتبر دور ریخته می‌شود', () {
      final s = CardTemplateSet()
        ..load({
          'version': 2,
          'templates': [
            {'id': 'a', 'name': 'الف', 'name_color': 'zzz'},
            {'id': 'a', 'name': 'تکراری'},
            {'id': 'b', 'name': 'ب', 'is_default': false},
            {'name': 'بی‌شناسه'},
          ],
        });
      expect(s.templates.map((t) => t.id), ['a', 'b']);
      expect(s.defaultTemplate.id, 'a');
      expect(s.templates.where((t) => t.isDefault), hasLength(1));
      expect(s.defaultTemplate.nameColor, '10141A');
    });

    test('شناسه‌ی قالب تازه تکراری نیست', () {
      final s = CardTemplateSet();
      final a = s.duplicate(s.defaultTemplate);
      final b = s.duplicate(s.defaultTemplate);
      expect({s.defaultTemplate.id, a.id, b.id}, hasLength(3));
      expect(a.isDefault, isFalse);
      expect(a.roles, isEmpty);
    });
  });

  group('صفحه‌ی PDF و اندازه‌ی طرح (۳۱)', () {
    test('صفحه (عرض + ۲×برش) × (ارتفاع + ۲×برش)', () {
      const g = CardPageGeometry(trimW: 85, trimH: 55, bleed: 3);
      expect(g.pageW, 91);
      expect(g.pageH, 61);
      expect(g.trimLeft, 3);
      expect(g.bleedLeft, 0);
      expect(g.bleedW, 91);
      expect(g.markLines(), isEmpty);
    });

    test('بدون حاشیه‌ی برش همان اندازه‌ی کارت', () {
      const g = CardPageGeometry(trimW: 85, trimH: 55, bleed: 0);
      expect((g.pageW, g.pageH), (85, 55));
    });

    test('علامت برش بیرون از حاشیه‌ی برش و داخل کاغذ', () {
      const g = CardPageGeometry(trimW: 85, trimH: 55, bleed: 3, cropMarks: true);
      expect(g.slug, 7);
      expect(g.pageW, 85 + 6 + 14);
      expect(g.trimLeft, 10);
      final lines = g.markLines();
      expect(lines, hasLength(8));
      final bl = g.bleedLeft, bt = g.bleedTop, br = bl + g.bleedW, bb = bt + g.bleedH;
      for (final l in lines) {
        for (final (x, y) in [(l.x1, l.y1), (l.x2, l.y2)]) {
          expect(x >= 0 && x <= g.pageW && y >= 0 && y <= g.pageH, isTrue, reason: '$l داخل کاغذ');
          final inBleed = x > bl && x < br && y > bt && y < bb;
          expect(inBleed, isFalse, reason: '$l روی طرح نیفتد');
        }
        // هر علامت هم‌راستای یکی از لبه‌های برش است.
        final onTrim = l.y1 == l.y2
            ? (l.y1 == g.trimTop || l.y1 == g.trimTop + 55)
            : (l.x1 == g.trimLeft || l.x1 == g.trimLeft + 85);
        expect(onTrim, isTrue);
      }
    });

    test('طرح درست با حاشیه‌ی برش', () {
      // ۹۱×۶۱ میلی‌متر در ۳۰۰ dpi
      final f = artworkFit(pxW: 1075, pxH: 720, needW: 91, needH: 61);
      expect(f.ok, isTrue);
      expect(artworkMessage('روی', f), contains('جور است'));
    });

    test('طرح بدون حاشیه‌ی برش: بزرگ و بریده می‌شود', () {
      // ۸۵×۵۵ میلی‌متر در ۳۰۰ dpi روی ناحیه‌ی ۹۱×۶۱
      final f = artworkFit(pxW: 1004, pxH: 650, needW: 91, needH: 61);
      expect(f.ok, isFalse);
      expect(f.scale, greaterThan(1.1));
      expect(f.cropsWidth, isTrue);
      expect(f.cropPct, closeTo(3.4, 0.2));
      expect(artworkMessage('روی', f),
          'طرح روی ۸۵×۵۵ است؛ ۱۱٪ بزرگ می‌شود و ۳٪ از عرضش بریده می‌شود. (اندازه‌ی لازم با حاشیه‌ی اضافه: ۹۱×۶۱)');
    });

    test('طرح بزرگ‌تر با همان نسبت فقط کوچک می‌شود', () {
      final f = artworkFit(pxW: 2150, pxH: 1441, needW: 91, needH: 61);
      expect(f.cropPct, lessThan(1));
      expect(f.scale, lessThan(1));
      expect(artworkMessage('پشت', f), contains('کوچک می‌شود'));
    });
  });

  group('selectForPrint (16)', () {
    final people = [('a', true), ('b', false), ('c', false), ('d', true)];
    List<String> ids(PrintScope sc, [Set<String> picked = const {}]) => selectForPrint(people, sc,
            printed: (p) => p.$2, idOf: (p) => p.$1, picked: picked)
        .map((p) => p.$1)
        .toList();

    test('all keeps order', () => expect(ids(PrintScope.all), ['a', 'b', 'c', 'd']));
    test('unprinted', () => expect(ids(PrintScope.unprinted), ['b', 'c']));
    test('manual keeps list order, ignores unknown ids', () => expect(ids(PrintScope.manual, {'d', 'a', 'zz'}), ['a', 'd']));
    test('manual empty', () => expect(ids(PrintScope.manual), isEmpty));
    test('reserves only with all', () {
      expect(printIncludesReserves(PrintScope.all), isTrue);
      expect(printIncludesReserves(PrintScope.unprinted), isFalse);
      expect(printIncludesReserves(PrintScope.manual), isFalse);
    });
  });
}

