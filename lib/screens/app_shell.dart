import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_models.dart';
import '../services/cleanup_service.dart';
import '../services/device_service.dart';
import '../services/network_service.dart';
import '../advanced/main.dart' as advanced;
import '../advanced/extras.dart' as extras;

const midnight = Color(0xFF0C1726);
const panel = Color(0xFF13243A);
const muted = Color(0xFF9FB1C4);
const emerald = Color(0xFF22C987);
const gold = Color(0xFFF3C969);
const blue = Color(0xFF73B8FF);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: index, children: [
          HomeTab(onNavigate: (value) => setState(() => index = value)),
          const CleanTab(),
          const NetworkTab(),
          const ToolsTab(),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        backgroundColor: midnight,
        indicatorColor: emerald.withValues(alpha: .15),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.cleaning_services_outlined), selectedIcon: Icon(Icons.cleaning_services), label: 'تنظيف'),
          NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'الشبكة'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'الأدوات'),
        ],
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({required this.onNavigate, super.key});
  final ValueChanged<int> onNavigate;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  DeviceSnapshot? snapshot;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final current = await DeviceService().readSnapshot();
      if (mounted) setState(() { snapshot = current; error = null; });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذرت قراءة حالة الجهاز. حاول التحديث.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = snapshot;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('مرتضى ستار', style: TextStyle(color: emerald, fontWeight: FontWeight.w700, letterSpacing: .5)),
        const SizedBox(height: 9),
        const Text('العناية بجهازك،\nبكل وضوح.', style: TextStyle(fontSize: 29, height: 1.25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        _Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.phone_android, color: gold, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d?.model ?? 'جارٍ قراءة الجهاز...', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(d?.platform ?? 'بيانات من هاتفك', style: const TextStyle(color: muted)),
            ])),
            IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
          const Divider(height: 32, color: Color(0xFF29415C)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat(label: 'البطارية', value: d == null ? '—' : '${d.batteryPercent}%', icon: Icons.battery_full, color: gold),
            _Stat(label: 'التخزين', value: d?.storagePercent == null ? 'غير متاح' : '${d!.storagePercent}%', icon: Icons.storage, color: blue),
            _Stat(label: 'الاتصال', value: d?.connectionLabel ?? '—', icon: Icons.wifi, color: emerald),
            const _Stat(label: 'RAM', value: 'غير متاح', icon: Icons.memory, color: muted),
          ]),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.orangeAccent))),
        ])),
        const SizedBox(height: 25),
        const _Heading('الأدوات الرئيسية'),
        const SizedBox(height: 10),
        _ActionTile(icon: Icons.cleaning_services_outlined, title: 'تنظيف الملفات المؤقتة', subtitle: 'فحص ومعاينة ثم تأكيد منك', color: emerald, onTap: () => widget.onNavigate(1)),
        _ActionTile(icon: Icons.network_check, title: 'اختبار الإنترنت', subtitle: 'استجابة وتحميل ورفع بشكل تقريبي', color: gold, onTap: () => widget.onNavigate(2)),
        _ActionTile(icon: Icons.dashboard_customize_outlined, title: 'الأدوات الإضافية', subtitle: 'ملفات مكررة، بطارية، تخزين وتشخيص', color: blue, onTap: () => widget.onNavigate(3)),
        const SizedBox(height: 14),
        const _Disclaimer('التطبيق لا يحذف أي ملف من دون تأكيد، ولا يستطيع تنظيف بيانات التطبيقات الأخرى تلقائياً.'),
      ]),
    );
  }
}

class CleanTab extends StatefulWidget {
  const CleanTab({super.key});

  @override
  State<CleanTab> createState() => _CleanTabState();
}

class _CleanTabState extends State<CleanTab> {
  CleanupReport? report;
  final selected = <String>{};
  bool scanning = false;
  bool deleting = false;
  String? message;

