// scripts/generate-style-previews.mjs
//
// TEK SEFERLİK: 6 stil × 6 oda = 36 stil önizleme görseli üret, Supabase
// Storage'a yükle, sonuçları stdout'a JSON map olarak yaz.
//
// Kullanım:
//   cd koala-api
//   node scripts/generate-style-previews.mjs
//
// Env: .env.local'den GEMINI_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY okunur.

import { createClient } from '@supabase/supabase-js';
import fs from 'node:fs';
import path from 'node:path';

// .env.local oku
const envPath = path.join(process.cwd(), '.env.local');
if (fs.existsSync(envPath)) {
  const txt = fs.readFileSync(envPath, 'utf8');
  for (const line of txt.split('\n')) {
    const m = line.match(/^([A-Z_][A-Z0-9_]*)="?(.*?)"?$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!GEMINI_API_KEY) throw new Error('GEMINI_API_KEY missing');
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const BUCKET = 'style-previews';

const RENDER_MODEL = 'gemini-2.5-flash-image';
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${RENDER_MODEL}:generateContent`;

const ROOMS = [
  { key: 'living_room', en: 'living room' },
  { key: 'bedroom', en: 'bedroom' },
  { key: 'kitchen', en: 'kitchen' },
  { key: 'bathroom', en: 'bathroom' },
  { key: 'dining_room', en: 'dining room' },
  { key: 'office', en: 'home office' },
];

const STYLES = [
  { key: 'minimalist', en: 'Minimalist', tag: 'clean lines, neutral palette, very few decor objects' },
  { key: 'scandinavian', en: 'Scandinavian', tag: 'light wood, white walls, cozy textiles, warm hygge' },
  { key: 'japandi', en: 'Japandi', tag: 'wabi-sabi, low furniture, muted earth tones, calm' },
  { key: 'modern', en: 'Modern', tag: 'sleek lines, glass and metal, monochrome with bold accent' },
  { key: 'bohemian', en: 'Bohemian', tag: 'patterned textiles, plants, layered rugs, warm earthy colors' },
  { key: 'industrial', en: 'Industrial', tag: 'exposed brick, concrete, dark metal, edison bulbs, raw' },
];

function buildPrompt(style, room) {
  return (
    `A photorealistic interior photograph of a beautiful ${style.en} ${room.en}. ` +
    `${style.tag}. ` +
    `The image MUST clearly show this is a ${room.en} (with all the typical fixtures of a ${room.en}). ` +
    `Editorial Architectural Digest aesthetic, natural daylight, soft shadows, ` +
    `8k high detail, no people, no text, no watermarks, square 1:1 framing.`
  );
}

async function ensureBucket() {
  const { data: buckets, error } = await sb.storage.listBuckets();
  if (error) throw error;
  if (!buckets.find((b) => b.name === BUCKET)) {
    const { error: cErr } = await sb.storage.createBucket(BUCKET, { public: true });
    if (cErr) throw cErr;
    console.log(`Bucket created: ${BUCKET}`);
  }
}

async function renderOne(style, room) {
  const prompt = buildPrompt(style, room);
  const res = await fetch(`${ENDPOINT}?key=${GEMINI_API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['IMAGE'], temperature: 0.85 },
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`gemini_${res.status}: ${t.slice(0, 200)}`);
  }
  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  const imgPart = parts.find((p) => p?.inlineData?.data || p?.inline_data?.data);
  const b64 = imgPart?.inlineData?.data ?? imgPart?.inline_data?.data;
  if (!b64) throw new Error('no_image_in_response');
  return Buffer.from(b64, 'base64');
}

async function uploadOne(buf, style, room) {
  const filename = `${style.key}-${room.key}.png`;
  const { error } = await sb.storage
    .from(BUCKET)
    .upload(filename, buf, {
      contentType: 'image/png',
      upsert: true,
      cacheControl: '2592000',
    });
  if (error) throw error;
  const { data } = sb.storage.from(BUCKET).getPublicUrl(filename);
  return data.publicUrl;
}

async function processCombo(style, room, attempt = 1) {
  try {
    process.stdout.write(`  ${style.key}/${room.key} … `);
    const buf = await renderOne(style, room);
    const url = await uploadOne(buf, style, room);
    console.log(`OK (${(buf.byteLength / 1024).toFixed(0)} KB)`);
    return { style: style.key, room: room.key, url };
  } catch (err) {
    if (attempt < 3) {
      console.log(`retry ${attempt} (${err.message})`);
      await new Promise((r) => setTimeout(r, 4000 * attempt));
      return processCombo(style, room, attempt + 1);
    }
    console.log(`FAIL ${err.message}`);
    return { style: style.key, room: room.key, url: null, error: err.message };
  }
}

async function runWithConcurrency(items, n, fn) {
  const results = [];
  let i = 0;
  async function worker() {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx]);
    }
  }
  await Promise.all(Array.from({ length: n }, worker));
  return results;
}

async function main() {
  await ensureBucket();

  const combos = [];
  for (const s of STYLES) for (const r of ROOMS) combos.push({ s, r });

  console.log(`Generating ${combos.length} style preview images (3 parallel)...\n`);
  const out = await runWithConcurrency(combos, 3, ({ s, r }) => processCombo(s, r));

  const map = {};
  for (const r of out) {
    if (!r.url) continue;
    map[r.style] = map[r.style] || {};
    map[r.style][r.room] = r.url;
  }

  const outPath = path.join(process.cwd(), 'scripts', 'style_previews.json');
  fs.writeFileSync(outPath, JSON.stringify(map, null, 2), 'utf8');
  console.log(`\nWrote ${outPath}`);

  const failed = out.filter((r) => !r.url);
  if (failed.length) {
    console.log(`\n${failed.length} failed:`);
    for (const f of failed) console.log(`  - ${f.style}/${f.room}: ${f.error}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
