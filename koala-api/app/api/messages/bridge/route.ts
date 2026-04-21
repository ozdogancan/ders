import { NextRequest, NextResponse } from 'next/server';
import {
  resolveHomeownerId,
  findOrCreateConversation,
  insertMessage,
} from '@/lib/supabase/evlumba-admin';
import { koalaService } from '@/lib/supabase/koala';
import { corsHeaders } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 30;

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

/**
 * POST /api/messages/bridge
 *
 * Koala → Evlumba mesaj köprüsü.
 * Koala client'ının `MessagingService.sendMessage`'ı bu endpoint'i çağırır
 * (fire-and-forget). Burada:
 *   1. Koala kullanıcısı için Evlumba'da shadow auth user oluştur/bul
 *   2. profiles satırını role='homeowner' olarak upsert et
 *   3. (homeowner_id, designer_id) conversation bul/oluştur
 *   4. messages tablosuna satır ekle
 *
 * Böylece Buse evlumba.com/mesajlar'dan mesajı görebilir.
 *
 * Auth: x-bridge-secret header'ı env.BRIDGE_SECRET ile eşleşmeli.
 */
export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));

  // ─── Auth ─────────────────────────────────────────────
  const expected = process.env.BRIDGE_SECRET;
  if (expected && req.headers.get('x-bridge-secret') !== expected) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401, headers: cors });
  }

  // ─── Parse body ───────────────────────────────────────
  let payload: {
    firebaseUid?: string;
    email?: string | null;
    displayName?: string | null;
    avatarUrl?: string | null;
    designerId?: string;
    body?: string;
    koalaConversationId?: string | null;
    attachmentUrl?: string | null;
  };
  try {
    payload = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers: cors });
  }

  const {
    firebaseUid,
    email,
    displayName,
    avatarUrl,
    designerId,
    body,
    koalaConversationId,
    attachmentUrl,
  } = payload;

  // body veya attachmentUrl en az biri olmalı (image-only mesaj caption boş olabilir).
  const trimmedBody = (body ?? '').trim();
  const hasAttachment = !!(attachmentUrl && attachmentUrl.length > 0);
  if (!firebaseUid || !designerId || (trimmedBody.length === 0 && !hasAttachment)) {
    return NextResponse.json(
      { error: 'firebaseUid, designerId, and (body or attachmentUrl) are required' },
      { status: 400, headers: cors },
    );
  }

  try {
    // 1) Canonical homeowner id (prefer REAL evlumba.com user over shadow).
    //    Kullanıcının evlumba.com'da gerçek bir homeowner hesabı varsa ona
    //    yazılır → designer inbox'ında "Can Özdoğan" ayrı chat açılmaz,
    //    mevcut conversation'ın devamı olur.
    const { homeownerId, source } = await resolveHomeownerId({
      firebaseUid,
      email,
      displayName,
      avatarUrl,
    });

    // 2) Conversation
    const conversationId = await findOrCreateConversation({
      homeownerId,
      designerId,
    });

    // 3) Message
    //    Evlumba `messages` tablosunda attachment_url kolonu yok.
    //    Foto eklendiyse URL'i body içine göm — designer evlumba.com'da en
    //    azından link'e tıklayıp resmi açabilsin. Schema bozulmaz, geriye
    //    dönük uyumludur.
    const evlumbaBody = hasAttachment
      ? (trimmedBody.length > 0
          ? `${trimmedBody}\n\n[Foto] ${attachmentUrl}`
          : `[Foto] ${attachmentUrl}`)
      : trimmedBody;
    const messageId = await insertMessage({
      conversationId,
      senderId: homeownerId,
      body: evlumbaBody,
    });

    // 4) SAFETY NET — Koala koala_conversations.last_message'ı
    //    service_role ile güncelle. Client tarafındaki UPDATE bazen 050 RLS
    //    policy'si (user_id = get_user_id()) ile sessizce block oluyor
    //    (x-user-id header race). Service_role RLS bypass eder → chat list
    //    preview her zaman güncel kalır.
    //    Sadece koalaConversationId verilmişse çalışır (eski client'lar
    //    için geriye dönük güvenli).
    if (koalaConversationId) {
      try {
        // Foto mesajları için chat list preview'da [image] marker kullan —
        // chat_list_screen_v1 _LastMessagePreview bunu yakalayıp modern
        // foto ikonu + caption olarak render ediyor.
        const koalaLastMessage = hasAttachment
          ? (trimmedBody.length > 0 ? `[image] ${trimmedBody}` : '[image]')
          : trimmedBody;
        const nowIso = new Date().toISOString();
        await koalaService
          .from('koala_conversations')
          .update({
            last_message: koalaLastMessage,
            last_message_at: nowIso,
            updated_at: nowIso,
          })
          .eq('id', koalaConversationId)
          .eq('user_id', firebaseUid); // user perspektifinden — designer mesajları inbound route'tan yazılır
      } catch (updateErr) {
        // Non-fatal: Evlumba bridge yazımı başarılı oldu, chat list preview
        // sadece biraz bayat kalır. Client'ın kendi UPDATE'i zaten paralel
        // çalışıyordu.
        console.warn(
          '[bridge] koala_conversations last_message fallback update failed:',
          updateErr instanceof Error ? updateErr.message : String(updateErr),
        );
      }
    }

    return NextResponse.json(
      {
        status: 'ok',
        evlumba_homeowner_id: homeownerId,
        evlumba_homeowner_source: source,
        evlumba_conversation_id: conversationId,
        evlumba_message_id: messageId,
        koala_conversation_id: koalaConversationId ?? null,
      },
      { headers: cors },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[bridge] error:', msg);
    return NextResponse.json(
      { status: 'error', error: msg },
      { status: 500, headers: cors },
    );
  }
}
