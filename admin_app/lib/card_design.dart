// طراحی کارت: متن‌های دلخواه روی هر سمت (ثابت، فیلد سامانه، ستون اکسل شرکت‌کننده‌ها، یا ستون یک فایل اکسل جدا)
// و فونت‌ها (وزیرمتن داخلی، و فونت‌های TTF که روی سرور بارگذاری شده‌اند).

import 'normalize.dart';

/// منبع متن.
const textSources = <String, String>{
  'static': 'متن ثابت',
  'field': 'فیلد سامانه',
  'column': 'ستون اکسل شرکت‌کننده‌ها',
  'file': 'ستون فایل اکسل جدا',
};

/// فیلدهای سامانه که متن کارت می‌تواند از آن‌ها بیاید.
const systemFields = <String, String>{
  'display_name': 'نام کامل با عنوان',
  'full_name': 'نام و نام خانوادگی',
  'first_name': 'نام',
  'last_name': 'نام خانوادگی',
  'title': 'عنوان (دکتر، مهندس…)',
  'organization': 'سازمان',
  'role': 'نقش',
  'type': 'نوع ثبت‌نام',
  'serial': 'شماره‌ی کارت',
  'country': 'کشور',
  'email': 'ایمیل',
  'mobile': 'موبایل',
  'qr_hint': 'راهنمای QR («اسکن کنید: …»)',
};

/// فونت‌های داخلی (وزیرمتن، همراه اپ). شناسه → (نام، وزن، فایل).
const builtinFonts = <String, (String, int, String)>{
  'vazir-regular': ('وزیرمتن معمولی', 400, 'Regular'),
  'vazir-semibold': ('وزیرمتن نیم‌پررنگ', 600, 'SemiBold'),
  'vazir-bold': ('وزیرمتن پررنگ', 700, 'Bold'),
  'vazir-extrabold': ('وزیرمتن خیلی پررنگ', 800, 'ExtraBold'),
};

/// نام خانواده‌ی فونت بارگذاری‌شده در Flutter (برای پیش‌نمایش و اندازه‌گیری).
String customFontFamily(String id) => 'roydadyar_font_$id';

/// یک متن روی کارت.
class CardText {
  String id;

  /// 'front' یا 'back'.
  String side;

  /// static | field | column | file
  String source;

  /// متن ثابت، کلید فیلد سامانه، یا نام ستون.
  String value;
  String prefix;
  String suffix;

  /// مرکز کادر متن، درصد از عرض و ارتفاع کارت.
  double x;
  double y;

  /// عرض کادر متن (میلی‌متر).
  double widthMm;

  /// right | center | left
  String align;

  /// شناسه‌ی فونت: یکی از [builtinFonts] یا شناسه‌ی فونت سرور.
  String font;

  /// اندازه (pt) و کمینه‌ی کوچک‌شدن خودکار.
  double size;
  double minSize;
  String color;
  int maxLines;

  /// روی کارت‌های رزرو (که صاحب ندارند) هم چاپ شود؟
  bool onReserve;

  /// مبدأ جا در ویرایشگر گوشی: c (مرکز، درصد)، tr، tl، tc، br، bl، bc. جای واقعی همیشه x و y است.
  String anchor;

  CardText({
    required this.id,
    this.side = 'front',
    this.source = 'static',
    this.value = '',
    this.prefix = '',
    this.suffix = '',
    this.x = 50,
    this.y = 50,
    this.widthMm = 70,
    this.align = 'center',
    this.font = 'vazir-bold',
    this.size = 12,
    this.minSize = 8,
    this.color = '10141A',
    this.maxLines = 1,
    bool? onReserve,
    this.anchor = 'c',
  }) : onReserve = onReserve ?? source == 'static';

