from pathlib import Path

p = Path("lib/chat_screen.dart")
s = p.read_text()
def swap(old, new):
    global s
    if old not in s:
        raise RuntimeError("Patch target not found: " + old[:80])
    s = s.replace(old, new, 1)

swap("import 'package:firebase_auth/firebase_auth.dart';",
     "import 'package:firebase_auth/firebase_auth.dart';\nimport 'package:firebase_core/firebase_core.dart';")
swap("  bool _loading = true, _sending = false, _processing = false;",
     "  bool _loading = true, _sending = false, _processing = false;\n"
     "  double? _uploadProgress;\n  String _uploadStage = 'تهيئة المرفق';")
start = s.index("  Future<String> _uploadEncrypted(")
end = s.index("  Future<void> _sendAttachment(", start)
s = s[:start] + r'''  String _uploadFailure(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code.contains('unauthorized') || code.contains('unauthenticated')) {
        return 'المخزن رفض صلاحية الرفع ($code). افتح Storage > Rules وانشر قواعد غرفتك الخاصة.';
      }
      if (code.contains('bucket-not-found') || code.contains('no-default-bucket') || code.contains('project-not-found')) {
        return 'مخزن Storage غير مفعّل ($code). يجب إنشاء المخزن داخل مشروع Firebase.';
      }
      if (code.contains('quota-exceeded')) {
        return 'تجاوزت سعة Firebase Storage أو تحتاج إعداد فوترة Blaze ($code).';
      }
      if (code.contains('retry-limit-exceeded') || code.contains('canceled')) {
        return 'تعذر اكتمال الرفع ($code). تحقق من الشبكة وجرب مرة ثانية.';
      }
      final detail = error.message?.toLowerCase() ?? '';
      if (detail.contains('billing') || detail.contains('blaze') || detail.contains('402') || detail.contains('403')) {
        return 'خدمة Firebase Storage تحتاج تفعيل خطة Blaze وربط الفوترة قبل رفع الملفات.';
      }
      return 'خطأ Firebase Storage ($code). تأكد من تشغيل Storage وقواعده الخاصة.';
    }
    if (error is StateError) return error.message.toString();
    if (error is SocketException) return 'الإنترنت غير متصل. تأكد من الشبكة ثم أعد الإرسال.';
    return 'تعذر رفع الملف. افحص Firebase Storage وخطة Blaze وصلاحيات غرفة الدردشة.';
  }

  Future<String> _uploadEncrypted(Uint8List bytes, String name) async {
    if (_roomId == null || _uid == null || _messageKey == null) throw StateError('ادخل غرفة الدردشة أولاً');
    if (bytes.isEmpty) throw StateError('الملف فارغ');
    if (bytes.length > _maxAttachmentBytes) throw StateError('الملف أكبر من 18 ميگابايت؛ اختَر حجماً أصغر');
    final bucket = Firebase.app().options.storageBucket;
    if (bucket == null || bucket.isEmpty) {
      throw StateError('مخزن Storage غير محدد بإعدادات التطبيق. حمّل آخر إصدار.');
    }
    final random = Random.secure();
    final id = '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
    final path = 'rooms/$_roomId/$_uid/$id.enc';
    if (mounted) setState(() { _uploadStage = 'جاري تشفير الملف'; _uploadProgress = null; });
    final encrypted = await _encryptBytes(bytes);
    if (encrypted.length > 19000000) throw StateError('تجاوز حجم الملف المشفّر حد الرفع');
    final task = _storage.ref(path).putData(encrypted, SettableMetadata(contentType: 'application/octet-stream'));
    final subscription = task.snapshotEvents.listen((snapshot) {
      if (!mounted || !_processing || snapshot.totalBytes == 0) return;
      setState(() {
        _uploadStage = 'جاري رفع المرفق المشفّر';
        _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
      });
    });
    try {
      await task;
      return path;
    } finally {
      await subscription.cancel();
    }
  }

''' + s[end:]

swap("    setState(() => _processing = true);\n    String? path;\n    try {\n      path = await _uploadEncrypted(bytes, name);",
     "    setState(() { _processing = true; _uploadProgress = null; _uploadStage = 'تهيئة المرفق'; });\n"
     "    String? path;\n    try {\n      path = await _uploadEncrypted(bytes, name);\n"
     "      if (mounted) setState(() { _uploadStage = 'جاري إرسال الرسالة'; _uploadProgress = null; });")
swap("""    } catch (e) {
      if (path != null) { try { await _storage.ref(path).delete(); } catch (_) {} }
      _notice('تعذّر رفع المرفق. تأكد من تفعيل Firebase Storage وقواعدها.');
    } finally { if (mounted) setState(() => _processing = false); }""",
"""    } catch (e) {
      if (path != null) { try { await _storage.ref(path).delete(); } catch (_) {} }
      final info = path != null && e is FirebaseException && e.plugin == 'cloud_firestore'
          ? 'الملف ارتفع، لكن قاعدة الرسائل رفضت إرساله (${e.code}). راجع قواعد Firestore.'
          : _uploadFailure(e);
      if (mounted) await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('تعذر إرسال المرفق'),
        content: Text(info),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ));
    } finally { if (mounted) setState(() { _processing = false; _uploadProgress = null; }); }""")
swap("    } catch (e) { _notice('تعذر فتح المرفق: $e'); }",
     "    } catch (e) { _notice('تعذر فتح المرفق: ${_uploadFailure(e)}'); }")
swap("      if (_processing) const LinearProgressIndicator(),",
"""      if (_processing) Column(children: [
        LinearProgressIndicator(value: _uploadProgress),
        const SizedBox(height: 5),
        Text(_uploadStage, style: const TextStyle(fontSize: 12)),
      ]),""")
p.write_text(s)
pubspec = Path("pubspec.yaml")
ptext = pubspec.read_text()
assert "version: 3.0.0+6" in ptext
pubspec.write_text(ptext.replace("version: 3.0.0+6", "version: 3.1.0+7"))
print("v3.1 attachment repair applied")
