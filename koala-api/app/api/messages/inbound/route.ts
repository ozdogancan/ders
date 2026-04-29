import { NextRequest, NextResponse } from 'next/server';
import { resolveHomeownerId, evlumbaAdmin } from '@/lib/supabase/evlumba-admin';
import { koalaAdmin } from '@/lib/supabase/koala';
import { corsHeaders } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';

// TODO[2026-Q3]: legacy mode kaldır — verifyAuthHeader.legacy=true → 401 yap.

export const runtime = 'nodejs';
export const maxDuration = 30;

/**
 * POST /api/messages/inbound
 *
 * Evlumba → Koala ters mesaj köprüsü (client-pull).
 * Flutter app ChatListScreen açılınca / foreground'a gelince çağırır.
 * Designer'ın evlumba.com'dan attığı mesajları Koala DB'sine çeker.
 *
 * Akış:
 *   1. firebaseUid → Evlumba homeowner_id çöz (shadow user)
 *   2. Homeowner'ın Evlumba conversation'larını listele (son 30 gün aktif olanlar)
 *   3. Her conversation için designer mesajlarını al (sender != homeowner)
 *   4. Koala tarafında karşılığı olan koala_conversations'ı bul
 *      (user_id=firebaseUid, designer_id=evlumba designer UUID)
 *   5. Dedupe et — metadata->>'evlumba_message_id' ile eşleşenleri geç
 *   6. Eksik mesajları koala_direct_messages'a insert et (service_role)
 *   7. koala_conversations.last_message + unread_count_user güncelle
 *
 * Body:  { firebaseUid, email?, displayName?, avatarUrl? }
 * Return: {
 *   synced: number,                    // toplam yeni insert edilen mesaj
 *   conversations: number,              // yeni mesaj alan conversation sayısı
 *   diag: { ...timings, errors },
 *   details: [{ designerId, koalaConversationId, newMessages }]
 * }
 */

const LOOKBACK_DAYS = 30;

