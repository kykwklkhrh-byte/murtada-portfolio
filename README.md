# Murtadha AI — مرتضى AI (Aurora Edition)

**مساعد ذكاء اصطناعي شخصي لأندرويد، بواجهة Aurora داكنة/فاتحة مخصصة مكتوبة بـ Flutter.**

## ما الذي يعمل في النسخة الأولى؟

- واجهة عربية RTL، وضع ليلي/نهاري، اسم وحقوق Murtadha Sattar.
- محادثة فعلية عبر GPT وGemini وClaude (بعد ربط API keys الخاصة بك بالسيرفر).
- الوضع التلقائي: يختار Gemini لمعظم الأسئلة وClaude للأسئلة التي تبدو برمجية. **اختيار مبدئي بسيط، وليس ذكاءً خارقاً**.
- سجل محادثات محلي، محادثة جديدة، نسخ النص، قراءة الرد بصوت Android TTS.
- إملاء صوتي عبر خدمة التعرف على الكلام في الجهاز (يدعم اللغة حسب محرك الجهاز).
- إرفاق صورة مضغوطة حتى نحو 900KB واستفسار عنها.
- 8 أدوات جاهزة تملأ خانة الطلب: هندسة، دراسة، برمجة، ترجمة، تلخيص، كتابة، صور، خطة يوم.
- رمز الدخول الشخصي محفوظ في تخزين الجهاز الآمن، ومفاتيح API تبقى على Cloudflare Worker فقط.

**ليس متاحاً بعد**: التحكم التلقائي بالتطبيقات/الهاتف، تنفيذ المهام بدون إذن، بحث الإنترنت المباشر، تحويل الإجابة إلى APK، إنشاء صور، إرسال الرسائل آلياً، فتح ملفات PDF. أدوات «البرمجة/الدراسة» حالياً قوالب جاهزة لبدء المحادثة. هذا المشروع مصدر أولي ولم يتم تشغيله كـ APK في بيئة إعداد الملفات.

## أولاً: إعداد خدمة الذكاء Cloudflare Workers

يمكن ضبط السيرفر من متصفح الموبايل بلا تثبيت أي برنامج:

