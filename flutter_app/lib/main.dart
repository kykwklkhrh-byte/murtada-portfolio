import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';

const surface = Color(0xFF101827);
const bg = Color(0xFF080F1C);
const mint = Color(0xFF52E0CE);
const lilac = Color(0xFFAE9BFF);
const muted = Color(0xFF9BAAC5);
const kinds = ['بودكاست', 'قصص', 'لحظات', 'قرآن'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.load();
  runApp(const ViralApp());
}

class ViralApp extends StatelessWidget {
  const ViralApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Viral Clips AI',
    theme: ThemeData(
      brightness: Brightness.dark, useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: lilac, secondary: mint, surface: surface),
      cardTheme: CardThemeData(color: surface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF1E2A40),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none)),
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: Home()),
  );
}

void toast(BuildContext context, Object message) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));
  }
}

Widget heading(String text, [String? sub]) => Padding(
  padding: const EdgeInsets.only(bottom: 12, top: 16),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
    if (sub != null) Text(sub, style: const TextStyle(color: muted)),
  ]),
);

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  int index = 0;
  final labels = ['الرئيسية', 'المصادر', 'القص', 'المقاطع', 'حساباتي'];
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: bg,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('VIRAL CLIPS AI', style: TextStyle(
            letterSpacing: 2.7, color: mint, fontSize: 11, fontWeight: FontWeight.w900)),
        Text(labels[index], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    ),
    body: IndexedStack(index: index, children: [
      Landing(onSelect: (i) => setState(() => index = i)),
      const Channels(), const Studio(), const Library(), const Accounts(),
    ]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index, backgroundColor: surface,
      indicatorColor: const Color(0xFF38315B),
      onDestinationSelected: (i) => setState(() => index = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.subscriptions_outlined), label: 'المصادر'),
        NavigationDestination(icon: Icon(Icons.cut_outlined), label: 'القص'),
        NavigationDestination(icon: Icon(Icons.movie_filter_outlined), label: 'مقاطعي'),
        NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), label: 'الحسابات'),
      ],
    ),
  );
}

class Landing extends StatelessWidget {
  final ValueChanged<int> onSelect;
  const Landing({super.key, required this.onSelect});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18),
    children: [
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(colors: [
            Color(0xFF49378F), Color(0xFF264069), Color(0xFF0D5858)
          ])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.auto_awesome, size: 38, color: mint),
          const SizedBox(height: 20),
          const Text('خلي اللحظة تصير حكاية',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('استوديو عربي لقص الفيديوهات المرخصة، معاينتها، وجدولتها لحسابات تيك توك الرسمية.'),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => onSelect(2),
              icon: const Icon(Icons.edit), label: const Text('ابدأ بالمونتاج')),
        ])),
      heading('طريقة الاستخدام'),
      ...[
        ('01', 'أضف قنوات يوتيوب', 'لمتابعة معلومات المقاطع وروابطها', 1),
        ('02', 'ارفع فيديو مسموحاً باستخدامه', 'القص يتم على سيرفرك باستخدام FFmpeg', 2),
        ('03', 'راجع المقطع', 'معاينة عمودية قبل النشر', 3),
        ('04', 'اربط حسابك وجدول', 'إرسال بتصريح رسمي بعد موافقتك', 4)
      ].map((v) => Card(child: ListTile(
          onTap: () => onSelect(v.$4),
          leading: CircleAvatar(backgroundColor: const Color(0xFF36304F),
              child: Text(v.$1, style: const TextStyle(color: mint))),
          title: Text(v.$2, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(v.$3),
          trailing: const Icon(Icons.chevron_left)))),
      const Padding(padding: EdgeInsets.all(10), child: Text(
          'هذه نسخة تجريبية تحتاج سيرفراً منفصلاً وبيانات TikTok وYouTube الرسمية.',
          style: TextStyle(color: muted))),
    ]);
}

