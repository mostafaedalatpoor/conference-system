// منطق خالص کارت، بدون Flutter تا با آزمون واحد سنجیده شود (test/card_logic_test.dart):
// اعتبارسنجی مشخصات، قالب‌های کارت (نسخه‌ی ۲)، تصمیم قالب هر فرد، هندسه‌ی صفحه‌ی PDF و اندازه‌ی طرح.
import 'dart:math' as math;

import 'normalize.dart';

// ---------------------------------------------------------------- اعتبارسنجی مشخصات (۳۰)

const double cardMinMm = 30;
const double cardMaxMm = 300;
const double bleedMaxMm = 10;
const double defaultBleedMm = 3;

final RegExp _decimal = RegExp(r'^(\d+(\.\d*)?|\.\d+)$');

/// عدد اعشاری از ورودی کاربر: ارقام فارسی و عربی، و «٫» یا «/» یا «,» به‌جای ممیز.
/// منفی، نماد علمی و متن نامعتبر null می‌دهد.
double? parseDecimal(String raw) {
  final s = latinDigits(raw).trim().replaceAll(RegExp('[٫/,،]'), '.');
  if (!_decimal.hasMatch(s)) return null;
  return double.tryParse(s);
}

/// خطای عرض یا ارتفاع کارت؛ null یعنی درست است.
String? cardSizeError(String raw, String label) {
  if (raw.trim().isEmpty) return '$label را بنویسید';
  final v = parseDecimal(raw);
  if (v == null) return '$label باید عدد باشد';
  if (v < cardMinMm || v > cardMaxMm) {
    return '$label باید بین ${faDigits(cardMinMm.toInt())} تا ${faDigits(cardMaxMm.toInt())} میلی‌متر باشد';
  }
  return null;
}

/// خطای حاشیه‌ی برش (bleed)؛ صفر مجاز است.
String? bleedError(String raw) {
  if (raw.trim().isEmpty) return 'حاشیه‌ی برش را بنویسید (بدون حاشیه: ۰)';
  final v = parseDecimal(raw);
  if (v == null) return 'حاشیه‌ی برش باید عدد باشد';
  if (v > bleedMaxMm) return 'حاشیه‌ی برش باید بین ۰ تا ${faDigits(bleedMaxMm.toInt())} میلی‌متر باشد';
  return null;
}

final RegExp _hex6 = RegExp(r'^[0-9a-fA-F]{6}$');

/// رنگ hex شش‌رقمی بدون #، با حروف بزرگ؛ ورودی نامعتبر null.
String? normalizeHex(String raw) {
  final s = latinDigits(raw).trim().replaceFirst('#', '');
  return _hex6.hasMatch(s) ? s.toUpperCase() : null;
}

String? hexColorError(String raw) {
  if (raw.trim().isEmpty) return 'رنگ را بنویسید';
  return normalizeHex(raw) == null ? 'رنگ باید کد hex شش‌رقمی باشد، مثل 10141A' : null;
}

/// میلی‌متر برای نمایش: ۸۵، ۸۵٫۵
String fmtMm(double v) {
  final r = (v * 10).round() / 10;
  final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  return faDigits(s).replaceAll('.', '٫');
}

// ---------------------------------------------------------------- قالب‌های کارت (۲۷)

const String defaultTemplateId = 'default';
const String defaultTemplateName = 'پیش‌فرض';

/// چیدمان یک قالب کارت. مختصات به درصد از عرض/ارتفاع کارت (لبه‌ی برش).
/// قاعده: نقش‌ها و نوع‌های ثبت‌نامی که این قالب را می‌گیرند. قالب پیش‌فرض بقیه را می‌گیرد.
class CardTemplate {
  String id;
  String name;
  bool isDefault;
  Set<String> roles;
  Set<String> types;

  /// مسیر تصویر طرح روی همین رایانه؛ به سرور فرستاده نمی‌شود.
  String frontImage = '';
  String backImage = '';

  double nameX = 50;
  double nameY = 70;
  double nameSize = 16;
  String nameColor = '10141A';
  bool showRole = true;
  double qrX = 50;
  double qrY = 45;
  double qrSizeMm = 30;
  bool showSerial = true;

  CardTemplate({
    this.id = defaultTemplateId,
    this.name = defaultTemplateName,
    this.isDefault = true,
    Set<String>? roles,
    Set<String>? types,
  })  : roles = roles ?? <String>{},
        types = types ?? <String>{};

  Map<String, dynamic> layoutJson() => {
        'name_x': nameX,
        'name_y': nameY,
        'name_size': nameSize,
        'name_color': nameColor,
        'show_role': showRole,
        'qr_x': qrX,
        'qr_y': qrY,
        'qr_size_mm': qrSizeMm,
        'show_serial': showSerial,
      };

