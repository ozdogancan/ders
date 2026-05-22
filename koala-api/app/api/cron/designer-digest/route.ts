import { NextRequest, NextResponse } from 'next/server';
import nodemailer from 'nodemailer';
import { koalaAdmin } from '@/lib/supabase/koala';
import { evlumbaAdmin } from '@/lib/supabase/evlumba-admin';

export const runtime = 'nodejs';
export const maxDuration = 60;
export const dynamic = 'force-dynamic';

/**
 * GET /api/cron/designer-digest
 *
 * Günlük tasarımcı özet e-postası. Son çalışmadan bu yana gelen tüm
 * kullanıcı→tasarımcı mesajlarını toplar ve her tasarımcıya TEK bir
 * "bugün N yeni mesajınız var" e-postası gönderir (Gmail SMTP).
 *
 * Tasarımcı e-postaları Evlumba auth'tan, kullanıcı adları Evlumba shadow
 * user metadata'sından (firebase_uid) çözülür — Koala `users` tablosu boş.
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>`.
 * Tetik: günde 1 kez (vercel.json cron).
 */

const FROM = 'Koala <info@evlumba.com>';
const SMTP_USER = 'info@evlumba.com';
const CTA_URL = 'https://www.evlumba.com';

interface DigestRow {
  designer_id: string;
  designer_name: string;
  user_id: string;
  content: string | null;
  attachment_url: string | null;
  created_at: string;
}

