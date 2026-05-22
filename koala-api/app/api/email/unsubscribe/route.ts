import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * GET /api/email/unsubscribe?k=designer&d=<id>&t=<token>
 *
 * Koala bildirim e-postalarındaki "abonelikten çık" bağlantısı.
 * Token = HMAC(kind:id, CRON_SECRET) — depolama gerektirmez.
 */

function unsubToken(kind: string, id: string): string {
  return crypto
    .createHmac('sha256', process.env.CRON_SECRET || 'koala')
    .update(`${kind}:${id}`)
    .digest('hex')
    .slice(0, 24);
}

function page(title: string, body: string): NextResponse {
  const html = `<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="margin:0;background:#F2F2F4;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="max-width:440px;margin:80px auto;background:#fff;border:1px solid #E7E7EB;border-radius:16px;padding:36px 32px;text-align:center;">
    <div style="font-size:17px;font-weight:800;color:#17171C;margin-bottom:20px;">Koala <span style="font-weight:500;color:#9A9AA4;font-size:13px;">by Evlumba</span></div>
    <p style="font-size:17px;font-weight:600;color:#23232A;margin:0 0 8px;">${title}</p>
    <p style="font-size:14px;line-height:1.6;color:#6E6E78;margin:0;">${body}</p>
  </div>
</body></html>`;
  return new NextResponse(html, {
    status: 200,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });
}

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const kind = sp.get('k') || '';
  const id = sp.get('d') || '';
  const token = sp.get('t') || '';

  if (!id || !token || token !== unsubToken(kind, id)) {
    return page(
      'Bağlantı geçersiz',
      'Bu abonelik bağlantısı geçersiz veya hatalı. Yardım için info@evlumba.com adresine yazabilirsiniz.',
    );
  }

  try {
    const admin = koalaAdmin();
    if (kind === 'designer') {
      await admin.from('koala_designer_email_state').upsert(
        {
          designer_id: id,
          unsubscribed: true,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'designer_id' },
      );
    } else {
      return page('Bağlantı geçersiz', 'Bu abonelik bağlantısı tanınmadı.');
    }
  } catch {
    return page(
      'Bir hata oluştu',
      'İşlem tamamlanamadı. Lütfen daha sonra tekrar deneyin.',
    );
  }

  return page(
    'Aboneliğiniz iptal edildi',
    'Artık Koala mesaj bildirim e-postaları almayacaksınız. Fikrinizi değiştirirseniz info@evlumba.com adresinden bize ulaşabilirsiniz.',
  );
}
