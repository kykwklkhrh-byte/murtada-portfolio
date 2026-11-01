import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MurtadhaAi());
}

const Color kIndigo = Color(0xFF8D78FF);
const Color kTurquoise = Color(0xFF3FE5C4);
const Color kDarkBg = Color(0xFF080F1E);

class ChatEntry {
  ChatEntry({required this.role, required this.text, DateTime? time, this.hasImage = false})
      : time = time ?? DateTime.now();
  final String role;
  final String text;
  final DateTime time;
  final bool hasImage;

  Map<String, Object?> toJson() => {
        'role': role,
        'text': text,
        'time': time.toIso8601String(),
        'hasImage': hasImage,
      };

  factory ChatEntry.fromJson(Map<String, dynamic> json) => ChatEntry(
        role: json['role'] == 'assistant' ? 'assistant' : 'user',
        text: (json['text'] ?? '').toString(),
        time: DateTime.tryParse((json['time'] ?? '').toString()),
        hasImage: json['hasImage'] == true,
      );
}

class ChatSession {
  ChatSession({required this.id, required this.title, this.provider = 'smart', List<ChatEntry>? messages})
      : messages = messages ?? [];
  final String id;
  String title;
  String provider;
  final List<ChatEntry> messages;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'provider': provider,
        'messages': messages.take(100).map((e) => e.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'محادثة').toString(),
        provider: (json['provider'] ?? 'smart').toString(),
        messages: (json['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ChatEntry.fromJson)
            .toList(),
      );
}

class MurtadhaAi extends StatefulWidget {
  const MurtadhaAi({super.key});

  @override
  State<MurtadhaAi> createState() => _MurtadhaAiState();
}

class _MurtadhaAiState extends State<MurtadhaAi> {
  final _secure = const FlutterSecureStorage();
  final _picker = ImagePicker();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  final _input = TextEditingController();
  final _endpointField = TextEditingController();
  final _tokenField = TextEditingController();
  final _geminiKeyField = TextEditingController();
  final _scroll = ScrollController();

  final List<ChatSession> _sessions = [];
  String? _currentId;
  String _endpoint = '';
  String _token = '';
  String _geminiKey = '';
  bool _dark = true;
  bool _sending = false;
  bool _listening = false;
  bool _obscureToken = true;
  bool _loading = true;
  int _page = 0;
  Uint8List? _image;
  String _imageMime = 'image/jpeg';

  static const _providers = <String, String>{
    'smart': 'تلقائي',
    'gemini': 'Gemini',
    'openai': 'GPT',
    'claude': 'Claude',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _endpointField.dispose();
    _tokenField.dispose();
    _geminiKeyField.dispose();
    _scroll.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  ChatSession get _active {
    if (_sessions.isEmpty) {
      final s = _newSessionObject();
      _sessions.add(s);
      _currentId = s.id;
      return s;
    }
    return _sessions.firstWhere(
      (s) => s.id == _currentId,
      orElse: () => _sessions.first,
    );
  }

  ChatSession _newSessionObject() => ChatSession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'محادثة جديدة',
      );

