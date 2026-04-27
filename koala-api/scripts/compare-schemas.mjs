// Compare table schemas between old (vgtgcjnrsladdharzkwn) and new (xgefjepaqnghaotqybpi)
// to confirm we can copy data row-for-row.
import { createClient } from '@supabase/supabase-js';

const OLD = createClient(
  'https://vgtgcjnrsladdharzkwn.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZndGdjam5yc2xhZGRoYXJ6a3duIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzQyNTU3MSwiZXhwIjoyMDg5MDAxNTcxfQ.ILl5EIRC53ndo1dc6RTfGssLM90AACSuG53jZtJjSAQ',
  { auth: { autoRefreshToken: false, persistSession: false } },
);
const NEW = createClient(
  'https://xgefjepaqnghaotqybpi.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhnZWZqZXBhcW5naGFvdHF5YnBpIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjcwOTcwNCwiZXhwIjoyMDg4Mjg1NzA0fQ.7zO3WigkeHcUFvkH0WWaEQ3HATX-lQW_DHO10RtUn-0',
  { auth: { autoRefreshToken: false, persistSession: false } },
);

const tables = [
  'profiles',
  'designer_projects',
  'designer_project_images',
  'designer_project_shop_links',
  'conversations',
  'messages',
];

// Strategy: read 1 row from OLD (has data), inspect columns.
// For NEW, OpenAPI swagger at /rest/v1/ shows columns even when empty.
async function getNewColumns(tableName) {
  const r = await fetch(
    'https://xgefjepaqnghaotqybpi.supabase.co/rest/v1/',
    {
      headers: {
        apikey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhnZWZqZXBhcW5naGFvdHF5YnBpIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjcwOTcwNCwiZXhwIjoyMDg4Mjg1NzA0fQ.7zO3WigkeHcUFvkH0WWaEQ3HATX-lQW_DHO10RtUn-0',
        Accept: 'application/openapi+json',
      },
    },
  );
  const j = await r.json();
  const def = j?.definitions?.[tableName];
  return def?.properties ? Object.keys(def.properties) : null;
}

console.log('=== Schema comparison OLD → NEW ===\n');

for (const t of tables) {
  const { data: oldRow } = await OLD.from(t).select('*').limit(1);
  const oldCols = oldRow && oldRow[0] ? Object.keys(oldRow[0]) : [];

  const newCols = await getNewColumns(t);

  console.log(`--- ${t} ---`);
  if (!newCols) {
    console.log(`  ⚠ NEW: table not found in OpenAPI`);
    console.log(`  OLD cols (${oldCols.length}): ${oldCols.join(', ')}\n`);
    continue;
  }

  const inOldNotNew = oldCols.filter((c) => !newCols.includes(c));
  const inNewNotOld = newCols.filter((c) => !oldCols.includes(c));

  console.log(`  OLD cols (${oldCols.length}): ${oldCols.join(', ')}`);
  console.log(`  NEW cols (${newCols.length}): ${newCols.join(', ')}`);
  if (inOldNotNew.length) console.log(`  ⚠ OLD has, NEW missing: ${inOldNotNew.join(', ')}`);
  if (inNewNotOld.length) console.log(`  ℹ NEW has, OLD missing: ${inNewNotOld.join(', ')}`);
  if (!inOldNotNew.length && !inNewNotOld.length) console.log(`  ✓ identical`);
  console.log();
}
