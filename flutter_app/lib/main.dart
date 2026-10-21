import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'source_tools.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const bg = Color(0xFFF6F2EA);
const panel = Color(0xFFFFFFFF);
const accent = Color(0xFFB55738);
const purple = Color(0xFF293E59);
const muted = Color(0xFF66717F);
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
    title: 'لقطة | Laqta',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.light(primary: accent, secondary: purple, surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: purple),
      cardTheme: CardThemeData(
        color: panel, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: purple, foregroundColor: Colors.white,
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
  final youtubeInput = TextEditingController();
  final tiktokInput = TextEditingController();
  List<String> youtubeLinks = [];
  List<String> tiktokHandles = [];
  String? selectedAccount;
  String? lastYoutubeTitle;
  String? lastYoutubeAuthor;
  bool checkingLink = false;
  bool importingVideo = false;


  @override
  void initState() {
    super.initState();
    loadClips();
    loadSources();
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
    youtubeInput.dispose();
    tiktokInput.dispose();
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
      if (mounted) setState(() => tab = 2);
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
          colors: [Color(0xFF1C3049), Color(0xFF3F4250), Color(0xFF9A553C)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.play_circle_filled_rounded, size: 32, color: Color(0xFFFFDEB6)),
        const SizedBox(height: 14),
        const Text('لقطة تستاهل تننشر',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.25, color: Colors.white)),
        const SizedBox(height: 8),
        const Text('قص المقاطع على جهازك مباشرة، بدون سيرفر أو تسجيل دخول.',
          style: TextStyle(color: Color(0xFFF7EBDF))),
      ]),
    ),
    Card(child: ListTile(
      leading: const Icon(Icons.link, color: accent),
      title: const Text('عندك رابط يوتيوب؟'),
      subtitle: const Text('أضفه بقسم يوتيوب وشوف معلوماته'),
      trailing: const Icon(Icons.arrow_back_ios_new, size: 15),
      onTap: () => setState(() => tab = 1),
    )),
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
    ]))),
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
          leading: const CircleAvatar(backgroundColor: Color(0xFFF8E7D7),
            child: Icon(Icons.play_arrow, color: accent)),
          title: Text('المقطع ' + (item.key + 1).toString()),
          subtitle: Text(path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () async { await showVideo(path); if (mounted) setState(() => tab = 0); },
        ),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () => shareClip(path),
            icon: const Icon(Icons.share_outlined), label: const Text('نشر / مشاركة'))),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'حذف', onPressed: () => deleteClip(path),
            icon: const Icon(Icons.delete_outline)),
        ]),
      ])));
    }),
  ]);

  Future<void> loadSources() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() {
        youtubeLinks = p.getStringList('laqta_sources') ?? [];
        tiktokHandles = p.getStringList('laqta_tiktok_profiles') ?? [];
        if (tiktokHandles.isNotEmpty) selectedAccount = tiktokHandles.first;
      });
    } catch (_) {}
  }

  Future<void> saveSources() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('laqta_sources', youtubeLinks);
      await p.setStringList('laqta_tiktok_profiles', tiktokHandles);
    } catch (_) { message('تعذر حفظ القائمة على الجهاز'); }
  }

  Future<void> launchExternal(String address) async {
    try {
      final uri = Uri.parse(address);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('المتصفح لم يفتح الرابط');
      }
    } catch (e) { message('ما قدرنا نفتح الرابط: $e'); }
  }

  Future<void> checkYoutubeLink() async {
    final link = youtubeInput.text.trim();
    final kind = classifyVideoLink(link);
    if (kind == VideoLinkKind.unsupported) {
      message('الرابط غير صحيح. استخدم رابط يوتيوب أو رابط مباشر لملف MP4 آمن.');
      return;
    }
    if (kind == VideoLinkKind.directMp4) {
      await importMp4(link);
      return;
    }
    if (checkingLink) return;
    setState(() => checkingLink = true);
    String title = 'رابط يوتيوب محفوظ';
    String author = 'يوتيوب';
    try {
      if (kind == VideoLinkKind.youtubeVideo) {
        final endpoint = Uri.https('www.youtube.com', '/oembed',
          {'url': link, 'format': 'json'});
        final response = await http.get(endpoint).timeout(const Duration(seconds: 14));
        if (response.statusCode == 200) {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          title = (result['title'] ?? title).toString();
          author = (result['author_name'] ?? author).toString();
        }
      } else {
        title = 'قناة أو قائمة يوتيوب';
      }
    } catch (_) {
      // A valid link can still be saved when metadata requests are unavailable.
    } finally {
      if (mounted) {
        setState(() {
          youtubeLinks.remove(link);
          youtubeLinks.insert(0, link);
          lastYoutubeTitle = title;
          lastYoutubeAuthor = author;
          checkingLink = false;
        });
      }
      await saveSources();
    }
    message('تم حفظ الرابط. افتحه لمشاهدته، ثم استورد ملفاً تملك حق استخدامه.');
  }

  Future<void> importMp4(String url) async {
    if (importingVideo) return;
    setState(() => importingVideo = true);
    http.Client? client;
    File? output;
    IOSink? sink;
    try {
      final uri = Uri.parse(url);
      client = http.Client();
      final response = await client.send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('الرابط رجّع HTTP ${response.statusCode}');
      }
      if (response.contentLength != null && response.contentLength! > 500 * 1024 * 1024) {
        throw Exception('حجم الفيديو أكبر من 500 ميغابايت');
      }
      final mime = response.headers['content-type']?.toLowerCase() ?? '';
      if (mime.contains('text/html') || mime.contains('application/json')) {
        throw Exception('الرابط مو ملف فيديو مباشر');
      }
      final dir = await getApplicationDocumentsDirectory();
      output = File('${dir.path}/Laqta_import_${DateTime.now().millisecondsSinceEpoch}.mp4');
      sink = output.openWrite();
      var size = 0;
      await for (final data in response.stream.timeout(const Duration(seconds: 65))) {
        size += data.length;
        if (size > 500 * 1024 * 1024) throw Exception('حجم الفيديو يتجاوز 500 ميغابايت');
        sink.add(data);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (size < 1024) throw Exception('ملف الفيديو غير مكتمل');
      await showVideo(output.path, isSource: true);
      if (mounted) setState(() => tab = 0);
      message('تم استيراد الفيديو. اختَر مدة المقطع واضغط قص الآن.');
    } catch (e) {
      message('فشل استيراد MP4: $e');
      try { await sink?.close(); } catch (_) {}
      try { if (output != null && await output.exists()) await output.delete(); } catch (_) {}
    } finally {
      client?.close();
      if (mounted) setState(() => importingVideo = false);
    }
  }

  Future<void> addTikTokHandle() async {
    final username = parseTikTokHandle(tiktokInput.text);
    if (username == null) {
      message('اكتب اسم حساب صحيح، مثل @example أو رابط الملف الشخصي');
      return;
    }
    setState(() {
      tiktokHandles.remove(username);
      tiktokHandles.insert(0, username);
      selectedAccount = username;
    });
    tiktokInput.clear();
    await saveSources();
    message('حفظنا الحساب للانتقال السريع. هذا مو تسجيل دخول API.');
  }

  Future<void> removeTikTokHandle(String handle) async {
    setState(() {
      tiktokHandles.remove(handle);
      if (selectedAccount == handle) {
        selectedAccount = tiktokHandles.isEmpty ? null : tiktokHandles.first;
      }
    });
    await saveSources();
  }

  Widget youtubeTab() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
    children: [
      caption('مصادر يوتيوب', 'ألصق رابط فيديو أو قناة. تظهر معلومات الفيديو وتكدر تفتحه من التطبيق.'),
      Card(child: Padding(padding: const EdgeInsets.all(17), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.smart_display_outlined, size: 40, color: accent),
          const SizedBox(height: 10),
          TextField(
            controller: youtubeInput,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://youtube.com/watch?v=...',
              labelText: 'رابط يوتيوب أو MP4 مباشر',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: checkingLink || importingVideo ? null : checkYoutubeLink,
            icon: const Icon(Icons.link),
            label: Text(importingVideo ? 'جارٍ تنزيل MP4...' :
                checkingLink ? 'جلب المعلومات...' : 'فحص الرابط وإضافته'),
          ),
          if (importingVideo || checkingLink) const LinearProgressIndicator(),
          if (lastYoutubeTitle != null) ...[
            const SizedBox(height: 12),
            Text(lastYoutubeTitle!, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(lastYoutubeAuthor ?? '', style: const TextStyle(color: muted)),
          ],
        ],
      ))),
      caption('القنوات والفيديوهات المحفوظة', 'المصدر يبقى محفوظ على الجهاز حتى تكدر ترجع له.'),
      if (youtubeLinks.isEmpty) const Card(child: ListTile(
        leading: Icon(Icons.video_library_outlined, color: accent),
        title: Text('ما ضفت روابط بعد'),
      )),
      ...youtubeLinks.map((link) => Card(child: ListTile(
        leading: const Icon(Icons.play_circle_outline, color: accent),
        title: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr),
        subtitle: const Text('افتح الفيديو على يوتيوب'),
        onTap: () => launchExternal(link),
        trailing: IconButton(
          tooltip: 'حذف الرابط', icon: const Icon(Icons.close),
          onPressed: () async {
            setState(() => youtubeLinks.remove(link));
            await saveSources();
          },
        ),
      ))),
      caption('شلون تحول رابط إلى مقطع؟', 'روابط يوتيوب تعرض معلومات الفيديو والمشاهدة. '
        'تنزيل فيديوهات القنوات وإعادة نشرها يحتاج حقوقاً وطريقة استيراد مسموحة. '
        'إذا عندك الملف الأصلي، استورده بالاستوديو، أو استخدم رابط MP4 مباشر آمن.'),
      OutlinedButton.icon(onPressed: () => setState(() => tab = 0),
        icon: const Icon(Icons.content_cut_outlined), label: const Text('الانتقال إلى أداة القص')),
    ],
  );

  Widget tiktokTab() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
    children: [
      caption('حساباتي على تيك توك', 'أضف حساباتك للانتقال السريع بينها، وتكدر تحذف أي حساب.'),
      Card(child: Padding(padding: const EdgeInsets.all(17), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.account_circle_outlined, size: 40, color: purple),
          const SizedBox(height: 12),
          TextField(
            controller: tiktokInput, textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'اسم الحساب أو رابط TikTok',
              hintText: '@username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: addTikTokHandle,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('إضافة الحساب إلى قائمتي')),
          const SizedBox(height: 9),
          const Text('ملاحظة: إضافة الاسم مو ربط رسمي ولا تعطي التطبيق صلاحية النشر باسمك.',
            style: TextStyle(color: muted, height: 1.6)),
        ],
      ))),
      caption('الحسابات المحفوظة', '${tiktokHandles.length} حساب'),
      if (tiktokHandles.isEmpty) const Card(child: ListTile(
        leading: Icon(Icons.person_off_outlined),
        title: Text('ما أضفت أي حساب بعد'),
      )),
      ...tiktokHandles.map((handle) => Card(child: ListTile(
        leading: Icon(
          selectedAccount == handle ? Icons.radio_button_checked : Icons.radio_button_off,
          color: accent,
        ),
        title: Text('@$handle', textDirection: TextDirection.ltr),
        subtitle: Text(selectedAccount == handle ? 'محدد للعرض' : 'اضغط لاختيار الحساب'),
        onTap: () => setState(() => selectedAccount = handle),
        trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'افتح حساب تيك توك',
            onPressed: () => launchExternal('https://www.tiktok.com/@$handle'),
            icon: const Icon(Icons.open_in_new, color: purple)),
          IconButton(tooltip: 'إزالة من القائمة', icon: const Icon(Icons.delete_outline),
            onPressed: () => removeTikTokHandle(handle)),
        ]),
      ))),
      caption('نشر مقطع على تيك توك', 'إذا عندك مقاطع جاهزة، افتح مشاركة أندرويد '
        'واختَر تيك توك، ثم تأكد من الحساب داخل TikTok قبل النشر.'),
      if (selectedAccount != null) Card(child: ListTile(
        title: Text('الحساب المختار: @$selectedAccount'),
        subtitle: const Text('اختيار الحساب هنا لا يغيّر الحساب المسجّل داخل تطبيق تيك توك'),
        trailing: IconButton(icon: const Icon(Icons.open_in_new),
          onPressed: () => launchExternal('https://www.tiktok.com/@$selectedAccount')),
      )),
      ...clips.take(3).map((file) => Card(child: ListTile(
        leading: const Icon(Icons.movie_outlined, color: accent),
        title: Text(file.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: FilledButton(onPressed: () => shareClip(file), child: const Text('مشاركة')),
      ))),
      if (clips.isEmpty) OutlinedButton.icon(
        onPressed: () => setState(() => tab = 0),
        icon: const Icon(Icons.content_cut),
        label: const Text('اصنع أول مقطع')),
      const SizedBox(height: 18),
      const Card(child: Padding(padding: EdgeInsets.all(16),
        child: Text('النشر التلقائي بواجهة TikTok الرسمية يحتاج تطبيق مطور معتمد، '
          'صلاحية video.publish، وموافقة تسجيل الدخول من تيك توك. '
          'ماكو صلاحية نشر مباشر مفعّلة بهذا الإصدار.',
          style: TextStyle(color: muted, height: 1.7)))),
    ],
  );

  Widget aboutTab() => ListView(padding: const EdgeInsets.all(18), children: [
    caption('عن التطبيق', 'إصدار 0.5.0 — مصمم للأندرويد'),
    const Card(child: Padding(padding: EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('لَقطة | LAQTA', style: TextStyle(fontSize: 20,
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
        Text('LAQTA • لَقطة', style: TextStyle(
          color: accent, fontSize: 14, letterSpacing: 1.4, fontWeight: FontWeight.w900)),
        Text('محرّر الفيديو القصير', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ]),
      actions: const [
        Padding(padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.video_camera_back_outlined, color: purple)),
      ],
    ),
    body: SafeArea(child: IndexedStack(index: tab, children: [homeTab(), youtubeTab(), clipsTab(), tiktokTab()])),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      backgroundColor: panel,
      indicatorColor: const Color(0xFFF5DFCE),
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.content_cut_outlined), label: 'الاستوديو'),
        NavigationDestination(icon: Icon(Icons.smart_display_outlined), label: 'يوتيوب'),
        NavigationDestination(icon: Icon(Icons.video_collection_outlined), label: 'مقاطعك'),
        NavigationDestination(icon: Icon(Icons.people_outline), label: 'تيك توك'),
      ],
    ),
  );
}
