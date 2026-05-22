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
 * Tasarımcılara "cevap bekleyen mesajlarınız" özet e-postası gönderir.
 *
 * Kadans (aşırı bildirim engelli):
 *   - Günlük kontrol edilir ama her gün mail atılmaz.
 *   - Yalnızca son bildirimden DAHA YENİ cevapsız mesaj varsa özet gider.
 *   - Yeni mesaj yoksa, ilk mailden REMINDER_DAYS gün sonra TEK hatırlatma.
 *   - Bir grup cevapsız mesaj için en fazla 1 özet + 1 hatırlatma.
 *
 * "Cevap bekleyen" = tasarımcının son cevabından sonra gelen kullanıcı
 * mesajları (tasarımcı cevapları inbound sync ile Koala'ya düşer).
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>`. Test: `?test=<email>`.
 */

const FROM = 'Koala <info@evlumba.com>';
const SMTP_USER = 'info@evlumba.com';
const CTA_URL = 'https://www.evlumba.com';
const REMINDER_DAYS = 3;
const MAX_PER_SENDER = 6;

interface PendingRow {
  designer_id: string;
  designer_name: string;
  user_id: string;
  content: string | null;
  attachment_url: string | null;
  created_at: string;
}
interface StateRow {
  designer_id: string;
  last_notified_at: string | null;
  last_emailed_at: string | null;
  reminded: boolean;
}
interface MailMessage {
  content: string;
  attachment_url: string | null;
  created_at: string;
}
interface UserGroup {
  name: string;
  messages: MailMessage[];
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

function clamp(s: string, max = 200): string {
  const t = s.trim();
  return t.length > max ? t.slice(0, max).trimEnd() + '…' : t;
}

function initials(name: string): string {
  const p = name.trim().split(/\s+/).filter(Boolean);
  if (p.length === 0) return 'K';
  if (p.length === 1) return p[0].slice(0, 1).toLocaleUpperCase('tr');
  return (p[0][0] + p[p.length - 1][0]).toLocaleUpperCase('tr');
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const h = Math.floor(diff / 3_600_000);
  if (h < 1) return 'az önce';
  if (h < 24) return `${h} saat önce`;
  const d = Math.floor(h / 24);
  return d === 1 ? 'dün' : `${d} gün önce`;
}

/** Modern, sade tasarımcı bildirim e-postası. */
function renderEmail(opts: {
  designerName: string;
  userGroups: UserGroup[];
  total: number;
  isReminder: boolean;
}): { subject: string; html: string } {
  const { designerName, userGroups, total, isReminder } = opts;
  const firstName = esc(designerName.split(/\s+/)[0] || 'Merhaba');
  const userCount = userGroups.length;

  const subject = isReminder
    ? `Hatırlatma — ${total} mesaj hâlâ yanıtınızı bekliyor`
    : total === 1
      ? 'Koala — cevap bekleyen 1 mesajınız var'
      : `Koala — cevap bekleyen ${total} mesajınız var`;

  const headline = isReminder
    ? total === 1
      ? '1 mesaj hâlâ yanıtınızı bekliyor'
      : `${total} mesaj hâlâ yanıtınızı bekliyor`
    : total === 1
      ? 'Cevap bekleyen 1 mesajınız var'
      : `Cevap bekleyen ${total} mesajınız var`;

  const sub = isReminder
    ? 'Bu müşteriler birkaç gündür yanıtınızı bekliyor — kısa bir cevap bile farkı yaratır.'
    : userCount === 1
      ? 'Bir müşteri Koala üzerinden size ulaştı.'
      : `${userCount} farklı müşteri Koala üzerinden size ulaştı.`;

  // Gönderen başına TEK balon: ardışık mesajlar içeride ince ayraçlı
  // satırlar halinde, en fazla MAX_PER_SENDER tanesi gösterilir.
  const senderBlocks = userGroups
    .map((g, idx) => {
      const latest = g.messages[g.messages.length - 1];
      const shownMsgs = g.messages.slice(0, MAX_PER_SENDER);
      const extra = g.messages.length - shownMsgs.length;

      const rows = shownMsgs
        .map((m) => {
          const parts: string[] = [];
          if (m.content && m.content.trim()) {
            parts.push(
              `<p style="margin:0;font-size:14px;line-height:1.55;color:#3C3C44;">${esc(clamp(m.content, 150))}</p>`,
            );
          }
          if (m.attachment_url) {
            parts.push(
              `<div style="margin-top:${parts.length ? '7' : '0'}px;"><img src="${esc(m.attachment_url)}" alt="Görsel" width="190" style="display:block;width:190px;max-width:100%;border-radius:8px;border:1px solid #EAEAEE;"></div>`,
            );
          }
          return `<tr><td style="padding:9px 0;">${parts.join('')}</td></tr>`;
        })
        .join(
          '<tr><td style="border-top:1px solid #F0F0F3;font-size:0;line-height:0;">&nbsp;</td></tr>',
        );
      const more =
        extra > 0
          ? `<tr><td style="border-top:1px solid #F0F0F3;padding:9px 0 0;font-size:12.5px;color:#9A9AA4;">+${extra} mesaj daha</td></tr>`
          : '';
      const bubble = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:11px;background:#FAFAFB;border:1px solid #EDEDF0;border-radius:10px;"><tr><td style="padding:3px 14px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0">${rows}${more}</table></td></tr></table>`;

      const divider =
        idx < userGroups.length - 1
          ? '<tr><td colspan="2" style="padding-top:24px;"><div style="border-top:1px solid #EFEFF2;font-size:0;line-height:0;">&nbsp;</div></td></tr>'
          : '';
      return `
        <tr>
          <td width="40" valign="top" style="padding:24px 12px 0 0;">
            <div style="width:40px;height:40px;border-radius:50%;background:#F0EFF6;color:#6C5CE7;font-size:14px;font-weight:700;line-height:40px;text-align:center;">${esc(initials(g.name))}</div>
          </td>
          <td valign="top" style="padding-top:24px;">
            <p style="margin:0;font-size:15px;font-weight:700;color:#17171C;">${esc(g.name)}</p>
            <p style="margin:3px 0 0;font-size:12.5px;color:#9A9AA4;">${g.messages.length} mesaj &middot; ${esc(timeAgo(latest.created_at))}</p>
            ${bubble}
          </td>
        </tr>
        ${divider}`;
    })
    .join('');

  const reminderPill = isReminder
    ? '<tr><td style="padding:0 0 14px;"><span style="display:inline-block;background:#FEF3E2;color:#B7791F;font-size:11px;font-weight:700;letter-spacing:0.6px;padding:5px 11px;border-radius:6px;">HATIRLATMA</span></td></tr>'
    : '';

  const html = `<!DOCTYPE html>
<html lang="tr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F2F2F4;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F2F4;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:544px;background:#FFFFFF;border:1px solid #E7E7EB;border-radius:16px;overflow:hidden;">
        <tr><td style="padding:22px 32px;border-bottom:1px solid #EEEEF1;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td style="font-size:18px;font-weight:800;color:#6C5CE7;letter-spacing:-0.3px;">Koala</td>
            <td align="right" style="font-size:12px;color:#A8A8B2;">Tasarımcı bildirimi</td>
          </tr></table>
        </td></tr>
        <tr><td style="padding:32px 32px 8px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${reminderPill}
            <tr><td>
              <p style="margin:0;font-size:20px;font-weight:800;line-height:1.35;color:#17171C;">Merhaba ${firstName}, ${esc(headline)}</p>
              <p style="margin:8px 0 0;font-size:14px;line-height:1.6;color:#6E6E78;">${esc(sub)}</p>
            </td></tr>
          </table>
        </td></tr>
        <tr><td style="padding:4px 32px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${senderBlocks}</table>
        </td></tr>
        <tr><td style="padding:30px 32px 6px;" align="center">
          <a href="${CTA_URL}" style="display:inline-block;background:#6C5CE7;color:#ffffff;text-decoration:none;font-size:14.5px;font-weight:600;padding:14px 32px;border-radius:11px;">Tüm mesajları görüntüle</a>
        </td></tr>
        <tr><td style="padding:12px 32px 30px;">
          <p style="margin:0;font-size:13px;line-height:1.6;color:#9A9AA4;text-align:center;">Anında cevap vermek için <span style="color:#6C5CE7;font-weight:600;">Evlumba uygulamasını</span> indirin.</p>
        </td></tr>
        <tr><td style="padding:18px 32px;background:#FAFAFB;border-top:1px solid #EEEEF1;">
          <p style="margin:0;font-size:12px;line-height:1.55;color:#A8A8B2;">Bu e-posta, Koala'da cevap bekleyen mesajlarınız için gönderildi. Sorularınız için <a href="mailto:info@evlumba.com" style="color:#8A82E0;text-decoration:none;">info@evlumba.com</a>.</p>
        </td></tr>
      </table>
      <p style="margin:16px 0 0;font-size:11px;color:#B4B4BC;">&copy; Evlumba &middot; evlumba.com</p>
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

export async function GET(req: NextRequest) {
  if (!authorized(req)) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = koalaAdmin();

  const { data: cfgRows, error: cfgErr } = await admin
    .from('koala_bridge_config')
    .select('key, value')
    .eq('key', 'gmail_app_password');
  if (cfgErr) {
    return NextResponse.json({ error: cfgErr.message }, { status: 500 });
  }
  const pass = cfgRows?.[0]?.value as string | undefined;
  if (!pass) {
    return NextResponse.json(
      { error: 'gmail_app_password not found in koala_bridge_config' },
      { status: 500 },
    );
  }

  // ─── TEST MODU ───────────────────────────────────────────────
  const testEmail = req.nextUrl.searchParams.get('test');
  const testReminder = req.nextUrl.searchParams.get('reminder') === '1';
  if (testEmail) {
    // Ahmet: WhatsApp tarzı ardışık burst (8 mesaj) — collapse'i gösterir.
    const burst = [
      'Selam',
      'Nasılsınız?',
      'Bir sorum olacaktı',
      'Profilinizdeki salon tasarımını çok beğendim',
      'Acaba yeni proje için müsait misiniz',
      'Bütçem orta seviye',
      'Fiyat ve süre alabilir miyim',
      'Cevabınızı bekliyorum, teşekkürler',
    ].map((c, i) => ({
      content: c,
      attachment_url: null,
      created_at: new Date(Date.now() - (8 - i) * 1800_000).toISOString(),
    }));
    const sample: UserGroup[] = [
      { name: 'Ahmet Yılmaz', messages: burst },
      {
        name: 'Zeynep Kaya',
        messages: [
          {
            content:
              'Yatak odam için fikirlerinizi merak ediyorum. Aşağıdaki gibi bir atmosfer hayal ediyorum:',
            attachment_url: 'https://picsum.photos/seed/koala/400/260',
            created_at: new Date(Date.now() - 26 * 3600_000).toISOString(),
          },
        ],
      },
    ];
    const { subject, html } = renderEmail({
      designerName: 'Tasarımcı',
      userGroups: sample,
      total: burst.length + 1,
      isReminder: testReminder,
    });
    const t = transporter(pass);
    try {
      await t.sendMail({ from: FROM, to: testEmail, subject: `[TEST] ${subject}`, html });
    } finally {
      t.close();
    }
    return NextResponse.json({ test: true, reminder: testReminder, sentTo: testEmail });
  }

  // ─── Cevap bekleyen mesajlar ─────────────────────────────────
  const { data: rows, error: rowsErr } = await admin.rpc(
    'koala_designer_pending_digest',
  );
  if (rowsErr) {
    return NextResponse.json({ error: rowsErr.message }, { status: 500 });
  }
  const list: PendingRow[] = Array.isArray(rows) ? (rows as PendingRow[]) : [];
  if (list.length === 0) {
    return NextResponse.json({ designers: 0, digests: 0, reminders: 0 });
  }

  // Durum tablosu.
  const { data: stateData } = await admin
    .from('koala_designer_email_state')
    .select('designer_id, last_notified_at, last_emailed_at, reminded');
  const stateMap = new Map<string, StateRow>(
    (stateData ?? []).map((s) => [s.designer_id as string, s as StateRow]),
  );

  // Evlumba: kullanıcı adları (firebase_uid → display_name).
  const userNames = new Map<string, string>();
  try {
    const { data: u } = await evlumbaAdmin().auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    for (const usr of u?.users ?? []) {
      const fb = (usr.user_metadata?.firebase_uid as string) || '';
      const nm = (usr.user_metadata?.display_name as string) || '';
      if (fb && nm) userNames.set(fb, nm);
    }
  } catch (e) {
    console.warn('[digest] evlumba listUsers failed:', e);
  }

  // Tasarımcıya göre grupla.
  const byDesigner = new Map<string, { name: string; rows: PendingRow[] }>();
  for (const r of list) {
    let d = byDesigner.get(r.designer_id);
    if (!d) {
      d = { name: r.designer_name || 'Tasarımcı', rows: [] };
      byDesigner.set(r.designer_id, d);
    }
    d.rows.push(r);
  }

  const t = transporter(pass);
  const evl = evlumbaAdmin();
  let digests = 0;
  let reminders = 0;
  let skipped = 0;
  const errors: Array<{ designer_id: string; error: string }> = [];

  for (const [designerId, group] of byDesigner) {
    try {
      const newest = group.rows
        .map((r) => r.created_at)
        .reduce((a, b) => (a > b ? a : b));
      const st = stateMap.get(designerId);

      let mode: 'digest' | 'reminder' | null = null;
      if (!st || !st.last_notified_at || newest > st.last_notified_at) {
        mode = 'digest';
      } else if (
        !st.reminded &&
        st.last_emailed_at &&
        Date.now() - new Date(st.last_emailed_at).getTime() >=
          REMINDER_DAYS * 86_400_000
      ) {
        mode = 'reminder';
      }
      if (!mode) {
        skipped++;
        continue;
      }

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
          ug = { name: userNames.get(r.user_id) || 'Koala müşterisi', messages: [] };
          byUser.set(r.user_id, ug);
        }
        ug.messages.push({
          content: r.content ?? '',
          attachment_url: r.attachment_url,
          created_at: r.created_at,
        });
      }

      const { subject, html } = renderEmail({
        designerName: group.name,
        userGroups: Array.from(byUser.values()),
        total: group.rows.length,
        isReminder: mode === 'reminder',
      });
      await t.sendMail({ from: FROM, to: email, subject, html });

      const nowIso = new Date().toISOString();
      await admin.from('koala_designer_email_state').upsert(
        {
          designer_id: designerId,
          last_notified_at: newest,
          last_emailed_at: nowIso,
          reminded: mode === 'reminder',
          updated_at: nowIso,
        },
        { onConflict: 'designer_id' },
      );

      if (mode === 'reminder') reminders++;
      else digests++;
    } catch (e) {
      errors.push({
        designer_id: designerId,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  t.close();

  return NextResponse.json({
    designers: byDesigner.size,
    digests,
    reminders,
    skipped,
    errors,
  });
}