function authorized(req: NextRequest): boolean {
  const secret = process.env.CRON_SECRET;
  return !!secret && req.headers.get('authorization') === `Bearer ${secret}`;
}

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function clamp(s: string, max = 220): string {
  const t = s.trim();
  return t.length > max ? t.slice(0, max).trimEnd() + '…' : t;
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'K';
  if (parts.length === 1) return parts[0].slice(0, 1).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

interface UserGroup {
  name: string;
  messages: { content: string; attachment_url: string | null; created_at: string }[];
}

/** Bir tasarımcının özet e-postasını üretir. */
function renderDigest(
  designerName: string,
  userGroups: UserGroup[],
  totalMessages: number,
): { subject: string; html: string } {
  const userCount = userGroups.length;
  const subject =
    totalMessages === 1
      ? 'Koala — 1 yeni mesajınız var'
      : `Koala — bugün ${totalMessages} yeni mesajınız var`;

  const greeting = esc(designerName.split(/\s+/)[0] || 'Merhaba');

  const blocks = userGroups
    .map((g) => {
      const msgs = g.messages
        .map((m) => {
          const text = m.content && m.content.trim().length > 0
            ? `<p style="margin:0;font-size:14px;line-height:1.6;color:#2A2733;">${esc(clamp(m.content))}</p>`
            : '';
          const img = m.attachment_url
            ? `<div style="margin-top:${text ? '10' : '0'}px;"><img src="${esc(m.attachment_url)}" alt="Görsel" width="180" style="display:block;width:180px;max-width:100%;border-radius:10px;border:1px solid #ECE8F5;"></div>`
            : '';
          return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:8px;"><tr><td style="background:#F6F4FB;border-radius:12px;padding:13px 15px;">${text}${img}</td></tr></table>`;
        })
        .join('');
      return `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:22px;">
        <tr>
          <td width="40" valign="top" style="padding-right:12px;">
            <div style="width:40px;height:40px;border-radius:50%;background:#EDEAFB;color:#6C5CE7;font-size:15px;font-weight:700;line-height:40px;text-align:center;">${esc(initials(g.name))}</div>
          </td>
          <td valign="middle">
            <p style="margin:0;font-size:15px;font-weight:700;color:#16131F;">${esc(g.name)}</p>
            <p style="margin:2px 0 0;font-size:12px;color:#9A95A6;">${g.messages.length} mesaj</p>
          </td>
        </tr>
        <tr><td colspan="2" style="padding-left:52px;">${msgs}</td></tr>
      </table>`;
    })
    .join('');

  const headline =
    totalMessages === 1
      ? '1 yeni mesajınız var'
      : `${totalMessages} yeni mesajınız var`;
  const sub =
    userCount === 1
      ? 'Bir müşteri size Koala üzerinden ulaştı.'
      : `${userCount} farklı müşteri size Koala üzerinden ulaştı.`;

  const html = `<!DOCTYPE html>
<html lang="tr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F1ECE3;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F1ECE3;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:520px;background:#FFFFFF;border-radius:24px;overflow:hidden;box-shadow:0 10px 36px rgba(108,92,231,0.13);">
        <tr><td style="background:linear-gradient(135deg,#7C6EF2 0%,#6C5CE7 100%);padding:30px 36px;">
          <span style="color:#ffffff;font-size:24px;font-weight:800;letter-spacing:-0.4px;">🐨 Koala</span>
        </td></tr>
        <tr><td style="padding:36px 36px 4px;">
          <p style="margin:0 0 4px;font-size:13px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;color:#7C6EF2;">Günlük özet</p>
          <p style="margin:0 0 6px;font-size:23px;font-weight:800;line-height:1.3;color:#16131F;">Merhaba ${greeting}, ${esc(headline)} ✨</p>
          <p style="margin:0;font-size:15px;line-height:1.6;color:#5E5A68;">${esc(sub)} İşte mesajları:</p>
        </td></tr>
        <tr><td style="padding:6px 36px 8px;">${blocks}</td></tr>
        <tr><td style="padding:30px 36px 8px;" align="center">
          <a href="${CTA_URL}" style="display:inline-block;background:#6C5CE7;color:#ffffff;text-decoration:none;font-size:15px;font-weight:700;padding:16px 44px;border-radius:14px;box-shadow:0 4px 14px rgba(108,92,231,0.35);">Tüm mesajları görüntüle ve cevapla</a>
        </td></tr>
        <tr><td style="padding:14px 36px 32px;">
          <p style="margin:0;font-size:13px;line-height:1.65;color:#9A95A6;text-align:center;">
            Müşterilerinize anında cevap vermek için <b style="color:#6C5CE7;">Evlumba uygulamasını</b> indirin — tüm yazışmalar tek yerde.
          </p>
        </td></tr>
        <tr><td style="padding:20px 36px;background:#FAF9F6;border-top:1px solid #EEEAE1;">
          <p style="margin:0;font-size:12px;line-height:1.55;color:#A9A4B0;">
            Bu özet Koala &amp; Evlumba tarafından günde bir kez gönderilir. Sorularınız için <a href="mailto:info@evlumba.com" style="color:#7C6EF2;text-decoration:none;">info@evlumba.com</a>.
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

export async function GET(req: NextRequest) {
  if (!authorized(req)) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = koalaAdmin();

  // Config: SMTP şifresi + son digest zamanı.
  const { data: cfgRows, error: cfgErr } = await admin
    .from('koala_bridge_config')
    .select('key, value')
    .in('key', ['gmail_app_password', 'last_digest_at']);
  if (cfgErr) {
    return NextResponse.json({ error: cfgErr.message }, { status: 500 });
  }
  const cfg = new Map(
    (cfgRows ?? []).map((r) => [r.key as string, r.value as string]),
  );
  const pass = cfg.get('gmail_app_password');
  if (!pass) {
    return NextResponse.json(
      { error: 'gmail_app_password not found in koala_bridge_config' },
      { status: 500 },
    );
  }
  const since =
    cfg.get('last_digest_at') ||
    new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const runStart = new Date().toISOString();

  // Pencere içindeki mesajlar.
  const { data: rows, error: rowsErr } = await admin.rpc(
    'koala_designer_digest_data',
    { p_since: since },
  );
  if (rowsErr) {
    return NextResponse.json({ error: rowsErr.message }, { status: 500 });
  }
  const list: DigestRow[] = Array.isArray(rows) ? (rows as DigestRow[]) : [];

  // Son digest zamanını her durumda ilerlet.
  const advanceClock = async () => {
    await admin
      .from('koala_bridge_config')
      .update({ value: runStart, updated_at: runStart })
      .eq('key', 'last_digest_at');
  };

  if (list.length === 0) {
    await advanceClock();
    return NextResponse.json({ designers: 0, sent: 0, messages: 0 });
  }

  // Evlumba: kullanıcı adlarını firebase_uid metadata'sından çöz.
  const userNameByFirebaseUid = new Map<string, string>();
  try {
    const evl = evlumbaAdmin();
    const { data: usersData } = await evl.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    for (const u of usersData?.users ?? []) {
      const fbUid = (u.user_metadata?.firebase_uid as string) || '';
      const name = (u.user_metadata?.display_name as string) || '';
      if (fbUid && name) userNameByFirebaseUid.set(fbUid, name);
    }
  } catch (e) {
    console.warn('[digest] evlumba listUsers failed:', e);
  }

  // Tasarımcıya göre grupla.
  const byDesigner = new Map<string, { name: string; rows: DigestRow[] }>();
  for (const r of list) {
    let d = byDesigner.get(r.designer_id);
    if (!d) {
      d = { name: r.designer_name || 'Tasarımcı', rows: [] };
      byDesigner.set(r.designer_id, d);
    }
    d.rows.push(r);
  }

  const transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: { user: SMTP_USER, pass },
  });
  const evl = evlumbaAdmin();

  let sent = 0;
  let skipped = 0;
  const errors: Array<{ designer_id: string; error: string }> = [];

  for (const [designerId, group] of byDesigner) {
    try {
      // Tasarımcı e-postası — Evlumba auth'tan.
      const { data: userRes, error: getErr } =
        await evl.auth.admin.getUserById(designerId);
      const email = userRes?.user?.email;
      if (getErr || !email) {
        skipped++;
        continue;
      }

      // Kullanıcıya göre alt grupla.
      const byUser = new Map<string, UserGroup>();
      for (const r of group.rows) {
        let ug = byUser.get(r.user_id);
        if (!ug) {
          ug = {
            name: userNameByFirebaseUid.get(r.user_id) || 'Koala müşterisi',
            messages: [],
          };
          byUser.set(r.user_id, ug);
        }
        ug.messages.push({
          content: r.content ?? '',
          attachment_url: r.attachment_url,
          created_at: r.created_at,
        });
      }

      const { subject, html } = renderDigest(
        group.name,
        Array.from(byUser.values()),
        group.rows.length,
      );
      await transporter.sendMail({ from: FROM, to: email, subject, html });
      sent++;
    } catch (e) {
      errors.push({
        designer_id: designerId,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  transporter.close();
  await advanceClock();

  return NextResponse.json({
    designers: byDesigner.size,
    sent,
    skipped,
    messages: list.length,
    errors,
  });
}