  void loadLayout(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    nameX = d('name_x', nameX);
    nameY = d('name_y', nameY);
    nameSize = d('name_size', nameSize);
    nameColor = normalizeHex((j['name_color'] ?? '').toString()) ?? nameColor;
    if (j.containsKey('show_role')) showRole = j['show_role'] != false;
    qrX = d('qr_x', qrX);
    qrY = d('qr_y', qrY);
    qrSizeMm = d('qr_size_mm', qrSizeMm);
    if (j.containsKey('show_serial')) showSerial = j['show_serial'] != false;
  }

  Map<String, dynamic> toJson({bool images = false}) => {
        'id': id,
        'name': name,
        'is_default': isDefault,
        'roles': roles.toList(),
        'types': types.toList(),
        ...layoutJson(),
        if (images) 'front_image': frontImage,
        if (images) 'back_image': backImage,
      };

  factory CardTemplate.fromJson(Map<String, dynamic> j) {
    final t = CardTemplate(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      isDefault: j['is_default'] == true,
      roles: ((j['roles'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      types: ((j['types'] as List?) ?? const []).map((e) => e.toString()).toSet(),
    );
    t.loadLayout(j);
    t.frontImage = (j['front_image'] ?? '').toString();
    t.backImage = (j['back_image'] ?? '').toString();
    return t;
  }

  /// قالب تازه با همین چیدمان و تصویرها، بدون قاعده.
  CardTemplate duplicate(String newId, String newName) {
    final t = CardTemplate.fromJson({...toJson(images: true), 'id': newId, 'name': newName, 'is_default': false});
    t.roles = {};
    t.types = {};
    return t;
  }
}

/// همه‌ی قالب‌های کارت یک رویداد (`events.card_template` با `version: 2`).
/// اندازه، حاشیه‌ی برش و علامت برش برای همه‌ی قالب‌ها یکی است تا یک فایل چاپی بسازند.
class CardTemplateSet {
  static const int version = 2;

  double widthMm = 85;
  double heightMm = 55;
  double bleedMm = defaultBleedMm;
  bool cropMarks = false;

  /// «قالب جدا برای هر دسته». خاموش: همه با قالب پیش‌فرض.
  bool separate = false;
  String reserveTemplateId = defaultTemplateId;
  List<CardTemplate> templates = [CardTemplate()];

  CardTemplate get defaultTemplate => templates.firstWhere((t) => t.isDefault, orElse: () => templates.first);

  CardTemplate? byId(String id) {
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// قالب کارت‌های رزرو؛ اگر قالب انتخاب‌شده حذف شده یا قالب‌ها جدا نیستند، پیش‌فرض.
  CardTemplate get reserveTemplate => separate ? (byId(reserveTemplateId) ?? defaultTemplate) : defaultTemplate;

  /// قالب‌هایی که به کار می‌آیند؛ با قالب‌های جدا خاموش فقط پیش‌فرض.
  List<CardTemplate> get activeTemplates => separate ? templates : [defaultTemplate];

  /// JSON برای سرور (`images: false`) یا فایل محلی (`images: true`).
  /// کلیدهای قدیمی سطح بالا همان قالب پیش‌فرض‌اند تا اپ‌های قدیمی یک قالب درست ببینند.
  Map<String, dynamic> toJson({bool images = false}) {
    final d = defaultTemplate;
    return {
      'version': version,
      'width_mm': widthMm,
      'height_mm': heightMm,
      'bleed_mm': bleedMm,
      'crop_marks': cropMarks,
      'separate': separate,
      'reserve_template': reserveTemplateId,
      ...d.layoutJson(),
      if (images) 'front_image': d.frontImage,
      if (images) 'back_image': d.backImage,
      'templates': [for (final t in templates) t.toJson(images: images)],
    };
  }

  /// خواندن نسخه‌ی ۲، یا قالب تکی قدیمی که قالب «پیش‌فرض» می‌شود.
  void load(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    widthMm = d('width_mm', widthMm);
    heightMm = d('height_mm', heightMm);
    bleedMm = d('bleed_mm', bleedMm);
    if (j.containsKey('crop_marks')) cropMarks = j['crop_marks'] == true;
    if (j.containsKey('separate')) separate = j['separate'] == true;
    if (j['reserve_template'] != null) reserveTemplateId = j['reserve_template'].toString();

    final list = j['templates'];
    if (list is List && list.isNotEmpty) {
      final seen = <String>{};
      final parsed = <CardTemplate>[];
      for (final e in list) {
        if (e is! Map) continue;
        final t = CardTemplate.fromJson(e.cast<String, dynamic>());
        if (t.id.isEmpty || !seen.add(t.id)) continue;
        if (t.name.trim().isEmpty) t.name = t.isDefault ? defaultTemplateName : 'قالب';
        parsed.add(t);
      }
      if (parsed.isNotEmpty) {
        // درست یک قالب پیش‌فرض: اولی که علامت دارد، وگرنه اولین قالب.
        final def = parsed.firstWhere((t) => t.isDefault, orElse: () => parsed.first);
        for (final t in parsed) {
          t.isDefault = identical(t, def);
        }
        templates = parsed;
        return;
      }
    }
    // قالب تکی قدیمی (نسخه‌ی ۱): یک قالب «پیش‌فرض» با همان چیدمان.
    final t = templates.length == 1 && templates.first.isDefault ? templates.first : CardTemplate();
    t
      ..id = defaultTemplateId
      ..name = t.name.isEmpty ? defaultTemplateName : t.name
      ..isDefault = true
      ..loadLayout(j);
    if (j.containsKey('front_image')) t.frontImage = (j['front_image'] ?? '').toString();
    if (j.containsKey('back_image')) t.backImage = (j['back_image'] ?? '').toString();
    templates = [t];
    separate = false;
    reserveTemplateId = defaultTemplateId;
  }

  /// مسیر تصویرهای طرح هر قالب (فقط محلی)، برای نگه‌داشتنشان وقتی قالب‌ها از سرور می‌آیند.
  Map<String, (String, String)> images() => {for (final t in templates) t.id: (t.frontImage, t.backImage)};

  void restoreImages(Map<String, (String, String)> m) {
    for (final t in templates) {
      final i = m[t.id];
      if (i == null) continue;
      if (t.frontImage.isEmpty) t.frontImage = i.$1;
      if (t.backImage.isEmpty) t.backImage = i.$2;
    }
  }

  /// شناسه‌ی تازه که با قالب‌های موجود تکرار نشود.
  String newId() {
    var i = templates.length + 1;
    while (byId('t$i') != null) {
      i++;
    }
    return 't$i';
  }

  /// قالب تازه با چیدمان و تصویرهای `from`، بدون قاعده، در انتهای فهرست.
  CardTemplate duplicate(CardTemplate from) {
    final t = from.duplicate(newId(), 'قالب ${faDigits(templates.length + 1)}');
    templates.add(t);
    return t;
  }
}

/// قالب هر فرد: اول قاعده‌ی نقش (اولویت دارد)، بعد قاعده‌ی نوع ثبت‌نام، وگرنه قالب پیش‌فرض.
/// اگر چند قالب بخورند، اولی در ترتیب فهرست.
CardTemplate templateFor(CardTemplateSet set, {required String typeCode, String? roleCode}) {
  if (!set.separate) return set.defaultTemplate;
  if (roleCode != null && roleCode.isNotEmpty) {
    for (final t in set.templates) {
      if (t.roles.contains(roleCode)) return t;
    }
  }
  for (final t in set.templates) {
    if (t.types.contains(typeCode)) return t;
  }
  return set.defaultTemplate;
}

/// «هر قالب یک فایل»: افراد به تفکیک قالب، به ترتیب فهرست قالب‌ها و با حفظ ترتیب ورودی.
/// قالبی که کسی را ندارد نمی‌آید.
List<(CardTemplate, List<P>)> groupByTemplate<P>(
  CardTemplateSet set,
  List<P> people, {
  required String Function(P) typeOf,
  required String? Function(P) roleOf,
}) {
  final by = <String, List<P>>{};
  for (final p in people) {
    by.putIfAbsent(templateFor(set, typeCode: typeOf(p), roleCode: roleOf(p)).id, () => []).add(p);
  }
  return [
    for (final t in set.activeTemplates)
      if (by[t.id] != null) (t, by[t.id]!),
  ];
}

// ---------------------------------------------------------------- هندسه‌ی صفحه‌ی PDF (۳۱)

/// یک خط علامت برش، میلی‌متر از گوشه‌ی بالا-چپ صفحه.
typedef MarkLine = ({double x1, double y1, double x2, double y2});

/// صفحه‌ی هر کارت: (عرض + ۲×حاشیه‌ی برش) × (ارتفاع + ۲×حاشیه‌ی برش).
/// با علامت برش، دور آن یک نوار اضافه می‌آید تا علامت‌ها بیرون از حاشیه‌ی برش و روی کاغذ بمانند.
class CardPageGeometry {
  final double trimW;
  final double trimH;
  final double bleed;
  final bool cropMarks;

  /// فاصله‌ی علامت از لبه‌ی حاشیه‌ی برش، طول علامت و فاصله‌ی آن تا لبه‌ی کاغذ.
  static const double markGap = 1;
  static const double markLen = 5;
  static const double markPad = 1;

  const CardPageGeometry({required this.trimW, required this.trimH, required this.bleed, this.cropMarks = false});

  /// نوار بیرون از حاشیه‌ی برش، فقط وقتی علامت برش روشن است.
  double get slug => cropMarks ? markGap + markLen + markPad : 0;
  double get pageW => trimW + 2 * (bleed + slug);
  double get pageH => trimH + 2 * (bleed + slug);

  /// گوشه‌ی بالا-چپ ناحیه‌ی طرح (کارت + حاشیه‌ی برش).
  double get bleedLeft => slug;
  double get bleedTop => slug;
  double get bleedW => trimW + 2 * bleed;
  double get bleedH => trimH + 2 * bleed;

  /// گوشه‌ی بالا-چپ لبه‌ی برش (خود کارت).
  double get trimLeft => slug + bleed;
  double get trimTop => slug + bleed;

  /// هشت خط علامت برش در چهار گوشه، هم‌راستای لبه‌ی برش و بیرون از حاشیه‌ی برش.
  List<MarkLine> markLines() {
    if (!cropMarks) return const [];
    final l = trimLeft, r = trimLeft + trimW, t = trimTop, b = trimTop + trimH;
    final near = bleed + markGap, far = bleed + markGap + markLen;
    return [
      for (final y in [t, b]) ...[
        (x1: l - far, y1: y, x2: l - near, y2: y),
        (x1: r + near, y1: y, x2: r + far, y2: y),
      ],
      for (final x in [l, r]) ...[
        (x1: x, y1: t - far, x2: x, y2: t - near),
        (x1: x, y1: b + near, x2: x, y2: b + far),
      ],
    ];
  }
}

// ---------------------------------------------------------------- اندازه‌ی طرح (۳۱)

/// تصویر طرح با BoxFit.cover روی ناحیه‌ی کارت + حاشیه‌ی برش کشیده می‌شود.
/// اندازه‌ی میلی‌متری تصویر با فرض ۳۰۰ dpi (همان که راهنما خواسته) حساب می‌شود.
class ArtworkFit {
  final double artW;
  final double artH;
  final double needW;
  final double needH;

  /// ضریب بزرگ‌نمایی برای پوشاندن ناحیه؛ بیشتر از ۱ یعنی بزرگ می‌شود.
  final double scale;

  /// درصد تصویر که بعد از بزرگ/کوچک‌شدن بیرون می‌ماند و بریده می‌شود.
  final double cropPct;

  /// محوری که بریده می‌شود: true عرض، false ارتفاع.
  final bool cropsWidth;

  const ArtworkFit(this.artW, this.artH, this.needW, this.needH, this.scale, this.cropPct, this.cropsWidth);

  /// نسبت جور است و اندازه حداکثر ۲٪ فرق دارد.
  bool get ok => cropPct < 1 && (scale - 1).abs() < 0.02;
}

ArtworkFit artworkFit(
    {required int pxW, required int pxH, required double needW, required double needH, double dpi = 300}) {
  final artW = pxW / dpi * 25.4;
  final artH = pxH / dpi * 25.4;
  final scale = math.max(needW / artW, needH / artH);
  final overW = artW * scale - needW;
  final overH = artH * scale - needH;
  final cropsWidth = overW >= overH;
  final cropPct = cropsWidth ? overW / (artW * scale) * 100 : overH / (artH * scale) * 100;
  return ArtworkFit(artW, artH, needW, needH, scale, cropPct, cropsWidth);
}

/// ردیف «اندازه‌ی طرح» در بررسی پیش از چاپ.
String artworkMessage(String side, ArtworkFit f) {
  final art = '${fmtMm(f.artW)}×${fmtMm(f.artH)}';
  final need = '${fmtMm(f.needW)}×${fmtMm(f.needH)}';
  if (f.ok) return 'اندازه‌ی طرح $side: $art میلی‌متر؛ با کارت و حاشیه‌ی برش ($need) جور است.';
  final parts = <String>[];
  final pct = ((f.scale - 1).abs() * 100).round();
  if (pct >= 2) parts.add('${faDigits(pct)}٪ ${f.scale > 1 ? 'بزرگ' : 'کوچک'} می‌شود');
  final crop = f.cropPct.round();
  if (f.cropPct >= 1) parts.add('${faDigits(crop)}٪ از ${f.cropsWidth ? 'عرض' : 'ارتفاع'}ش بریده می‌شود');
  return 'طرح $side $art است؛ ${parts.join(' و ')}. (اندازه‌ی لازم با حاشیه‌ی اضافه: $need)';
}
