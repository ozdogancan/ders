// Apply saved_items_anon_all RLS policy via Supabase Management API.
import fs from 'node:fs';
import path from 'node:path';

const envPath = path.join(process.cwd(), '.env.local');
const txt = fs.readFileSync(envPath, 'utf8');
for (const line of txt.split('\n')) {
  const m = line.match(/^([A-Z_][A-Z0-9_]*)="?(.*?)"?$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}

const URL_ = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
console.log('URL:', URL_, 'KEY len:', KEY?.length);

const sql = fs.readFileSync(
  path.join(process.cwd(), '..', 'supabase', 'migrations', '20260427_saved_items_anon_policy.sql'),
  'utf8',
);

// Direct policy creation via REST is not supported. Use pg-meta endpoint via project ref.
const ref = URL_.match(/https:\/\/([^.]+)/)[1];
console.log('project ref:', ref);

// Try Supabase Management API (requires PAT, not service role) — fallback to direct SQL via /pg/query.
// The pg-meta endpoint is exposed as /pg/query in newer projects under same hostname.
const tryEndpoints = [
  { url: `${URL_}/pg/query`, body: { query: sql } },
  { url: `${URL_}/rest/v1/rpc/exec_sql`, body: { sql } },
];

for (const ep of tryEndpoints) {
  const res = await fetch(ep.url, {
    method: 'POST',
    headers: {
      apikey: KEY,
      Authorization: `Bearer ${KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(ep.body),
  });
  const t = await res.text();
  console.log(ep.url, res.status, t.slice(0, 300));
  if (res.ok) {
    console.log('OK');
    process.exit(0);
  }
}

console.log('\nAll endpoints failed. Manual application needed via Supabase dashboard SQL editor.');
process.exit(1);
