// POST /api/push/send — FCM HTTP v1 push gönderimi (firebase-admin).
//
// ESKİ: supabase-edge-functions/send-push legacy `fcm/send` endpoint'ini
// kullanıyordu — Google Haziran 2024'te kapattı (404, hiç push gitmiyordu).
// YENİ: bu route firebase-admin SDK ile FCM HTTP v1 üzerinden gönderir.
//
// Auth: dahili-only. `X-Push-Secret` header'ı `PUSH_SEND_SECRET` env var'ı
// ile eşleşmeli. Env set değilse fail-closed (401) — yetkisiz çağrı geçmez.
//
// Çağıran: Supabase `send-push` edge function (outbound_queue webhook tüketicisi).
//
// curl örneği:
//   curl -X POST https://koala-api-olive.vercel.app/api/push/send \
//     -H "X-Push-Secret: $PUSH_SEND_SECRET" \
//     -H "Content-Type: application/json" \
//     -d '{"userId":"FIREBASE_UID","title":"Merhaba","body":"Test","data":{"type":"new_message"}}'

import { NextRequest, NextResponse } from 'next/server';
import { sendPushToUser } from '@/lib/push';

// firebase-admin Node.js gerektirir — edge runtime KULLANMA.
export const runtime = 'nodejs';
export const maxDuration = 30;

export async function POST(req: NextRequest) {
  // ─── Auth: shared secret (fail-closed) ────────────────────────
  const expectedSecret = process.env.PUSH_SEND_SECRET;
  if (!expectedSecret) {
    console.error('[push/send] PUSH_SEND_SECRET not configured — failing closed');
    return NextResponse.json(
      { error: 'push_secret_not_configured' },
      { status: 401 },
    );
  }
  const provided = req.headers.get('x-push-secret') ?? '';
  if (provided !== expectedSecret) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  // ─── Body parse ───────────────────────────────────────────────
  let body: {
    userId?: string;
    title?: string;
    body?: string;
    data?: Record<string, string>;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400 });
  }

  const userId = (body.userId ?? '').trim();
  const title = (body.title ?? '').trim();
  const text = (body.body ?? '').trim();

  if (!userId || !title || !text) {
    return NextResponse.json(
      { error: 'userId, title and body are required' },
      { status: 400 },
    );
  }

  // data alanını saf string-string map'e normalize et (FCM data zorunluluğu).
  let data: Record<string, string> | undefined;
  if (body.data && typeof body.data === 'object') {
    data = {};
    for (const [k, v] of Object.entries(body.data)) {
      if (v != null) data[k] = String(v);
    }
  }

  // ─── Gönder ───────────────────────────────────────────────────
  try {
    const result = await sendPushToUser({ userId, title, body: text, data });

    if (result.error) {
      console.error('[push/send] send error:', result.error);
      return NextResponse.json(
        { sent: 0, failed: 0, error: result.error },
        { status: 500 },
      );
    }

    return NextResponse.json({
      sent: result.sent,
      failed: result.failed,
      ...(result.noToken ? { noToken: true } : {}),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[push/send] unexpected error:', msg);
    return NextResponse.json(
      { sent: 0, failed: 0, error: msg },
      { status: 500 },
    );
  }
}
