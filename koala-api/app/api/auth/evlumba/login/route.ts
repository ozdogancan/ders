// POST /api/auth/evlumba/login
//
// Evlumba hesabıyla Koala'ya giriş. Kullanıcının Evlumba e-posta+şifresini
// Evlumba Supabase auth'ta doğrular; geçerliyse:
//   1) Evlumba profilinden ad + meslek alır (best-effort).
//   2) Firebase'de e-postaya karşılık find-or-create user → custom token üretir.
//   3) Koala koala_user_profiles → mode='pro', verified=true (+ ad/meslek).
// Dönen custom_token ile client signInWithCustomToken yapar = otomatik
// PROFESYONEL (Evlumba ile giriş yapabilen zaten profesyoneldir).
//
// GÜVENLİK: Şifre yalnız Evlumba gotrue'ya iletilir, hiçbir yere kaydedilmez.

import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
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
  if (!checkRateLimit(req, 'evlumba-login', 10)) {
    return NextResponse.json({ error: 'rate_limited' }, { status: 429, headers: cors });
  }

  let body: { email?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers: cors });
  }
  const email = (body.email ?? '').trim().toLowerCase();
  const password = body.password ?? '';
  if (!email || !password) {
    return NextResponse.json({ error: 'missing_fields' }, { status: 400, headers: cors });
  }

  const evUrl = process.env.EVLUMBA_SUPABASE_URL;
  const evAnon = process.env.EVLUMBA_SUPABASE_ANON_KEY;
  if (!evUrl || !evAnon) {
    return NextResponse.json({ error: 'evlumba_not_configured' }, { status: 500, headers: cors });
  }

  // ─── 1) Evlumba kimlik doğrulama (gotrue, anon) ───────────────────
  const evAuth = createClient(evUrl, evAnon, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: signIn, error: signErr } =
    await evAuth.auth.signInWithPassword({ email, password });
  if (signErr || !signIn?.user) {
    // Yanlış e-posta/şifre — kullanıcıya nötr mesaj.
    return NextResponse.json(
      { error: 'invalid_credentials' },
      { status: 401, headers: cors },
    );
  }
  const evUserId = signIn.user.id;
  const evEmail = (signIn.user.email ?? email).toLowerCase();

  // ─── 2) Evlumba profilinden ad + meslek (best-effort) ─────────────
  let fullName = (signIn.user.user_metadata?.full_name as string) ||
    (signIn.user.user_metadata?.display_name as string) || '';
  let profession = '';
  // 2026-06-02: Evlumba'da PROFESYONEL mi yoksa EV SAHİBİ mi? Profesyonel
  // değilse (title/meslek yok ve tasarım yok) → Koala'da PRO YAPMA, ev sahibi
  // olarak al. Profesyonel ise pro + meslek.
  // NOT: service-role anahtarı bu projede geçersiz; bunun yerine GİRİŞ YAPAN
  // kullanıcının KENDİ oturumuyla (evAuth artık authenticated) sorgula — RLS
  // kendi profilini/tasarımlarını okumaya izin verir.
  let isProfessional = false;
  try {
    const { data: prof } = await evAuth
      .from('profiles')
      .select('full_name, business_name, profession, specialty')
      .eq('id', evUserId)
      .maybeSingle();
    if (prof) {
      fullName = (prof.full_name as string) || (prof.business_name as string) || fullName;
      profession = ((prof.profession as string) || (prof.specialty as string) || '').trim();
    }
    if (profession) {
      isProfessional = true;
    } else {
      const { count } = await evAuth
        .from('designer_projects')
        .select('id', { count: 'exact', head: true })
        .eq('designer_id', evUserId)
        .eq('is_published', true);
      isProfessional = (count ?? 0) > 0;
    }
  } catch {
    /* best-effort — emin değilsek ev sahibi (güvenli taraf) */
  }
  if (!fullName) fullName = evEmail.split('@')[0];

  // ─── 3) Firebase find-or-create + custom token ────────────────────
  const adminAuth = getAdminAuth();
  if (!adminAuth) {
    return NextResponse.json({ error: 'firebase_unavailable' }, { status: 500, headers: cors });
  }
  let uid: string;
  try {
    const existing = await adminAuth.getUserByEmail(evEmail).catch(() => null);
    if (existing) {
      uid = existing.uid;
    } else {
      const created = await adminAuth.createUser({
        email: evEmail,
        emailVerified: true,
        displayName: fullName,
      });
      uid = created.uid;
    }
  } catch (e) {
    return NextResponse.json(
      { error: 'firebase_user_failed', detail: e instanceof Error ? e.message : String(e) },
      { status: 500, headers: cors },
    );
  }

  let customToken: string;
  try {
    customToken = await adminAuth.createCustomToken(uid, { evlumba: true });
  } catch (e) {
    return NextResponse.json(
      { error: 'token_failed', detail: e instanceof Error ? e.message : String(e) },
      { status: 500, headers: cors },
    );
  }

  // ─── 4) Koala profili — PROFESYONEL ise pro, değilse EV SAHİBİ ────
  try {
    const sb = koalaAdmin();
    const now = new Date().toISOString();
    // Ev sahibinin mevcut mode'unu 'pro'ya ZORLAMA; profesyonel değilse
    // 'homeowner'. (Daha önce pro yapılmış bir hesabı da düşürmemek için
    // profesyonelse pro, değilse mevcut değer korunur — yeni satırda homeowner.)
    const row: Record<string, unknown> = {
      uid,
      display_name: fullName,
      updated_at: now,
    };
    if (isProfessional) {
      row.mode = 'pro';
      row.verified = true;
      row.profession = profession || null;
    } else {
      row.mode = 'homeowner';
      row.verified = false;
    }
    await sb.from('koala_user_profiles').upsert(row, { onConflict: 'uid' });
  } catch (e) {
    console.warn('[evlumba/login] profile upsert failed:', e instanceof Error ? e.message : e);
  }

  return NextResponse.json(
    {
      custom_token: customToken,
      uid,
      display_name: fullName,
      profession: isProfessional ? profession : '',
      is_professional: isProfessional,
    },
    { headers: cors },
  );
}
