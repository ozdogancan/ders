// POST /api/auth/evlumba/magic/verify
//
// Magic link token'ını doğrular → Firebase custom token döner. Uygulama
// /evlumba-magic?token=... rotasında bunu çağırır, signInWithCustomToken yapar.
//
// NOT: Magic link ile giren kullanıcı şimdilik EV SAHİBİ olarak gelir.
// Profesyonel (pro) işaretleme Evlumba üyelik doğrulaması (service-role)
// gerektirir; geçerli service-role anahtarı gelince eklenecek.

import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { koalaAdmin } from '@/lib/supabase/koala';
import { getAdminAuth } from '@/lib/firebase-admin';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 20;

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'), 'POST, OPTIONS');
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403, headers: cors });
  }
  if (!checkRateLimit(req, 'evlumba-magic-verify', 20)) {
    return NextResponse.json({ error: 'rate_limited' }, { status: 429, headers: cors });
  }

  let body: { token?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers: cors });
  }
  const token = (body.token ?? '').trim();
  if (!token || token.length < 16) {
    return NextResponse.json({ error: 'invalid_token' }, { status: 400, headers: cors });
  }

  const db = koalaAdmin();
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

  // Token bul (kullanılmamış + süresi geçmemiş)
  const { data: row } = await db
    .from('koala_magic_links')
    .select('id, email, expires_at, used')
    .eq('token_hash', tokenHash)
    .maybeSingle();
  if (!row || row.used === true) {
    return NextResponse.json({ error: 'token_invalid_or_used' }, { status: 401, headers: cors });
  }
  if (new Date(row.expires_at as string).getTime() < Date.now()) {
    return NextResponse.json({ error: 'token_expired' }, { status: 401, headers: cors });
  }

  // Tek kullanım: hemen used işaretle
  await db.from('koala_magic_links').update({ used: true }).eq('id', row.id);

  const email = (row.email as string).toLowerCase();

  // Firebase find-or-create + custom token
  const adminAuth = getAdminAuth();
  if (!adminAuth) {
    return NextResponse.json({ error: 'firebase_unavailable' }, { status: 500, headers: cors });
  }
  let uid: string;
  try {
    const existing = await adminAuth.getUserByEmail(email).catch(() => null);
    uid = existing
      ? existing.uid
      : (await adminAuth.createUser({ email, emailVerified: true })).uid;
  } catch (e) {
    return NextResponse.json(
      { error: 'firebase_user_failed', detail: e instanceof Error ? e.message : String(e) },
      { status: 500, headers: cors },
    );
  }

  let customToken: string;
  try {
    customToken = await adminAuth.createCustomToken(uid, { evlumba_magic: true });
  } catch (e) {
    return NextResponse.json(
      { error: 'token_mint_failed', detail: e instanceof Error ? e.message : String(e) },
      { status: 500, headers: cors },
    );
  }

  // Koala profili — mevcut yoksa ev sahibi oluştur (pro'ya ZORLAMA).
  try {
    const now = new Date().toISOString();
    const existingProfile = await db
      .from('koala_user_profiles')
      .select('uid')
      .eq('uid', uid)
      .maybeSingle();
    if (!existingProfile.data) {
      await db.from('koala_user_profiles').insert({
        uid,
        mode: 'homeowner',
        verified: false,
        display_name: email.split('@')[0],
        updated_at: now,
      });
    }
  } catch (e) {
    console.warn('[magic/verify] profile ensure failed:', e instanceof Error ? e.message : e);
  }

  return NextResponse.json({ custom_token: customToken, uid }, { headers: cors });
}
