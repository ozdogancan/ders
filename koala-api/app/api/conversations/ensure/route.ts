import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { corsHeaders } from '@/lib/security';

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

  try {
    const admin = koalaAdmin();

    // 1) `users` satırını ensure et — koala_conversations.user_id bu tabloya
    //    FK ile bağlı. Anonim Firebase sign-in yeni uid üretiyor ama bu uid
    //    `users` tablosunda yoksa conversation INSERT foreign key constraint
    //    ile patlar. Idempotent upsert.
    {
      const userRow: Record<string, unknown> = { id: firebaseUid };
      const email =
        typeof payload.email === 'string' && payload.email.trim().length > 0
          ? payload.email.trim()
          : null;
      const displayName =
        typeof payload.displayName === 'string' &&
        payload.displayName.trim().length > 0
          ? payload.displayName.trim()
          : null;
      const photoUrl =
        typeof payload.photoUrl === 'string' &&
        payload.photoUrl.trim().length > 0
          ? payload.photoUrl.trim()
          : null;
      if (email) userRow.email = email;
      if (displayName) userRow.display_name = displayName;
      if (photoUrl) userRow.photo_url = photoUrl;
      const { error: userErr } = await admin
        .from('users')
        .upsert(userRow, { onConflict: 'id', ignoreDuplicates: true });
      if (userErr) {
        console.error('[conv/ensure] users upsert error:', userErr);
        return NextResponse.json(
          { error: `users upsert: ${userErr.message}` },
          { status: 500, headers: cors },
        );
      }
    }

    // 2) Mevcut konuşma?
    const { data: existing, error: selErr } = await admin
      .from('koala_conversations')
      .select('*')
      .eq('user_id', firebaseUid)
      .eq('designer_id', designerId)
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
        designer_id: designerId,
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
