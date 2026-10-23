import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

final Directory kRoot = Directory('/storage/emulated/0');

Future<bool> ensureAll(BuildContext c) async {
  if (!Platform.isAndroid) return false;
  var ok = await Permission.manageExternalStorage.isGranted;
  if (!ok) ok = (await Permission.manageExternalStorage.request()).isGranted;
  if (!ok && c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('هذه الأداة تحتاج إذن الوصول لكل الملفات')));
  }
  return ok;
}

Future<void> walkFiles(Directory d, Future<void> Function(File f) cb, [int depth = 0]) async {
  if (depth > 10) return;
  try {
    await for (final e in d.list(followLinks: false)) {
      if (e is Directory) {
        if (depth == 0 && e.path.toLowerCase().endsWith('/android')) continue;
        await walkFiles(e, cb, depth + 1);
      } else if (e is File) {
        try {
          await cb(e);
        } catch (_) {
          // Access to individual files can be denied on newer Android versions.
        }
      }
    }
  } catch (_) {}
}

Widget busyView(String t) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: kGold), const SizedBox(height: 14), Text(t)]));

Future<void> saveSpeed(double d, double u, int? p) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final l = List<String>.from(sp.getStringList('speed') ?? []);
    l.insert(0, '${DateTime.now().toIso8601String()}|${d.toStringAsFixed(1)}|${u.toStringAsFixed(1)}|${p ?? 0}');
    await sp.setStringList('speed', l.take(30).toList());
  } catch (_) {}
}

// ---------- محلل التخزين ----------
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});
  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  static const cats = {
    'الصور': ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'],
    'الفيديو': ['mp4', 'mkv', 'avi', 'mov', '3gp', 'webm'],
    'الصوت': ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac', 'opus'],
    'المستندات': ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'],
    'تطبيقات وأرشيف': ['apk', 'zip', 'rar', '7z'],
  };
  final sizes = <String, int>{};
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!await ensureAll(context)) {
      if (mounted) setState(() => busy = false);
      return;
    }
    await walkFiles(kRoot, (f) async {
      final ext = f.path.split('.').last.toLowerCase();
      var k = 'أخرى';
      for (final e in cats.entries) {
        if (e.value.contains(ext)) k = e.key;
      }
      sizes[k] = (sizes[k] ?? 0) + await f.length();
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = sizes.values.fold<int>(0, (a, b) => a + b);
    final rows = sizes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('محلل التخزين')),
      body: busy
          ? busyView('جاري تحليل التخزين...')
          : sizes.isEmpty
              ? const Center(child: Text('لا توجد بيانات. امنح إذن الوصول لكل الملفات.'))
              : ListView(padding: const EdgeInsets.all(18), children: [
                  Text('الإجمالي: ${fmt(total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(r.key), Text(fmt(r.value), style: const TextStyle(color: kMuted))]),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: total == 0 ? 0 : r.value / total, color: kGold, backgroundColor: kCard, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                      ]),
                    ),
                ]),
    );
  }
}

// ---------- الملفات المكررة ----------
class DupGroup {
  final int size;
  final List<File> files;
  DupGroup(this.size, this.files);
}

