import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';

// TODO[2026-Q3]: legacy mode kaldır — verifyAuthHeader.legacy=true → 401 yap.

export const runtime = 'nodejs';
export const maxDuration = 15;

/**
 * POST /api/conversations/ensure
 *
 * Koala conversation'ı service_role ile upsert eder.
 * Client (Flutter) bunu, Supabase direct yerine çağırır → RLS/x-user-id
 * header race'i devre dışı kalır. Cold-start / slow auth restore / anon
 * sign-in gecikmelerinden etkilenmez.
 *
 * Body:
 *   {
 *     firebaseUid: string,   // auth.currentUser!.uid (zorunlu)
 *     designerId: string,    // sohbetin karşı tarafı
 *     title?: string | null, // ilk ekran için başlık (proje adı vs.)
 *   }
 *
 * Response: koala_conversations row (whole object).
 */
export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers: cors });
  }
  if (!checkRateLimit(req, 'conversations-ensure', 30)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers: cors },
    );
  }

  let payload: {
    firebaseUid?: string;
    designerId?: string;
    title?: string | null;
    email?: string | null;
    displayName?: string | null;
    photoUrl?: string | null;
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
  const designerId = (payload.designerId ?? '').trim();
  const title =
    typeof payload.title === 'string' && payload.title.trim().length > 0
      ? payload.title.trim()
      : null;

  if (!firebaseUid || !designerId) {
    return NextResponse.json(
      { error: 'firebaseUid and designerId are required' },
      { status: 400, headers: cors },
    );
  }

  // ─── AUTH (dual-mode) ─────────────────────────────────────────
  const authResult = await verifyAuthHeader(req, firebaseUid);
  logAuthOutcome('conversations/ensure', authResult, {
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
    const admin = koalaAdmin();

    // ─── Evlumba designer → Koala hesabı eşlemesi ────────────────
    // Bazı Evlumba tasarımcılarının (örn. Muratcan) ayrı bir Koala pro
    // hesabı var. Mesajın Koala'da doğru kişiye düşmesi + tasarımcının kendi
    // sohbet listesinde görmesi için designer_id = Koala uid yapılır;
    // Evlumba köprüsü için orijinal id `evlumba_designer_id`'de saklanır.
    let effectiveDesignerId = designerId;
    let evlumbaDesignerId: string | null = null;
    let linkedName: string | null = null;
    let linkedAvatar: string | null = null;
    try {
      const { data: link } = await admin
        .from('koala_designer_links')
        .select('koala_uid')
        .eq('evlumba_designer_id', designerId)
        .maybeSingle();
      if (link?.koala_uid) {
        effectiveDesignerId = link.koala_uid as string;
        evlumbaDesignerId = designerId;
        // Bağlı tasarımcının adı/avatarını konuşma satırına denormalize et —
        // chat listesi Evlumba cache'inde bulamadığında bunu gösterir (yoksa
        // jenerik "Tasarımcı" görünür).
        const { data: prof } = await admin
          .from('koala_user_profiles')
          .select('display_name, avatar_url')
          .eq('uid', effectiveDesignerId)
          .maybeSingle();
        linkedName = (prof?.display_name as string | null) ?? null;
        linkedAvatar = (prof?.avatar_url as string | null) ?? null;
      }
    } catch (e) {
      console.error('[conv/ensure] designer link lookup failed:', e);
    }

    // NOT: Eskiden burada `users` tablosuna idempotent upsert vardı —
    // koala_conversations.user_id'nin users(id) FK'sine bağlı olduğu
    // varsayımıyla. Gerçekte koala_conversations.user_id `text` ve tabloda
    // HİÇBİR FK yok; `users.id` ise uuid (Firebase uid'leriyle uyumsuz).
    // Bu upsert hiçbir işe yaramıyordu ama PostgREST'te "display_name kolonu
    // yok" / uuid cast hatasıyla sohbet başlatmayı tamamen bloke ediyordu.
    // Kaldırıldı — conversation insert service_role ile, RLS/FK engeli yok.

    // Mevcut konuşma?
    const { data: existing, error: selErr } = await admin
      .from('koala_conversations')
      .select('*')
      .eq('user_id', firebaseUid)
      .eq('designer_id', effectiveDesignerId)
      .maybeSingle();

    if (selErr) {
      console.error('[conv/ensure] select error:', selErr);
      return NextResponse.json(
        { error: `select: ${selErr.message}` },
        { status: 500, headers: cors },
      );
    }
    if (existing) {
      return NextResponse.json(existing, { headers: cors });
    }

    // 2) Yoksa yarat
    const { data: created, error: insErr } = await admin
      .from('koala_conversations')
      .insert({
        user_id: firebaseUid,
        designer_id: effectiveDesignerId,
        evlumba_designer_id: evlumbaDesignerId,
        ...(linkedName ? { designer_name: linkedName } : {}),
        ...(linkedAvatar ? { designer_avatar: linkedAvatar } : {}),
        title,
        status: 'active',
      })
      .select('*')
      .single();

    if (insErr || !created) {
      console.error('[conv/ensure] insert error:', insErr);
      return NextResponse.json(
        { error: `insert: ${insErr?.message ?? 'unknown'}` },
        { status: 500, headers: cors },
      );
    }

    return NextResponse.json(created, { status: 201, headers: cors });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[conv/ensure] unexpected:', msg);
    return NextResponse.json(
      { error: msg },
      { status: 500, headers: cors },
    );
  }
}