type SyncDetail = {
  designerId: string;
  koalaConversationId: string;
  newMessages: number;
};

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));
  const t0 = Date.now();

  // ⚠️ AUTH GAP (bilinçli, TODO):
  // Bu endpoint Flutter client tarafından çağrılır (`MessagingService.pullInbound`).
  // Şu an `firebaseUid`'yi body'den okuyup o UID'nin mesajlarını pull ediyoruz —
  // bir saldırgan başka bir kullanıcının UID'sini bilirse response'dan o
  // kullanıcının hangi tasarımcılarla konuştuğunu (designerId listesi) öğrenebilir.
  // Message body response'a sızmıyor ama metadata sızar.
  //
  // DOĞRU ÇÖZÜM: Flutter client `Authorization: Bearer <Firebase ID Token>`
  // göndersin. Burada token'ı Firebase Admin SDK ile verify edip `decoded.uid`'i
  // body.firebaseUid ile karşılaştır. Farklıysa 401 döndür.
  //
  // Şimdilik pragmatik durum: Firebase UID'ler kolay harvest edilmez, attack
  // surface dar. Prod-grade için aşağıdaki TODO'yu gerçekle:
  //
  //   const authHeader = req.headers.get('authorization');
  //   const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
  //   if (!token) return NextResponse.json({ error: 'unauthorized' }, { status: 401, headers: cors });
  //   const decoded = await getAuth().verifyIdToken(token);
  //   if (decoded.uid !== firebaseUid) return NextResponse.json({ error: 'uid mismatch' }, { status: 403, headers: cors });

  let payload: {
    firebaseUid?: string;
    email?: string | null;
    displayName?: string | null;
    avatarUrl?: string | null;
  };
  try {
    payload = await req.json();
  } catch {
    return NextResponse.json(
      { error: 'Invalid JSON' },
      { status: 400, headers: cors },
    );
  }

  const firebaseUid = (payload.firebaseUid ?? '').trim();
  if (!firebaseUid) {
    return NextResponse.json(
      { error: 'firebaseUid is required' },
      { status: 400, headers: cors },
    );
  }

  // ─── AUTH (dual-mode) ─────────────────────────────────────────
  const authResult = await verifyAuthHeader(req, firebaseUid);
  logAuthOutcome('messages/inbound', authResult, {
    userId: firebaseUid,
    ip: req.headers.get('x-forwarded-for'),
  });
  if (!authResult.ok) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers: cors },
    );
  }

  try {
    // ─── 1) Homeowner resolve ─────────────────────────────────────
    const { homeownerId } = await resolveHomeownerId({
      firebaseUid,
      email: payload.email ?? null,
      displayName: payload.displayName ?? null,
      avatarUrl: payload.avatarUrl ?? null,
    });
    const tResolve = Date.now() - t0;

    const evlumba = evlumbaAdmin();
    const koala = koalaAdmin();

    // ─── 2) Evlumba conversations for this homeowner ──────────────
    const lookbackIso = new Date(
      Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();

    const { data: convs, error: convErr } = await evlumba
      .from('conversations')
      .select('id, designer_id, homeowner_id')
      .eq('homeowner_id', homeownerId);

    if (convErr) {
      return NextResponse.json(
        {
          synced: 0,
          conversations: 0,
          diag: { stage: 'evlumba_conversations', error: convErr.message },
          details: [],
        },
        { status: 200, headers: cors },
      );
    }

    if (!convs || convs.length === 0) {
      return NextResponse.json(
        {
          synced: 0,
          conversations: 0,
          diag: { stage: 'no_conversations', tResolve, homeownerId },
          details: [],
        },
        { headers: cors },
      );
    }

    // ─── 3-7) Her conversation için inbound pull ──────────────────
    let totalSynced = 0;
    let convWithNew = 0;
    const details: SyncDetail[] = [];
    const errors: string[] = [];

    for (const c of convs) {
      const evlumbaConvId = c.id as string;
      const designerId = c.designer_id as string;

      // 3) Designer mesajlarını al (lookback içinde)
      const { data: msgs, error: msgErr } = await evlumba
        .from('messages')
        .select('id, sender_id, body, created_at')
        .eq('conversation_id', evlumbaConvId)
        .eq('sender_id', designerId) // sadece designer'ın yazdıkları
        .gte('created_at', lookbackIso)
        .order('created_at', { ascending: true });

      if (msgErr) {
        errors.push(`msgs[${evlumbaConvId}]: ${msgErr.message}`);
        continue;
      }
      if (!msgs || msgs.length === 0) continue;

      // 4) Karşılık gelen Koala conversation'ı bul
      const { data: koalaConv, error: koalaConvErr } = await koala
        .from('koala_conversations')
        .select('id, last_message_at, unread_count_user')
        .eq('user_id', firebaseUid)
        .eq('designer_id', designerId)
        .maybeSingle();

      if (koalaConvErr) {
        errors.push(`koalaConv[${designerId}]: ${koalaConvErr.message}`);
        continue;
      }
      // Koala tarafında hiç başlatılmamış sohbet — skip (user hiç yazmamış,
      // inbound auto-create etmek istemiyoruz — designer tarafında yanlış
      // chat yaratır).
      if (!koalaConv) continue;
      const koalaConvId = koalaConv.id as string;

      // 5) Dedupe — lookback window'daki Koala mesajlarını çek, metadata'dan
      //    evlumba_message_id'leri çıkar (JS-side filter, PostgREST JSON path
      //    IN filter'ından daha uyumlu).
      const { data: existing, error: existErr } = await koala
        .from('koala_direct_messages')
        .select('metadata')
        .eq('conversation_id', koalaConvId)
        .not('metadata', 'is', null)
        .gte('created_at', lookbackIso);

      if (existErr) {
        errors.push(`dedupe[${designerId}]: ${existErr.message}`);
        continue;
      }

      const existingIds = new Set<string>();
      for (const r of existing ?? []) {
        const meta = (r.metadata ?? {}) as Record<string, unknown>;
        const eid = meta.evlumba_message_id;
        if (typeof eid === 'string' && eid.length > 0) existingIds.add(eid);
      }

      const toInsert = msgs.filter((m) => !existingIds.has(String(m.id)));
      if (toInsert.length === 0) continue;

      const inserted = await insertAndUpdate(
        koala,
        koalaConvId,
        designerId,
        firebaseUid,
        toInsert,
        koalaConv,
      );
      if (inserted > 0) {
        totalSynced += inserted;
        convWithNew += 1;
        details.push({
          designerId,
          koalaConversationId: koalaConvId,
          newMessages: inserted,
        });
      }
    }

    return NextResponse.json(
      {
        synced: totalSynced,
        conversations: convWithNew,
        diag: {
          tResolve,
          tTotal: Date.now() - t0,
          evlumbaConvs: convs.length,
          homeownerId,
          errors: errors.length > 0 ? errors : undefined,
        },
        details,
      },
      { headers: cors },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[inbound] error:', msg);
    return NextResponse.json(
      { synced: 0, conversations: 0, diag: { error: msg }, details: [] },
      { status: 500, headers: cors },
    );
  }
}

/**
 * Mesajları koala_direct_messages'a insert et, sonra
 * koala_conversations.last_message + unread_count_user güncelle.
 * Return: gerçekten insert edilen mesaj sayısı.
 */
async function insertAndUpdate(
  koala: ReturnType<typeof koalaAdmin>,
  koalaConvId: string,
  designerId: string,
  firebaseUid: string,
  msgs: Array<{ id: unknown; body: unknown; created_at: unknown }>,
  koalaConv: { last_message_at?: string | null; unread_count_user?: number | null },
): Promise<number> {
  const rows = msgs.map((m) => {
    const rawBody = typeof m.body === 'string' ? m.body : '';
    // Evlumba body'sine gömülü [Foto] URL marker'ı varsa attachment_url'e taşı
    // (bridge route'un yazdığı pattern ile simetrik).
    let content = rawBody;
    let attachmentUrl: string | null = null;
    const fotoMatch = rawBody.match(/\[Foto\]\s+(https?:\/\/\S+)/);
    if (fotoMatch) {
      attachmentUrl = fotoMatch[1];
      content = rawBody.replace(/\n?\[Foto\]\s+https?:\/\/\S+/, '').trim();
    }

    return {
      conversation_id: koalaConvId,
      sender_id: designerId, // designer'ın Evlumba UUID'si
      content: content || null,
      message_type: attachmentUrl ? 'image' : 'text',
      attachment_url: attachmentUrl,
      metadata: {
        evlumba_message_id: String(m.id),
        source: 'inbound_bridge',
      },
      created_at: typeof m.created_at === 'string' ? m.created_at : new Date().toISOString(),
    };
  });

  const { data: inserted, error: insErr } = await koala
    .from('koala_direct_messages')
    .insert(rows)
    .select('id, created_at');

  if (insErr) {
    console.error('[inbound] insert messages error:', insErr);
    return 0;
  }

  const insertedCount = inserted?.length ?? 0;
  if (insertedCount === 0) return 0;

  // koala_conversations preview + unread güncelle
  const lastMsg = rows[rows.length - 1];
  const lastMessagePreview =
    lastMsg.attachment_url
      ? lastMsg.content && lastMsg.content.length > 0
        ? `[image] ${lastMsg.content}`
        : '[image]'
      : lastMsg.content ?? '';
  const lastMessageAtCandidate = lastMsg.created_at;
  const existingLastAt = koalaConv.last_message_at ?? null;
  const newLastAt =
    !existingLastAt ||
    new Date(lastMessageAtCandidate).getTime() >
      new Date(existingLastAt).getTime()
      ? lastMessageAtCandidate
      : existingLastAt;

  const prevUnread = koalaConv.unread_count_user ?? 0;

  await koala
    .from('koala_conversations')
    .update({
      last_message: lastMessagePreview,
      last_message_at: newLastAt,
      unread_count_user: prevUnread + insertedCount,
      updated_at: new Date().toISOString(),
    })
    .eq('id', koalaConvId)
    .eq('user_id', firebaseUid);

  return insertedCount;
}