1. افتح [Cloudflare Dashboard](https://dash.cloudflare.com/) ثم **Workers & Pages**.
2. اضغط **Create Worker** وأنشئ عامل Worker باسم مثل `murtadha-ai-private`.
3. افتح **Edit code** والصق محتوى [`worker/src.js`](worker/src.js) كاملاً، ثم **Deploy**.
4. افتح Worker → **Settings** → **Variables and Secrets**. أضف كل قيمة بالنوع **Secret** وليس نصاً عاماً:
   - `APP_ACCESS_TOKEN`: كلمة مرور عشوائية طويلة **20 حرفاً على الأقل**، ويفضل 32+؛ مثال للتوضيح فقط وليس للاستخدام `REPLACE_WITH_YOUR_OWN_LONG_RANDOM_TOKEN`.
   - `GEMINI_API_KEY`: مفتاح Google AI Studio من <https://aistudio.google.com/apikey>.
   - `OPENAI_API_KEY`: مفتاح OpenAI Platform من <https://platform.openai.com/api-keys>.
   - `ANTHROPIC_API_KEY`: مفتاح Anthropic Console من <https://console.anthropic.com/>.
5. يمكنك تشغيل التطبيق بمفتاح **Gemini فقط** إذا كنت تستعمل Gemini؛ إضافة الآخرين اختيارية. ستظهر رسالة إعدادات مفهومة عند اختيار مزود بلا مفتاح.
6. انسخ رابط `https://YOUR-WORKER.workers.dev` واحتفظ بالرمز الذي أنشأته. لا تنشر الرمز أو مفاتيح الخدمات في مستودع GitHub، ولا تشاركها بالمحادثة.
7. افتح تطبيق Murtadha AI → **الإعدادات** → الصق رابط Worker و`APP_ACCESS_TOKEN` → **حفظ** ثم ابدأ الدردشة.

للتحكم بنموذج كل مزود، يمكنك إضافة متغيرات Worker اختيارية: `GEMINI_MODEL` (الافتراضي `gemini-3.5-flash-lite`)، `OPENAI_MODEL` (الافتراضي `gpt-6-luna`)، `CLAUDE_MODEL` (الافتراضي `claude-haiku-5-5`). يلزم أن يكون النموذج متاحاً ضمن رصيد حساب API.

## ثانياً: بناء APK من GitHub بدون ضغط اللابتوب

1. المشروع مرفوع على فرع `murtadha-ai-app` في مستودع `kykwklkhrh-byte/murtada-portfolio`، بدون تعديل الفرع `main`.
2. افتح **Actions** واختر **Build Murtadha AI APK**؛ يتم البناء تلقائياً عند إرسال تحديث للفرع إذا كانت Actions مفعّلة.
3. يمكنك أيضاً تشغيل **Run workflow** واختيار الفرع `murtadha-ai-app` عندما يكون GitHub يعرض هذا الخيار.
4. عندما تنتهي عملية البناء بنجاح، افتح الـ run، وتحت **Artifacts** نزّل `Murtadha-AI-APK`.
5. ملف Artifacts يُنزّل كـ ZIP؛ افتحه وستجد داخله `app-release.apk`. انقله للموبايل وثبّته.

> الملف `app-release.apk` بعد GitHub Actions موقع بمفتاح debug الخاص ببيئة Flutter (توقيع تلقائي للبناء release في القالب الافتراضي)، مناسب للتجربة الشخصية وليس لتوزيع تطبيق احترافي عبر متجر Google Play. يلزم توقيع إصدار رسمي بمفتاح خاص قبل النشر العام.

### البناء على حاسوب عليه Flutter

```bash
flutter create --platforms=android --org com.murtadha --project-name murtadha_ai .
python scripts/patch_manifest.py
flutter pub get
flutter analyze
flutter build apk --release
```

الـ APK النهائي في `build/app/outputs/flutter-apk/app-release.apk` بعد نجاح البناء.

### اختبار كود السيرفر محلياً (لمن عنده Node.js)

```bash
cd worker
node --test worker.test.mjs
```

## نقاط الأمان والخصوصية

- رمز الدخول المخزن في Android Keystore ليس بديلاً عن نظام مستخدمين كامل؛ هذه نسخة **شخصية** لمستخدم واحد. لا تنشر Worker URL ورمز الدخول معاً، ولا تستخدم الرمز نفسه في مواقع أخرى.
- API keys مُحفوظة كـ Cloudflare Secrets. لا تضع مفاتيح API في `lib/main.dart` أو `pubspec.yaml`.
- سِجل المحادثة يُحفظ **محلياً كنص غير مشفّر** عبر SharedPreferences، لذلك تجنب إرسال بيانات شديدة الحساسية؛ يمكنك حذفه من داخل التطبيق.
- الصور لا تُحفظ في سجل المحادثات المحلي بعد إغلاق التطبيق؛ النصوص فقط تُحفظ.
- Worker لا يُسجل الرسائل ولا يخزنها في قواعد بيانات، لكنه يرسلها إلى مزوّد الذكاء الذي اخترته. راجع سياساتهم قبل استخدام معلومات حساسة.
- Worker يتحقق من رمز الوصول، يرفض طلبات الحجم الكبير، ويحدّ النصوص المتبادلة. **ليس بعد نظاماً للإنتاج واسع النطاق**: أضف rate limiting ومصادقة متعددة المستخدمين ومراقبة تكاليف إن نشرت التطبيق للآخرين.
- حسابات ChatGPT Plus/Gemini/Claude العادية لا تغني بالضرورة عن استخدام API، وقد تكون هناك رسوم وقيود حسب حسابك.

## الملفات

```text
lib/main.dart                      Flutter UI and client
pubspec.yaml                      Flutter dependencies
worker/src.js                     Cloudflare Worker API gateway
worker/wrangler.toml              Optional CLI deployment config
worker/worker.test.mjs            Server tests
scripts/patch_manifest.py        Android permissions and app label
.github/workflows/build-apk.yml   GitHub Actions automated APK build
```

© 2026 Murtadha Sattar — project starter intended for personal use.
