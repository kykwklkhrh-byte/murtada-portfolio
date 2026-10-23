import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

/// اختبار تنزيل ورفع HTTP تقريبي، وليس Ping بنمط ICMP.
class NetworkService {
  final Connectivity _connectivity = Connectivity();

  Future<NetworkReport> measure() async {
    final connections = await _connectivity.checkConnectivity();
    if (connections.isEmpty || connections.every((e) => e == ConnectivityResult.none)) {
      throw const SocketException('لا يوجد اتصال بالشبكة');
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final pingTimer = Stopwatch()..start();
      final pingRequest = await client.getUrl(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace')).timeout(const Duration(seconds: 10));
      final pingResponse = await pingRequest.close().timeout(const Duration(seconds: 10));
      if (pingResponse.statusCode != HttpStatus.ok) throw const HttpException('خادم القياس غير متاح');
      await pingResponse.drain<void>().timeout(const Duration(seconds: 10));
      pingTimer.stop();

      const requestedBytes = 2000000;
      final downloadRequest = await client.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=$requestedBytes')).timeout(const Duration(seconds: 10));
      final downloadTimer = Stopwatch()..start();
      final downloadResponse = await downloadRequest.close().timeout(const Duration(seconds: 12));
      if (downloadResponse.statusCode != HttpStatus.ok) throw const HttpException('فشل اختبار التنزيل');
      var count = 0;
      await for (final block in downloadResponse.timeout(const Duration(seconds: 18))) {
        count += block.length;
      }
      downloadTimer.stop();
      if (count <= 0 || downloadTimer.elapsedMicroseconds <= 0) throw const HttpException('لم تصل بيانات التنزيل');
      final downloadMbps = count * 8 / downloadTimer.elapsedMicroseconds; // bytes * 8 / µs == Mbps

      double? uploadMbps;
      try {
        const uploadBytes = 1000000;
        final uploadRequest = await client.postUrl(Uri.parse('https://speed.cloudflare.com/__up')).timeout(const Duration(seconds: 10));
        uploadRequest.headers.contentType = ContentType.binary;
        uploadRequest.contentLength = uploadBytes;
        final payload = List<int>.filled(65536, 0);
        final timer = Stopwatch()..start();
        var remaining = uploadBytes;
        while (remaining > 0) {
          final take = remaining > payload.length ? payload.length : remaining;
          uploadRequest.add(take == payload.length ? payload : payload.sublist(0, take));
          remaining -= take;
        }
        final response = await uploadRequest.close().timeout(const Duration(seconds: 20));
        await response.drain<void>().timeout(const Duration(seconds: 8));
        timer.stop();
        if (response.statusCode >= 200 && response.statusCode < 300 && timer.elapsedMicroseconds > 0) {
          uploadMbps = uploadBytes * 8 / timer.elapsedMicroseconds;
        }
      } catch (_) {
        // فشل خادم الرفع لا يبطل نتيجة التنزيل. نعرض «غير متاح» للرفع.
      }

      final result = NetworkReport(
        latencyMs: pingTimer.elapsedMilliseconds,
        downloadMbps: downloadMbps,
        uploadMbps: uploadMbps,
        connectionLabel: connections.contains(ConnectivityResult.wifi) ? 'Wi-Fi' : 'بيانات/اتصال آخر',
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        final rows = prefs.getStringList('speed') ?? [];
        rows.insert(0, '${DateTime.now().toIso8601String()}|${downloadMbps.toStringAsFixed(1)}|${uploadMbps?.toStringAsFixed(1) ?? '—'}|${result.latencyMs}');
        await prefs.setStringList('speed', rows.take(30).toList());
      } catch (_) { /* The test result can still be shown if saving fails. */ }
      return result;
    } finally {
      client.close(force: true);
    }
  }
}
