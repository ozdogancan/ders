// Inspect existing embedding tables: schema + actual row count.
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';

const t = readFileSync('.env.production', 'utf8');
for (const raw of t.split('\n')) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  const eq = line.indexOf('=');
  if (eq < 0) continue;
  const k = line.slice(0, eq).trim();
  let v = line.slice(eq + 1).trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
  v = v.replace(/\\n/g, '').replace(/\\r/g, '').replace(/\\\\/g, '\\');
  process.env[k] = v;
}

const sb = createClient(
  process.env.EVLUMBA_SUPABASE_URL,
  process.env.EVLUMBA_SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } },
);

const tables = ['designer_project_embeddings', 'project_embeddings', 'designer_embeddings', 'embeddings'];

for (const name of tables) {
  console.log(`\n=== ${name} ===`);
  // Try to fetch first row with all columns (no head)
  const { data, error } = await sb.from(name).select('*').limit(1);
  if (error) {
    console.log('  error:', error.message);
    continue;
  }
  console.log(`  fetched_rows=${data.length}`);
  if (data[0]) {
    // Mask vector field if present (huge)
    const masked = {};
    for (const [k, v] of Object.entries(data[0])) {
      if (Array.isArray(v) && v.length > 10) masked[k] = `<vector len=${v.length}>`;
      else if (typeof v === 'string' && v.length > 200) masked[k] = `<long string len=${v.length}>`;
      else masked[k] = v;
    }
    console.log('  columns:', Object.keys(data[0]).join(', '));
    console.log('  sample:', JSON.stringify(masked, null, 2));
  }
  // Try without head, with non-exact count
  const { count } = await sb.from(name).select('*', { count: 'planned', head: true });
  console.log('  planned_count=', count);
  const { count: exactCount } = await sb.from(name).select('*', { count: 'exact', head: true });
  console.log('  exact_count=', exactCount);
}
