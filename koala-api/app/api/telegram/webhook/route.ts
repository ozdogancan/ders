// POST /api/telegram/webhook
//
// Evlumba Stüdyo Telegram grubundaki Onayla/Reddet inline butonlarının
// callback'ini işler. Pro başvuru kararını verir:
//   1) koala_pro_application_decide RPC (status + profil mode=pro/verified +
//      koala_notifications satırı)
//   2) sendPushToUser ile gerçek FCM push (kullanıcı anlık bilgilensin)
//   3) answerCallbackQuery + mesajı düzenle (sonucu yaz, butonları kaldır)
//
// Auth: Telegram setWebhook `secret_token` → her istekte
// `X-Telegram-Bot-Api-Secret-Token` header'ı. koala_bridge_config
// 'tg_webhook_secret' ile eşleşmezse 401. Bot token da aynı tablodan.
//
// callback_data formatı: `prodec:<approve|reject>:<application_uuid>`

import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { sendPushToUser } from '@/lib/push';

export const runtime = 'nodejs';
export const maxDuration = 30;

interface TgCallbackQuery {
  id: string;
  from?: { username?: string; first_name?: string; id?: number };
  message?: { message_id: number; chat: { id: number }; text?: string };
  data?: string;
}

async function tg(token: string, method: string, body: unknown): Promise<void> {
  try {
    // 2026-06-02: Türkçe karakterler "?" gelmesin diye açık UTF-8 encode.
    await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: new TextEncoder().encode(JSON.stringify(body)),
    });
  } catch (e) {
    console.warn(`[tg/webhook] ${method} failed:`, e instanceof Error ? e.message : String(e));
  }
}

export async function POST(req: NextRequest) {
  const sb = koalaAdmin();

  // ─── Config: bot token + webhook secret ──────────────────────────
  const { data: cfgRows } = await sb
    .from('koala_bridge_config')
    .select('key, value')
    .in('key', ['tg_bot_token', 'tg_webhook_secret']);
  const cfg = new Map((cfgRows ?? []).map((r) => [r.key as string, r.value as string]));
  const tgToken = cfg.get('tg_bot_token');
  const webhookSecret = cfg.get('tg_webhook_secret');

  // ─── Auth: secret header (fail-closed) ───────────────────────────
  const provided = req.headers.get('x-telegram-bot-api-secret-token') ?? '';
  if (!webhookSecret || provided !== webhookSecret) {
    return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }
  if (!tgToken) {
    return NextResponse.json({ ok: false, error: 'bot_token_missing' }, { status: 500 });
  }

  let update: { callback_query?: TgCallbackQuery };
  try {
    update = await req.json();
  } catch {
    return NextResponse.json({ ok: true }); // yut, Telegram retry etmesin
  }

  const cq = update.callback_query;
  // callback dışındaki update'leri (mesaj vs.) sessizce yok say.
  if (!cq || !cq.data) return NextResponse.json({ ok: true });

  const m = cq.data.match(/^prodec:(approve|reject):(.+)$/);
  if (!m) {
    await tg(tgToken, 'answerCallbackQuery', { callback_query_id: cq.id });
    return NextResponse.json({ ok: true });
  }

  const action = m[1];
  const appId = m[2];
  const newStatus = action === 'approve' ? 'approved' : 'rejected';
  const reviewer = `telegram:${cq.from?.username ?? cq.from?.first_name ?? cq.from?.id ?? '?'}`;

  // ─── Karar ver ───────────────────────────────────────────────────
  const { data: rpcRes, error: rpcErr } = await sb.rpc('koala_pro_application_decide', {
    p_id: appId,
    p_status: newStatus,
    p_reviewer: reviewer,
    p_notes: null,
  });

  const result = (rpcRes ?? {}) as { ok?: boolean; uid?: string; error?: string };

  if (rpcErr || result.error) {
    const why = rpcErr?.message ?? result.error ?? 'unknown';
    await tg(tgToken, 'answerCallbackQuery', {
      callback_query_id: cq.id,
      text: why === 'not_pending'
        ? 'Bu başvuru zaten karara bağlanmış.'
        : `Hata: ${why}`,
      show_alert: true,
    });
    return NextResponse.json({ ok: false, error: why });
  }

  const uid = result.uid;

  // ─── Push (best-effort) ──────────────────────────────────────────
  let pushNote = '';
  if (uid) {
    const title = newStatus === 'approved'
      ? 'Tebrikler! Profesyonel olarak onaylandın 🎉'
      : 'Başvurun şu an için onaylanmadı';
    const body = newStatus === 'approved'
      ? 'Artık Koala’da tasarımlarını paylaşabilir, takipçi toplayabilirsin.'
      : 'Detaylar için profil ekranındaki başvuru durumunu kontrol et.';
    try {
      const pr = await sendPushToUser({
        userId: uid,
        title,
        body,
        data: { type: 'pro_decision', action_type: 'open_profile', status: newStatus },
      });
      pushNote = pr.noToken
        ? ' (cihaz token yok → push gitmedi)'
        : pr.error
          ? ` (push hata: ${pr.error})`
          : ` (push: ${pr.sent} cihaz)`;
    } catch (e) {
      pushNote = ` (push exception: ${e instanceof Error ? e.message : String(e)})`;
    }
  }

  // ─── Telegram'da geri bildirim: popup + mesajı düzenle ───────────
  const verdict = newStatus === 'approved' ? '✅ ONAYLANDI' : '❌ REDDEDİLDİ';
  await tg(tgToken, 'answerCallbackQuery', {
    callback_query_id: cq.id,
    text: `${verdict}${pushNote}`,
  });
  if (cq.message) {
    const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
    const newText = `${cq.message.text ?? ''}\n\n━━━━━━━━━━\n${verdict} · ${reviewer} · ${stamp} UTC${pushNote}`;
    await tg(tgToken, 'editMessageText', {
      chat_id: cq.message.chat.id,
      message_id: cq.message.message_id,
      text: newText,
      reply_markup: { inline_keyboard: [] }, // butonları kaldır
    });
  }

  return NextResponse.json({ ok: true, status: newStatus, uid });
}
