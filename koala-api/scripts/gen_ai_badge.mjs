// One-off: generate a small, clean "Koala AI" badge emblem with Gemini,
// resize to a tiny square webp and upload to koala-seed/icons/ai-badge.webp.
// Run from koala-api/:  node scripts/gen_ai_badge.mjs
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import { createClient } from '@supabase/supabase-js';

function readEnv(key) {
  const txt = fs.readFileSync(path.join(process.cwd(), '.env.local'), 'utf8');
  for (const line of txt.split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m && m[1] === key) return m[2].replace(/^["']|["']$/g, '').trim();
  }
  return '';
}
const apiKey = readEnv('GEMINI_API_KEY');
const sb = createClient(readEnv('SUPABASE_URL'), readEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});
const MODEL = process.env.HERO_MODEL || 'gemini-3-pro-image-preview';

const prompt = `A minimal, modern app-style ICON emblem for "Koala AI".
Design: a cute, simplified koala face combined with a subtle AI sparkle/star
accent. Flat vector look, clean geometric shapes, soft rounded square badge.
Single tasteful soft gradient using calm violet→indigo tones on a clean
background, gentle and premium. Centered, lots of padding, perfectly symmetric.
Simple and elegant — NOT busy, NO text, NO letters, NO clutter, NO photo.
Looks great at tiny sizes (like a 24px badge). High contrast, crisp edges.`;

const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
const res = await fetch(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { responseModalities: ['IMAGE'] },
  }),
});
if (!res.ok) { console.error('HTTP', res.status, (await res.text()).slice(0, 400)); process.exit(1); }
const j = await res.json();
const part = (j?.candidates?.[0]?.content?.parts ?? []).find((p) => p.inlineData?.data);
if (!part) { console.error('no image', JSON.stringify(j).slice(0, 400)); process.exit(1); }
const raw = Buffer.from(part.inlineData.data, 'base64');
// Kare, 144px (retina için), webp q82 — küçük ama net.
const webp = await sharp(raw).resize(144, 144, { fit: 'cover' }).webp({ quality: 82 }).toBuffer();
const key = 'icons/ai-badge-v1.webp';
const { error } = await sb.storage.from('koala-seed').upload(key, webp, {
  contentType: 'image/webp', upsert: true, cacheControl: '31536000',
});
if (error) { console.error('upload error:', error.message); process.exit(1); }
const { data: pub } = sb.storage.from('koala-seed').getPublicUrl(key);
console.log(`OK ${(webp.length / 1024).toFixed(1)}KB → ${pub.publicUrl}`);
