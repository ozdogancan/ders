// Full introspection of the Al-Tutor (xgefjepaqnghaotqybpi) project.
// Lists all public tables, their row counts, and a sample row for schema verification.
import { createClient } from '@supabase/supabase-js';

const URL = 'https://xgefjepaqnghaotqybpi.supabase.co';
const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhnZWZqZXBhcW5naGFvdHF5YnBpIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjcwOTcwNCwiZXhwIjoyMDg4Mjg1NzA0fQ.7zO3WigkeHcUFvkH0WWaEQ3HATX-lQW_DHO10RtUn-0';

const sb = createClient(URL, KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Probe a wide list of likely tables (evlumba + koala namespaces).
const probes = [
  // evlumba surface
  'designer_projects',
  'designer_project_images',
  'designer_project_shop_links',
  'designer_project_embeddings',
  'profiles',
  'conversations',
  'messages',
  'reviews',
  'favorites',
  // koala surface
  'koala_designers',
  'koala_users',
  'koala_messages',
  'user_style_profiles',
  'analytics_events',
  'restyle_results',
  'mekan_uploads',
  'subscriptions',
  'notifications',
];

console.log('=== Al-Tutor (xgefjepaqnghaotqybpi) introspection ===\n');

for (const t of probes) {
  // Get count
  const { count, error: countErr } = await sb
    .from(t)
    .select('*', { count: 'exact', head: true });

  if (countErr) {
    console.log(`✗ ${t.padEnd(32)} ${countErr.message.slice(0, 70)}`);
    continue;
  }

  // Get one sample row to read columns
  const { data: sample, error: sampleErr } = await sb
    .from(t)
    .select('*')
    .limit(1);

  const cols =
    sample && sample.length
      ? Object.keys(sample[0]).slice(0, 12).join(', ')
      : '(empty — cannot read columns)';

  console.log(
    `✓ ${t.padEnd(32)} count=${String(count).padEnd(6)} cols=${cols}${
      sample && sample.length && Object.keys(sample[0]).length > 12 ? ', …' : ''
    }`,
  );
}
