import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const maxDuration = 60;
export const dynamic = 'force-dynamic';

/**
 * GET /api/cron/escalate-stale
 *
 * 24 saat cevapsızlık eskalasyonu. Gerçek tasarımcıya atılmış, 24 saattir
 * yanıtsız kalan konuşmalar için:
 *   1. Kullanıcının sohbetine bir bilgilendirme mesajı ekler (+ FCM push).
 *   2. Telegram'a admin uyarısı atar (aksiyon alınabilir başlık).
 *
 * Eskalasyon mesajı son mesajı tasarımcı-kaynaklı yaptığı için konuşma
 * bir daha listeye girmez — tekrar-eskalasyon otomatik engellenir.
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>`. Tetik: n8n, 3 saatte bir.
 */

const ESCALATION_TEXT =
  '⏳ Tasarımcınız henüz dönüş yapamadı. Evlumba ekibi durumu takibe aldı — ' +
  'en kısa sürede size yardımcı olacağız. (Otomatik bilgilendirme)';

interface StaleRow {
  conversation_id: string;
  user_id: string;
  designer_id: string;
  designer_name: string;
  last_message: string | null;
  last_message_at: string;
}

function authorized(req: NextRequest): boolean {
  const s = process.env.CRON_SECRET;
  return !!s && req.headers.get('authorization') === `Bearer ${s}`;
}

export async function GET(req: NextRequest) {
  if (!authorized(req)) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = koalaAdmin();

  const { data: cfgRows } = await admin
    .from('koala_bridge_config')
    .select('key, value')
    .in('key', ['tg_bot_token', 'tg_chat_id']);
  const cfg = new Map(
    (cfgRows ?? []).map((r) => [r.key as string, r.value as string]),
  );
  const tgToken = cfg.get('tg_bot_token');
  const tgChat = cfg.get('tg_chat_id');

  const { data: rows, error } = await admin.rpc('koala_stale_conversations');
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  const list: StaleRow[] = Array.isArray(rows) ? (rows as StaleRow[]) : [];
  if (list.length === 0) {
    return NextResponse.json({ escalated: 0, total: 0 });
  }

  let escalated = 0;
  const errors: Array<{ conversation_id: string; error: string }> = [];

  for (const c of list) {
    try {
      // 1. Kullanıcının sohbetine bilgilendirme mesajı (+ FCM push trigger'ı).
      const { error: rpcErr } = await admin.rpc('koala_escalate_conversation', {
        p_conversation_id: c.conversation_id,
        p_designer_id: c.designer_id,
        p_content: ESCALATION_TEXT,
      });
      if (rpcErr) throw new Error(rpcErr.message);

      // 2. Telegram admin uyarısı — aksiyon alınabilir.
      if (tgToken && tgChat) {
        const preview = (c.last_message ?? '').slice(0, 220);
        const text =
          '⚠️ 24 saattir YANITSIZ mesaj\n\n' +
          `👤 Tasarımcı: ${c.designer_name}\n` +
          `💬 Müşteri mesajı: ${preview}\n` +
          `🆔 Konuşma: ${c.conversation_id}\n\n` +
          'Müşteri bekliyor — tasarımcıya hatırlatma ya da Evlumba ekibinin ' +
          'devralması gerekebilir.';
        const tgRes = await fetch(
          `https://api.telegram.org/bot${tgToken}/sendMessage`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: tgChat, text }),
          },
        );
        if (!tgRes.ok) {
          console.warn(
            '[escalate] telegram alert failed:',
            c.conversation_id,
            await tgRes.text().catch(() => ''),
          );
        }
      }

      escalated++;
    } catch (e) {
      errors.push({
        conversation_id: c.conversation_id,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return NextResponse.json({ escalated, total: list.length, errors });
}
