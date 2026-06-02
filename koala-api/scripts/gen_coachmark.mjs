// One-off: generate 6 coachmark banner images with Gemini (Nano Banana),
// optimize to a small ~3:1 WEBP and upload to koala-seed/coachmark/.
// Run from koala-api/:  node scripts/gen_coachmark.mjs
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
if (!apiKey) { console.error('No GEMINI_API_KEY'); process.exit(1); }
const sb = createClient(readEnv('SUPABASE_URL'), readEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});

const MODEL = process.env.HERO_MODEL || 'gemini-3-pro-image-preview';

// Ortak stil: koala app'in sıcak, premium, mor TİNT İÇERMEYEN estetiği.
// 3:1 yatay banner; alt kısım sakin (karta otursun); insan/yazı/logo YOK.
const STYLE = `Editorial, premium interior-design photography aesthetic. Warm
neutral palette (cream, sand, soft taupe, light oak wood), bright airy natural
light, shallow depth of field, magazine quality. Wide ~3:1 horizontal banner
composition, subject centered, calm uncluttered edges. ABSOLUTELY NO purple or
violet tint, NO people, NO text, NO logos, NO watermark, NO UI elements.`;

const STEPS = [
  { file: 'home-v1', prompt: `A beautifully styled modern living room interior, warm Scandinavian/Japandi, cozy sofa, plants, large sunlit window. ${STYLE}` },
  { file: 'chat-v1', prompt: `A serene, minimalist designer's desk corner with a laptop, a mood board with fabric/material swatches and color samples, a small plant and a coffee cup, soft daylight. Suggests conversation/collaboration with an interior designer. ${STYLE}` },
  { file: 'paylas-v1', prompt: `A smartphone lying on a light wooden table showing a softly blurred photo of a room, next to interior material samples and a small plant — implying sharing/uploading a room photo for redesign. ${STYLE}` },
  { file: 'ai-v1', prompt: `A flat-lay of interior design tools on a cream surface: paint color swatches/fan deck, fabric samples, a small brush, a mood board — creative AI design toolkit vibe. ${STYLE}` },
  { file: 'profile-v1', prompt: `A tasteful styled shelf/vignette in a warm modern home: framed neutral art, ceramics, a small plant and books on light oak — personal, curated, profile-like. ${STYLE}` },
  { file: 'bell-v1', prompt: `A calm cozy corner of a warm modern living room with soft morning light through sheer curtains, a small side table with a candle and plant — gentle, notification-calm mood. ${STYLE}` },
];

async function genOne(prompt) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['IMAGE'] },
    }),
  });
  if (!res.ok) throw new Error(`gemini ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const j = await res.json();
  const parts = j?.candidates?.[0]?.content?.parts ?? [];
  const imgPart = parts.find((p) => p.inlineData?.data);
  if (!imgPart) throw new Error('no image: ' + JSON.stringify(j).slice(0, 300));
  return Buffer.from(imgPart.inlineData.data, 'base64');
}

for (const step of STEPS) {
  try {
    process.stdout.write(`gen ${step.file} ... `);
    const raw = await genOne(step.prompt);
    // 3:1 banner, retina için ~840x280, webp q72 → küçük & hızlı.
    const webp = await sharp(raw)
      .resize(840, 280, { fit: 'cover', position: 'attention' })
      .webp({ quality: 72 })
      .toBuffer();
    const key = `coachmark/${step.file}.webp`;
    const { error } = await sb.storage.from('koala-seed').upload(key, webp, {
      contentType: 'image/webp',
      upsert: true,
      cacheControl: '31536000',
    });
    if (error) throw new Error(error.message);
    console.log(`OK ${(webp.length / 1024).toFixed(1)}KB → ${key}`);
  } catch (e) {
    console.error(`FAIL ${step.file}:`, e.message);
  }
}
console.log('done.');