  Future<void> _load() async {
    try {
      final pref = await SharedPreferences.getInstance();
      _endpoint = pref.getString('server_endpoint') ?? '';
      _dark = pref.getBool('dark_mode') ?? true;
      _token = await _secure.read(key: 'private_access_token') ?? '';
      _geminiKey = await _secure.read(key: 'gemini_api_key') ?? '';
      final stored = pref.getString('chat_history');
      if (stored != null) {
        final items = jsonDecode(stored) as List<dynamic>;
        _sessions.addAll(items.whereType<Map<String, dynamic>>().map(ChatSession.fromJson));
      }
      _currentId = pref.getString('current_chat');
      if (_sessions.isEmpty) {
        _sessions.add(_newSessionObject());
        _currentId = _sessions.first.id;
      }
      _endpointField.text = _endpoint;
      _tokenField.text = _token;
      _geminiKeyField.text = _geminiKey;
    } catch (_) {
      // An invalid older local cache must not prevent launching the app.
      if (_sessions.isEmpty) {
        _sessions.add(_newSessionObject());
        _currentId = _sessions.first.id;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    final pref = await SharedPreferences.getInstance();
    await pref.setString('chat_history', jsonEncode(_sessions.take(50).map((e) => e.toJson()).toList()));
    await pref.setString('current_chat', _active.id);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _newChat() {
    if (_sending) return;
    setState(() {
      final s = _newSessionObject();
      _sessions.insert(0, s);
      _currentId = s.id;
      _page = 0;
      _image = null;
      _input.clear();
    });
    _persist();
  }

  void _switchChat(ChatSession session) {
    if (_sending) return;
    Navigator.of(context).maybePop();
    setState(() {
      _currentId = session.id;
      _page = 0;
      _image = null;
      _input.clear();
    });
    _persist();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  String _pickSmartProvider(String text) {
    final t = text.toLowerCase();
    if (t.contains('كود') || t.contains('برمج') || t.contains('flutter') || t.contains('python')) {
      return 'claude';
    }
    if (t.contains('ترجم') || t.contains('translate') || t.contains('صورة')) return 'gemini';
    return 'gemini';
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1100, maxHeight: 1100, imageQuality: 55,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 900000) {
        _notify('الصورة كبيرة. اختار صورة أصغر من 900KB.');
        return;
      }
      setState(() {
        _image = bytes;
        _imageMime = file.path.toLowerCase().endsWith('.png') ? 'image/png' :
            file.path.toLowerCase().endsWith('.webp') ? 'image/webp' : 'image/jpeg';
      });
    } catch (_) {
      _notify('ما گدرت أفتح الصورة. تأكد من صلاحية المعرض.');
    }
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ready) {
        _notify('خدمة التعرف على الصوت مو متوفرة على هذا الجهاز.');
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(onResult: (result) {
        if (!mounted) return;
        setState(() {
          _input.text = result.recognizedWords;
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        });
      });
    } catch (_) {
      if (mounted) setState(() => _listening = false);
      _notify('تحقق من إذن المايكروفون وإعدادات اللغة.');
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      try { await _tts.setLanguage('ar-IQ'); } catch (_) { await _tts.setLanguage('ar-SA'); }
      await _tts.setSpeechRate(0.48);
      await _tts.speak(text.length > 1800 ? text.substring(0, 1800) : text);
    } catch (_) {
      _notify('محرك قراءة النص غير متوفر.');
    }
  }

  Uri? _chatUri() {
    final u = Uri.tryParse(_endpoint.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty || u.userInfo.isNotEmpty) return null;
    if (u.path.endsWith('/chat')) return u;
    return u.replace(path: '${u.path.replaceAll(RegExp(r'/$'), '')}/chat');
  }


  // Personal-device Gemini mode: key is held in Android encrypted storage,
  // and is sent only over HTTPS to Google's Gemini API, never to our gateway.
  Future<String> _askGeminiDirect(List<ChatEntry> messages,
      Uint8List? image, String imageMime, {String? keyOverride}) async {
    final key = keyOverride ?? _geminiKey;
    if (key.trim().isEmpty) throw const FormatException('أضف مفتاح Gemini من الإعدادات.');
    final uri = Uri.https('generativelanguage.googleapis.com',
        '/v1beta/models/gemini-2.5-flash:generateContent');
    final recent = messages.length > 12 ? messages.sublist(messages.length - 12) : messages;
    final transcript = recent.map((m) =>
        (m.role == 'assistant' ? 'المساعد: ' : 'المستخدم: ') + m.text).join('\n\n');
    final parts = <Map<String, dynamic>>[
      {'text': 'أنت Murtadha AI، مساعد شخصي مهذب وصادق. جاوب بالعراقي إذا المستخدم يحچي بالعراقي. '
          'ساعد بالدراسة والهندسة والبرمجة، ولا تدعي أنك نفذت أي إجراء خارج التطبيق.\n\n'
          + transcript + '\n\nأجب على آخر طلب للمستخدم.'},
    ];
    if (image != null) {
      parts.add({'inline_data': {'mime_type': imageMime, 'data': base64Encode(image)}});
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 22);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 25));
      request.headers.set('x-goog-api-key', key.trim());
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.write(jsonEncode({'contents': [
        {'role': 'user', 'parts': parts}
      ], 'generationConfig': {'maxOutputTokens': 4096}}));
      final response = await request.close().timeout(const Duration(seconds: 75));
      final raw = await utf8.decoder.bind(response).join();
      Map<String, dynamic> data;
      try { data = jsonDecode(raw) as Map<String, dynamic>; }
      catch (_) { throw const FormatException('Google رجّع استجابة غير مفهومة.'); }
      if (response.statusCode != 200) {
        final error = (data['error'] is Map) ? data['error'] as Map : <String, dynamic>{};
        final apiMessage = (error['message'] ?? '').toString();
        if (response.statusCode == 400 || response.statusCode == 401 ||
            response.statusCode == 403) {
          throw const FormatException('مفتاح Gemini غير صحيح أو غير مفعّل. أنشئ مفتاح جديد من Google AI Studio.');
        }
        if (response.statusCode == 429) {
          throw const FormatException('وصلت حد الطلبات المسموح من Google. حاول بوقت آخر.');
        }
        if (response.statusCode == 404) {
          throw const FormatException('نموذج Gemini غير متوفر في حسابك حالياً.');
        }
        throw FormatException('Google رجّع خطأ ' + response.statusCode.toString() +
            (apiMessage.isEmpty ? '.' : ': ' + apiMessage.substring(0, apiMessage.length > 180 ? 180 : apiMessage.length)));
      }
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      final answer = candidates.whereType<Map<String, dynamic>>().expand((candidate) {
        final content = candidate['content'];
        if (content is! Map) return <String>[];
        final rawParts = content['parts'];
        if (rawParts is! List) return <String>[];
        return rawParts.whereType<Map>().where((p) => p['thought'] != true)
            .map((p) => (p['text'] ?? '').toString());
      }).join('\n').trim();
      if (answer.isEmpty) throw const FormatException('Gemini ما رجّع نص. جرّب صياغة أبسط.');
      return answer;
    } on SocketException {
      throw const FormatException('ماكو اتصال بالإنترنت. تأكد من الشبكة.');
    } on HandshakeException {
      throw const FormatException('تعذّر الاتصال الآمن مع Google.');
    } finally { client.close(force: true); }
  }

  Future<void> _testGemini() async {
    final key = _geminiKeyField.text.trim();
    if (key.isEmpty) {
      _notify('أولاً أنشئ مفتاح Gemini والصقه هنا.');
      return;
    }
    _notify('جاري فحص مفتاح Gemini...');
    try {
      final reply = await _askGeminiDirect(
          [ChatEntry(role: 'user', text: 'جاوب فقط بكلمة تم')],
          null, 'image/jpeg', keyOverride: key);
      if (mounted) _notify('نجح الاتصال بـ Gemini! ' +
          reply.substring(0, reply.length > 70 ? 70 : reply.length));
    } catch (e) {
      if (mounted) _notify(e is FormatException ? e.message : 'فشل فحص Gemini. تحقق من الشبكة.');
    }
  }

  Future<String> _askBackend(String provider, List<ChatEntry> messages,
      Uint8List? image, String imageMime) async {
    final uri = _chatUri();
    if (uri == null) throw const FormatException('رابط السيرفر لازم يبدأ https:// ويكون صحيح.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 25));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      final list = messages.length > 18 ? messages.sublist(messages.length - 18) : messages;
      final payload = <String, dynamic>{
        'provider': provider,
        'messages': list.map((m) => {'role': m.role, 'text': m.text}).toList(),
      };
      if (image != null && (payload['messages'] as List).isNotEmpty) {
        (payload['messages'] as List).last['image'] = {
          'mime': imageMime,
          'base64': base64Encode(image),
        };
      }
      req.write(jsonEncode(payload));
      final response = await req.close().timeout(const Duration(seconds: 70));
      final raw = await utf8.decoder.bind(response).join();
      Map<String, dynamic> data;
      try { data = jsonDecode(raw) as Map<String, dynamic>; }
      catch (_) { throw const FormatException('استجابة غير مفهومة من السيرفر.'); }
      if (response.statusCode != 200) {
        throw FormatException((data['error'] ?? 'فشل الاتصال بالسيرفر.').toString());
      }
      final answer = (data['answer'] ?? '').toString().trim();
      if (answer.isEmpty) throw const FormatException('وصل رد فارغ من السيرفر.');
      return answer;
    } finally { client.close(force: true); }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    final image = _image;
    if (text.isEmpty && image == null) return;
    if (_geminiKey.isEmpty && (_chatUri() == null || _token.isEmpty)) {
      setState(() => _page = 2);
      _notify('حتى يجاوبك التطبيق، أضف مفتاح Gemini أولاً. ما تحتاج سيرفر.');
      return;
    }
    final session = _active;
    final provider = session.provider == 'smart' ? _pickSmartProvider(text) : session.provider;
    final entry = ChatEntry(role: 'user', text: text.isEmpty ? 'اشرح لي الصورة المرفقة' : text,
        hasImage: image != null);
    final imageMime = _imageMime;
    setState(() {
      session.messages.add(entry);
      if (session.title == 'محادثة جديدة') {
        session.title = entry.text.length > 32 ? '${entry.text.substring(0, 32)}…' : entry.text;
      }
      _sending = true;
      _image = null;
      _input.clear();
    });
    _persist();
    _scrollToBottom();
    try {
      final useGemini = _geminiKey.isNotEmpty &&
          (provider == 'gemini' || _chatUri() == null || _token.isEmpty);
      if (useGemini && provider != 'gemini' && session.provider != 'smart') {
        _notify('الذكاء المحدد يحتاج سيرفر، فراح أستخدم Gemini هسه.');
      }
      final answer = useGemini
          ? await _askGeminiDirect(session.messages, image, imageMime)
          : await _askBackend(provider, session.messages, image, imageMime);
      if (!mounted) return;
      setState(() => session.messages.add(ChatEntry(role: 'assistant', text: answer)));
      _persist();
    } catch (e) {
      if (!mounted) return;
      final errorText = e is FormatException ? e.message : 'تعذّر الاتصال. تأكد من الإنترنت وإعدادات السيرفر.';
      _notify(errorText);
      setState(() => session.messages.add(ChatEntry(role: 'assistant', text: '⚠️ $errorText')));
      _persist();
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _testServer() async {
    final entered = _endpointField.text.trim();
    final uri = Uri.tryParse(entered);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _notify('أدخل رابط HTTPS صحيح أولاً.');
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final r = await client.getUrl(uri.replace(path: '/health')).timeout(const Duration(seconds: 10));
      final response = await r.close().timeout(const Duration(seconds: 10));
      _notify(response.statusCode == 200
          ? 'السيرفر شغّال! هذا الفحص لا يتحقق من مفاتيح الذكاء.'
          : 'السيرفر رجع رمز ${response.statusCode}.');
    } catch (_) {
      _notify('السيرفر غير متاح. تأكد من الرابط والاتصال.');
    } finally { client.close(force: true); }
  }

  Future<void> _saveSettings() async {
    _endpoint = _endpointField.text.trim().replaceAll(RegExp(r'/$'), '');
    _token = _tokenField.text.trim();
    _geminiKey = _geminiKeyField.text.trim();
    if (_endpoint.isNotEmpty && _chatUri() == null) {
      _notify('الرابط لازم يكون HTTPS صحيح.');
      return;
    }
    await _secure.write(key: 'private_access_token', value: _token);
    await _secure.write(key: 'gemini_api_key', value: _geminiKey);
    final pref = await SharedPreferences.getInstance();
    await pref.setString('server_endpoint', _endpoint);
    if (!mounted) return;
    setState(() => _page = 0);
    _notify(_geminiKey.isNotEmpty
        ? 'انحفظ مفتاح Gemini بأمان على جهازك. ارجع للمحادثة واسألني!'
        : 'انحفظت الإعدادات. تحتاج مفتاح Gemini أو سيرفر حقيقي حتى يجاوب التطبيق.');
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('حذف كل المحادثات؟'),
          content: const Text('راح تنمسح المحادثات المخزونة من هذا الجهاز. ما نكدر نسترجعها.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ));
    if (ok != true || !mounted) return;
    setState(() {
      _sessions.clear();
      _sessions.add(_newSessionObject());
      _currentId = _sessions.first.id;
      _page = 0;
    });
    await _persist();
    _notify('تم حذف سجل المحادثات المحلي.');
  }

  void _chooseTool(String prompt) {
    _input.text = prompt;
    _input.selection = TextSelection.collapsed(offset: prompt.length);
    setState(() => _page = 0);
    _notify('عدّل الطلب أو أرسله من المحادثة.');
  }

  // A custom Aurora visual system — deliberately not Flutter's starter screen.
  bool get _isDark => _dark;
  Color get _surface => _isDark ? const Color(0xFF142038) : Colors.white;
  Color get _muted => _isDark ? const Color(0xFF9AAAC3) : const Color(0xFF52637B);
  Color get _line => _isDark ? const Color(0xFF2A3B58) : const Color(0xFFDDE6EF);

  ThemeData _theme(bool dark) {
    final primary = dark ? kTurquoise : const Color(0xFF087E79);
    final base = ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: primary,
          brightness: dark ? Brightness.dark : Brightness.light),
      scaffoldBackgroundColor: dark ? kDarkBg : const Color(0xFFF4F8FD),
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent, elevation: 0),
      cardTheme: CardThemeData(elevation: 0,
        color: dark ? const Color(0xFF142038) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: dark ? const Color(0xFF2A3B58) : const Color(0xFFE3EAF2)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1A2942) : const Color(0xFFEAF1F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 1.4)),
      ),
    );
  }

  Widget _brandMark({double size = 42}) => Container(
    height: size, width: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
        colors: [Color(0xFF3FE5C4), Color(0xFF4B95FC), Color(0xFF8D78FF)]),
      borderRadius: BorderRadius.circular(size * .33),
      boxShadow: [BoxShadow(color: kTurquoise.withValues(alpha: .20), blurRadius: 18, offset: const Offset(0, 5))],
    ),
    child: Icon(Icons.hub_rounded, color: const Color(0xFF07152A), size: size * .53),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 8),
    child: Row(children: [
      Builder(builder: (inner) => IconButton(
        tooltip: 'المحادثات السابقة', icon: const Icon(Icons.grid_view_rounded),
        onPressed: () => Scaffold.of(inner).openDrawer(),
      )),
      _brandMark(),
      const SizedBox(width: 11),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MURTADHA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.7)),
        Text('ذكاء يساعدك بكل يوم', style: TextStyle(fontSize: 11, color: kTurquoise)),
      ])),
      if (_page == 0) IconButton(
        tooltip: 'محادثة جديدة', onPressed: _newChat,
        icon: const Icon(Icons.edit_square, size: 23),
      ),
    ]),
  );

  Widget _navButton(int index, IconData icon, String label) {
    final selected = _page == index;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: () => setState(() => _page = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: selected ? LinearGradient(colors: [kTurquoise.withValues(alpha: .20), kIndigo.withValues(alpha: .17)]) : null,
          border: Border.all(color: selected ? kTurquoise.withValues(alpha: .45) : Colors.transparent),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 21, color: selected ? kTurquoise : _muted),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? (_dark ? Colors.white : const Color(0xFF13304A)) : _muted)),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murtadha AI',
      debugShowCheckedModeBanner: false,
      theme: _theme(false), darkTheme: _theme(true),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: _loading ? const Scaffold(body: Center(child: CircularProgressIndicator())) :
      Scaffold(
        extendBody: false,
        backgroundColor: _dark ? kDarkBg : const Color(0xFFF4F8FD),
        drawer: _drawer(),
        body: SafeArea(child: Column(children: [
          _topBar(),
          Expanded(child: IndexedStack(index: _page, children: [
            _chatPage(), _toolsPage(), _settingsPage(),
          ])),
        ])),
        bottomNavigationBar: SafeArea(top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 3, 12, 10),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(25),
              border: Border.all(color: _line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _dark ? .26 : .07),
                blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              _navButton(0, Icons.forum_rounded, 'الدردشة'),
              _navButton(1, Icons.auto_awesome_mosaic_rounded, 'الأدوات'),
              _navButton(2, Icons.tune_rounded, 'الإعدادات'),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _drawer() => Drawer(
    backgroundColor: _dark ? const Color(0xFF101B30) : Colors.white,
    child: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [_brandMark(size: 48), const SizedBox(width: 12),
            const Text('محادثاتي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))]),
          const SizedBox(height: 19),
          FilledButton.icon(
            onPressed: () { Navigator.pop(context); _newChat(); },
            icon: const Icon(Icons.add), label: const Text('محادثة جديدة'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF178F86),
              foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
          ),
        ])),
      Divider(height: 1, color: _line),
      Expanded(child: ListView.builder(itemCount: _sessions.length, itemBuilder: (_, i) {
        final session = _sessions[i];
        final selected = session.id == _active.id;
        return Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            selected: selected,
            selectedTileColor: kTurquoise.withValues(alpha: .09),
            leading: Icon(Icons.chat_bubble_outline, color: selected ? kTurquoise : _muted),
            title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${session.messages.length} رسالة', style: TextStyle(fontSize: 11, color: _muted)),
            onTap: () => _switchChat(session),
          ));
      })),
      Padding(padding: const EdgeInsets.all(22),
        child: Text('صنع خصيصاً لمرتضى ستار • 2026',
          style: TextStyle(color: _muted, fontSize: 12), textAlign: TextAlign.center)),
    ])),
  );

  Widget _chatPage() {
    final chat = _active;
    return Column(children: [
      SizedBox(height: 63, child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        children: _providers.entries.map((p) {
          final selected = chat.provider == p.key;
          return Padding(padding: const EdgeInsetsDirectional.only(end: 9), child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _sending ? null : () { setState(() => chat.provider = p.key); _persist(); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(30),
                color: selected ? kTurquoise.withValues(alpha: .16) : _surface,
                border: Border.all(color: selected ? kTurquoise.withValues(alpha: .62) : _line)),
              child: Row(children: [
                Icon(p.key == 'smart' ? Icons.auto_awesome_rounded : Icons.bolt_rounded,
                  size: 17, color: selected ? kTurquoise : _muted),
                const SizedBox(width: 6),
                Text(p.value, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? (_dark ? Colors.white : const Color(0xFF125B5B)) : _muted)),
              ]),
            ),
          ));
        }).toList(),
      )),
      Expanded(child: chat.messages.isEmpty ? _welcome() : ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: chat.messages.length + (_sending ? 1 : 0),
        itemBuilder: (_, index) {
          if (index == chat.messages.length) {
            return Align(
              alignment: Alignment.centerRight,
              child: Card(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('جاي أفكر...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              )),
            );
          }
          return _bubble(chat.messages[index]);
        },
      )),
      if (_image != null) Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        alignment: Alignment.centerRight,
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_image!, width: 76, height: 70, fit: BoxFit.cover)),
          Positioned(top: 0, left: 0, child: InkWell(
            onTap: () => setState(() => _image = null),
            child: const CircleAvatar(radius: 12, backgroundColor: Colors.black87,
              child: Icon(Icons.close, color: Colors.white, size: 15)),
          )),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: _line)),
          color: _dark ? const Color(0xFF0E182B) : const Color(0xFFF4F8FD),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(onPressed: _sending ? null : _pickImage, tooltip: 'إرفاق صورة', icon: const Icon(Icons.add_photo_alternate_outlined)),
          Expanded(child: TextField(
            controller: _input,
            minLines: 1, maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'اسألني أو اطلب مني مهمة...',
              contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            ),
          )),
          IconButton(
            onPressed: _toggleListen,
            tooltip: _listening ? 'إيقاف الاستماع' : 'اكتب بصوتك',
            icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Colors.redAccent : null),
          ),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            tooltip: 'إرسال',
            icon: const Icon(Icons.arrow_upward),
            style: IconButton.styleFrom(backgroundColor: const Color(0xFF178F86), foregroundColor: Colors.white),
          ),
        ]),
      ),
    ]);
  }

  Widget _welcome() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
    children: [
      Row(children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: kTurquoise, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(_endpoint.isEmpty ? 'جاهز للإعداد • اربط الذكاء أولاً' : 'إعدادات الربط محفوظة',
          style: TextStyle(color: _muted, fontSize: 12)),
      ]),
      const SizedBox(height: 17),
      ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Container(
          height: 249,
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topRight, end: Alignment.bottomLeft,
            colors: [Color(0xFF163A50), Color(0xFF172447), Color(0xFF36235B)])),
          child: Stack(children: [
            Positioned(left: -45, top: -74, child: Container(width: 198, height: 198,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: kTurquoise.withValues(alpha: .19), width: 28)))),
            Positioned(left: 1, bottom: -65, child: Container(width: 166, height: 166,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: kIndigo.withValues(alpha: .18), width: 25)))),
            Positioned(left: 23, top: 22,
              child: Icon(Icons.blur_on_rounded, color: Colors.white.withValues(alpha: .14), size: 86)),
            Padding(padding: const EdgeInsets.all(23),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(30)),
                  child: const Text('✦  مساعدك الذكي الخاص',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                const Spacer(),
                const Text('هلا مرتضى 👋', style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 5),
                const Text('شنو ننجز اليوم؟', style: TextStyle(color: Colors.white,
                  fontSize: 29, fontWeight: FontWeight.w900, height: 1.25)),
                const SizedBox(height: 9),
                const Text('اسأل، اكتب، تعلّم، وخلّي أفكارك تصير واقع.\nكلشي بمكان واحد.',
                  style: TextStyle(color: Color(0xFFE2EAF8), fontSize: 12.5, height: 1.55)),
              ])),
          ]),
        ),
      ),
      const SizedBox(height: 23),
      Row(children: [
        const Text('جرّب تسألني', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        Text('اختار فكرة وابدأ', style: TextStyle(color: _muted, fontSize: 11)),
      ]),
      const SizedBox(height: 12),
      _suggestion('اشرحلي مسألة هندسة مدنية خطوة بخطوة', Icons.architecture_rounded, const Color(0xFF40DBC3)),
      _suggestion('صمّم لي تطبيق أندرويد بشكل احترافي', Icons.code_rounded, const Color(0xFFAB93FF)),
      _suggestion('رتّب لي خطة دراسة ومراجعة للأسبوع', Icons.calendar_month_rounded, const Color(0xFFFFC37C)),
      _suggestion('ترجملي نص من العربي للإنجليزي', Icons.translate_rounded, const Color(0xFF89B8FF)),
      if (_endpoint.isEmpty) Padding(padding: const EdgeInsets.only(top: 9),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF178F86),
            foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
          onPressed: () => setState(() => _page = 2),
          icon: const Icon(Icons.link_rounded),
          label: const Text('ربط الذكاء الاصطناعي'),
        )),
    ],
  );

  Widget _suggestion(String message, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: () { _input.text = message; setState(() {}); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(19),
          border: Border.all(color: _line)),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(
            color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 23)),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          Icon(Icons.arrow_back_ios_new_rounded, color: _muted, size: 15),
        ]),
      ),
    ),
  );

  Widget _bubble(ChatEntry m) {
    final mine = m.role == 'user';
    final c = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        child: Card(
          color: mine ? const Color(0xFF254B66) : _surface,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(mine ? Icons.person_outline : Icons.auto_awesome,
                    size: 16, color: mine ? Colors.white70 : kTurquoise),
                const SizedBox(width: 6),
                Text(mine ? 'إنت' : 'Murtadha AI',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
                        color: mine ? Colors.white70 : c.onSurfaceVariant)),
              ]),
              if (m.hasImage) const Padding(
                padding: EdgeInsets.only(top: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.image_outlined, size: 18), SizedBox(width: 6), Text('صورة مرفقة'),
                ]),
              ),
              const SizedBox(height: 8),
              SelectableText(m.text, style: TextStyle(height: 1.65, fontSize: 14.5,
                  color: mine ? Colors.white : c.onSurface)),
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  onTap: () async { await Clipboard.setData(ClipboardData(text: m.text)); _notify('تم نسخ النص.'); },
                  child: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.copy_outlined,
                    size: 17, color: mine ? Colors.white70 : c.onSurfaceVariant)),
                ),
                if (!mine) InkWell(
                  onTap: () => _speak(m.text),
                  child: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.volume_up_outlined,
                    size: 18, color: c.onSurfaceVariant)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _toolsPage() {
    const tools = <(String, String, IconData, String)>[
      ('مساعد البرمجة', 'كود Flutter وواجهات', Icons.code, 'اكتبلي كود Flutter لتطبيق Android مرتب، واشرح خطوات تشغيله.'),
      ('مساعد الدراسة', 'شرح واختبارات', Icons.school, 'اشرح لي موضوع دراسي بشكل مبسط مع أمثلة ثم اختبرني بخمسة أسئلة.'),
      ('الترجمة', 'عربي وإنجليزي', Icons.translate, 'ترجم النص التالي إلى الإنجليزية بأسلوب طبيعي:\n'),
      ('تلخيص النصوص', 'تلخيص مرتب', Icons.summarize, 'لخّص النص التالي في نقاط واضحة واذكر أهم النتائج:\n'),
      ('خطة اليوم', 'جدول ومهام', Icons.today, 'رتب لي خطة اليوم حسب المهام التالية، مع أوقات مقترحة:\n'),
      ('كاتب الرسائل', 'صياغة احترافية', Icons.edit_note, 'اكتب لي رسالة محترمة وبأسلوب عراقي لطيف حول الموضوع التالي:\n'),
      ('شرح الصور', 'أرسل صورة', Icons.image_search, 'اشرحلي تفاصيل هذه الصورة بأسلوب واضح.'),
      ('مساعدة هندسية', 'خرسانة وكميات', Icons.architecture, 'ساعدني بمسألة هندسة مدنية واشرح القوانين والخطوات بالتفصيل:\n'),
    ];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      itemCount: tools.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemBuilder: (_, i) {
        if (i == tools.length) return Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.add_circle_outline, size: 30, color: kTurquoise),
            const SizedBox(height: 8),
            const Text('أدوات أكثر قريباً', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 7),
            Text('ربط خدمات ومهام فعلية', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ));
        final item = tools[i];
        return Card(child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _chooseTool(item.$4),
          child: Padding(padding: const EdgeInsets.all(15), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(item.$3, size: 30, color: kTurquoise),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.$1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(item.$2, style: TextStyle(fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ],
          )),
        ));
      },
    );
  }

  Widget _settingsPage() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('تشغيل الذكاء الاصطناعي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('ما تحتاج سيرفر ولا رمز دخول. مفتاح Gemini واحد يكفي لتشغيل الدردشة والصور.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('الخطوة 1: افتح Google AI Studio',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('افتح موقع إنشاء مفتاح Gemini'),
              onPressed: () async {
                final ok = await launchUrl(
                  Uri.parse('https://aistudio.google.com/apikey'),
                  mode: LaunchMode.externalApplication,
                );
                if (!ok) _notify('افتح aistudio.google.com/apikey من المتصفح.');
              },
            ),
            const SizedBox(height: 5),
            const SelectableText('https://aistudio.google.com/apikey',
                textDirection: TextDirection.ltr),
            const SizedBox(height: 5),
            const Text('اختر Create API Key ثم انسخ المفتاح من حسابك. لا تدز المفتاح لأي شخص.'),
            const SizedBox(height: 15),
            const Text('الخطوة 2: الصق مفتاح Gemini هنا',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _geminiKeyField,
              obscureText: _obscureToken,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(hintText: 'Gemini API Key', suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
                icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              )),
            ),
            const SizedBox(height: 11),
            FilledButton.icon(onPressed: _saveSettings,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('حفظ وتشغيل Gemini')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _testGemini,
                icon: const Icon(Icons.network_check),
                label: const Text('فحص مفتاح Gemini')),
            const SizedBox(height: 8),
            Text('المفتاح ينخزن بخزن أندرويد الآمن وينرسل إلى Google فقط مع أسئلتك. '
              'هذه طريقة مبسطة للاستعمال الشخصي؛ للتوزيع العام يفضّل سيرفر آمن.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
          ],
        ))),
        const SizedBox(height: 20),
        const Text('إعدادات متقدمة: ربط GPT وClaude عبر سيرفرك',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('رابط السيرفر', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 9),
            TextField(
              controller: _endpointField,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://your-worker.workers.dev'),
            ),
            const SizedBox(height: 16),
            const Text('رمز الدخول الشخصي', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 9),
            TextField(
              controller: _tokenField,
              textDirection: TextDirection.ltr,
              obscureText: _obscureToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(hintText: 'APP_ACCESS_TOKEN', suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
                icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              )),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _saveSettings,
                icon: const Icon(Icons.save_outlined), label: const Text('حفظ الإعدادات')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _testServer,
                icon: const Icon(Icons.network_check), label: const Text('فحص اتصال السيرفر')),
          ],
        ))),
        const SizedBox(height: 14),
        Card(child: SwitchListTile(
          title: const Text('الوضع الليلي'),
          subtitle: const Text('غيّر شكل التطبيق'),
          secondary: const Icon(Icons.dark_mode_outlined),
          value: _dark,
          onChanged: (value) async {
            setState(() => _dark = value);
            final pref = await SharedPreferences.getInstance();
            await pref.setBool('dark_mode', value);
          },
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: const Text('حذف سجل المحادثات'),
          subtitle: const Text('يحذف المحادثات المخزونة على جهازك فقط'),
          onTap: _clearHistory,
        )),
        const SizedBox(height: 18),
        Text('مهم: يجب تفعيل مفاتيح API في خدمة Worker قبل استعمال الدردشة. استخدام API قد يكلّف رسوماً منفصلة عن الاشتراكات المعتادة. سجل المحادثات يُحفظ محلياً كنص عادي، لذلك لا تضع فيه أسراراً حساسة.',
            style: TextStyle(fontSize: 12, height: 1.7,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        const Center(child: Text('Murtadha AI v1.0 • © Murtadha Sattar', style: TextStyle(fontSize: 12))),
      ]);
}