  Future<void> scan() async {
    if (scanning || deleting) return;
    setState(() { scanning = true; message = null; });
    try {
      final value = await CleanupService().scanSafeCache();
      if (mounted) setState(() { report = value; selected.clear(); });
    } catch (_) {
      if (mounted) setState(() => message = 'تعذر فحص الملفات المؤقتة.');
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> confirmDelete() async {
    final r = report;
    if (r == null || selected.isEmpty || deleting) return;
    final bytes = r.items.where((e) => selected.contains(e.path)).fold<int>(0, (s, e) => s + e.bytes);
    final accepted = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text('سيتم حذف ${selected.length} ملف مؤقت (${formatBytes(bytes)}) نهائياً. هل توافق؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف المحدد')),
      ],
    ));
    if (accepted != true || !mounted) return;
    setState(() => deleting = true);
    try {
      final result = await CleanupService().removeSelected(r, selected);
      if (!mounted) return;
      setState(() => message = 'تم حذف ${result.deletedCount} ملف (${formatBytes(result.deletedBytes)}). ${result.errors.isEmpty ? '' : 'تعذر حذف ${result.errors.length} ملف.'}');
      await scanAfterDelete();
    } catch (_) {
      if (mounted) setState(() => message = 'حدث خطأ أثناء التنظيف.');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  Future<void> scanAfterDelete() async {
    try {
      final refreshed = await CleanupService().scanSafeCache();
      if (mounted) setState(() { report = refreshed; selected.clear(); });
    } catch (_) { /* Keep the last visible report if re-scan fails. */ }
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    return ListView(padding: const EdgeInsets.all(18), children: [
      const _Heading('تنظيف آمن'),
      const SizedBox(height: 8),
      const Text('نفحص الملفات المؤقتة الخاصة بهذا التطبيق فقط. لن تُحدد أي ملفات للحذف تلقائياً.', style: TextStyle(color: muted, height: 1.5)),
      const SizedBox(height: 15),
      _Surface(child: Column(children: [
        const Icon(Icons.cleaning_services_rounded, size: 44, color: emerald),
        const SizedBox(height: 10),
        Text(r == null ? 'لم يبدأ الفحص' : formatBytes(r.totalBytes), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        Text(r == null ? 'اختر فحص الملفات' : '${r.items.length} ملف في ذاكرة التطبيق المؤقتة', style: const TextStyle(color: muted)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: scanning || deleting ? null : scan,
          icon: scanning ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
          label: Text(scanning ? 'جاري الفحص...' : 'فحص الملفات المؤقتة'),
        )),
      ])),
      if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!)),
      if (r != null) ...[
        const SizedBox(height: 20),
        const _Heading('معاينة الملفات'),
        if (r.items.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد ملفات مؤقتة قابلة للتنظيف.', style: TextStyle(color: muted)))
        else ...[
          Text('المجلد: ${r.scannedPath}', style: const TextStyle(color: muted, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          CheckboxListTile(
            value: selected.length == r.items.length && selected.isNotEmpty,
            onChanged: deleting ? null : (v) => setState(() { selected.clear(); if (v == true) selected.addAll(r.items.where((e) => e.safeToRemove).map((e) => e.path)); }),
            title: const Text('تحديد الكل'),
          ),
          for (final item in r.items.take(200))
            CheckboxListTile(
              value: selected.contains(item.path),
              onChanged: deleting || !item.safeToRemove ? null : (value) => setState(() { if (value == true) { selected.add(item.path); } else { selected.remove(item.path); } }),
              title: Text(item.label, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatBytes(item.bytes), style: const TextStyle(color: muted)),
            ),
          if (r.items.length > 200) Text('المعروض أول 200 ملف من ${r.items.length}.', style: const TextStyle(color: muted)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: deleting || selected.isEmpty ? null : confirmDelete, icon: const Icon(Icons.delete_outline), label: Text('حذف المحدد (${selected.length})'))),
        ],
      ],
      const SizedBox(height: 15),
      const _Disclaimer('التنظيف لا يشمل صورك أو فيديوهاتك ولا ملفات التطبيقات الأخرى. يتم التحقق من مسار الملف مرة ثانية قبل الحذف.'),
    ]);
  }
}

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});
  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  NetworkReport? report;
  bool busy = false;
  String? error;

  Future<void> measure() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final value = await NetworkService().measure();
      if (mounted) setState(() => report = value);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر الاتصال بخادم القياس. افحص الإنترنت وحاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    return ListView(padding: const EdgeInsets.all(18), children: [
      const _Heading('اختبار الشبكة'),
      const SizedBox(height: 8),
      const Text('قياس تقريبي عبر Cloudflare. النتائج تختلف باختلاف الشبكة والخادم.', style: TextStyle(color: muted)),
      const SizedBox(height: 18),
      _Surface(child: Column(children: [
        const Icon(Icons.speed, color: gold, size: 60),
        const SizedBox(height: 12),
        Text(r == null ? '—' : r.downloadMbps.toStringAsFixed(1), style: const TextStyle(fontSize: 54, fontWeight: FontWeight.bold)),
        const Text('Mbps • سرعة التنزيل', style: TextStyle(color: muted)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _NetworkMetric('استجابة HTTP', r == null ? '—' : '${r.latencyMs} ms'),
          _NetworkMetric('الرفع', r?.uploadMbps == null ? '—' : '${r!.uploadMbps!.toStringAsFixed(1)} Mbps'),
        ]),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: busy ? null : measure,
          icon: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
          label: Text(busy ? 'جاري القياس...' : 'بدء اختبار السرعة'),
        )),
      ])),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.orangeAccent))),
      const SizedBox(height: 18),
      _ActionTile(icon: Icons.history, title: 'سجل اختبارات السرعة', subtitle: 'آخر القياسات المخزّنة على جهازك', color: blue, onTap: () => _open(context, const extras.HistoryPage())),
      _ActionTile(icon: Icons.network_check, title: 'فحص جودة الاتصال', subtitle: 'اختبار نجاح اتصال TCP بالخوادم', color: emerald, onTap: () => _open(context, const extras.NetToolsPage())),
      const SizedBox(height: 10),
      const _Disclaimer('الاستجابة ليست ICMP Ping، والاختبار لا يرفع سرعة الإنترنت. الاستهلاك الشبكي للاختبار يصل إلى عدة ميغابايت.'),
    ]);
  }
}

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const _Heading('أدوات الجهاز'),
    const SizedBox(height: 8),
    const Text('معلومات حقيقية من النظام وأدوات إضافية باختيارك.', style: TextStyle(color: muted)),
    const SizedBox(height: 12),
    _ActionTile(icon: Icons.phone_android, title: 'معلومات الهاتف', subtitle: 'الطراز والنظام والتخزين', color: blue, onTap: () => _open(context, const advanced.DevicePage())),
    _ActionTile(icon: Icons.battery_charging_full, title: 'البطارية', subtitle: 'نسبة الشحن وحالة الاتصال بالطاقة', color: gold, onTap: () => _open(context, const extras.BatteryPage())),
    _ActionTile(icon: Icons.wifi, title: 'معلومات الشبكة', subtitle: 'نوع الاتصال وعناوين الشبكة', color: emerald, onTap: () => _open(context, const advanced.NetworkPage())),
    const SizedBox(height: 20),
    const _Heading('إدارة متقدمة — اختيارية'),
    const SizedBox(height: 8),
    const Text('قد تحتاج بعض أدوات الملفات إلى إذن خاص للوصول إلى التخزين؛ لا تمنحه إلا إذا كنت تحتاجه.', style: TextStyle(color: muted)),
    const SizedBox(height: 9),
    _ActionTile(icon: Icons.pie_chart_outline, title: 'تحليل الملفات', subtitle: 'تصنيف الملفات حسب النوع والحجم', color: blue, onTap: () => _askStorage(context, const extras.StoragePage())),
    _ActionTile(icon: Icons.file_copy_outlined, title: 'الملفات المتكررة', subtitle: 'مقارنة SHA-256 ثم موافقة قبل الحذف', color: gold, onTap: () => _askStorage(context, const extras.DuplicatesPage())),
    _ActionTile(icon: Icons.folder_off_outlined, title: 'المجلدات الفارغة', subtitle: 'معاينة وحذف بموافقة المستخدم', color: emerald, onTap: () => _askStorage(context, const extras.EmptyFoldersPage())),
    const SizedBox(height: 16),
    _ActionTile(icon: Icons.settings_outlined, title: 'الإعدادات والحقوق', subtitle: 'الخصوصية وأذونات النظام', color: muted, onTap: () => _open(context, const extras.AboutPage())),
    _ActionTile(icon: Icons.open_in_new, title: 'إعدادات التطبيقات', subtitle: 'إدارة الأذونات من أندرويد', color: muted, onTap: () { openAppSettings(); }),
    const SizedBox(height: 10),
    const _Disclaimer('إذن الوصول الكامل إلى الملفات واسع وقد ترفضه سياسة Google Play. أدوات الملفات الإضافية ليست بديلاً عن مدير الملفات الخاص بالنظام.'),
  ]);
}

void _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

Future<void> _askStorage(BuildContext context, Widget page) async {
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: const Text('وصول اختياري إلى الملفات'),
    content: const Text('قد تطلب هذه الأداة إذن الوصول إلى الملفات المشتركة. تأكد من الملفات قبل أي حذف. هل تريد فتح الأداة؟'),
    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('متابعة'))],
  ));
  if (ok == true && context.mounted) _open(context, page);
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29415C))),
    child: child,
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800));
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 13),
    decoration: BoxDecoration(color: midnight, borderRadius: BorderRadius.circular(13)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: color), const SizedBox(width: 7), Text('$label: $value', style: const TextStyle(fontSize: 12))]),
  );
}

class _NetworkMetric extends StatelessWidget {
  const _NetworkMetric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(label, style: const TextStyle(color: muted, fontSize: 12))]);
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: panel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.all(13), child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_left, color: muted),
        ])),
      ),
    ),
  );
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, size: 18, color: muted),
      const SizedBox(width: 10),
      Expanded(child: Text(value, style: const TextStyle(color: muted, fontSize: 12, height: 1.6))),
    ]),
  );
}
