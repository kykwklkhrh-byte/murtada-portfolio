/** Murtadha AI private gateway for Cloudflare Workers.
 * No provider keys are shipped inside the Android app.
 * The app sends a separate private bearer access token.
 */

const SYSTEM_PROMPT = `You are Murtadha AI, a helpful, accurate personal assistant.
Reply in the user's language. When the user writes Iraqi Arabic, use clear natural Iraqi Arabic.
Help with studying, civil engineering, programming, planning and everyday tasks.
Be honest about limits: never pretend to have executed a real-world action, sent a message,
or browsed the web. Do not invent sources. Ask for permission before impactful actions.`;
const MAX_REQUEST_BYTES = 2_000_000;
const MAX_TEXT = 12_000;

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
      'x-content-type-options': 'nosniff' },
  });
}
function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  let diff = a.length ^ b.length;
  const size = Math.max(a.length, b.length);
  for (let i = 0; i < size; i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}
function briefError(responseStatus) {
  if (responseStatus === 401 || responseStatus === 403) return 'مفتاح مزود الذكاء غير صحيح أو ليس لديه صلاحية.';
  if (responseStatus === 402 || responseStatus === 429) return 'رصيد أو حد استخدام خدمة الذكاء الاصطناعي لا يسمح بالطلب حالياً.';
  return `تعذر الاتصال بخدمة الذكاء الاصطناعي (HTTP ${responseStatus}).`;
}
function normalizeMessages(data) {
  if (!Array.isArray(data.messages) || !data.messages.length) throw new Error('اكتب رسالتك أولاً.');
  return data.messages.slice(-18).map((m) => {
    const role = m.role === 'assistant' ? 'assistant' : 'user';
    const text = String(m.text ?? '').slice(0, MAX_TEXT);
    let image;
    if (role === 'user' && m.image && typeof m.image === 'object') {
      const mime = m.image.mime;
      const base64 = m.image.base64;
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(mime) ||
          typeof base64 !== 'string' || base64.length > 1_400_000 ||
          !/^[A-Za-z0-9+/]*={0,2}$/.test(base64)) {
        throw new Error('الصورة غير مدعومة أو كبيرة. جرّب صورة أصغر من 1MB.');
      }
      image = {mime, base64};
    }
    return {role, text, ...(image ? {image} : {})};
  });
}
function makeTranscript(messages) {
  return messages.map(m => `${m.role === 'user' ? 'المستخدم' : 'المساعد'}: ${m.text}${m.image ? ' [أرفق صورة]' : ''}`).join('\n\n');
}
async function providerRequest(provider, messages, env) {
  const lastImage = [...messages].reverse().find(m => m.role === 'user' && m.image)?.image;
  const prompt = SYSTEM_PROMPT + '\n\n--- سجل المحادثة ---\n' + makeTranscript(messages) + '\n\nأجب على آخر رسالة للمستخدم.';
  let url, headers, body;
  if (provider === 'gemini') {
    if (!env.GEMINI_API_KEY) throw new Error('مفتاح Gemini غير مضاف للسيرفر.');
    const model = env.GEMINI_MODEL || 'gemini-3.5-flash-lite';
    url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
    headers = {'x-goog-api-key': env.GEMINI_API_KEY, 'content-type':'application/json'};
    body = {contents: [{role:'user', parts: [{text:prompt}, ...(lastImage ? [{inline_data: {mime_type: lastImage.mime, data: lastImage.base64}}] : [])]}]};
  } else if (provider === 'openai') {
    if (!env.OPENAI_API_KEY) throw new Error('مفتاح OpenAI غير مضاف للسيرفر.');
    url = 'https://api.openai.com/v1/responses';
    headers = {authorization: `Bearer ${env.OPENAI_API_KEY}`, 'content-type':'application/json'};
    body = {model: env.OPENAI_MODEL || 'gpt-6-luna', store: false, max_output_tokens: 4096,
      input: [{role: 'user', content: [ {type:'input_text',text:prompt},
        ...(lastImage ? [{type:'input_image',image_url: `data:${lastImage.mime};base64,${lastImage.base64}`}] : []) ]}]};
  } else if (provider === 'claude') {
    if (!env.ANTHROPIC_API_KEY) throw new Error('مفتاح Claude غير مضاف للسيرفر.');
    url = 'https://api.anthropic.com/v1/messages';
    headers = {'x-api-key':env.ANTHROPIC_API_KEY, 'anthropic-version':'2023-06-01', 'content-type':'application/json'};
    body = {model: env.CLAUDE_MODEL || 'claude-haiku-5-5', max_tokens: 2048,
      messages: [{role:'user', content: [ {type:'text',text:prompt},
        ...(lastImage ? [{type:'image',source:{type:'base64', media_type:lastImage.mime, data:lastImage.base64}}] : []) ]}]};
  } else throw new Error('مزود غير معروف.');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 55_000);
  try {
    const res = await fetch(url, {method:'POST', headers, body:JSON.stringify(body), signal:controller.signal});
    if (!res.ok) return {status: 502, error: briefError(res.status)};
    const data = await res.json();
    let answer;
    if (provider === 'gemini') {
      answer = (data.candidates?.[0]?.content?.parts || []).filter(p => typeof p.text === 'string' && p.thought !== true).map(p => p.text).join('\n');
    } else if (provider === 'openai') {
      answer = (data.output || []).filter(o => o.type === 'message')
        .flatMap(o => o.content || []).filter(c => c.type === 'output_text').map(c => c.text || '').join('\n');
    } else {
      answer = (data.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
    }
    if (!answer?.trim()) return {status:502, error:'رجع رد فارغ من المزود. جرّب سؤال أبسط.'};
    return {status:200, answer: answer.slice(0, 60_000), model: data.model || provider};
  } catch (err) {
    return {status:502, error: err?.name === 'AbortError' ? 'انتهت مهلة الاتصال بالمزود، جرّب مرة ثانية.' : 'فشل الاتصال بمزود الذكاء، تحقق من الشبكة.'};
  } finally { clearTimeout(timeout); }
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/health') return json({ok:true, app:'Murtadha AI', version:'1.0.0'});
    if (path !== '/chat') return json({error:'Not found'}, 404);
    if (request.method !== 'POST') return json({error:'Method not allowed'}, 405);
    if (!env.APP_ACCESS_TOKEN || env.APP_ACCESS_TOKEN.length < 20) {
      return json({error:'السيرفر غير مهيّأ: يجب ضبط APP_ACCESS_TOKEN بطول 20 حرفاً على الأقل.'}, 503);
    }
    const auth = request.headers.get('authorization') || '';
    if (!safeEqual(auth, `Bearer ${env.APP_ACCESS_TOKEN}`)) return json({error:'رمز الدخول غير صحيح.'}, 401);
    if (Number(request.headers.get('content-length') || 0) > MAX_REQUEST_BYTES) return json({error:'الرسالة أو الصورة كبيرة جداً.'}, 413);
    let raw;
    try { raw = await request.text(); } catch { return json({error:'تعذّر قراءة الطلب.'}, 400); }
    if (raw.length > MAX_REQUEST_BYTES) return json({error:'الرسالة أو الصورة كبيرة جداً.'}, 413);
    let data, messages;
    try { data = JSON.parse(raw); messages = normalizeMessages(data); }
    catch (e) { return json({error:e?.message || 'بيانات غير صحيحة.'}, 400); }
    const provider = data.provider;
    if (!['gemini','openai','claude'].includes(provider)) return json({error:'اختر مزوداً صحيحاً.'}, 400);
    try {
      const r = await providerRequest(provider, messages, env);
      return r.error ? json({error:r.error}, r.status) : json({answer:r.answer, model:r.model});
    } catch (e) { return json({error: e?.message || 'خطأ إعدادات السيرفر.'}, 503); }
  },
};
