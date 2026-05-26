// POST /api/admin/test-push — manuel test push gönderici.
//
// Auth: `?token=$ADMIN_TOKEN` query param ile shared-secret check.
//       (grant-pro Authorization header kullanıyor; bu endpoint'i curl'den
//        tek satırda çağırmak için query param tercih edildi.)
//
// Kullanım:
//   curl -X POST 'https://koala-api-olive.vercel.app/api/admin/test-push?token=YOUR_ADMIN_TOKEN&uid=jySTWZ6ewGUo8WZtFMPvQsOc6Yo1'
//
// Body opsiyonel. Boş bırakılırsa hard-coded test mesajı gönderilir:
//   title: "Koala test 🐨"
//   body : "Sistem çalışıyor — bildirim ulaştı."
// Body verilirse JSON: { title?, body?, data? } ile override edilir.
//
// Cevap: { ok: true, sent, failed, noToken? } | { error }

import { NextRequest, NextResponse } from 'next/server';
import { sendPushToUser } from '@/lib/push';

export const runtime = 'nodejs';
export const maxDuration = 30;

export async function POST(req: NextRequest) {
  const adminToken = process.env.ADMIN_TOKEN;
  if (!adminToken) {
    return NextResponse.json(
      { error: 'admin_token_not_configured' },
      { status: 500 },
    );
  }

  const { searchParams } = new URL(req.url);
  const providedToken = searchParams.get('token') ?? '';
  if (providedToken !== adminToken) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const uid = (searchParams.get('uid') ?? '').trim();
  if (!uid) {
    return NextResponse.json(
      { error: 'uid query param required' },
      { status: 400 },
    );
  }

  // Body override (opsiyonel). Hata olursa default mesajla devam et.
  let override: {
    title?: string;
    body?: string;
    data?: Record<string, string>;
  } = {};
  try {
    const len = req.headers.get('content-length');
    if (len && parseInt(len, 10) > 0) {
      override = await req.json();
    }
  } catch {
    /* JSON parse fail — default ile devam */
  }

  const title = (override.title ?? '').trim() || 'Koala test 🐨';
  const body = (override.body ?? '').trim() || 'Sistem çalışıyor — bildirim ulaştı.';
  const data: Record<string, string> = {
    type: 'system',
    action_type: 'open_notifications',
    deep_link: '/notifications',
    ...(override.data ?? {}),
  };

  try {
    const result = await sendPushToUser({ userId: uid, title, body, data });
    if (result.error) {
      console.error('[admin/test-push] send error:', result.error);
      return NextResponse.json(
        { ok: false, sent: 0, failed: 0, error: result.error },
        { status: 500 },
      );
    }
    return NextResponse.json({
      ok: true,
      sent: result.sent,
      failed: result.failed,
      ...(result.noToken ? { noToken: true } : {}),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[admin/test-push] unexpected error:', msg);
    return NextResponse.json(
      { ok: false, error: msg },
      { status: 500 },
    );
  }
}
