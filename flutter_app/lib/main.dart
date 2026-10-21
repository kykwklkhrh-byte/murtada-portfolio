import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const bg = Color(0xFF0A101B);
const panel = Color(0xFF162133);
const accent = Color(0xFF5DE1C1);
const purple = Color(0xFFAA9AFF);
const muted = Color(0xFFABB5C7);
const channel = MethodChannel('viral_clips_ai/native_video');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Never block runApp on platform storage, networking, or user authentication.
  runApp(const ViralApp());
}

class ViralApp extends StatelessWidget {
  const ViralApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Viral Clips AI',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: accent, secondary: purple, surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: Colors.white),
      cardTheme: CardThemeData(
        color: panel, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent, foregroundColor: const Color(0xFF0C1720),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: ViralHome()),
  );
}

class ViralHome extends StatefulWidget {
  const ViralHome({super.key});
  @override State<ViralHome> createState() => _ViralHomeState();
}

class _ViralHomeState extends State<ViralHome> {
  int tab = 0, lengthSeconds = 30, number = 3;
  double startSeconds = 0;
  String category = 'بودكاست';
  String? selected;
  String? chosenName;
  VideoPlayerController? player;
  bool cutting = false;
  List<String> clips = [];
  String progress = '';
  final categories = ['بودكاست', 'قصص', 'لحظات', 'قرآن'];

  @override
  void initState() {
    super.initState();
    loadClips();
  }

  Future<void> loadClips() async {
    try {
      final pref = await SharedPreferences.getInstance();
      final paths = pref.getStringList('saved_clips') ?? [];
      final good = paths.where((p) => File(p).existsSync()).toList();
      if (mounted) setState(() => clips = good);
    } catch (_) {
      // Storage failure must never prevent the home screen from opening.
    }
  }

