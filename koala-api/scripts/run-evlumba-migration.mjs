// Run a SQL migration against Evlumba via Supabase pgmeta query endpoint.
// Supabase doesn't expose raw SQL via PostgREST. We have two options:
//   A. psql with DB_URL — needs direct postgres connection string
//   B. Via Supabase dashboard SQL editor (manual paste)
//
// This script attempts option A using EVLUMBA_DATABASE_URL if present;
// otherwise it prints the SQL and instructs to paste it manually.
//
// Usage: node scripts/run-evlumba-migration.mjs sql/evlumba/001_pro_match_embeddings.sql

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

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

const file = process.argv[2];
if (!file) {
  console.error('Usage: node scripts/run-evlumba-migration.mjs <sql-file>');
  process.exit(1);
}
const sql = readFileSync(resolve(file), 'utf8');
const dbUrl = process.env.EVLUMBA_DATABASE_URL;

if (!dbUrl) {
  console.log('ℹ️  EVLUMBA_DATABASE_URL is not set in .env.production.');
  console.log('   To run automatically, add it (Supabase → Project Settings → Database → Connection string → URI mode).');
  console.log('\n--- SQL to paste in Evlumba Supabase SQL Editor ---\n');
  console.log(sql);
  process.exit(0);
}

// Try pg directly
const { default: pg } = await import('pg').catch(() => ({ default: null }));
if (!pg) {
  console.error('pg package not installed. Run: npm i -D pg');
  process.exit(1);
}
const client = new pg.Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
await client.connect();
console.log(`Connected. Running ${file}…`);
try {
  await client.query(sql);
  console.log('✅ Migration applied.');
} catch (e) {
  console.error('❌ Migration failed:', e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
