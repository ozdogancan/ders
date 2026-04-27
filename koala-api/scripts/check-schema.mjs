// Detect which schema designer_projects lives in.
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

const url = process.env.EVLUMBA_SUPABASE_URL;
const ref = url.replace('https://', '').split('.')[0];
console.log('=== Target Evlumba ===');
console.log('  URL :', url);
console.log('  Ref :', ref);
console.log('  Dashboard URL: https://supabase.com/dashboard/project/' + ref);
console.log('  → SQL editor URL: https://supabase.com/dashboard/project/' + ref + '/sql/new');
console.log('');
console.log('=== Sanity ===');

const sb = createClient(url, process.env.EVLUMBA_SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// PostgREST default schema is public — table count via head request
const tables = ['designer_projects', 'profiles', 'designer_project_images', 'conversations'];
for (const tbl of tables) {
  const { count, error } = await sb.from(tbl).select('*', { count: 'exact', head: true });
  console.log(`  ${tbl.padEnd(30)} ${error ? 'ERROR: ' + error.message : 'count = ' + count}`);
}
