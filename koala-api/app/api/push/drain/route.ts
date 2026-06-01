// POST /api/push/drain — outbound_queue (fcm_push) kuyruğunu boşaltıp FCM
// push'larını gönderir. Mesaj/pro-onay/review gibi tüm bildirimler
// koala_notifications + outbound_queue'ya düşer; bu endpoint kuyruğu drenajla
// gerçek push'a çevirir.
//
// Auth: n8n dakikalık cron çağırır. `x-bridge-secret` header'ı
// koala_bridge_config.bridge_secret ile eşleşmeli (n8n bu secret'ı zaten
// Telegram köprüsünde kullanıyor). Alternatif olarak PUSH_SEND_SECRET de kabul.
//
// Idempotent + güvenli: token'ı olmayan kullanıcıda satır 'sent' işaretlenir
// (sonsuz retry olmaz); gerçek hata 3 denemeye kadar 'pending' kalır, sonra
// 'failed'.

import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { sendPushToUser } from '@/lib/push';

export const runtime = 'nodejs';
export const maxDuration = 60;

export async function POST(req: NextRequest) {
  const db = koalaAdmin();

  // ─── Auth: bridge_secret (n8n) veya PUSH_SEND_SECRET ──────────────
  const provided =
    req.headers.get('x-bridge-secret') ??
    req.headers.get('x-push-secret') ??
    '';
  let authorized = false;
  if (process.env.PUSH_SEND_SECRET && provided === process.env.PUSH_SEND_SECRET) {
    authorized = true;
  } else if (provided) {
    try {
      const { data } = await db
        .from('koala_bridge_config')
        .select('value')
        .eq('key', 'bridge_secret')
        .maybeSingle();
      if (data?.value && data.value === provided) authorized = true;
    } catch {
      /* ignore */
    }
  }
  if (!authorized) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  // ─── Bekleyen fcm_push satırlarını çek ────────────────────────────
  const nowIso = new Date().toISOString();
  const { data: rows, error } = await db
    .from('outbound_queue')
    .select('id, user_id, title, body, payload, attempts, max_attempts')
    .eq('channel', 'fcm_push')
    .eq('status', 'pending')
    .lte('send_after', nowIso)
    .order('created_at', { ascending: true })
    .limit(40);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  if (!rows || rows.length === 0) {
    return NextResponse.json({ ok: true, drained: 0, sent: 0, failed: 0 });
  }

  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      const data: Record<string, string> = {};
      const p = (row.payload ?? {}) as Record<string, unknown>;
      for (const k of Object.keys(p)) {
        if (p[k] != null) data[k] = String(p[k]);
      }
      const res = await sendPushToUser({
        userId: String(row.user_id),
        title: (row.title as string) || 'Koala',
        body: (row.body as string) || '',
        data,
      });
      // Token yoksa da 'sent' işaretle — sonsuz retry'ı önle. Gerçek init/FCM
      // hatası varsa retry'a bırak.
      if (res.error && !res.noToken) {
        throw new Error(res.error);
      }
      await db
        .from('outbound_queue')
        .update({ status: 'sent', processed_at: new Date().toISOString() })
        .eq('id', row.id);
      sent++;
    } catch (e) {
      const attempts = ((row.attempts as number) ?? 0) + 1;
      const max = (row.max_attempts as number) ?? 3;
      await db
        .from('outbound_queue')
        .update({
          attempts,
          status: attempts >= max ? 'failed' : 'pending',
          last_error: String((e as Error)?.message ?? e).slice(0, 300),
          send_after: new Date(Date.now() + 60_000).toISOString(),
        })
        .eq('id', row.id);
      failed++;
    }
  }

  return NextResponse.json({ ok: true, drained: rows.length, sent, failed });
}
