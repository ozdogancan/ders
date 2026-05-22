import { NextRequest, NextResponse } from 'next/server';
import nodemailer from 'nodemailer';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const maxDuration = 60;
export const dynamic = 'force-dynamic';

/**
 * GET /api/cron/send-emails
 *
 * `outbound_queue` tablosundaki bekleyen e-posta (channel='email') satırlarını
 * işler ve Gmail SMTP (info@evlumba.com) üzerinden gönderir.
 *
 * Neden burada: n8n sunucusu (DigitalOcean) giden SMTP portlarını engelliyor.
 * Vercel'den SMTP çalışıyor. n8n bu endpoint'i dakikada bir tetikler.
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>` zorunlu.
 * Secret: koala_bridge_config.gmail_app_password (info@evlumba.com app password) —
 *         RLS kilitli tabloda, yalnız service_role okur. Vercel env gerekmez.
 */

const FROM = 'Koala <info@evlumba.com>';
const SMTP_USER = 'info@evlumba.com';

interface QueueRow {
  id: string;
  title: string | null;
  body: string | null;
  payload: Record<string, unknown> | null;
}

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/** Tasarımcıya "yeni mesajınız var" e-postası — Koala markalı HTML şablon. */
function renderDesignerEmail(row: QueueRow): { subject: string; html: string } {
  const p = row.payload ?? {};
  const senderName = esc((p.sender_name as string) || 'Bir Koala kullanıcısı');
  const message = esc((p.message as string) || row.body || '');
  const replyUrl = (p.reply_url as string) || 'https://www.evlumba.com';
  const subject =
    row.title || `${(p.sender_name as string) || 'Bir kullanıcı'} size mesaj gönderdi`;

  const html = `<!DOCTYPE html>
<html lang="tr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F1ECE3;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F1ECE3;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:484px;background:#FFFFFF;border-radius:24px;overflow:hidden;box-shadow:0 8px 32px rgba(108,92,231,0.12);">
        <tr><td style="background:linear-gradient(135deg,#7C6EF2 0%,#6C5CE7 100%);padding:30px 36px;">
          <span style="color:#ffffff;font-size:24px;font-weight:800;letter-spacing:-0.4px;">🐨 Koala</span>
        </td></tr>
        <tr><td style="padding:38px 36px 6px;">
          <p style="margin:0 0 6px;font-size:13px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;color:#7C6EF2;">Yeni mesaj</p>
          <p style="margin:0 0 16px;font-size:22px;font-weight:800;line-height:1.3;color:#16131F;">Bir müşteri sizinle iletişime geçti ✨</p>
          <p style="margin:0 0 22px;font-size:15px;line-height:1.65;color:#5E5A68;">
            <b style="color:#16131F;">${senderName}</b>, Koala uygulamasında bir tasarımınızı beğendi ve size ulaşmak istiyor:
          </p>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:6px;">
            <tr><td style="background:#F4F1FF;border-radius:14px;border-left:4px solid #7C6EF2;padding:18px 20px;font-size:15px;line-height:1.7;color:#16131F;">
              ${message}
            </td></tr>
          </table>
        </td></tr>
        <tr><td style="padding:22px 36px 6px;" align="center">
          <a href="${replyUrl}" style="display:inline-block;background:#6C5CE7;color:#ffffff;text-decoration:none;font-size:15px;font-weight:700;padding:16px 40px;border-radius:14px;box-shadow:0 4px 14px rgba(108,92,231,0.35);">Mesajı görüntüle ve cevapla</a>
        </td></tr>
        <tr><td style="padding:14px 36px 32px;">
          <p style="margin:0;font-size:13px;line-height:1.65;color:#9A95A6;text-align:center;">
            Tüm müşteri yazışmalarınızı tek yerden yönetmek için <b style="color:#6C5CE7;">Evlumba uygulamasını</b> indirin — mesajlara oradan da anında cevap verebilirsiniz.
          </p>
        </td></tr>
        <tr><td style="padding:20px 36px;background:#FAF9F6;border-top:1px solid #EEEAE1;">
          <p style="margin:0;font-size:12px;line-height:1.55;color:#A9A4B0;">
            Bu bildirim Koala &amp; Evlumba tarafından gönderildi. Sorularınız için <a href="mailto:info@evlumba.com" style="color:#7C6EF2;text-decoration:none;">info@evlumba.com</a>.
          </p>
        </td></tr>
      </table>
      <p style="margin:18px 0 0;font-size:11px;color:#B4AEA2;">© Evlumba · evlumba.com</p>
    </td></tr>
  </table>
</body>
</html>`;

  return { subject, html };
}

function authorized(req: NextRequest): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  return req.headers.get('authorization') === `Bearer ${secret}`;
}

export async function GET(req: NextRequest) {
  if (!authorized(req)) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = koalaAdmin();

  // Secret'ları RLS-kilitli config tablosundan al (yalnız service_role okur):
  //   bridge_secret      -> RPC koruması
  //   gmail_app_password -> Gmail SMTP şifresi
  const { data: cfgRows, error: cfgErr } = await admin
    .from('koala_bridge_config')
    .select('key, value')
    .in('key', ['bridge_secret', 'gmail_app_password']);
  if (cfgErr) {
    return NextResponse.json({ error: cfgErr.message }, { status: 500 });
  }
  const cfg = new Map(
    (cfgRows ?? []).map((r) => [r.key as string, r.value as string]),
  );
  const secret = cfg.get('bridge_secret');
  const pass = cfg.get('gmail_app_password');
  if (!secret) {
    return NextResponse.json(
      { error: 'bridge_secret not found in koala_bridge_config' },
      { status: 500 },
    );
  }
  if (!pass) {
    return NextResponse.json(
      { error: 'gmail_app_password not found in koala_bridge_config' },
      { status: 500 },
    );
  }

  // Bekleyen e-posta satırlarını atomik olarak claim et (attempts++).
  const { data: rows, error: fetchErr } = await admin.rpc(
    'koala_outbox_fetch_emails',
    { p_secret: secret },
  );
  if (fetchErr) {
    return NextResponse.json({ error: fetchErr.message }, { status: 500 });
  }

  const list: QueueRow[] = Array.isArray(rows) ? (rows as QueueRow[]) : [];
  if (list.length === 0) {
    return NextResponse.json({ processed: 0, sent: 0, failed: 0 });
  }

  const transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: { user: SMTP_USER, pass },
  });

  let sent = 0;
  let failed = 0;
  const errors: Array<{ id: string; error: string }> = [];

  for (const row of list) {
    const to = (row.payload?.email as string) || '';
    if (!to) {
      failed++;
      errors.push({ id: row.id, error: 'no recipient email in payload' });
      continue;
    }
    try {
      const { subject, html } = renderDesignerEmail(row);
      await transporter.sendMail({ from: FROM, to, subject, html });
      await admin.rpc('koala_outbox_mark_sent', { p_secret: secret, p_id: row.id });
      sent++;
    } catch (e) {
      // attempts fetch RPC'de zaten +1 oldu; satır 'pending' kalır, sonraki
      // turda tekrar denenir; max_attempts'e ulaşınca fetch artık almaz.
      failed++;
      errors.push({ id: row.id, error: e instanceof Error ? e.message : String(e) });
    }
  }

  transporter.close();

  return NextResponse.json({ processed: list.length, sent, failed, errors });
}