class Channels extends StatefulWidget {
  const Channels({super.key});
  @override State<Channels> createState() => _ChannelsState();
}
class _ChannelsState extends State<Channels> {
  final input = TextEditingController();
  String category = kinds.first;
  List<dynamic> data = [];
  bool busy = false;
  @override void initState() { super.initState(); refresh(); }
  @override void dispose() { input.dispose(); super.dispose(); }
  Future<void> refresh() async {
    try { final v = await Api.instance.call('GET', '/channels');
      if (mounted) setState(() => data = v as List<dynamic>);
    } catch (_) {}
  }
  Future<void> add() async {
    setState(() => busy = true);
    try {
      await Api.instance.call('POST', '/channels', {'url': input.text.trim(), 'category': category});
      input.clear(); await refresh();
      if (mounted) toast(context, 'تمت إضافة القناة');
    } catch (e) { if (mounted) toast(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18),
    children: [
      heading('قنوات يوتيوب', 'استخدم فقط المحتوى الذي تمتلك حقوق إعادة نشره.'),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Column(children: [
          TextField(controller: input, decoration: const InputDecoration(
              labelText: 'رابط قناة يوتيوب', prefixIcon: Icon(Icons.link))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: category,
            decoration: const InputDecoration(labelText: 'النوع'),
            items: kinds.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (v) => setState(() => category = v ?? category)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy ? null : add, child: const Text('إضافة قناة'))),
        ]))),
      heading('المصادر المحفوظة (' + data.length.toString() + ')'),
      OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh),
          label: const Text('تحديث القائمة')),
      ...data.map((c) => Card(child: ListTile(
        title: Text((c['title'] ?? '').toString()),
        subtitle: Text((c['category'] ?? '').toString()),
        leading: const Icon(Icons.smart_display_outlined, color: mint),
        trailing: IconButton(icon: const Icon(Icons.sync), onPressed: () async {
          try {
            await Api.instance.call('POST', '/channels/' + c['id'].toString() + '/sync');
            if (context.mounted) toast(context, 'تم تحديث فيديوهات القناة');
          } catch (e) { if (context.mounted) toast(context, e); }
        }),
      ))),
    ]);
}