  CardText copy() => CardText.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'side': side,
        'source': source,
        'value': value,
        'prefix': prefix,
        'suffix': suffix,
        'x': x,
        'y': y,
        'width_mm': widthMm,
        'align': align,
        'font': font,
        'size': size,
        'min_size': minSize,
        'color': color,
        'max_lines': maxLines,
        'on_reserve': onReserve,
        'anchor': anchor,
      };

  factory CardText.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    String s(String k, String def) => (j[k] ?? def).toString();
    final source = textSources.containsKey(j['source']) ? j['source'] as String : 'static';
    return CardText(
      id: s('id', DateTime.now().microsecondsSinceEpoch.toString()),
      side: j['side'] == 'back' ? 'back' : 'front',
      source: source,
      value: s('value', ''),
      prefix: s('prefix', ''),
      suffix: s('suffix', ''),
      x: d('x', 50),
      y: d('y', 50),
      widthMm: d('width_mm', 70),
      align: const ['right', 'center', 'left'].contains(j['align']) ? j['align'] as String : 'center',
      font: s('font', 'vazir-bold'),
      size: d('size', 12),
      minSize: d('min_size', 8),
      color: s('color', '10141A').replaceAll('#', ''),
      maxLines: ((j['max_lines'] as num?)?.toInt() ?? 1).clamp(1, 5),
      onReserve: j['on_reserve'] is bool ? j['on_reserve'] as bool : null,
      anchor: cardAnchors.contains(j['anchor']) ? j['anchor'] as String : 'c',
    );
  }

  /// برچسب کوتاه برای فهرست متن‌ها: «نام کامل (فیلد)».
  String get label => switch (source) {
        'static' => value.isEmpty ? 'متن ثابت' : '«$value»',
        'field' => systemFields[value] ?? value,
        'column' => 'ستون «$value»',
        'file' => 'فایل جدا: «$value»',
        _ => value,
      };
}

/// داده‌ی یک نفر برای پرکردن متن‌ها. برای کارت رزرو [isReserve] درست است و بقیه خالی.
class CardSubject {
  final bool isReserve;
  final Map<String, String> fields;
  final Map<String, String> extra;
  final Map<String, String> fileRow;
  const CardSubject({required this.isReserve, this.fields = const {}, this.extra = const {}, this.fileRow = const {}});
}

/// مقدار نهایی یک متن برای یک کارت؛ null یعنی این متن روی این کارت چاپ نمی‌شود.
String? resolveCardText(CardText t, CardSubject sub) {
  if (sub.isReserve && !t.onReserve) return null;
  final String raw = switch (t.source) {
    'static' => t.value,
    'field' => sub.fields[t.value] ?? '',
    'column' => sub.extra[t.value] ?? '',
    'file' => sub.fileRow[t.value] ?? '',
    _ => '',
  };
  if (raw.trim().isEmpty) return null;
  return '${t.prefix}${raw.trim()}${t.suffix}';
}

/// فایل اکسل جدا را به افراد وصل می‌کند: با ایمیل، اگر نبود موبایل، اگر نبود نام کامل.
/// [personKeys] برای هر نفر (ایمیل، موبایل، نام کامل) است. خروجی: شناسه‌ی نفر → ردیف (ستون → مقدار).
Map<String, Map<String, String>> matchExtraFile({
  required List<String> headers,
  required List<List<String>> rows,
  required Map<String, int> mapping,
  required Map<String, (String, String, String)> personKeys,
}) {
  String cell(List<String> r, String k) {
    final i = mapping[k];
    return i == null || i < 0 || i >= r.length ? '' : r[i].trim();
  }

  final byEmail = <String, String>{}, byMobile = <String, String>{}, byName = <String, String>{};
  personKeys.forEach((id, k) {
    if (k.$1.isNotEmpty) byEmail[k.$1.toLowerCase()] = id;
    if (k.$2.isNotEmpty) byMobile[normalizeMobile(k.$2)] = id;
    if (k.$3.isNotEmpty) byName[normalizeText(k.$3)] = id;
  });
  final out = <String, Map<String, String>>{};
  for (final r in rows) {
    final email = cell(r, 'email').toLowerCase();
    final mobile = normalizeMobile(cell(r, 'mobile'));
    var name = cell(r, 'full_name');
    if (name.isEmpty) name = '${cell(r, 'first_name')} ${cell(r, 'last_name')}'.trim();
    final id = (email.isNotEmpty ? byEmail[email] : null) ??
        (mobile.isNotEmpty ? byMobile[mobile] : null) ??
        (name.isNotEmpty ? byName[normalizeText(name)] : null);
    if (id == null || out.containsKey(id)) continue;
    out[id] = {
      for (var i = 0; i < headers.length && i < r.length; i++)
        if (headers[i].trim().isNotEmpty) headers[i].trim(): r[i].trim(),
    };
  }
  return out;
}

/// مبدأهای جای عنصر در ویرایشگر: مرکز، و شش گوشه/لبه.
const cardAnchors = ['c', 'tr', 'tl', 'tc', 'br', 'bl', 'bc'];
const cardAnchorLabels = {
  'tr': 'بالا-راست',
  'tc': 'بالا-وسط',
  'tl': 'بالا-چپ',
  'c': 'وسط',
  'br': 'پایین-راست',
  'bc': 'پایین-وسط',
  'bl': 'پایین-چپ',
};

