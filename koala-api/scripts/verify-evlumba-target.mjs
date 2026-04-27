// Quick verification: confirm designer_projects exists in Evlumba target.
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
console.log('Target Evlumba URL:', url);
console.log('Project ref:', url?.replace('https://', '').split('.')[0]);

const sb = createClient(url, process.env.EVLUMBA_SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const { count, error } = await sb.from('designer_projects').select('*', { count: 'exact', head: true });
console.log(error ? `ERROR: ${error.message}` : `designer_projects rows: ${count}`);
