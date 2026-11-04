import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;

import 'api.dart';

final _persian = RegExp(r'[؀-ۿ]');

/// خطا را به جمله‌ی فارسی با راه حل تبدیل می‌کند؛ متن خام Exception یا کد HTTP نمایش داده نمی‌شود.
String friendlyError(Object e, {bool login = false}) {
  if (e is ApiException) {
    // پیام‌های افزونه فارسی‌اند و همان را نشان می‌دهیم.
    final generic = e.code == 'bad_response' || e.code.startsWith('http_');
    if (!generic && _persian.hasMatch(e.message)) return e.message;
    if (e.status == 401 || e.status == 403) {
      return login ? 'کد رویداد یا PIN درست نیست.' : 'دسترسی این گوشی باطل شده. دوباره وارد شوید.';
    }
    if (e.status == 404) return 'کد رویداد پیدا نشد. آدرس سایت و کد رویداد را بررسی کنید.';
    return 'سرور فعلاً جواب درستی نمی‌دهد. چند لحظه بعد دوباره امتحان کنید.';
  }
  if (e is TimeoutException) return 'سرور جواب نداد. اینترنت را بررسی کنید و دوباره امتحان کنید.';
  if (e is SocketException || e is ClientException || e is HandshakeException) {
    return login
        ? 'اینترنت وصل نیست؛ برای ورود اول اینترنت لازم است.'
        : 'اینترنت وصل نیست؛ کارها روی گوشی امن است.';
  }
  if (e is FormatException || e is ArgumentError) return 'آدرس سایت درست نیست.';
  return login ? 'ورود ناموفق بود. دوباره امتحان کنید.' : 'کار ناموفق بود. دوباره امتحان کنید.';
}
