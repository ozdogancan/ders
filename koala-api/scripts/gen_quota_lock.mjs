// One-off: generate a premium PORTRAIT interior image for the swipe "daily limit
// reached" locked card, then upload to Supabase storage koala-seed/share/quota-lock.jpg
// Run from koala-api dir: node scripts/gen_quota_lock.mjs
import fs from 'node:fs';
import path from 'node:path';
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
if (!apiKey) {
  console.error('No GEMINI_API_KEY in .env.local');
  process.exit(1);
}

const MODEL = process.env.HERO_MODEL || 'gemini-3-pro-image-preview';
const prompt = `Generate a premium, editorial interior-design photograph for a PORTRAIT
(vertical 3:4) mobile app card.

Scene: a stunning, aspirational living space — warm minimalist Japandi / modern
luxury style, light oak wood, soft beige, cream and sand tones, a sculptural
designer armchair, layered textures, a few elegant plants, large window with
soft golden natural light, tasteful high-end decor. Editorial magazine quality,
shallow depth of field, airy, inviting, premium.

Composition: vertical 3:4 portrait. Keep the LOWER THIRD calmer and softly
shadowed so it can fade smoothly into a dark overlay where text will be placed.
No people, no text, no logos, no watermark. Photorealistic, high-end interior
photography aesthetic. Warm neutrals only — absolutely NO purple/violet tint.
Bright, clean, premium, desirable.`;

const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;

const res = await fetch(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { responseModalities: ['IMAGE'] },
  }),
});

if (!res.ok) {
  console.error('HTTP', res.status, (await res.text()).slice(0, 600));
  process.exit(1);
}
const j = await res.json();
const parts = j?.candidates?.[0]?.content?.parts ?? [];
const imgPart = parts.find((p) => p.inlineData?.data);
if (!imgPart) {
  console.error('No image in response:', JSON.stringify(j).slice(0, 600));
  process.exit(1);
}
const buf = Buffer.from(imgPart.inlineData.data, 'base64');
const out = path.join(process.cwd(), 'scripts', 'quota-lock.png');
fs.writeFileSync(out, buf);
console.log('wrote', out, buf.length, 'bytes; mime', imgPart.inlineData.mimeType);

// Upload to Supabase storage
const sb = createClient(readEnv('SUPABASE_URL'), readEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});
const { data, error } = await sb.storage
  .from('koala-seed')
  .upload('share/quota-lock.jpg', buf, {
    contentType: 'image/jpeg',
    upsert: true,
    cacheControl: '31536000',
  });
if (error) {
  console.error('upload error:', error.message);
  process.exit(1);
}
console.log('uploaded:', data?.path);
const { data: pub } = sb.storage.from('koala-seed').getPublicUrl('share/quota-lock.jpg');
console.log('public url:', pub.publicUrl);