class Studio extends StatefulWidget {
  const Studio({super.key});
  @override State<Studio> createState() => _StudioState();
}
class _StudioState extends State<Studio> {
  PlatformFile? file;
  bool rights = false, captions = false, busy = false;
  String category = kinds.first, asset = '';
  int seconds = 35, count = 3;
  List<dynamic> assets = [], jobs = [];
  @override void initState() {super.initState(); refresh();}
  Future<void> refresh() async {
    try {
      final a = await Api.instance.call('GET', '/assets');
      final b = await Api.instance.call('GET', '/jobs');
      if (mounted) setState(() { assets = a as List<dynamic>; jobs = b as List<dynamic>; });
    } catch (_) {}
  }
  Future<void> choose() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
        allowedExtensions: ['mp4','mov','webm','mkv']);
    if (picked != null && picked.files.isNotEmpty && mounted) {
      setState(() => file = picked.files.first);
    }
  }
  Future<void> upload() async {
    if (!rights || file == null) return toast(context, 'اختر ملفاً وأكد حقوق استخدامه');
    setState(() => busy = true);
    try {
      final r = await Api.instance.upload(file!);
      if (mounted) setState(() => asset = r['id'].toString());
      await refresh();
      if (mounted) toast(context, 'اكتمل رفع الفيديو');
    } catch (e) { if (mounted) toast(context, e); }
    finally {if (mounted) setState(() => busy = false);}
  }
  Future<void> create() async {
    if (asset.isEmpty) return toast(context, 'ارفع فيديو أولاً');
    setState(() => busy = true);
    try {
      await Api.instance.call('POST', '/jobs', {
        'asset_id': asset, 'category': category, 'seconds': seconds,
        'count': count, 'subtitles': captions
      });
      await refresh();
      if (mounted) toast(context, 'تم تسجيل مهمة القص');
    } catch (e) {if (mounted) toast(context, e);}
    finally {if (mounted) setState(() => busy = false);}
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18),
    children: [
      heading('استوديو المقاطع', 'مقاطع رأسية من 20 إلى 60 ثانية.'),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        ListTile(onTap: busy ? null : choose,
          leading: const Icon(Icons.video_file_outlined, size: 36, color: mint),
          title: Text(file?.name ?? 'اختر ملف فيديو'),
          subtitle: const Text('MP4 · MOV · MKV · WEBM')),
        CheckboxListTile(value: rights,
          title: const Text('أمتلك حقوق الفيديو أو عندي إذن باستخدامه'),
          onChanged: (v) => setState(() => rights = v ?? false)),
        FilledButton.icon(onPressed: busy ? null : upload,
            icon: const Icon(Icons.cloud_upload), label: const Text('رفع الفيديو')),
      ]))),
      heading('خيارات القص'),
      if (assets.isNotEmpty) DropdownButtonFormField<String>(
        value: assets.any((v) => v['id'].toString() == asset) ? asset : null,
        hint: const Text('اختر ملفاً مرفوعاً'),
        items: assets.map((v) => DropdownMenuItem<String>(
            value: v['id'].toString(), child: Text(v['filename'].toString()))).toList(),
        onChanged: (v) => setState(() => asset = v ?? '')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: category,
        items: kinds.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
        onChanged: (v) => setState(() => category = v ?? category)),
      Text('طول المقطع: ' + seconds.toString() + ' ثانية'),
      Slider(min: 20, max: 60, divisions: 8, value: seconds.toDouble(),
        onChanged: (v) => setState(() => seconds = v.round())),
      Text('العدد: ' + count.toString()),
      Slider(min: 1, max: 6, divisions: 5, value: count.toDouble(),
        onChanged: (v) => setState(() => count = v.round())),
      SwitchListTile(value: captions,
        title: const Text('إضافة ترجمة تلقائية'),
        subtitle: const Text('تحتاج تفعيل نموذج التفريغ في السيرفر، ويفضل مراجعة النص'),
        onChanged: (v) => setState(() => captions = v)),
      FilledButton.icon(onPressed: busy ? null : create,
          icon: const Icon(Icons.auto_awesome), label: const Text('إنشاء المقاطع')),
      heading('حالة المهام'),
      OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
      ...jobs.take(15).map((j) => Card(child: ListTile(
        leading: const Icon(Icons.movie_creation_outlined),
        title: Text(j['status'].toString()), subtitle: Text(j['message'].toString())))),
    ]);
}

