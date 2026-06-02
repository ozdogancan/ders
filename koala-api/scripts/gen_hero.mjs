// One-off: generate a premium share-hero image with Gemini (Nano Banana)
// and write it locally. Run: node scripts/gen_hero.mjs
import fs from 'node:fs';
import path from 'node:path';

function readEnv(key) {
  const envPath = path.join(process.cwd(), '.env.local');
  const txt = fs.readFileSync(envPath, 'utf8');
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
const prompt = `Generate a premium, editorial photograph for the TOP BANNER of an
interior-design mobile app's "share your design" screen.

Scene: a beautifully designed, sunlit modern living room — warm minimalist
Scandinavian/Japandi style, light oak wood, soft beige and cream tones,
a cozy sofa, a few plants, large window with soft natural light, tasteful
decor. Editorial magazine quality, shallow depth of field, airy and inviting.

Composition: wide 16:9 landscape. Keep the LOWER THIRD calmer / softly lit so
it can fade smoothly into a light background. No people, no text, no logos,
no watermark. Photorealistic, high-end interior photography aesthetic.
Color palette: warm neutrals (cream, sand, soft taupe, light wood) — absolutely
NO purple/violet tint. Bright, clean, premium.`;

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
const out = path.join(process.cwd(), 'scripts', 'hero-v3.png');
fs.writeFileSync(out, buf);
console.log('wrote', out, buf.length, 'bytes; mime', imgPart.inlineData.mimeType);
