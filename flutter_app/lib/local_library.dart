import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefer app-private JSON persistence, with migration from legacy preferences.
class LocalLibrary {
  static final RegExp _safeKey = RegExp(r'^[a-z_]+$');

  static Future<File> _file(String name) async {
    if (!_safeKey.hasMatch(name)) throw ArgumentError('Unsafe storage key');
    final root = await getApplicationSupportDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return File(root.path + '/laqta_' + name + '.json');
  }

  static List<String> parseList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Expected list');
    return decoded.whereType<String>().where((s) => s.isNotEmpty).toList();
  }

  static Future<List<String>> readList(String name, {String? legacyKey}) async {
    try {
      final path = await _file(name);
      if (await path.exists()) return parseList(await path.readAsString());
    } catch (_) {}
    if (legacyKey != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final previous = prefs.getStringList(legacyKey) ?? <String>[];
        if (previous.isNotEmpty) {
          try { await writeList(name, previous, legacyKey: legacyKey); } catch (_) {}
        }
        return previous;
      } catch (_) {}
    }
    return [];
  }

  static Future<void> writeList(String name, List<String> values,
      {String? legacyKey}) async {
    final safe = values.where((s) => s.isNotEmpty).toSet().take(200).toList();
    Object? fileError;
    try {
      final file = await _file(name);
      final temp = File(file.path + '.tmp');
      await temp.writeAsString(jsonEncode(safe), flush: true);
      await temp.rename(file.path);
      return;
    } catch (e) { fileError = e; }
    if (legacyKey != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (await prefs.setStringList(legacyKey, safe)) return;
      } catch (_) {}
    }
    throw FileSystemException('Unable to save local data', name + ': ' + fileError.toString());
  }
}
