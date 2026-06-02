// READ-ONLY: muratcan yeniaras Evlumba hesaplarını incele.
// Hiçbir şeyi DEĞİŞTİRMEZ — sadece raporlar.
// Run from koala-api/:  node scripts/inspect_evlumba_user.mjs
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
const ev = createClient(readEnv('EVLUMBA_SUPABASE_URL'), readEnv('EVLUMBA_SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { autoRefreshToken: false, persistSession: false },
});

const TARGET_EMAILS = ['muratcanyeniarastasarim@gmail.com', 'muratcanyeniaras@gmail.com'];

// 1) profiles tablosundan muratcan ile eşleşenler
const { data: profs, error: pErr } = await ev
  .from('profiles')
  .select('id, full_name, business_name, avatar_url, profession, specialty, city')
  .or('full_name.ilike.%muratcan%,business_name.ilike.%muratcan%');
console.log('=== profiles (muratcan) ===');
if (pErr) console.log('profiles error:', pErr.message);
for (const p of profs ?? []) {
  // designer_projects sayısı (resim var mı?)
  let projCount = 0;
  try {
    const { count } = await ev
      .from('designer_projects')
      .select('id', { count: 'exact', head: true })
      .eq('designer_id', p.id);
    projCount = count ?? 0;
  } catch (e) { projCount = -1; }
  // auth email
  let email = '(?)';
  try {
    const { data: u } = await ev.auth.admin.getUserById(p.id);
    email = u?.user?.email ?? '(no-email)';
  } catch (e) { email = '(lookup-fail)'; }
  console.log({
    id: p.id,
    email,
    full_name: p.full_name,
    business_name: p.business_name,
    has_avatar: !!p.avatar_url,
    projects: projCount,
    profession: p.profession || p.specialty || '',
    city: p.city || '',
  });
}

// 2) hedef e-postalar auth.users'ta var mı? (listUsers ile tara)
console.log('=== auth lookup by target emails ===');
const found = {};
let page = 1;
for (;;) {
  const { data, error } = await ev.auth.admin.listUsers({ page, perPage: 200 });
  if (error) { console.log('listUsers error:', error.message); break; }
  const users = data?.users ?? [];
  for (const u of users) {
    const em = (u.email || '').toLowerCase();
    if (TARGET_EMAILS.includes(em)) {
      found[em] = { id: u.id, created_at: u.created_at, last_sign_in_at: u.last_sign_in_at };
    }
  }
  if (users.length < 200) break;
  page++;
  if (page > 30) break; // güvenlik
}
console.log(JSON.stringify(found, null, 2));
console.log('done (read-only).');
