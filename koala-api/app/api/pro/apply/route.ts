import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, isOriginAllowed } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const maxDuration = 30;

/**
 * POST /api/pro/apply
 *
 * Body:
 *   { uid, full_name, profession, city?, ig_url?, portfolio_url?, reason? }
 *
 * 1) `koala_pro_apply` RPC ile başvuruyu kaydet (pending) — re-submit safe.
 * 2) Evlumba Stüdyo Telegram grubuna admin uyarısı gönder. Admin SQL ya da
 *    ileride gelecek admin paneli üzerinden karar verir (koala_pro_application_decide).
 *
 * Auth: app kullanıcısı (Bearer ya da X-User-Id) — billing/status ile aynı
 * dual-mode davranış. Origin allowlist kontrol.
 */

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'), 'POST, OPTIONS');
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers: cors });
  }

  const authResult = await verifyAuthHeader(req);
  const xUserId = req.headers.get('x-user-id');
  logAuthOutcome('pro/apply', authResult, { userId: xUserId });
  if (!authResult.ok && !xUserId) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers: cors },
    );
  }
  const uid = authResult.uid ?? xUserId;
  if (!uid) {
    return NextResponse.json(
      { error: 'unauthorized', reason: 'no-uid' },
      { status: 401, headers: cors },
    );
  }

  let body: {
    full_name?: string;
    profession?: string;
    city?: string;
    ig_url?: string;
    portfolio_url?: string;
    reason?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers: cors });
  }

  const fullName = (body.full_name ?? '').trim();
  const profession = (body.profession ?? '').trim();
  const city = (body.city ?? '').trim() || null;
  const igUrl = (body.ig_url ?? '').trim() || null;
  const portfolioUrl = (body.portfolio_url ?? '').trim() || null;
  const reason = (body.reason ?? '').trim() || null;

  if (!fullName || !profession) {
    return NextResponse.json(
      { error: 'missing_fields' },
      { status: 400, headers: cors },
    );
  }

  const sb = koalaAdmin();

  const { data: rpcRes, error: rpcErr } = await sb.rpc('koala_pro_apply', {
    p_uid: uid,
    p_full_name: fullName,
    p_profession: profession,
    p_city: city,
    p_ig_url: igUrl,
    p_portfolio_url: portfolioUrl,
    p_reason: reason,
  });
  if (rpcErr) {
    return NextResponse.json(
      { error: 'rpc_failed', detail: rpcErr.message },
      { status: 500, headers: cors },
    );
  }
  const res = rpcRes as { id?: string; status?: string; error?: string };
  if (res?.error) {
    return NextResponse.json(res, { status: 400, headers: cors });
  }

  // Telegram uyarısı — fail tolerant. Bridge config'inden token + chat.
  try {
    const { data: cfgRows } = await sb
      .from('koala_bridge_config')
      .select('key, value')
      .in('key', ['tg_bot_token', 'tg_chat_id']);
    const cfg = new Map(
      (cfgRows ?? []).map((r) => [r.key as string, r.value as string]),
    );
    const tgToken = cfg.get('tg_bot_token');
    const tgChat = cfg.get('tg_chat_id');
    if (tgToken && tgChat) {
      // NOT: parse_mode KULLANMA. Markdown modunda profession/reason içindeki
      // alt çizgi/yıldız ve footer'daki `koala_pro_application_decide` gibi
      // metinler Telegram'da "can't parse entities" (HTTP 400) hatası verip
      // mesajı sessizce düşürüyordu (catch yutuyor). Düz metin = sağlam.
      const lines = [
        '🎓 Yeni Profesyonel Başvurusu',
        '',
        `👤 ${fullName}`,
        `🛠️ ${profession}${city ? `  ·  📍 ${city}` : ''}`,
        igUrl ? `📷 ${igUrl}` : null,
        portfolioUrl ? `🌐 ${portfolioUrl}` : null,
        reason ? `\n💬 ${reason}` : null,
        '',
        `🆔 App: ${res.id}`,
        `👤 UID: ${uid}`,
        '',
        'Aşağıdaki butonlarla karar ver 👇',
      ].filter(Boolean).join('\n');
      // 2026-06-02: tıklanabilir Onayla/Reddet butonları. callback_data
      // /api/telegram/webhook tarafından işlenir → koala_pro_application_decide
      // RPC + push. callback_data ≤ 64 byte (prefix 15 + uuid 36 = 51).
      // 2026-06-02: Türkçe karakterler Telegram'da "?" geliyordu. String body
      // bazı runtime'larda Latin-1'e düşüyor; açıkça UTF-8 byte'a encode edip
      // charset=utf-8 başlığıyla gönder → garanti UTF-8.
      const tgPayload = JSON.stringify({
        chat_id: tgChat,
        text: lines,
        reply_markup: {
          inline_keyboard: [[
            { text: '✅ Onayla', callback_data: `prodec:approve:${res.id}` },
            { text: '❌ Reddet', callback_data: `prodec:reject:${res.id}` },
          ]],
        },
      });
      await fetch(
        `https://api.telegram.org/bot${tgToken}/sendMessage`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json; charset=utf-8' },
          body: new TextEncoder().encode(tgPayload),
        },
      );
    }
  } catch (e) {
    console.warn('[pro/apply] telegram alert failed:',
      e instanceof Error ? e.message : String(e));
  }

  return NextResponse.json(
    { id: res.id, status: res.status ?? 'pending' },
    { headers: cors },
  );
}