class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key});
  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  final groups = <DupGroup>[];
  final selected = <String>{};
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!await ensureAll(context)) {
      if (mounted) setState(() => busy = false);
      return;
    }
    groups.clear();
    selected.clear();
    final bySize = <int, List<File>>{};
    await walkFiles(kRoot, (f) async {
      final s = await f.length();
      if (s > 102400 && s < 300 * 1048576) bySize.putIfAbsent(s, () => []).add(f);
    });
    for (final en in bySize.entries.where((e) => e.value.length > 1)) {
      final byHash = <String, List<File>>{};
      for (final f in en.value) {
        try {
          final h = (await sha256.bind(f.openRead()).first).toString();
          byHash.putIfAbsent(h, () => []).add(f);
        } catch (_) {}
      }
      for (final g in byHash.values.where((x) => x.length > 1)) {
        groups.add(DupGroup(en.key, g));
        // Keep the first item as a protected original copy.
        // Never preselect duplicates for permanent deletion.
      }
    }
    groups.sort((a, b) => (b.size * b.files.length).compareTo(a.size * a.files.length));
    if (mounted) setState(() => busy = false);
  }

  int get waste => groups.fold(0, (s, g) => s + g.size * g.files.where((f) => selected.contains(f.path)).length);

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('سيتم حذف ${selected.length} نسخة مكررة (${fmt(waste)}) نهائياً.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('احذف'))],
      ),
    );
    if (ok != true) return;
    var freed = 0;
    var skipped = 0;
    for (final g in groups) {
      final original = g.files.first;
      try {
        if (!await original.exists() || await original.length() != g.size) {
          skipped++;
          continue;
        }
        final originalHash = await sha256.bind(original.openRead()).first;
        for (final f in List<File>.from(g.files.skip(1))) {
          if (!selected.contains(f.path)) continue;
          try {
            final canonical = await f.resolveSymbolicLinks();
            final root = await kRoot.resolveSymbolicLinks();
            if (canonical == root || !canonical.startsWith('$root/') ||
                !await f.exists() || await f.length() != g.size ||
                await sha256.bind(f.openRead()).first != originalHash) {
              skipped++;
              continue;
            }
            await f.delete();
            freed += g.size;
            g.files.remove(f);
            selected.remove(f.path);
          } catch (_) { skipped++; }
        }
      } catch (_) { skipped++; }
    }
    groups.removeWhere((g) => g.files.length < 2);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تحرير ${fmt(freed)}${skipped > 0 ? ' — تم تجاوز $skipped ملف متغيّر أو غير متاح' : ''}')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الملفات المكررة')),
        body: busy
            ? busyView('جاري البحث عن المكررات...')
            : groups.isEmpty
                ? const Center(child: Text('لا توجد ملفات مكررة.'))
                : Column(children: [
                    Expanded(
                      child: ListView(children: [
                        for (final g in groups)
                          ExpansionTile(
                            title: Text(g.files.first.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${g.files.length} نسخ — ${fmt(g.size)} للنسخة', style: const TextStyle(color: kMuted)),
                            children: [
                              for (final f in g.files)
                                CheckboxListTile(
                                  dense: true,
                                  activeColor: kGold,
                                  value: selected.contains(f.path),
                                  onChanged: f.path == g.files.first.path ? null : (v) => setState(() => v == true ? selected.add(f.path) : selected.remove(f.path)),
                                  title: Text('${f.path == g.files.first.path ? '🔒 نسخة محفوظة • ' : ''}${f.path.replaceFirst('/storage/emulated/0/', '')}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
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
                            onPressed: selected.isEmpty ? null : _delete,
                            child: Text('حذف المحدد ${fmt(waste)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  ]),
      );
}

// ---------- المجلدات الفارغة ----------
class EmptyFoldersPage extends StatefulWidget {
  const EmptyFoldersPage({super.key});
  @override
  State<EmptyFoldersPage> createState() => _EmptyFoldersPageState();
}

class _EmptyFoldersPageState extends State<EmptyFoldersPage> {
  final dirs = <Directory>[];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<bool> _scan(Directory d, int depth) async {
    var empty = true;
    try {
      await for (final e in d.list(followLinks: false)) {
        if (e is Directory) {
          if (depth == 0 && e.path.toLowerCase().endsWith('/android')) {
            empty = false;
            continue;
          }
          if (depth < 10 && await _scan(e, depth + 1)) {
            dirs.add(e);
          } else {
            empty = false;
          }
        } else {
          empty = false;
        }
      }
    } catch (_) {
      return false;
    }
    return empty;
  }

  Future<void> _run() async {
    if (!await ensureAll(context)) {
      if (mounted) setState(() => busy = false);
      return;
    }
    await _scan(kRoot, 0);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد حذف المجلدات'),
        content: Text('سيتم حذف ${dirs.length} مجلد فارغ فقط. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (ok != true) return;
    var n = 0;
    final list = [...dirs]..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final d in list) {
      try {
        await d.delete();
        dirs.remove(d);
        n++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف $n مجلد فارغ')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المجلدات الفارغة')),
        body: busy
            ? busyView('جاري الفحص...')
            : dirs.isEmpty
                ? const Center(child: Text('لا توجد مجلدات فارغة.'))
                : Column(children: [
                    Expanded(child: ListView(children: [for (final d in dirs) ListTile(dense: true, leading: const Icon(Icons.folder_open_rounded, color: kGold), title: Text(d.path.replaceFirst('/storage/emulated/0/', ''), textDirection: TextDirection.ltr))])),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(width: double.infinity, height: 52, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kBg), onPressed: _delete, child: Text('حذف ${dirs.length} مجلد', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
                      ),
                    ),
                  ]),
      );
}

// ---------- أدوات الشبكة ----------
class NetToolsPage extends StatefulWidget {
  const NetToolsPage({super.key});
  @override
  State<NetToolsPage> createState() => _NetToolsPageState();
}

class _NetToolsPageState extends State<NetToolsPage> {
  static const targets = [('Google DNS', '8.8.8.8', 53), ('Cloudflare DNS', '1.1.1.1', 53), ('Google HTTPS', 'google.com', 443)];
  final results = <String, String>{};
  bool running = false;

  Future<void> _run() async {
    setState(() {
      running = true;
      results.clear();
    });
    for (final t in targets) {
      final times = <int>[];
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        try {
          final s = await Socket.connect(t.$2, t.$3, timeout: const Duration(seconds: 3));
          s.destroy();
          times.add(sw.elapsedMilliseconds);
        } catch (_) {}
      }
      final failureRate = (5 - times.length) * 20;
      final avg = times.isEmpty ? '—' : '${(times.reduce((a, b) => a + b) / times.length).round()} ms';
      if (mounted) setState(() => results[t.$1] = '$avg  |  فشل اتصال $failureRate%');
    }
    if (mounted) setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('فحص جودة الاتصال')),
        body: Column(children: [
          Expanded(
            child: ListView(children: [
              for (final t in targets) ListTile(title: Text(t.$1), subtitle: Text(t.$2, style: const TextStyle(color: kMuted)), trailing: Text(results[t.$1] ?? '', textDirection: TextDirection.ltr, style: const TextStyle(color: kGold, fontWeight: FontWeight.w600))),
            ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(width: double.infinity, height: 52, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kBg), onPressed: running ? null : _run, child: Text(running ? 'جاري الفحص...' : 'ابدأ الفحص', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
            ),
          ),
        ]),
      );
}

// ---------- سجل السرعة ----------
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<List<String>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    rows = (sp.getStringList('speed') ?? []).map((e) => e.split('|')).where((e) => e.length == 4).toList();
    if (mounted) setState(() {});
  }

  Future<void> _clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('speed');
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سجل السرعة'), actions: [IconButton(onPressed: rows.isEmpty ? null : _clear, icon: const Icon(Icons.delete_outline_rounded))]),
        body: rows.isEmpty
            ? const Center(child: Text('لا توجد قياسات محفوظة بعد.'))
            : ListView(children: [
                for (final r in rows)
                  ListTile(
                    title: Text(r[0].substring(0, 16).replaceFirst('T', ' '), textDirection: TextDirection.ltr, style: const TextStyle(color: kMuted, fontSize: 13)),
                    subtitle: Text('↓ ${r[1]}   ↑ ${r[2]} Mbps   ${r[3]} ms', textDirection: TextDirection.ltr, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                  ),
              ]),
      );
}

// ---------- البطارية ----------
class BatteryPage extends StatefulWidget {
  const BatteryPage({super.key});
  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  final b = Battery();
  int level = 0;
  BatteryState st = BatteryState.unknown;
  Timer? t;
  StreamSubscription<BatteryState>? sub;

  @override
  void initState() {
    super.initState();
    _read();
    t = Timer.periodic(const Duration(seconds: 5), (_) => _read());
    sub = b.onBatteryStateChanged.listen((s) {
      if (mounted) setState(() => st = s);
    });
  }

  Future<void> _read() async {
    try {
      final l = await b.batteryLevel;
      final s = await b.batteryState;
      if (mounted) setState(() {
        level = l;
        st = s;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    t?.cancel();
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = st == BatteryState.charging ? 'يشحن' : st == BatteryState.full ? 'ممتلئة' : 'لا يشحن';
    return Scaffold(
      appBar: AppBar(title: const Text('البطارية')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 210, height: 210, child: CustomPaint(painter: RingPainter(level / 100), child: Center(child: Text('$level%', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold))))),
          const SizedBox(height: 18),
          Text(txt, style: const TextStyle(fontSize: 18, color: kGold)),
          const SizedBox(height: 10),
          Text(level <= 20 && st != BatteryState.charging ? 'المستوى منخفض، يُنصح بالشحن.' : 'الحالة جيدة.', style: const TextStyle(color: kMuted)),
        ]),
      ),
    );
  }
}

// ---------- حول التطبيق ----------
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات وحول التطبيق')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          const Center(child: StarLogo(size: 90)),
          const SizedBox(height: 14),
          const Center(child: Text('مرتضى ستار', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
          const Center(child: Text('الإصدار 4.0', style: TextStyle(color: kMuted))),
          const SizedBox(height: 24),
          ListTile(leading: const Icon(Icons.security_rounded, color: kGold), title: const Text('إدارة أذونات التطبيق'), subtitle: const Text('فتح إعدادات النظام', style: TextStyle(color: kMuted)), onTap: openAppSettings),
          const ListTile(leading: Icon(Icons.lock_outline_rounded, color: kGold), title: Text('الخصوصية'), subtitle: Text('لا توجد حسابات أو رفع لقوائم ملفاتك. اختبار الإنترنت يتصل بخوادم خارجية يمكنها رؤية عنوان IP العام.', style: TextStyle(color: kMuted))),
          const SizedBox(height: 30),
          const Center(child: Text('© مرتضى ستار — جميع الحقوق محفوظة', style: TextStyle(color: kMuted, fontSize: 12))),
        ]),
      );
}
