// نرمال‌سازی متن برای جستجو؛ باید با cd_normalize در افزونه‌ی وردپرس یکی باشد.

const Map<String, String> _digits = {
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
  '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
};

const Map<String, String> _letters = {
  'ي': 'ی', 'ى': 'ی', 'ئ': 'ی', 'ك': 'ک', 'ة': 'ه', 'ۀ': 'ه',
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ؤ': 'و', 'ـ': '',
  '‌': ' ', '‍': '', '‎': '', '‏': '',
};

final RegExp _harakat = RegExp('[ً-ْٰ]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _nonDigit = RegExp(r'\D+');

String latinDigits(String s) {
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    b.write(_digits[ch] ?? ch);
  }
  return b.toString();
}

String normalizeText(String s) {
  final b = StringBuffer();
  for (final rune in latinDigits(s).runes) {
    final ch = String.fromCharCode(rune);
    b.write(_letters[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(_harakat, '')
      .toLowerCase()
      .replaceAll(_spaces, ' ')
      .trim();
}

String normalizeMobile(String s) {
  var d = latinDigits(s).replaceAll(_nonDigit, '');
  if (d.isEmpty) return '';
  if (d.startsWith('0098')) {
    d = '0${d.substring(4)}';
  } else if (d.startsWith('98') && d.length == 12) {
    d = '0${d.substring(2)}';
  } else if (d.length == 10 && d.startsWith('9')) {
    d = '0$d';
  }
  return d;
}

const List<String> _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

String faDigits(Object s) {
  final b = StringBuffer();
  for (final rune in s.toString().runes) {
    final ch = String.fromCharCode(rune);
    final i = '0123456789'.indexOf(ch);
    b.write(i >= 0 ? _faDigits[i] : ch);
  }
  return b.toString();
}

/// ساعت محلی به شکل ۰۸:۳۰
String hm(DateTime t) {
  final l = t.toLocal();
  return faDigits('${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}');
}

final RegExp _tokenRe = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

/// توکن کارت از محتوای QR: لینک .../c/<token> یا ?c=<token> یا خود توکن.
String? tokenFromScan(String raw) {
  final s = raw.trim();
  if (_tokenRe.hasMatch(s)) return s;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  final q = uri.queryParameters['c'];
  if (q != null && _tokenRe.hasMatch(q)) return q;
  final segs = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  final i = segs.lastIndexOf('c');
  if (i >= 0 && i + 1 < segs.length && _tokenRe.hasMatch(segs[i + 1])) {
    return segs[i + 1];
  }
  return null;
}
