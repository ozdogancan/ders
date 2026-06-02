// POST /api/auth/apply-override
//
// Koala tarafı PROFESYONEL istisna uygulaması. İstemci her girişten sonra
// (Google / Evlumba / magic link) Bearer idToken ile çağırır. Token'daki
// DOĞRULANMIŞ e-posta koala_pro_overrides'ta aktif kayıtla eşleşirse,
// kullanıcının Koala profili pro + verified yapılır. Evlumba'ya dokunmaz.
//
// GÜVENLİK: E-posta client parametresinden DEĞİL, doğrulanmış Firebase
// token'ından alınır → kimse başkasının override e-postasını kullanamaz.

import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { getAdminAuth } from '@/lib/firebase-admin';
import { corsHeaders, isOriginAllowed } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 15;

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'), 'POST, OPTIONS');
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ applied: false, error: 'forbidden' }, { status: 403, headers: cors });
  }

  const authHeader = req.headers.get('authorization') ?? '';
  const m = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!m) {
    return NextResponse.json({ applied: false, error: 'no_token' }, { status: 401, headers: cors });
  }
  const auth = getAdminAuth();
  if (!auth) {
    return NextResponse.json({ applied: false, error: 'auth_unavailable' }, { status: 500, headers: cors });
  }

  let uid = '';
  let email = '';
  try {
    const decoded = await auth.verifyIdToken(m[1]);
    uid = decoded.uid;
    email = (decoded.email ?? '').toLowerCase();
  } catch {
    return NextResponse.json({ applied: false, error: 'invalid_token' }, { status: 401, headers: cors });
  }
  if (!uid || !email) {
    return NextResponse.json({ applied: false }, { headers: cors });
  }

  const db = koalaAdmin();
  const { data: ov } = await db
    .from('koala_pro_overrides')
    .select('display_name, profession, active')
    .eq('email', email)
    .maybeSingle();
  if (!ov || ov.active !== true) {
    return NextResponse.json({ applied: false }, { headers: cors });
  }

  try {
    const now = new Date().toISOString();
    const prof = (ov.profession as string | null)?.trim() || null;
    const name = (ov.display_name as string | null)?.trim() || null;
    const row: Record<string, unknown> = {
      uid,
      mode: 'pro',
      verified: true,
      updated_at: now,
    };
    if (prof) row.profession = prof;
    if (name) row.display_name = name;
    await db.from('koala_user_profiles').upsert(row, { onConflict: 'uid' });
  } catch (e) {
    return NextResponse.json(
      { applied: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500, headers: cors },
    );
  }

  return NextResponse.json({ applied: true }, { headers: cors });
}
