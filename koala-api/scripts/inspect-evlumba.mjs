// Evlumba schema inspection — pgvector + designer/project tables.
// Usage: node scripts/inspect-evlumba.mjs
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Load .env.production manually (no dotenv dep needed)
const envText = readFileSync(resolve('.env.production'), 'utf8');
for (const rawLine of envText.split('\n')) {
  const line = rawLine.trim();
  if (!line || line.startsWith('#')) continue;
  const eq = line.indexOf('=');
  if (eq < 0) continue;
  const k = line.slice(0, eq).trim();
  let v = line.slice(eq + 1).trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
    v = v.slice(1, -1);
  }
  // Unescape \n / \r / \\ — JWT'lerde escape edilmiş newline çıkıyor.
  v = v.replace(/\\n/g, '').replace(/\\r/g, '').replace(/\\\\/g, '\\');
  process.env[k] = v;
}

const url = process.env.EVLUMBA_SUPABASE_URL;
const key = process.env.EVLUMBA_SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('Missing EVLUMBA_SUPABASE_URL or SERVICE_ROLE_KEY');
  process.exit(1);
}

const sb = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
});

console.log(`\n=== Evlumba @ ${url}\n`);

// 1. pgvector? — inferred from column probes below.
console.log('--- 1) pgvector extension --- (will infer from column probes)');

// 2. profiles row sample
console.log('\n--- 2) profiles (designer role) ---');
{
  const { data, error, count } = await sb
    .from('profiles')
    .select('*', { count: 'exact' })
    .eq('role', 'designer')
    .limit(3);
  if (error) console.log('  ERROR:', error.message);
  else {
    console.log(`  count=${count}, sample:`);
    console.log(JSON.stringify(data, null, 2));
  }
}

// 3. designer_projects schema + sample
console.log('\n--- 3) designer_projects ---');
{
  const { data, error, count } = await sb
    .from('designer_projects')
    .select('*', { count: 'exact' })
    .eq('is_published', true)
    .limit(3);
  if (error) console.log('  ERROR:', error.message);
  else {
    console.log(`  count(published)=${count}, sample (first row keys):`);
    if (data?.[0]) console.log('  KEYS:', Object.keys(data[0]).join(', '));
    console.log(JSON.stringify(data?.[0] ?? null, null, 2));
  }
}

// 4. project_type distribution
console.log('\n--- 4) project_type distribution ---');
{
  const { data, error } = await sb
    .from('designer_projects')
    .select('project_type')
    .eq('is_published', true)
    .limit(500);
  if (error) console.log('  ERROR:', error.message);
  else {
    const m = new Map();
    for (const r of data) m.set(r.project_type, (m.get(r.project_type) || 0) + 1);
    console.log(JSON.stringify(Object.fromEntries([...m.entries()].sort((a,b) => b[1]-a[1])), null, 2));
  }
}

// 5. designer_project_images
console.log('\n--- 5) designer_project_images ---');
{
  const { data, error, count } = await sb
    .from('designer_project_images')
    .select('*', { count: 'exact' })
    .limit(2);
  if (error) console.log('  ERROR:', error.message);
  else {
    console.log(`  count=${count}, sample keys:`);
    if (data?.[0]) console.log('  KEYS:', Object.keys(data[0]).join(', '));
    console.log(JSON.stringify(data?.[0] ?? null, null, 2));
  }
}

// 6. Hypothetical embedding tables — see if they exist
console.log('\n--- 6) embedding tables (check if any exist) ---');
for (const t of [
  'designer_project_embeddings',
  'designer_embeddings',
  'project_embeddings',
  'designer_projects_embeddings',
]) {
  const { error } = await sb.from(t).select('*', { count: 'exact', head: true });
  console.log(`  ${t}: ${error ? `NO (${error.code})` : 'YES — exists'}`);
}

// 7. Try selecting an "embedding" column from designer_projects
console.log('\n--- 7) designer_projects.embedding column? ---');
{
  const { error } = await sb.from('designer_projects').select('id,embedding').limit(1);
  console.log(`  designer_projects.embedding: ${error ? `NO (${error.message})` : 'YES — exists'}`);
}
{
  const { error } = await sb.from('designer_project_images').select('id,embedding').limit(1);
  console.log(`  designer_project_images.embedding: ${error ? `NO (${error.message})` : 'YES — exists'}`);
}

console.log('\n=== Done.\n');
