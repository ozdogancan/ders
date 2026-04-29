import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';

// TODO[2026-Q3]: legacy mode kaldır — verifyAuthHeader.legacy=true → 401 yap.

// Saved items proxy — Flutter anon client RLS engelinden geçemiyordu
// (saved_items tablosunda sadece service_role policy'si var, anon yok).
// Bu endpoint service_role ile yazıyor, RLS bypass ediyor.
//
// Güvenlik: client `userId` (Firebase UID) gönderir, biz onunla filtreliyoruz.
// Origin kontrolü mevcut (corsHeaders + isOriginAllowed).

export const runtime = 'nodejs';
export const maxDuration = 30;

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

function admin() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

interface Body {
  op: 'save' | 'remove' | 'isSaved';
  userId: string;
  itemType: string;
  itemId: string;
  title?: string;
  imageUrl?: string;
  subtitle?: string;
  extraData?: Record<string, unknown>;
  collectionId?: string;
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }
  if (!checkRateLimit(req, 'saved-items', 60)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers },
    );
  }

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  const { op, userId, itemId } = body;
  let { itemType } = body;
  if (!op || !userId || !itemType || !itemId) {
    return NextResponse.json(
      { error: 'op, userId, itemType, itemId required' },
      { status: 400, headers },
    );
  }

  // ─── AUTH (dual-mode) ─────────────────────────────────────────
  const authResult = await verifyAuthHeader(req, userId);
  logAuthOutcome('saved-items', authResult, {
    userId,
    ip: req.headers.get('x-forwarded-for'),
  });
  if (!authResult.ok) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers },
    );
  }
  // Production check constraint sadece project|designer|product kabul ediyor;
  // Flutter `design` ve `palette` gönderiyor → uyumlu isimlere çeviriyoruz.
  if (itemType === 'design') itemType = 'project';
  if (itemType === 'palette') itemType = 'product';

  const sb = admin();

  try {
    if (op === 'isSaved') {
      const { data, error } = await sb
        .from('saved_items')
        .select('id')
        .eq('user_id', userId)
        .eq('item_type', itemType)
        .eq('item_id', itemId)
        .limit(1);
      if (error) throw error;
      return NextResponse.json({ saved: (data?.length ?? 0) > 0 }, { headers });
    }

    if (op === 'save') {
      const row: Record<string, unknown> = {
        user_id: userId,
        item_type: itemType,
        item_id: itemId,
        title: body.title ?? null,
        image_url: body.imageUrl ?? null,
        subtitle: body.subtitle ?? null,
        extra_data: body.extraData ?? null,
      };
      if (body.collectionId) row.collection_id = body.collectionId;
      const { error } = await sb
        .from('saved_items')
        .upsert(row, { onConflict: 'user_id,item_type,item_id' });
      if (error) throw error;
      return NextResponse.json({ ok: true }, { headers });
    }

    if (op === 'remove') {
      const { error } = await sb
        .from('saved_items')
        .delete()
        .eq('user_id', userId)
        .eq('item_type', itemType)
        .eq('item_id', itemId);
      if (error) throw error;
      return NextResponse.json({ ok: true }, { headers });
    }

    return NextResponse.json({ error: 'unknown op' }, { status: 400, headers });
  } catch (err) {
    const detail =
      err instanceof Error
        ? { message: err.message, stack: err.stack }
        : err && typeof err === 'object'
          ? err
          : { value: String(err) };
    console.error('[saved-items] error', { op, userId, itemType, itemId, detail });
    const msg =
      err instanceof Error
        ? err.message
        : (err as { message?: string })?.message ?? JSON.stringify(detail);
    return NextResponse.json({ error: msg, detail }, { status: 500, headers });
  }
}
