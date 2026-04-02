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

    // Kullanıcının FCM token'larını çek
    const { data: tokens } = await supabase
      .from('koala_push_tokens')
      .select('device_token')
      .eq('user_id', record.user_id)
      .eq('is_active', true)
      .order('last_used_at', { ascending: false })
      .limit(2)

    if (!tokens || tokens.length === 0) {
      await supabase.from('outbound_queue')
        .update({ status: 'skipped', processed_at: new Date().toISOString() })
        .eq('id', record.id)
      return new Response('no_token', { status: 200 })
    }

    // FCM gönder (her token için dene)
    let success = false
    for (const t of tokens) {
      const res = await fetch('https://fcm.googleapis.com/fcm/send', {
        method: 'POST',
        headers: {
          'Authorization': 'key=' + Deno.env.get('FCM_SERVER_KEY')!,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          to: t.device_token,
          notification: { title: record.title, body: record.body },
          data: record.payload,
        }),
      })
      if (res.ok) success = true
    }

    // Kuyruk durumunu güncelle
    await supabase.from('outbound_queue').update({
      status: success ? 'sent' : 'failed',
      attempts: record.attempts + 1,
      processed_at: new Date().toISOString(),
      last_error: success ? null : 'FCM request failed',
    }).eq('id', record.id)

    return new Response('ok', { status: 200 })
  } catch (e: any) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500 })
  }
})
