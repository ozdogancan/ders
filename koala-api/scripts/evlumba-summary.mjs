// Compact summary — keys + counts + project_type histogram + embedding probe.
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

const out = {};

// 1. profiles count
{
  const { count: total } = await sb.from('profiles').select('*', { count: 'exact', head: true });
  const { count: designers } = await sb.from('profiles').select('*', { count: 'exact', head: true }).eq('role', 'designer');
  const { count: homeowners } = await sb.from('profiles').select('*', { count: 'exact', head: true }).eq('role', 'homeowner');
  out.profiles = { total, designers, homeowners };
}

// 2. designer_projects keys + counts
{
  const { data: row1 } = await sb.from('designer_projects').select('*').limit(1).maybeSingle();
  const { count: total } = await sb.from('designer_projects').select('*', { count: 'exact', head: true });
  const { count: published } = await sb.from('designer_projects').select('*', { count: 'exact', head: true }).eq('is_published', true);
  out.designer_projects = {
    columns: row1 ? Object.keys(row1) : [],
    count: total,
    published,
  };
}

// 3. project_type histogram
{
  const { data } = await sb.from('designer_projects').select('project_type').eq('is_published', true).limit(2000);
  const m = new Map();
  for (const r of data || []) m.set(r.project_type ?? '(null)', (m.get(r.project_type ?? '(null)') || 0) + 1);
  out.project_type_histogram = Object.fromEntries([...m.entries()].sort((a, b) => b[1] - a[1]));
}

// 4. designer_project_images
{
  const { data: row1 } = await sb.from('designer_project_images').select('*').limit(1).maybeSingle();
  const { count } = await sb.from('designer_project_images').select('*', { count: 'exact', head: true });
  out.designer_project_images = { columns: row1 ? Object.keys(row1) : [], count };
}

// 5. embedding probes
{
  const probes = {};
  for (const t of ['designer_project_embeddings', 'project_embeddings', 'designer_embeddings', 'embeddings']) {
    const { error, count } = await sb.from(t).select('*', { count: 'exact', head: true });
    probes[t] = error ? `MISSING (${error.code || 'err'})` : `EXISTS (count=${count})`;
  }
  // Column probe: try selecting `embedding` from main tables
  for (const tbl of ['designer_projects', 'designer_project_images']) {
    const { error } = await sb.from(tbl).select('id,embedding').limit(1);
    probes[`${tbl}.embedding`] = error
      ? `NO COLUMN (${error.message?.slice(0, 80) || 'err'})`
      : 'COLUMN EXISTS';
  }
  out.embedding_probes = probes;
}

// 6. Sample one designer_projects row keys + a row with media (for n8n input)
{
  const { data } = await sb
    .from('designer_projects')
    .select('id, title, project_type, location, designer_id, cover_image_url, designer_project_images(image_url)')
    .eq('is_published', true)
    .limit(2);
  out.sample_projects = data;
}

// 7. profiles columns (designer perspective)
{
  const { data: row1 } = await sb.from('profiles').select('*').eq('role', 'designer').limit(1).maybeSingle();
  out.profiles_columns = row1 ? Object.keys(row1) : [];
}

console.log(JSON.stringify(out, null, 2));
