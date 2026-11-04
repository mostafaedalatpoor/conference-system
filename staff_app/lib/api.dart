import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String code;
  final String message;
  final int status;
  ApiException(this.code, this.message, this.status);

  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

/// کلاینت API افزونه‌ی Conference Day برای گوشی‌ها.
class Api {
  final String server;
  final String? token;
  Api(this.server, [this.token]);

  Uri _uri(String path) {
    final base = server.endsWith('/') ? server.substring(0, server.length - 1) : server;
    return Uri.parse('$base/wp-json/conf/v1$path');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (token != null) 'X-Conf-Device': token!,
      };

  Future<Map<String, dynamic>> get(String path, {Duration timeout = const Duration(seconds: 30)}) async {
    final r = await http.get(_uri(path), headers: _headers).timeout(timeout);
    return _decode(r);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final r = await http.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(timeout);
    return _decode(r);
  }

  Map<String, dynamic> _decode(http.Response r) {
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw ApiException('bad_response', 'پاسخ سرور قابل خواندن نیست (کد ${r.statusCode}).', r.statusCode);
    }
    if (r.statusCode >= 200 && r.statusCode < 300 && j is Map) {
      return j.cast<String, dynamic>();
    }
    if (j is Map && j['message'] != null) {
      throw ApiException(j['code']?.toString() ?? 'error', j['message'].toString(), r.statusCode);
    }
    throw ApiException('http_${r.statusCode}', 'خطای سرور (کد ${r.statusCode}).', r.statusCode);
  }
}
