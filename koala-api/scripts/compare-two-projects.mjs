// Compare both Supabase projects to find which one is the real evlumba data home.
import { createClient } from '@supabase/supabase-js';

const A = {
  name: 'xgefjepaqnghaotqybpi (Al-Tutor / SUPABASE_URL)',
  url: 'https://xgefjepaqnghaotqybpi.supabase.co',
  key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhnZWZqZXBhcW5naGFvdHF5YnBpIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjcwOTcwNCwiZXhwIjoyMDg4Mjg1NzA0fQ.7zO3WigkeHcUFvkH0WWaEQ3HATX-lQW_DHO10RtUn-0',
};

const B = {
  name: 'vgtgcjnrsladdharzkwn (eski EVLUMBA_SUPABASE_URL)',
  url: 'https://vgtgcjnrsladdharzkwn.supabase.co',
  key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZndGdjam5yc2xhZGRoYXJ6a3duIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzQyNTU3MSwiZXhwIjoyMDg5MDAxNTcxfQ.ILl5EIRC53ndo1dc6RTfGssLM90AACSuG53jZtJjSAQ',
};

const tables = [
  'designer_projects',
  'designer_project_images',
  'designer_project_shop_links',
  'profiles',
  'koala_designers',
  'user_style_profiles',
  'conversations',
  'messages',
];

for (const proj of [A, B]) {
  console.log('\n===', proj.name, '===');
  const sb = createClient(proj.url, proj.key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  for (const t of tables) {
    const { count, error } = await sb.from(t).select('*', { count: 'exact', head: true });
    const tag = t.padEnd(30);
    if (error) {
      const msg = error.message.length > 60 ? error.message.slice(0, 60) + '…' : error.message;
      console.log(`  ${tag} ✗ ${msg}`);
    } else {
      console.log(`  ${tag} ✓ count=${count}`);
    }
  }
}