class Library extends StatefulWidget {
  const Library({super.key});
  @override State<Library> createState() => _LibraryState();
}
class _LibraryState extends State<Library> {
  List<dynamic> clips = [], accounts = [];
  String? account;
  bool busy = false;
  int gap = 120;
  @override void initState() {super.initState(); refresh();}
  Future<void> refresh() async {
    try {
      final a = await Api.instance.call('GET', '/clips');
      final b = await Api.instance.call('GET', '/tiktok/accounts');
      if (mounted) setState(() {clips = a as List<dynamic>; accounts = b as List<dynamic>;});
    } catch (_) {}
  }
  Future<void> schedule(Map<dynamic,dynamic> clip) async {
    if (account == null) return toast(context, 'اختر حساب تيك توك أولاً');
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Directionality(textDirection: TextDirection.rtl,
        child: VideoPreview(clip: clip))));
    if (!mounted) return;
    final creator = await Api.instance.call('GET', '/tiktok/creator?account_id=' +
      Uri.encodeQueryComponent(account!));
    if (!mounted) return;
    final privacy = (creator['privacy_level_options'] as List<dynamic>? ?? []);
    if (privacy.isEmpty) return toast(context, 'لا توجد صلاحيات نشر متاحة');
    String selection = privacy.first.toString();
    final caption = TextEditingController(text: clip['title'].toString());
    bool approved = false;
    try {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('موافقة على جدولة فيديو'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            children: [
              Text('الحساب: ' + (creator['creator_nickname'] ?? '').toString()),
              TextField(controller: caption,
                  decoration: const InputDecoration(labelText: 'وصف الفيديو')),
              DropdownButtonFormField<String>(initialValue: selection,
                items: privacy.map((e) => DropdownMenuItem<String>(
                  value: e.toString(), child: Text(e.toString()))).toList(),
                onChanged: (v) => update(() => selection = v ?? selection)),
              CheckboxListTile(value: approved,
                title: const Text('عاينت هذا المقطع وأملك حقوقه وأوافق على جدولته لهذا الحساب'),
                onChanged: (v) => update(() => approved = v ?? false)),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(onPressed: approved ? () => Navigator.pop(ctx, true) : null,
              child: const Text('موافقة وجدولة')),
          ],
        )));
      if (ok != true) return;
      setState(() => busy = true);
      await Api.instance.call('POST', '/schedule/queue', {
        'account_id': account, 'clip_id': clip['id'], 'confirm': true, 'reviewed': true,
        'privacy': selection, 'caption': caption.text.trim(),
        'min_minutes': gap, 'max_minutes': gap + 60, 'max_daily': 4,
        'tz_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'quiet_start': 0, 'quiet_end': 7,
      });
      if (mounted) toast(context, 'تمت إضافة المقطع إلى جدول النشر');
    } catch (e) {if (mounted) toast(context, e);}
    finally {caption.dispose(); if (mounted) setState(() => busy = false);}
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18),
    children: [
      heading('مكتبتي', 'عاين كل مقطع قبل إرسال الموافقة.'),
      OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh),
          label: const Text('تحديث المقاطع')),
      if (accounts.isNotEmpty) DropdownButtonFormField<String>(
        hint: const Text('اختر حساب النشر'), value: account,
        items: accounts.map((a) => DropdownMenuItem<String>(
          value: a['id'].toString(), child: Text(a['nickname'].toString()))).toList(),
        onChanged: (v) => setState(() => account = v)),
      Text('الفاصل بين المقاطع: ' + gap.toString() + ' دقيقة'),
      Slider(min: 60, max: 300, divisions: 8, value: gap.toDouble(),
        onChanged: (v) => setState(() => gap = v.round())),
      if (clips.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(30),
          child: Text('ماكو مقاطع حالياً. اصنع أول مقطع من الاستوديو.'))),
      ...clips.map((c) => Card(child: Padding(padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['title'].toString(), style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold)),
          Text(c['duration'].toString() + ' ثانية · ' +
              c['category'].toString(), style: const TextStyle(color: muted)),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Directionality(textDirection: TextDirection.rtl,
                  child: VideoPreview(clip: c)))),
              icon: const Icon(Icons.play_arrow), label: const Text('معاينة')),
            FilledButton.icon(onPressed: busy ? null : () => schedule(c),
              icon: const Icon(Icons.schedule_send), label: const Text('جدولة')),
          ]),
        ])))),
    ]);
}

class VideoPreview extends StatefulWidget {
  final Map<dynamic,dynamic> clip;
  const VideoPreview({super.key, required this.clip});
  @override State<VideoPreview> createState() => _VideoPreviewState();
}
class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? controller;
  String? error;
  @override void initState() {super.initState(); initialize();}
  Future<void> initialize() async {
    VideoPlayerController? value;
    try {
      value = VideoPlayerController.networkUrl(
        Api.instance.at('/clips/' + widget.clip['id'].toString() + '/media'),
        httpHeaders: Api.instance.headers);
      await value.initialize();
      await value.setLooping(true);
      await value.play();
      if (mounted) setState(() => controller = value);
      else await value.dispose();
    } catch (e) {
      await value?.dispose();
      if (mounted) setState(() => error = e.toString());
    }
  }
  @override void dispose() {controller?.dispose(); super.dispose();}
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('معاينة المقطع')),
    body: Center(child: error != null ? Text(error!) : controller == null
      ? const CircularProgressIndicator()
      : AspectRatio(aspectRatio: controller!.value.aspectRatio,
          child: VideoPlayer(controller!))),
  );
}

