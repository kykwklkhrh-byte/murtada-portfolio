import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_models.dart';

/// يمسح ملفات temp الخاصة بهذا التطبيق فقط. لا يتبع الروابط الرمزية.
class CleanupService {
  Future<CleanupReport> scanSafeCache() async {
    final root = await getTemporaryDirectory();
    final canonicalRoot = await root.resolveSymbolicLinks();
    final items = <CleanupItem>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final target = await entity.resolveSymbolicLinks();
        if (!_isInside(target, canonicalRoot)) continue;
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file || stat.size <= 0) continue;
        items.add(CleanupItem(
          path: entity.path,
          label: p.basename(entity.path),
          bytes: stat.size,
          safeToRemove: true,
          modifiedAt: stat.modified,
        ));
      } on FileSystemException { /* File changed or cannot be read. */ }
    }
    items.sort((a, b) => b.bytes.compareTo(a.bytes));
    return CleanupReport(items: items, scannedPath: canonicalRoot);
  }

  Future<CleanupResult> removeSelected(CleanupReport report, Set<String> selectedPaths) async {
    final root = await getTemporaryDirectory();
    final canonicalRoot = await root.resolveSymbolicLinks();
    var count = 0;
    var bytes = 0;
    final errors = <String>[];
    for (final item in report.items) {
      if (!selectedPaths.contains(item.path) || !item.safeToRemove || !_isInside(item.path, root.path)) continue;
      try {
        final file = File(item.path);
        final target = await file.resolveSymbolicLinks();
        if (!_isInside(target, canonicalRoot)) { errors.add('${item.label}: مسار غير آمن'); continue; }
        final current = await file.stat();
        if (current.type != FileSystemEntityType.file || current.size != item.bytes || current.modified != item.modifiedAt) {
          errors.add('${item.label}: تغيّر بعد الفحص');
          continue;
        }
        await file.delete();
        count++;
        bytes += current.size;
      } on FileSystemException {
        errors.add('${item.label}: تعذر الحذف');
      }
    }
    return CleanupResult(deletedCount: count, deletedBytes: bytes, errors: errors);
  }

  bool _isInside(String candidate, String root) {
    final rel = p.relative(p.normalize(candidate), from: p.normalize(root));
    return rel != '.' && rel != '..' && !rel.startsWith('..${p.separator}') && !p.isAbsolute(rel);
  }
}
