// Evlumba logosunu evlumba.com'dan çek, küçük webp'e çevir, koala-seed/icons/'a yükle.
// Run from koala-api/:  node scripts/seed_evlumba_logo.mjs
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
const sb = createClient(readEnv('SUPABASE_URL'), readEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});

const res = await fetch('https://www.evlumba.com/web_icon2.png');
if (!res.ok) { console.error('fetch logo failed', res.status); process.exit(1); }
const raw = Buffer.from(await res.arrayBuffer());
// 144px kare, şeffaflık korunur (png) — login butonu ikonu için net.
const png = await sharp(raw).resize(144, 144, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer();
const key = 'icons/evlumba-logo-v1.png';
const { error } = await sb.storage.from('koala-seed').upload(key, png, {
  contentType: 'image/png', upsert: true, cacheControl: '31536000',
});
if (error) { console.error('upload error', error.message); process.exit(1); }
const { data: pub } = sb.storage.from('koala-seed').getPublicUrl(key);
console.log(`OK ${(png.length / 1024).toFixed(1)}KB → ${pub.publicUrl}`);
