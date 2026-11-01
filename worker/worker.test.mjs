import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './src.js';

const url = 'https://murtadha-ai.workers.dev/chat';
const env = {APP_ACCESS_TOKEN:'abcdefghijklmnopqrstuvwxyz123456', GEMINI_API_KEY:'test-gemini', OPENAI_API_KEY:'test-openai', ANTHROPIC_API_KEY:'test-claude'};
function req(payload, token=env.APP_ACCESS_TOKEN) {
  return new Request(url, {method:'POST',headers:{authorization:`Bearer ${token}`, 'content-type':'application/json'},body:JSON.stringify(payload)});
}
function message(provider, image) {
  return {provider,messages:[{role:'user',text:'هلو شلونك',...(image ? {image:{mime:'image/jpeg',base64:'aGVsbG8='}} : {})}]};
}

test('health does not expose credentials', async () => {
  const response = await worker.fetch(new Request('https://murtadha-ai.workers.dev/health'), env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).ok, true);
});

test('rejects unauthorized requests and missing server configuration', async () => {
  assert.equal((await worker.fetch(req(message('gemini'), 'wrong'), env)).status, 401);
  assert.equal((await worker.fetch(req(message('gemini')), {...env,APP_ACCESS_TOKEN:''})).status, 503);
});

test('rejects bad providers and invalid images', async () => {
  assert.equal((await worker.fetch(req(message('bad')), env)).status, 400);
  const r = await worker.fetch(req({provider:'gemini',messages:[{role:'user',text:'abc',image:{mime:'image/svg+xml',base64:'abc'}}]}), env);
  assert.equal(r.status, 400);
});

test('Gemini: use server-side key and return text', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (target, options) => {
    assert.match(target, /generativelanguage\.googleapis\.com/);
    assert.equal(options.headers['x-goog-api-key'], env.GEMINI_API_KEY);
    const body = JSON.parse(options.body);
    assert.equal(body.contents[0].parts[0].text.includes('هلو شلونك'), true);
    return Response.json({candidates:[{content:{parts:[{text:'أهلاً بيك'}]}}]});
  };
  try {
    const r = await worker.fetch(req(message('gemini')), env);
    assert.equal(r.status, 200);
    assert.equal((await r.json()).answer, 'أهلاً بيك');
  } finally {globalThis.fetch = original;}
});

test('GPT Responses: body format and parse output', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (_, options) => {
    assert.equal(options.headers.authorization, `Bearer ${env.OPENAI_API_KEY}`);
    const body=JSON.parse(options.body);
    assert.equal(body.store, false);
    assert.equal(body.input[0].content[0].type, 'input_text');
    return Response.json({model:'gpt-6-luna',output:[{type:'message',content:[{type:'output_text',text:'رد GPT'}]}]});
  };
  try {
    const r=await worker.fetch(req(message('openai')),env);
    assert.equal(r.status,200);
    assert.equal((await r.json()).answer,'رد GPT');
  } finally {globalThis.fetch = original;}
});

test('Claude: sends image as base64 source and parses response', async () => {
  const original=globalThis.fetch;
  globalThis.fetch=async (_, options)=>{
    const body=JSON.parse(options.body);
    assert.equal(body.messages[0].content[1].source.type,'base64');
    assert.equal(body.messages[0].content[1].source.media_type,'image/jpeg');
    return Response.json({content:[{type:'text',text:'الصورة واضحة'}]});
  };
  try {
    const r=await worker.fetch(req(message('claude',true)),env);
    assert.equal(r.status,200);
    assert.equal((await r.json()).answer,'الصورة واضحة');
  } finally {globalThis.fetch=original;}
});

test('missing provider API key produces setup message', async () => {
  const r=await worker.fetch(req(message('openai')),{APP_ACCESS_TOKEN:env.APP_ACCESS_TOKEN});
  assert.equal(r.status,503);
  assert.match((await r.json()).error,/OpenAI/);
});
