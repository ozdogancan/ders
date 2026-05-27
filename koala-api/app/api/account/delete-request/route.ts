import { NextRequest, NextResponse } from 'next/server';
import nodemailer from 'nodemailer';
import { getAdminAuth } from '@/lib/firebase-admin';
import { koalaAdmin } from '@/lib/supabase/koala';
import { checkRateLimit } from '@/lib/security';

// Public account-deletion request endpoint.
// Google Play 2024 requires a public web flow for account deletion. This is
// the *first* step: user types email → we email them a Firebase sign-in link
// pointing to /account/delete/confirm. The actual hard-delete runs only after
// the user verifies ownership of the email via that link.
//
// SECURITY: never leak whether an account exists. Always return ok:true.

export const runtime = 'nodejs';
export const maxDuration = 30;

const FROM = 'Koala by Evlumba <info@evlumba.com>';
const SMTP_USER = 'info@evlumba.com';
const CONFIRM_URL = 'https://koala-api-olive.vercel.app/account/delete/confirm';
const LOGO_URL = 'https://www.koalatutor.com/icons/Icon-512.png';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface Body {
  email?: string;
  reason?: string;
}

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderEmail(link: string): { subject: string; html: string } {
  const subject = 'Koala hesabı silme — onay linki';
  const html = `<!DOCTYPE html>
<html lang="tr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F2F2F4;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F2F4;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:520px;background:#FFFFFF;border:1px solid #E7E7EB;border-radius:16px;overflow:hidden;">
        <tr><td style="padding:20px 32px;border-bottom:1px solid #EEEEF1;">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>
            <td width="40" style="padding-right:11px;"><img src="${LOGO_URL}" alt="Koala" width="40" height="40" style="display:block;width:40px;height:40px;border-radius:10px;"></td>
            <td style="font-size:17px;font-weight:800;color:#17171C;letter-spacing:-0.3px;">Koala <span style="font-weight:500;color:#9A9AA4;font-size:13px;">by Evlumba</span></td>
          </tr></table>
        </td></tr>
        <tr><td style="padding:30px 32px 10px;">
          <p style="margin:0;font-size:19px;font-weight:600;color:#23232A;">Hesap silme talebin alındı</p>
          <p style="margin:10px 0 0;font-size:14.5px;line-height:1.6;color:#5C5C66;">
            Aşağıdaki butona tıkladığında Koala hesabın ve tüm verilerin (AI tasarımların, sohbet geçmişin, profilin) kalıcı olarak silinecek. Bu işlem <strong>geri alınamaz.</strong>
          </p>
        </td></tr>
        <tr><td style="padding:22px 32px 8px;" align="center">
          <a href="${esc(link)}" style="display:inline-block;background:#E11D48;color:#ffffff;text-decoration:none;font-size:14.5px;font-weight:600;padding:14px 32px;border-radius:11px;">Hesabımı kalıcı olarak sil</a>
        </td></tr>
        <tr><td style="padding:14px 32px 30px;">
          <p style="margin:0;font-size:12.5px;line-height:1.55;color:#9A9AA4;text-align:center;">
            Bu talebi sen göndermediysen bu e-postayı yok say — hesabına dokunulmayacak. Link 1 saat içinde geçersiz olur.
          </p>
        </td></tr>
        <tr><td style="padding:18px 32px;background:#FAFAFB;border-top:1px solid #EEEEF1;">
          <p style="margin:0;font-size:12px;line-height:1.55;color:#A8A8B2;">Sorun yaşarsan <a href="mailto:info@evlumba.com" style="color:#8A82E0;">info@evlumba.com</a></p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  return { subject, html };
}

function transporter(pass: string) {
  return nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: { user: SMTP_USER, pass },
  });
}

const GENERIC_OK = {
  ok: true,
  message: 'Onay e-postası gönderildi',
};

export async function POST(req: NextRequest) {
  // Rate-limit aggressively — this is unauth + sends mail.
  if (!checkRateLimit(req, 'account-delete-request', 3)) {
    return NextResponse.json(
      { ok: false, message: 'Çok fazla deneme. Bir süre sonra tekrar dene.' },
      { status: 429 },
    );
  }

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json(
      { ok: false, message: 'Geçersiz istek.' },
      { status: 400 },
    );
  }

  const email = (body.email ?? '').trim().toLowerCase();
  const reason = (body.reason ?? '').trim().slice(0, 1000);

  if (!email || !EMAIL_RE.test(email)) {
    return NextResponse.json(
      { ok: false, message: 'Geçerli bir e-posta adresi girin.' },
      { status: 400 },
    );
  }

  const adminAuth = getAdminAuth();
  if (!adminAuth) {
    console.error('[delete-request] firebase admin not configured');
    return NextResponse.json(
      { ok: false, message: 'Şu an talebini işleyemedik. Lütfen tekrar dene.' },
      { status: 500 },
    );
  }

  // Look up the user; if not found, silently succeed (don't leak).
  let uid: string | null = null;
  try {
    const u = await adminAuth.getUserByEmail(email);
    uid = u.uid;
  } catch {
    // user not found — return generic success so we don't reveal account existence
    return NextResponse.json(GENERIC_OK);
  }

  // Optional reason logging (best-effort, never blocks).
  if (reason && uid) {
    try {
      await koalaAdmin()
        .from('koala_account_delete_requests')
        .insert({
          user_id: uid,
          email,
          reason,
          requested_at: new Date().toISOString(),
        });
    } catch {
      // table might not exist yet — ignore
    }
  }

  // Generate Firebase email sign-in link.
  let signInLink: string;
  try {
    signInLink = await adminAuth.generateSignInWithEmailLink(email, {
      url: `${CONFIRM_URL}?email=${encodeURIComponent(email)}`,
      handleCodeInApp: true,
    });
  } catch (e) {
    console.error('[delete-request] generateSignInWithEmailLink failed', e);
    return NextResponse.json(
      { ok: false, message: 'Onay linki oluşturulamadı. Lütfen tekrar dene.' },
      { status: 500 },
    );
  }

  // Fetch Gmail app password (same source as designer-digest).
  let smtpPass: string | undefined;
  try {
    const { data: cfgRows } = await koalaAdmin()
      .from('koala_bridge_config')
      .select('value')
      .eq('key', 'gmail_app_password');
    smtpPass = cfgRows?.[0]?.value as string | undefined;
  } catch (e) {
    console.error('[delete-request] config fetch failed', e);
  }

  if (!smtpPass) {
    return NextResponse.json(
      { ok: false, message: 'E-posta servisi şu an kullanılamıyor.' },
      { status: 500 },
    );
  }

  // Send the email.
  const { subject, html } = renderEmail(signInLink);
  const t = transporter(smtpPass);
  try {
    await t.sendMail({ from: FROM, to: email, subject, html });
  } catch (e) {
    console.error('[delete-request] sendMail failed', e);
    return NextResponse.json(
      { ok: false, message: 'E-posta gönderilemedi. Lütfen tekrar dene.' },
      { status: 500 },
    );
  } finally {
    t.close();
  }

  return NextResponse.json(GENERIC_OK);
}
