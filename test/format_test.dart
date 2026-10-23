import 'package:flutter_test/flutter_test.dart';
import 'package:murtada_star/models/app_models.dart';

void main() {
  test('تصنيف حجم الملفات يعرض القيم الصحيحة', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1024 * 1024), '1.00 MB');
    expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
  });

  test('مجموع حجم الملفات يتم حسابه حسابياً', () {
    final report = CleanupReport(scannedPath: '/cache', items: [
      CleanupItem(path: '/cache/a', label: 'a', bytes: 5, safeToRemove: true, modifiedAt: DateTime(2026)),
      CleanupItem(path: '/cache/b', label: 'b', bytes: 7, safeToRemove: true, modifiedAt: DateTime(2026)),
    ]);
    expect(report.totalBytes, 12);
  });
}
