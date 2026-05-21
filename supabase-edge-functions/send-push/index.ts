// DEPRECATED — legacy FCM endpoint decommissioned. Use koala-api /api/push/send instead.
//
// Bu Edge Function ARTIK doğrudan FCM'e gitmiyor. Google legacy
// `fcm.googleapis.com/fcm/send` endpoint'ini Haziran 2024'te kapattı (404).
//
// YENİ AKIŞ:
//   mesaj → DB trigger → outbound_queue → Supabase DB Webhook → bu fonksiyon
//        → koala-api POST /api/push/send (firebase-admin / FCM HTTP v1) → FCM
//
// Bu fonksiyon hâlâ outbound_queue webhook tüketicisi olarak duruyor (DB
// webhook'u onu çağırıyor, kolayca değiştirilemez). Tek yaptığı: kuyruktan
// payload'ı alıp koala-api'ye proxy'lemek ve kuyruk durumunu güncellemek.
// Gerçek gönderim koala-api'de firebase-admin ile yapılıyor.
//
// Gereken Edge Function Secret'ları (Supabase Dashboard > Edge Functions):
//   SUPABASE_URL                (otomatik)
//   SUPABASE_SERVICE_ROLE_KEY   (otomatik)
//   KOALA_API_URL               — örn. https://koala-api-olive.vercel.app
//   PUSH_SEND_SECRET            — koala-api'deki PUSH_SEND_SECRET ile AYNI değer
//
// FCM_SERVER_KEY artık KULLANILMIYOR — kaldırılabilir.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { record } = await req.json()

    // Sadece FCM push kanalını işle
    if (record.channel !== 'fcm_push') {
      return new Response('skip', { status: 200 })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const koalaApiUrl = Deno.env.get('KOALA_API_URL')
    const pushSecret = Deno.env.get('PUSH_SEND_SECRET')
    if (!koalaApiUrl || !pushSecret) {
      await supabase.from('outbound_queue').update({
        status: 'failed',
        attempts: record.attempts + 1,
        processed_at: new Date().toISOString(),
        last_error: 'KOALA_API_URL or PUSH_SEND_SECRET not configured',
      }).eq('id', record.id)
      return new Response('not_configured', { status: 500 })
    }

    // koala-api'ye proxy'le — token lookup + FCM HTTP v1 gönderimi orada yapılır.
    const res = await fetch(`${koalaApiUrl}/api/push/send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Push-Secret': pushSecret,
      },
      body: JSON.stringify({
        userId: record.user_id,
        title: record.title,
        body: record.body,
        data: record.payload ?? {},
      }),
    })

    let result: { sent?: number; failed?: number; noToken?: boolean; error?: string } = {}
    try {
      result = await res.json()
    } catch {
      // gövde JSON değilse boş bırak
    }

    // Token yoksa skipped, en az 1 başarılıysa sent, aksi failed.
    let status: 'sent' | 'failed' | 'skipped'
    let lastError: string | null = null
    if (result.noToken) {
      status = 'skipped'
    } else if (res.ok && (result.sent ?? 0) > 0) {
      status = 'sent'
    } else {
      status = 'failed'
      lastError = result.error ?? `koala-api ${res.status}`
    }

    await supabase.from('outbound_queue').update({
      status,
      attempts: record.attempts + 1,
      processed_at: new Date().toISOString(),
      last_error: lastError,
    }).eq('id', record.id)

    return new Response('ok', { status: 200 })
  } catch (e: any) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500 })
  }
})