/// جای یک کادر (عرض w و ارتفاع h، میلی‌متر) به‌صورت فاصله‌ی گوشه‌ی هم‌نام کادر از گوشه‌ی هم‌نام کارت.
/// از مرکز درصدی (cx٪، cy٪) به (X، Y) میلی‌متری و برعکس. در «وسط» X و Y فاصله از مرکز کارت است.
(double, double) anchorFromCenter(String a, double cxPct, double cyPct, double w, double h, double cardW, double cardH) {
  final cx = cardW * cxPct / 100, cy = cardH * cyPct / 100;
  final double x = switch (a[a.length - 1]) {
    'r' => cardW - (cx + w / 2),
    'l' => cx - w / 2,
    _ => cx - cardW / 2,
  };
  final double y = switch (a[0]) {
    't' => cy - h / 2,
    'b' => cardH - (cy + h / 2),
    _ => cy - cardH / 2,
  };
  return (x, y);
}

(double, double) centerFromAnchor(String a, double x, double y, double w, double h, double cardW, double cardH) {
  final double cx = switch (a[a.length - 1]) {
    'r' => cardW - x - w / 2,
    'l' => x + w / 2,
    _ => cardW / 2 + x,
  };
  final double cy = switch (a[0]) {
    't' => y + h / 2,
    'b' => cardH - y - h / 2,
    _ => cardH / 2 + y,
  };
  return (cx / cardW * 100, cy / cardH * 100);
}

/// تصویر (مثلاً لوگو) روی کارت؛ فایل روی سرور است.
class CardImage {
  String id;
  String side;
  String url;
  double x, y, widthMm, heightMm;
  String anchor;
  bool onReserve;
  CardImage({required this.id, this.side = 'front', required this.url, this.x = 50, this.y = 20, this.widthMm = 20, this.heightMm = 20, this.anchor = 'tc', this.onReserve = true});

  Map<String, dynamic> toJson() =>
      {'id': id, 'side': side, 'url': url, 'x': x, 'y': y, 'width_mm': widthMm, 'height_mm': heightMm, 'anchor': anchor, 'on_reserve': onReserve};

  factory CardImage.fromJson(Map<String, dynamic> j) => CardImage(
        id: (j['id'] ?? '').toString(),
        side: j['side'] == 'back' ? 'back' : 'front',
        url: (j['url'] ?? '').toString(),
        x: (j['x'] as num?)?.toDouble() ?? 50,
        y: (j['y'] as num?)?.toDouble() ?? 20,
        widthMm: (j['width_mm'] as num?)?.toDouble() ?? 20,
        heightMm: (j['height_mm'] as num?)?.toDouble() ?? 20,
        anchor: cardAnchors.contains(j['anchor']) ? j['anchor'] as String : 'c',
        onReserve: j['on_reserve'] != false,
      );
}

/// مستطیل رنگی (نوار، کادر) روی کارت.
class CardShape {
  String id;
  String side;
  double x, y, widthMm, heightMm, radiusMm;
  String color;
  String anchor;
  bool onReserve;
  CardShape({required this.id, this.side = 'front', this.x = 50, this.y = 90, this.widthMm = 40, this.heightMm = 6, this.radiusMm = 0, this.color = '0B7A7B', this.anchor = 'bc', this.onReserve = true});

  Map<String, dynamic> toJson() => {
        'id': id,
        'side': side,
        'x': x,
        'y': y,
        'width_mm': widthMm,
        'height_mm': heightMm,
        'radius_mm': radiusMm,
        'color': color,
        'anchor': anchor,
        'on_reserve': onReserve,
      };

  factory CardShape.fromJson(Map<String, dynamic> j) => CardShape(
        id: (j['id'] ?? '').toString(),
        side: j['side'] == 'back' ? 'back' : 'front',
        x: (j['x'] as num?)?.toDouble() ?? 50,
        y: (j['y'] as num?)?.toDouble() ?? 90,
        widthMm: (j['width_mm'] as num?)?.toDouble() ?? 40,
        heightMm: (j['height_mm'] as num?)?.toDouble() ?? 6,
        radiusMm: (j['radius_mm'] as num?)?.toDouble() ?? 0,
        color: (j['color'] ?? '0B7A7B').toString().replaceAll('#', ''),
        anchor: cardAnchors.contains(j['anchor']) ? j['anchor'] as String : 'c',
        onReserve: j['on_reserve'] != false,
      );
}
