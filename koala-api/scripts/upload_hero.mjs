// Upload scripts/hero-v3.png to Supabase storage koala-seed/share/hero-v3.jpg
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

const sb = createClient(readEnv('SUPABASE_URL'), readEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});

const buf = fs.readFileSync(path.join(process.cwd(), 'scripts', 'hero-v3.png'));
const { data, error } = await sb.storage
  .from('koala-seed')
  .upload('share/hero-v3.jpg', buf, {
    contentType: 'image/jpeg',
    upsert: true,
    cacheControl: '31536000',
  });
if (error) {
  console.error('upload error:', error.message);
  process.exit(1);
}
console.log('uploaded:', data?.path);
const { data: pub } = sb.storage.from('koala-seed').getPublicUrl('share/hero-v3.jpg');
console.log('public url:', pub.publicUrl);
