// Mevcut style-previews PNG'leri (1.4MB) → küçük JPG versiyonları
// (~80KB) olarak `style-previews-sm` bucket'ına yükler. Tek seferlik.

import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';

const envPath = path.join(process.cwd(), '.env.local');
const txt = fs.readFileSync(envPath, 'utf8');
for (const line of txt.split('\n')) {
  const m = line.match(/^([A-Z_][A-Z0-9_]*)="?(.*?)"?$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}

const SB_URL = process.env.SUPABASE_URL;
const SB_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SB_URL || !SB_KEY) throw new Error('Supabase env missing');

const sb = createClient(SB_URL, SB_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const SRC_BUCKET = 'style-previews';
const DEST_BUCKET = 'style-previews-sm';

async function ensureBucket() {
  const { data: buckets } = await sb.storage.listBuckets();
  if (!buckets.find((b) => b.name === DEST_BUCKET)) {
    const { error } = await sb.storage.createBucket(DEST_BUCKET, {
      public: true,
    });
    if (error) throw error;
    console.log(`Created bucket ${DEST_BUCKET}`);
  }
}

async function processFile(name) {
  const { data, error } = await sb.storage.from(SRC_BUCKET).download(name);
  if (error) {
    console.log(`  ${name} download fail: ${error.message}`);
    return;
  }
  const buf = Buffer.from(await data.arrayBuffer());
  const out = await sharp(buf)
    .resize({ width: 720, withoutEnlargement: true })
    .jpeg({ quality: 72, mozjpeg: true })
    .toBuffer();
  const dest = name.replace(/\.png$/, '.jpg');
  const { error: upErr } = await sb.storage
    .from(DEST_BUCKET)
    .upload(dest, out, {
      contentType: 'image/jpeg',
      upsert: true,
      cacheControl: '2592000',
    });
  if (upErr) {
    console.log(`  ${dest} upload fail: ${upErr.message}`);
    return;
  }
  console.log(
    `  OK ${dest}  ${(buf.byteLength / 1024).toFixed(0)}KB → ${(out.byteLength / 1024).toFixed(0)}KB`,
  );
}

async function main() {
  await ensureBucket();
  const { data, error } = await sb.storage.from(SRC_BUCKET).list('', {
    limit: 200,
  });
  if (error) throw error;
  const files = (data ?? []).filter((f) => f.name.endsWith('.png'));
  console.log(`Optimizing ${files.length} files...`);
  for (const f of files) {
    await processFile(f.name);
  }
  console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
