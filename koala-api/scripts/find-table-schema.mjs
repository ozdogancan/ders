// Find which schema designer_projects lives in via information_schema.
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

// Try several common schemas explicitly
const schemas = ['public', 'evlumba', 'marketplace', 'koala', 'app'];
for (const schema of schemas) {
  const { count, error } = await sb.schema(schema).from('designer_projects').select('*', { count: 'exact', head: true });
  console.log(`  schema=${schema.padEnd(15)} → ${error ? 'ERROR: ' + error.message.slice(0, 70) : 'count=' + count}`);
}