  Future<void> saveClips() async {
    try {
      final pref = await SharedPreferences.getInstance();
      await pref.setStringList('saved_clips', clips.take(100).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  void message(Object value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(value.toString())),
    );
  }

  Future<void> showVideo(String filename, {bool isSource = false}) async {
    VideoPlayerController? newPlayer;
    try {
      newPlayer = VideoPlayerController.file(File(filename));
      await newPlayer.initialize();
      await newPlayer.setLooping(true);
      if (!mounted) {
        await newPlayer.dispose();
        return;
      }
      final previous = player;
      setState(() {
        selected = filename;
        player = newPlayer;
        if (isSource) startSeconds = 0;
      });
      if (previous != null) await previous.dispose();
      await newPlayer.play();
    } catch (e) {
      await newPlayer?.dispose();
      message('تعذرت معاينة الفيديو. تأكد من نوع الملف. ' + e.toString());
    }
  }

  Future<void> pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video, allowMultiple: false, withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null) {
        message('الملف غير قابل للقراءة على هذا الجهاز');
        return;
      }
      chosenName = file.name;
      await showVideo(file.path!, isSource: true);
    } catch (e) {
      message('مشكلة في اختيار الفيديو: ' + e.toString());
    }
  }

  int get durationMs => player == null || !player!.value.isInitialized
      ? 0 : player!.value.duration.inMilliseconds;

  Future<void> makeClips() async {
    if (cutting || selected == null || durationMs <= 1000) {
      message('اختر فيديو من الجهاز أولاً');
      return;
    }
    final source = selected!;
    final videoDurationMs = durationMs;
    final startMs = (startSeconds * 1000).round();
    final lengthMs = lengthSeconds * 1000;
    setState(() { cutting = true; progress = 'جارٍ تجهيز القص...'; tab = 0; });
    var successes = 0;
    try {
      for (var i = 0; i < number; i++) {
        final position = startMs + i * lengthMs;
        if (position >= videoDurationMs - 1000) break;
        final currentLength = math.min(lengthMs, videoDurationMs - position);
        if (mounted) {
          setState(() => progress = 'قص المقطع ' + (i + 1).toString() + ' من ' + number.toString());
        }
        final output = await channel.invokeMethod<String>('trim', {
          'path': source, 'startMs': position, 'durationMs': currentLength,
        });
        if (output == null || !File(output).existsSync()) {
          throw Exception('لم ينتج التطبيق ملف فيديو');
        }
        successes++;
        if (mounted) setState(() => clips.insert(0, output));
        await saveClips();
      }
      if (successes == 0) throw Exception('ماكو وقت كافي من الفيديو حتى نقصه');
      message('تم تجهيز ' + successes.toString() + ' مقاطع بنجاح');
      if (mounted) setState(() => tab = 1);
    } on PlatformException catch (e) {
      message('ما قدرنا نقص هذا الترميز. جرب MP4 H.264. ' + (e.message ?? e.code));
    } catch (e) {
      message('فشل القص: ' + e.toString());
    } finally {
      if (mounted) setState(() { cutting = false; progress = ''; });
    }
  }

  Future<void> shareClip(String path) async {
    if (!File(path).existsSync()) {
      message('ملف المقطع مو موجود');
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'video/mp4')],
        text: 'مقطع قصير من Viral Clips AI',
      ));
    } catch (e) {
      message('تعذرت المشاركة: ' + e.toString());
    }
  }

  Future<void> deleteClip(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => clips.remove(path));
      await saveClips();
    } catch (e) {
      message('تعذر الحذف: ' + e.toString());
    }
  }

  String clock(int seconds) =>
      (seconds ~/ 60).toString().padLeft(2, '0') + ':' +
      (seconds % 60).toString().padLeft(2, '0');

  Widget caption(String title, String sub) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      Text(sub, style: const TextStyle(fontSize: 13, color: muted, height: 1.65)),
    ]),
  );

  Widget homeTab() => ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 35), children: [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [Color(0xFF453A7B), Color(0xFF254A65), Color(0xFF156056)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome_rounded, size: 32, color: accent),
        const SizedBox(height: 14),
        const Text('فيديو طويل، مقاطع جاهزة',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.25)),
        const SizedBox(height: 8),
        const Text('قص المقاطع على جهازك مباشرة، بدون سيرفر أو تسجيل دخول.',
          style: TextStyle(color: Color(0xFFE0F4F4))),
      ]),
    ),
    caption('اختيار الفيديو', 'اختر فيديو MP4 محفوظاً بجهازك، أو ملفاً تملك حق استخدامه.'),
    Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
      if (player != null && player!.value.isInitialized)
        ClipRRect(borderRadius: BorderRadius.circular(15),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: AspectRatio(
              aspectRatio: player!.value.aspectRatio,
              child: VideoPlayer(player!),
            ),
          )),
      if (chosenName != null) Padding(
        padding: const EdgeInsets.all(10),
        child: Text(chosenName!, maxLines: 2, overflow: TextOverflow.ellipsis)),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: cutting ? null : pickVideo,
        icon: const Icon(Icons.video_library_outlined),
        label: const Text('اختيار فيديو من الجهاز'),
      )),
    ])),
    caption('إعدادات القص', 'حدد بداية القص، مدة كل مقطع، وعدد المقاطع المتتابعة.'),
    Card(child: Padding(padding: const EdgeInsets.all(17), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('بداية القص', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(clock(startSeconds.round()) + ' / ' + clock(durationMs ~/ 1000),
            style: const TextStyle(color: accent)),
        ]),
        Slider(
          value: startSeconds.clamp(0.0, math.max(1.0, durationMs / 1000 - 1)).toDouble(),
          max: math.max(1.0, durationMs / 1000 - 1),
          onChanged: selected == null || cutting ? null :
            (v) {
              setState(() => startSeconds = v);
              player?.seekTo(Duration(milliseconds: (v * 1000).round()));
            },
        ),
        const SizedBox(height: 10),
        const Text('مدة المقطع', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: [15, 30, 40, 60].map((n) =>
          ChoiceChip(label: Text(n.toString() + ' ثانية'),
            selected: lengthSeconds == n,
            onSelected: cutting ? null : (_) => setState(() => lengthSeconds = n))).toList()),
        const SizedBox(height: 15),
        const Text('نوع المحتوى', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: categories.map((c) =>
          ChoiceChip(label: Text(c), selected: category == c,
            onSelected: cutting ? null : (_) => setState(() => category = c))).toList()),
        const SizedBox(height: 15),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('عدد المقاطع', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(number.toString(), style: const TextStyle(color: accent, fontSize: 20)),
        ]),
        Slider(
          value: number.toDouble(), min: 1, max: 6, divisions: 5,
          onChanged: cutting ? null : (v) => setState(() => number = v.round())),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: selected == null || cutting ? null : makeClips,
          icon: const Icon(Icons.content_cut_rounded),
          label: const Text('قص الآن'),
        ),
        if (cutting) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
          Padding(padding: const EdgeInsets.only(top: 9),
              child: Text(progress, textAlign: TextAlign.center)),
        ],
      ],
    ))),
    const SizedBox(height: 12),
    const Text('القص دقيق تقريبياً عند الإطارات الرئيسية. يدعم الفيديوهات المتوافقة مع ترميز MP4.',
      style: TextStyle(color: muted, fontSize: 12, height: 1.7)),
  ]);

  Widget clipsTab() => ListView(padding: const EdgeInsets.all(18), children: [
    caption('مقاطعك الجاهزة', 'كل المقاطع محفوظة محلياً. اضغط مشاركة لإرسال المقطع إلى تيك توك أو أي تطبيق آخر.'),
    if (clips.isEmpty) const Card(child: Padding(
      padding: EdgeInsets.all(25),
      child: Column(children: [
        Icon(Icons.movie_creation_outlined, size: 45, color: purple),
        SizedBox(height: 10),
        Text('بعدك ما قصيت أي مقطع'),
        Text('ارجع للاستوديو واختر فيديو', style: TextStyle(color: muted)),
      ]),
    )),
    ...clips.asMap().entries.map((item) {
      final path = item.value;
      return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFF324A52),
            child: Icon(Icons.play_arrow, color: accent)),
          title: Text('المقطع ' + (item.key + 1).toString()),
          subtitle: Text(path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () async { await showVideo(path); if (mounted) setState(() => tab = 0); },
        ),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () => shareClip(path),
            icon: const Icon(Icons.share_outlined), label: const Text('مشاركة'))),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'حذف', onPressed: () => deleteClip(path),
            icon: const Icon(Icons.delete_outline)),
        ]),
      ])));
    }),
  ]);

  Widget aboutTab() => ListView(padding: const EdgeInsets.all(18), children: [
    caption('عن التطبيق', 'إصدار 0.4.0 — مصمم للأندرويد'),
    const Card(child: Padding(padding: EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('VIRAL CLIPS AI', style: TextStyle(fontSize: 20,
          letterSpacing: 2, fontWeight: FontWeight.w900, color: accent)),
        SizedBox(height: 12),
        Text('القص يعمل داخل تلفونك، حتى بدون إنترنت.'),
        SizedBox(height: 10),
        Text('نشر تيك توك يتم عن طريق نافذة مشاركة أندرويد، مو نشر تلقائي للحساب.'),
        SizedBox(height: 10),
        Text('تحويل الفيديو إلى عمودي 9:16، توليد الترجمة، واختيار اللقطات بالذكاء الاصطناعي غير متوفرة بهذي النسخة.'),
        SizedBox(height: 15),
        Text('حقوق التطبيق © mortadaa', style: TextStyle(color: muted)),
      ],
    ))),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 18,
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('VIRAL CLIPS AI', style: TextStyle(
          color: accent, fontSize: 12, letterSpacing: 2.4, fontWeight: FontWeight.w900)),
        Text('استوديو المقاطع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ]),
      actions: const [
        Padding(padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.video_camera_back_outlined, color: purple)),
      ],
    ),
    body: SafeArea(child: IndexedStack(index: tab, children: [homeTab(), clipsTab(), aboutTab()])),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      backgroundColor: panel,
      indicatorColor: const Color(0xFF36594F),
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.content_cut_outlined), label: 'الاستوديو'),
        NavigationDestination(icon: Icon(Icons.video_collection_outlined), label: 'مقاطعك'),
        NavigationDestination(icon: Icon(Icons.info_outline_rounded), label: 'عن التطبيق'),
      ],
    ),
  );
}
