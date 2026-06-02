// POST /api/auth/evlumba/forgot
//
// Evlumba hesabı için şifre sıfırlama e-postası tetikler (Evlumba gotrue).
// Kullanıcı Evlumba'nın sıfırlama akışıyla yeni şifre belirler, sonra Koala'da
// "Evlumba ile giriş" ekranından yeni şifreyle girer.
//
// GİZLİLİK: E-postanın kayıtlı olup olmadığını SIZDIRMA — her durumda ok döner
// (enumeration koruması). UI "kayıtlıysa e-posta gönderildi" der.

import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';

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
    return NextResponse.json({ error: 'forbidden' }, { status: 403, headers: cors });
  }
  if (!checkRateLimit(req, 'evlumba-forgot', 5)) {
    return NextResponse.json({ error: 'rate_limited' }, { status: 429, headers: cors });
  }

  let body: { email?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers: cors });
  }
  const email = (body.email ?? '').trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return NextResponse.json({ error: 'invalid_email' }, { status: 400, headers: cors });
  }

  const evUrl = process.env.EVLUMBA_SUPABASE_URL;
  const evAnon = process.env.EVLUMBA_SUPABASE_ANON_KEY;
  if (evUrl && evAnon) {
    try {
      const evAuth = createClient(evUrl, evAnon, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      // Evlumba'nın kendi reset e-postası gönderilir (kendi redirect ayarıyla).
      await evAuth.auth.resetPasswordForEmail(email, {
        redirectTo: 'https://www.evlumba.com',
      });
    } catch (e) {
      // Yut — enumeration sızdırma.
      console.warn('[evlumba/forgot] reset failed:', e instanceof Error ? e.message : e);
    }
  }

  // Her durumda ok (enumeration koruması).
  return NextResponse.json({ ok: true }, { headers: cors });
}