class Accounts extends StatefulWidget {
  const Accounts({super.key});
  @override State<Accounts> createState() => _AccountsState();
}
class _AccountsState extends State<Accounts> {
  final url = TextEditingController(text: Api.instance.server);
  final key = TextEditingController(text: Api.instance.key);
  List<dynamic> accounts = [];
  String status = '';
  bool busy = false;
  @override void initState() {super.initState(); refresh();}
  @override void dispose() {url.dispose(); key.dispose(); super.dispose();}
  Future<void> refresh() async {
    try {
      final a = await Api.instance.call('GET', '/health');
      final b = await Api.instance.call('GET', '/tiktok/status');
      if (mounted) setState(() {
        status = a['ok'] == true ? 'متصل' : 'غير متصل';
        accounts = b['accounts'] as List<dynamic>? ?? [];
      });
    } catch (_) {
      if (mounted) setState(() => status = 'غير متصل');
    }
  }
  Future<void> save() async {
    try {
      await Api.instance.save(url.text, key.text);
      await refresh(); if (mounted) toast(context, 'تم حفظ إعدادات السيرفر');
    } catch (e) {if (mounted) toast(context, e);}
  }
  Future<void> connect() async {
    try {
      final data = await Api.instance.call('GET', '/tiktok/oauth/url');
      final uri = Uri.parse(data['url'].toString());
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('لم يفتح رابط TikTok');
      }
    } catch (e) {if (mounted) toast(context, e);}
  }
  Future<void> unlink(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('فصل الحساب'),
      content: const Text('هل تريد إلغاء صلاحية هذا الحساب؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('فصل')),
      ]));
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await Api.instance.call('DELETE', '/tiktok/accounts/' + Uri.encodeComponent(id));
      await refresh();
      if (mounted) toast(context, 'تم فصل الحساب');
    } catch (e) {if (mounted) toast(context, e);}
    finally {if (mounted) setState(() => busy = false);}
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18),
    children: [
      heading('إعداد الاتصال', 'عنوان HTTPS الخاص بسيرفر المقاطع.'),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(controller: url, decoration: const InputDecoration(
          labelText: 'عنوان السيرفر', hintText: 'https://your-server.example')),
        const SizedBox(height: 12),
        TextField(controller: key, obscureText: true,
            decoration: const InputDecoration(labelText: 'مفتاح API')),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: save, icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات')),
        Text('حالة السيرفر: ' + status, style: const TextStyle(color: mint)),
      ]))),
      heading('حسابات تيك توك', 'تقدر تربط حساباً أو أكثر وتفصل أي حساب.'),
      FilledButton.icon(onPressed: busy ? null : connect,
        icon: const Icon(Icons.link), label: const Text('ربط حساب تيك توك')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: refresh,
          icon: const Icon(Icons.refresh), label: const Text('تحديث الحسابات')),
      ...accounts.map((a) => Card(child: ListTile(
        leading: const Icon(Icons.account_circle, color: mint),
        title: Text(a['nickname'].toString()),
        trailing: IconButton(tooltip: 'فصل الحساب',
          onPressed: busy ? null : () => unlink(a['id'].toString()),
          icon: const Icon(Icons.link_off)),
      ))),
      heading('حول التطبيق'),
      const Card(child: Padding(padding: EdgeInsets.all(18),
        child: Text('Viral Clips AI · 0.3.1\nحقوق التطبيق © mortadaa\n'
          'نسخة عميل أولية: تحتاج Backend آمن وشهادة HTTPS ومفاتيح TikTok رسمية.'))),
    ]);
}
