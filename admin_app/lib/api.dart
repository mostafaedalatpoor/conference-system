import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String code;
  final String message;
  final int status;
  final dynamic data;
  ApiException(this.code, this.message, this.status, [this.data]);

  @override
  String toString() => message;
}

/// کلاینت API مدیریت افزونه‌ی Conference Day (هدر X-Conf-Admin).
class AdminApi {
  final String server;
  final String key;
  AdminApi(this.server, this.key);

  Uri _uri(String path) {
    final base = server.endsWith('/') ? server.substring(0, server.length - 1) : server;
    return Uri.parse('$base/wp-json/conf/v1$path');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'X-Conf-Admin': key,
      };

  Future<dynamic> get(String path) async {
    final r = await http.get(_uri(path), headers: _headers).timeout(const Duration(seconds: 60));
    return _decode(r);
  }

  Future<dynamic> post(String path, Object body) async {
    final r = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    return _decode(r);
  }

  dynamic _decode(http.Response r) {
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw ApiException('bad_response', 'پاسخ سرور قابل خواندن نیست (کد ${r.statusCode}).', r.statusCode);
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return j;
    if (j is Map && j['message'] != null) {
      throw ApiException(j['code']?.toString() ?? 'error', j['message'].toString(), r.statusCode, j['data']);
    }
    throw ApiException('http_${r.statusCode}', 'خطای سرور (کد ${r.statusCode}).', r.statusCode);
  }
}
