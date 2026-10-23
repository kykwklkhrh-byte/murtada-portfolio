import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'extras.dart';

const kBg = Color(0xFF0B1F2E);
const kCard = Color(0xFF123246);
const kGold = Color(0xFFF2B84B);
const kMint = Color(0xFF5EE0B0);
const kText = Color(0xFFEAF2F6);
const kMuted = Color(0xFF8FA9B8);

void main() => runApp(const MurtadaApp());

String fmt(num b) {
  if (b <= 0) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = (log(b) / log(1024)).floor().clamp(0, 4);
  return '${(b / pow(1024, i)).toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

class MurtadaApp extends StatelessWidget {
  const MurtadaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'مرتضى ستار',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kGold, secondary: kMint, surface: kCard),
          appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0, centerTitle: true),
          useMaterial3: true,
        ),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomePage(),
      );
}

// ---------- هوية التطبيق ----------
class StarLogo extends StatelessWidget {
  final double size;
  const StarLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(size * 0.23),
          border: Border.all(color: kGold, width: size > 60 ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text('MS', textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w900,
                color: kText, letterSpacing: -1.4)),
      );
}

// ---------- الحلقة ----------
class RingPainter extends CustomPainter {
  final double value;
  RingPainter(this.value);
  @override
  void paint(Canvas canvas, Size s) {
    final rect = Rect.fromLTWH(10, 10, s.width - 20, s.height - 20);
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 14..color = const Color(0xFF1B4F6B);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = value > 0.9 ? Colors.redAccent : kGold;
    canvas.drawArc(rect, 0, 2 * pi, false, base);
    canvas.drawArc(rect, -pi / 2, 2 * pi * value.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(covariant RingPainter old) => old.value != value;
}

// ---------- الرئيسية ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double total = 0, free = 0; // MB

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await DiskSpacePlus().getTotalDiskSpace;
      final f = await DiskSpacePlus().getFreeDiskSpace;
      if (!mounted) return;
      setState(() {
        total = t ?? 0;
        free = f ?? 0;
      });
    } catch (_) {}
  }

  void _go(Widget p) => Navigator.push(context, MaterialPageRoute(builder: (_) => p)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final used = total - free;
    final ratio = total > 0 ? used / total : 0.0;
    final tools = <(IconData, String, Widget)>[
      (Icons.cleaning_services_rounded, 'منظف الملفات', const CleanerPage()),
      (Icons.speed_rounded, 'سرعة الإنترنت', const SpeedPage()),
      (Icons.wifi_rounded, 'الشبكة', const NetworkPage()),
      (Icons.phone_android_rounded, 'معلومات الجهاز', const DevicePage()),
      (Icons.pie_chart_rounded, 'محلل التخزين', const StoragePage()),
      (Icons.file_copy_rounded, 'الملفات المكررة', const DuplicatesPage()),
      (Icons.folder_off_rounded, 'المجلدات الفارغة', const EmptyFoldersPage()),
      (Icons.network_ping_rounded, 'جودة الاتصال', const NetToolsPage()),
      (Icons.history_rounded, 'سجل السرعة', const HistoryPage()),
      (Icons.battery_charging_full_rounded, 'البطارية', const BatteryPage()),
      (Icons.settings_rounded, 'الإعدادات', const AboutPage()),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          StarLogo(size: 34),
          SizedBox(width: 10),
          Text('مرتضى ستار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24)),
          child: Column(children: [
            SizedBox(
              width: 190,
              height: 190,
              child: CustomPaint(
                painter: RingPainter(ratio),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${(ratio * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                    const Text('مساحة مستخدمة', style: TextStyle(color: kMuted)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('المتاح ${fmt(free * 1048576)} من ${fmt(total * 1048576)}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () => _go(const CleanerPage()),
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('افحص ونظّف الآن', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        const Text('تُعرض أدوات فحص محلية؛ لا يُحذف أي ملف دون تأكيدك. بعض أدوات التخزين تحتاج إذناً إضافياً.', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.25,
          children: [
            for (final t in tools)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _go(t.$3),
                child: Ink(
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(t.$1, size: 34, color: kGold),
                    const SizedBox(height: 10),
                    Text(t.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 26),
        const Center(child: Text('© مرتضى ستار — جميع الحقوق محفوظة', style: TextStyle(color: kMuted, fontSize: 12))),
      ]),
    );
  }
}

// ---------- منظف الملفات ----------
class Item {
  final File file;
  final int size;
  final String kind;
  bool selected;
  Item(this.file, this.size, this.kind, this.selected);
}

class CleanerPage extends StatefulWidget {
  const CleanerPage({super.key});
  @override
  State<CleanerPage> createState() => _CleanerPageState();
}

class _CleanerPageState extends State<CleanerPage> {
  List<Item> items = [];
  bool scanning = true, hasAll = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _askAll() async {
    await Permission.manageExternalStorage.request();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => scanning = true);
    final out = <Item>[];
    final roots = <Directory>[];
    try { roots.add(await getTemporaryDirectory()); } catch (_) {}
    try { roots.add(await getApplicationCacheDirectory()); } catch (_) {}
    try {
      final ex = await getExternalCacheDirectories();
      if (ex != null) roots.addAll(ex);
    } catch (_) {}
    for (final r in roots) {
      await _walk(r, out, 0, 'كاش التطبيق');
    }
    var all = false;
    if (Platform.isAndroid) {
      try { all = await Permission.manageExternalStorage.isGranted; } catch (_) {}
      if (all) await _walk(Directory('/storage/emulated/0'), out, 0, null);
    }
    out.sort((a, b) => b.size.compareTo(a.size));
    if (!mounted) return;
    setState(() {
      items = out;
      hasAll = all;
      scanning = false;
    });
  }

  Future<void> _walk(Directory d, List<Item> out, int depth, String? force) async {
    if (depth > 8) return;
    try {
      await for (final e in d.list(followLinks: false)) {
        final p = e.path.toLowerCase();
        if (e is Directory) {
          if (depth == 0 && p.endsWith('/android')) continue;
          await _walk(e, out, depth + 1, force);
        } else if (e is File) {
          try {
            final size = await e.length();
            final kind = force ?? _classify(p, size);
            if (kind == null) continue;
            final safe = force == 'كاش التطبيق' && kind == 'كاش التطبيق';
            out.add(Item(e, size, kind, safe));
          } catch (_) {
            // A locked/inaccessible file must not abort the entire directory scan.
          }
        }
      }
    } catch (_) {}
  }

  String? _classify(String p, int size) {
    for (final x in ['.tmp', '.temp', '.log', '.bak', '.old', '.chk', '.dmp']) {
      if (p.endsWith(x)) return 'ملفات مؤقتة';
    }
    if (p.contains('/.thumbnails/')) return 'صور مصغرة';
    if (p.endsWith('.apk')) return 'ملفات APK';
    if (size > 100 * 1048576) return 'ملفات كبيرة';
    return null;
  }

  int get selectedSize => items.where((i) => i.selected).fold(0, (s, i) => s + i.size);

  Future<void> _delete() async {
    final sel = items.where((i) => i.selected).toList();
    if (sel.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('سيتم حذف ${sel.length} ملف (${fmt(selectedSize)}) نهائياً ولا يمكن التراجع. راجع الملفات المحددة جيداً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    var freed = 0, failed = 0;
    for (final i in sel) {
      try {
        if (!await i.file.exists()) {
          failed++;
          continue;
        }
        await i.file.delete();
        freed += i.size;
        items.remove(i);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تحرير ${fmt(freed)}${failed > 0 ? ' — تعذر حذف $failed ملف' : ''}')));
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Item>>{};
    for (final i in items) {
      groups.putIfAbsent(i.kind, () => []).add(i);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('منظف الملفات'), actions: [IconButton(tooltip: 'إعادة الفحص', onPressed: scanning ? null : _scan, icon: const Icon(Icons.refresh_rounded))]),
      body: scanning
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: kGold), SizedBox(height: 14), Text('جاري الفحص...')]))
          : Column(children: [
              if (!hasAll && Platform.isAndroid)
                Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Expanded(child: Text('يمكن فحص الملفات المشتركة بإذن اختياري. لن يتم اختيار ملفاتك الشخصية للحذف تلقائياً.', style: TextStyle(color: kMuted))),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _askAll, child: const Text('امنح الإذن')),
                  ]),
                ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('لا توجد ملفات غير ضرورية. جهازك نظيف.'))
                    : ListView(children: [
                        for (final g in groups.entries)
                          ExpansionTile(
                            title: Text(g.key),
                            subtitle: Text('${g.value.length} ملف — ${fmt(g.value.fold<int>(0, (s, i) => s + i.size))}', style: const TextStyle(color: kMuted)),
                            children: [
                              for (final i in g.value.take(200))
                                CheckboxListTile(
                                  dense: true,
                                  activeColor: kGold,
                                  value: i.selected,
                                  onChanged: (v) => setState(() => i.selected = v ?? false),
                                  title: Text(i.file.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(fmt(i.size), style: const TextStyle(color: kMuted)),
                                ),
                            ],
                          ),
                      ]),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kBg),
                      onPressed: selectedSize > 0 ? _delete : null,
                      child: Text('تنظيف ${fmt(selectedSize)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }
}

// ---------- سرعة الإنترنت ----------
class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key});
  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  double down = 0, up = 0;
  int? ping;
  String stage = '';
  bool running = false;
  String? error;

  Future<void> _run() async {
    if (running) return;
    setState(() {
      running = true;
      error = null;
      stage = 'الاتصال بخادم الاختبار';
      down = 0;
      up = 0;
      ping = null;
    });
    final client = http.Client();
    try {
      final times = <int>[];
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        final response = await client.get(
          Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) throw const HttpException('استجابة فاشلة');
        times.add(watch.elapsedMilliseconds);
      }
      if (!mounted) return;
      setState(() {
        ping = times.reduce(min); // HTTP RTT، وليس ICMP ping
        stage = 'جاري قياس التحميل';
      });
      final response = await client.send(http.Request('GET',
        Uri.parse('https://speed.cloudflare.com/__down?bytes=10000000'),
      )).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw const HttpException('خادم التحميل غير متاح');
      var received = 0;
      var lastUiMs = 0;
      final sw = Stopwatch()..start();
      await for (final chunk in response.stream.timeout(const Duration(seconds: 12))) {
        received += chunk.length;
        final ms = sw.elapsedMilliseconds;
        if (ms > 12000) break;
        if (ms - lastUiMs >= 250 && mounted) {
          lastUiMs = ms;
          setState(() => down = received * 8000 / (ms * 1000000));
        }
      }
      if (received == 0 || sw.elapsedMilliseconds == 0) throw const HttpException('لم تصل بيانات التحميل');
      if (!mounted) return;
      setState(() {
        down = received * 8000 / (sw.elapsedMilliseconds * 1000000);
        stage = 'جاري قياس الرفع';
      });
      final upload = Uint8List(2000000);
      final upWatch = Stopwatch()..start();
      final uploaded = await client.post(
        Uri.parse('https://speed.cloudflare.com/__up'),
        body: upload,
      ).timeout(const Duration(seconds: 25));
      if (uploaded.statusCode < 200 || uploaded.statusCode >= 300) {
        throw const HttpException('خادم الرفع غير متاح');
      }
      if (!mounted) return;
      final seconds = upWatch.elapsedMilliseconds / 1000;
      setState(() {
        up = seconds > 0 ? upload.length * 8 / 1000000 / seconds : 0;
        stage = 'اكتمل الاختبار (نتيجة تقديرية)';
      });
      await saveSpeed(down, up, ping);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر إكمال الاختبار؛ تأكد من الإنترنت أو أعد المحاولة.');
    } finally {
      client.close();
      if (mounted) setState(() => running = false);
    }
  }

  Widget _box(String label, String value, String unit) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            Text(label, style: const TextStyle(color: kMuted)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kGold)),
            Text(unit, style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سرعة الإنترنت')),
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            const SizedBox(height: 20),
            Text(down.toStringAsFixed(1), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold)),
            const Text('ميجابت/ثانية — تقدير التحميل', style: TextStyle(color: kMuted)),
            const SizedBox(height: 24),
            Row(children: [
              _box('الرفع', up.toStringAsFixed(1), 'Mbps'),
              _box('الاستجابة', ping?.toString() ?? '—', 'ms'),
            ]),
            const SizedBox(height: 16),
            Text(error ?? stage, style: TextStyle(color: error != null ? Colors.redAccent : kMuted)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kBg),
                onPressed: running ? null : _run,
                child: Text(running ? 'جاري القياس...' : 'ابدأ القياس', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
}

// ---------- الشبكة ----------
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});
  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  String type = '...', publicIp = '...', country = '...';
  List<String> local = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Connectivity().checkConnectivity();
      final names = {
        ConnectivityResult.wifi: 'Wi-Fi',
        ConnectivityResult.mobile: 'بيانات الجوال',
        ConnectivityResult.ethernet: 'سلكي',
        ConnectivityResult.vpn: 'VPN',
        ConnectivityResult.bluetooth: 'بلوتوث',
        ConnectivityResult.none: 'غير متصل',
      };
      type = r.map((e) => names[e] ?? 'أخرى').join(' + ');
    } catch (_) {
      type = 'غير معروف';
    }
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      local = [for (final i in ifs) for (final a in i.addresses) '${i.name}: ${a.address}'];
    } catch (_) {}
    if (mounted) setState(() {});
    try {
      final r = await http.get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw const HttpException('فشل الاتصال');
      final m = <String, String>{};
      for (final line in r.body.split('\n')) {
        final pos = line.indexOf('=');
        if (pos > 0) m[line.substring(0, pos)] = line.substring(pos + 1).trim();
      }
      publicIp = m['ip'] ?? 'غير متاح';
      country = m['loc'] ?? 'غير متاح';
    } catch (_) {
      publicIp = 'غير متاح';
      country = 'غير متاح';
    }
    if (mounted) setState(() {});
  }

  Widget _row(String k, String v) => ListTile(title: Text(k, style: const TextStyle(color: kMuted)), trailing: Text(v, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الشبكة'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
        body: ListView(children: [
          _row('نوع الاتصال', type),
          _row('العنوان العام', publicIp),
          _row('الدولة', country),
          const Divider(),
          for (final l in local) _row('عنوان محلي', l),
        ]),
      );
}

// ---------- معلومات الجهاز ----------
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final data = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        data['الشركة'] = a.manufacturer;
        data['الطراز'] = a.model;
        data['أندرويد'] = '${a.version.release} (API ${a.version.sdkInt})';
        data['المعالج'] = a.hardware;
      } else if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        data['الطراز'] = i.utsname.machine;
        data['النظام'] = i.systemVersion;
      }
    } catch (_) {}
    try {
      final b = Battery();
      data['البطارية'] = '${await b.batteryLevel}%';
      final s = await b.batteryState;
      data['حالة الشحن'] = s == BatteryState.charging ? 'يشحن' : s == BatteryState.full ? 'ممتلئة' : 'لا يشحن';
    } catch (_) {}
    try {
      final t = await DiskSpacePlus().getTotalDiskSpace;
      final f = await DiskSpacePlus().getFreeDiskSpace;
      data['التخزين الكلي'] = fmt((t ?? 0) * 1048576);
      data['التخزين المتاح'] = fmt((f ?? 0) * 1048576);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('معلومات الجهاز')),
        body: ListView(children: [
          for (final e in data.entries) ListTile(title: Text(e.key, style: const TextStyle(color: kMuted)), trailing: Text(e.value, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
