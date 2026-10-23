import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

import '../models/app_models.dart';

class DeviceService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<DeviceSnapshot> readSnapshot() async {
    var battery = 0;
    try { battery = await _battery.batteryLevel; } catch (_) {}
    var connectionLabel = 'غير معروف';
    try {
      final connections = await _connectivity.checkConnectivity();
      connectionLabel = connections.contains(ConnectivityResult.wifi) ? 'Wi-Fi'
          : connections.contains(ConnectivityResult.mobile) ? 'بيانات الهاتف'
          : connections.contains(ConnectivityResult.ethernet) ? 'Ethernet' : 'غير متصل';
    } catch (_) {}

    String model = 'هاتفك الحالي';
    String platform = Platform.operatingSystem;
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        model = '${info.manufacturer} ${info.model}'.trim();
        platform = 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        model = info.utsname.machine;
        platform = 'iOS ${info.systemVersion}';
      }
    } catch (_) {}

    int? storagePercent;
    try {
      final service = DiskSpacePlus();
      final totalMb = await service.getTotalDiskSpace;
      final freeMb = await service.getFreeDiskSpace;
      if (totalMb != null && freeMb != null && totalMb > 0 && freeMb >= 0) {
        storagePercent = (((totalMb - freeMb) / totalMb) * 100).round().clamp(0, 100);
      }
    } catch (_) {}

    return DeviceSnapshot(
      model: model,
      platform: platform,
      batteryPercent: battery.clamp(0, 100),
      connectionLabel: connectionLabel,
      storagePercent: storagePercent,
      memoryPercent: null, // لا نعرض نسبة RAM غير مقاسة.
    );
  }
}
