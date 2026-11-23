import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Thin wrapper over the shared Express REST API.
/// Every request sends `X-Client: mobile` so the web activity feed can show
/// that a change came from the phone.
class ApiClient {
  /// Base URL of the server, e.g. http://192.168.1.10:4000 (no trailing /api).
  String baseUrl;
  String? token;

  ApiClient({required this.baseUrl, this.token});

  /// Sensible default per platform; override at build time with
  /// --dart-define=API_URL=https://your-api.example.com
  static String get defaultBaseUrl {
    const fromEnv = String.fromEnvironment('API_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // The Android emulator reaches the host machine via 10.0.2.2.
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base/api$path').replace(queryParameters: query);
  }

  String endpointUrl(String path) => _uri(path).toString();

  /// Turns a relative upload path (/uploads/x.jpg) into a full URL.
  String fileUrl(String url) => url.startsWith('http') ? url : '${baseUrl.replaceAll(RegExp(r'/$'), '')}$url';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Client': 'mobile',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send(() => http.get(_uri(path, query), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) => _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> patch(String path, Object body) => _send(() => http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  Future<dynamic> uploadFile(String path, File file, {String field = 'file'}) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll({'X-Client': 'mobile', if (token != null) 'Authorization': 'Bearer $token'})
        ..files.add(await http.MultipartFile.fromPath(field, file.path, contentType: _mime(file.path)));
      return http.Response.fromStream(await req.send());
    });
  }

  static MediaType _mime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return MediaType('image', 'png');
    if (p.endsWith('.webp')) return MediaType('image', 'webp');
    if (p.endsWith('.heic')) return MediaType('image', 'heic');
    if (p.endsWith('.pdf')) return MediaType('application', 'pdf');
    return MediaType('image', 'jpeg');
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(Duration(seconds: 20));
    } on SocketException {
      throw ApiException(0, 'Cannot reach the server at $baseUrl. Check the server address in Settings.');
    } on http.ClientException {
      throw ApiException(0, 'Cannot reach the server at $baseUrl. Check the server address in Settings.');
    } on Exception {
      throw ApiException(0, 'The server took too long to respond.');
    }
    if (res.statusCode == 204) return null;
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 400) {
      final msg = body is Map && body['error'] != null ? body['error'].toString() : 'Request failed (${res.statusCode})';
      throw ApiException(res.statusCode, msg);
    }
    return body;
  }
}
