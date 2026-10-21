import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Api {
  static final Api instance = Api._();
  Api._();
  final store = const FlutterSecureStorage();
  String server = 'https://example.invalid';
  String key = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    server = prefs.getString('viral_server') ?? server;
    key = await store.read(key: 'viral_api_key') ?? '';
  }

  Future<void> save(String value, String token) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') {
      throw Exception('استخدم عنوان سيرفر HTTPS صحيح');
    }
    server = value.trim().replaceAll(RegExp(r'/+$'), '');
    key = token.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('viral_server', server);
    await store.write(key: 'viral_api_key', value: key);
  }

  Uri at(String path) => Uri.parse(server + path);
  Map<String, String> get headers => {'X-API-Key': key};

  Future<dynamic> call(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = at(path);
    final common = <String, String>{...headers, 'Content-Type': 'application/json'};
    http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: common).timeout(const Duration(seconds: 30));
      } else if (method == 'DELETE') {
        response = await http.delete(uri, headers: common).timeout(const Duration(seconds: 30));
      } else if (method == 'PATCH') {
        response = await http.patch(uri, headers: common, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 40));
      } else {
        response = await http.post(uri, headers: common, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 45));
      }
    } catch (e) {
      throw Exception('السيرفر غير متاح: ' + e.toString());
    }
    dynamic result;
    try { result = jsonDecode(response.body); } catch (_) { result = response.body; }
    if (response.statusCode >= 400) {
      throw Exception('HTTP ' + response.statusCode.toString() + ': ' +
          (result is Map ? (result['detail'] ?? result).toString() : result.toString()));
    }
    return result;
  }

  Future<dynamic> upload(PlatformFile file) async {
    if (file.path == null) throw Exception('الملف غير متاح للرفع');
    final req = http.MultipartRequest('POST', at('/assets/upload'));
    req.headers.addAll(headers);
    req.fields['rights_confirmed'] = 'true';
    req.files.add(await http.MultipartFile.fromPath('file', file.path!, filename: file.name));
    final stream = await req.send().timeout(const Duration(minutes: 15));
    final response = await http.Response.fromStream(stream);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) throw Exception(data.toString());
    return data;
  }
}
