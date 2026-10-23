class DeviceSnapshot {
  const DeviceSnapshot({
    required this.model,
    required this.platform,
    required this.batteryPercent,
    required this.connectionLabel,
    required this.storagePercent,
    required this.memoryPercent,
  });

  final String model;
  final String platform;
  final int batteryPercent;
  final String connectionLabel;
  final int? storagePercent;
  final int? memoryPercent;
}

class CleanupItem {
  const CleanupItem({
    required this.path,
    required this.label,
    required this.bytes,
    required this.safeToRemove,
    required this.modifiedAt,
  });

  final String path;
  final String label;
  final int bytes;
  final bool safeToRemove;
  final DateTime modifiedAt;
}

class CleanupReport {
  const CleanupReport({required this.items, required this.scannedPath});

  final List<CleanupItem> items;
  final String scannedPath;

  int get totalBytes => items.fold(0, (sum, item) => sum + item.bytes);
}

class CleanupResult {
  const CleanupResult({required this.deletedCount, required this.deletedBytes, this.errors = const []});

  final int deletedCount;
  final int deletedBytes;
  final List<String> errors;
}

class NetworkReport {
  const NetworkReport({
    required this.latencyMs,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.connectionLabel,
  });

  final int latencyMs;
  final double downloadMbps;
  final double? uploadMbps;
  final String connectionLabel;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
