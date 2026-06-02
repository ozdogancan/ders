// POST /api/auth/evlumba/magic/start
//
// Şifresiz "magic link" ile giriş başlat: token üret + sakla + güzel bir
// e-posta gönder. Link → https://www.koalatutor.com/evlumba-magic?token=...
// → uygulama /api/auth/evlumba/magic/verify çağırır → Firebase custom token.
//
// E-posta gönderimi: nodemailer + koala_bridge_config.gmail_app_password
// (designer-digest ile aynı). Link 15 dk geçerli, tek kullanımlık.

import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import nodemailer from 'nodemailer';
import { koalaAdmin } from '@/lib/supabase/koala';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 20;

const FROM = 'Koala by Evlumba <info@evlumba.com>';
const SMTP_USER = 'info@evlumba.com';
const LOGO_URL = 'https://www.koalatutor.com/icons/Icon-512.png';
const APP_BASE = 'https://www.koalatutor.com';
const TTL_MIN = 15;

function maskEmail(email: string): string {
  const [u, d] = email.split('@');
  if (!u || !d) return email;
  const head = u.slice(0, Math.min(2, u.length));
  return `${head}${'*'.repeat(Math.max(2, u.length - head.length))}@${d}`;
}

function emailHtml(link: string): { subject: string; html: string } {
  const subject = 'Koala giriş bağlantın';
  const html = `<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"></head>
<body style="margin:0;padding:0;background:#F2F2F4;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F2F4;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:472px;background:#FFFFFF;border:1px solid #E7E7EB;border-radius:18px;overflow:hidden;">
        <tr><td style="padding:22px 32px 18px;border-bottom:1px solid #EEEEF1;">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>
            <td width="40" style="padding-right:11px;"><img src="${LOGO_URL}" alt="Koala" width="40" height="40" style="display:block;width:40px;height:40px;border-radius:10px;"></td>
            <td style="font-size:17px;font-weight:800;color:#17171C;letter-spacing:-0.3px;">Koala <span style="font-weight:500;color:#9A9AA4;font-size:13px;">by Evlumba</span></td>
          </tr></table>
        </td></tr>
        <tr><td style="padding:34px 32px 8px;">
          <h1 style="margin:0;font-size:21px;font-weight:800;color:#23232A;letter-spacing:-0.4px;">Giriş bağlantın hazır 🔑</h1>
          <p style="margin:12px 0 0;font-size:14.5px;line-height:1.6;color:#6E6E78;">Aşağıdaki butona dokun, şifre girmeden Koala'ya giriş yap. Bu bağlantı <b>${TTL_MIN} dakika</b> geçerlidir ve yalnızca bir kez kullanılabilir.</p>
        </td></tr>
        <tr><td style="padding:26px 32px 6px;" align="center">
          <a href="${link}" style="display:inline-block;background:#6C5CE7;color:#ffffff;text-decoration:none;font-size:15px;font-weight:700;padding:15px 40px;border-radius:12px;">Koala'ya giriş yap</a>
        </td></tr>
        <tr><td style="padding:18px 32px 4px;">
          <p style="margin:0;font-size:12px;line-height:1.6;color:#9A9AA4;">Buton çalışmazsa bu bağlantıyı tarayıcına yapıştır:</p>
          <p style="margin:6px 0 0;font-size:11.5px;line-height:1.5;color:#8A82E0;word-break:break-all;">${link}</p>
        </td></tr>
        <tr><td style="padding:20px 32px 28px;">
          <p style="margin:0;font-size:12px;line-height:1.6;color:#A8A8B2;">Bu girişi sen talep etmediysen bu e-postayı yok sayabilirsin — hesabın güvende.</p>
        </td></tr>
        <tr><td style="padding:16px 32px;background:#FAFAFB;border-top:1px solid #EEEEF1;">
          <p style="margin:0;font-size:12px;color:#A8A8B2;text-align:center;">© Evlumba · <a href="mailto:info@evlumba.com" style="color:#8A82E0;text-decoration:none;">info@evlumba.com</a></p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
  return { subject, html };
}

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
  if (!checkRateLimit(req, 'evlumba-magic-start', 5)) {
    return NextResponse.json({ error: 'rate_limited' }, { status: 429, headers: cors });
  }

  let body: { email?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers: cors });
  }
  const email = (body.email ?? '').trim().toLowerCase();
  if (!email.includes('@') || email.length < 5) {
    return NextResponse.json({ error: 'invalid_email' }, { status: 400, headers: cors });
  }

  const db = koalaAdmin();

  // gmail app password — koala_bridge_config
  const { data: cfg } = await db
    .from('koala_bridge_config')
    .select('value')
    .eq('key', 'gmail_app_password')
    .maybeSingle();
  const pass = cfg?.value as string | undefined;
  if (!pass) {
    return NextResponse.json({ error: 'mail_not_configured' }, { status: 500, headers: cors });
  }

  // token üret + sakla
  const token = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const expiresAt = new Date(Date.now() + TTL_MIN * 60_000).toISOString();
  try {
    await db.from('koala_magic_links').insert({
      email,
      token_hash: tokenHash,
      expires_at: expiresAt,
    });
  } catch (e) {
    return NextResponse.json(
      { error: 'store_failed', detail: e instanceof Error ? e.message : String(e) },
      { status: 500, headers: cors },
    );
  }

  const link = `${APP_BASE}/evlumba-magic?token=${token}`;
  const { subject, html } = emailHtml(link);
  const transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: { user: SMTP_USER, pass },
  });
  try {
    await transporter.sendMail({ from: FROM, to: email, subject, html });
  } catch (e) {
    return NextResponse.json(
      { error: 'send_failed', detail: e instanceof Error ? e.message : String(e) },
      { status: 502, headers: cors },
    );
  } finally {
    transporter.close();
  }

  return NextResponse.json(
    { ok: true, masked_email: maskEmail(email), expires_in: TTL_MIN * 60 },
    { headers: cors },
  );
}
