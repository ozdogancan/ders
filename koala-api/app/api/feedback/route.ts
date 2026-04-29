import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';

// TODO[2026-Q3]: legacy mode kaldır — verifyAuthHeader.legacy=true → 401 yap.

// Design feedback proxy — Flutter anon client RLS bypass için service_role
// kullanır. design_feedback tablosu (user_id, design_id) üzerinde unique;
// upsert ile tek user'ın tek design'a son rating'ini saklar.

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
  userId: string;
  designId: string;
  rating: 'like' | 'dislike';
  room?: string;
  theme?: string;
  palette?: string;
  layout?: string;
  afterUrl?: string;
  extraData?: Record<string, unknown>;
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }
  if (!checkRateLimit(req, 'feedback', 60)) {
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

  const { userId, designId, rating } = body;
  if (!userId || !designId || !rating) {
    return NextResponse.json(
      { error: 'userId, designId, rating required' },
      { status: 400, headers },
    );
  }
  if (rating !== 'like' && rating !== 'dislike') {
    return NextResponse.json(
      { error: "rating must be 'like' or 'dislike'" },
      { status: 400, headers },
    );
  }

  // ─── AUTH (dual-mode) ─────────────────────────────────────────
  const authResult = await verifyAuthHeader(req, userId);
  logAuthOutcome('feedback', authResult, {
    userId,
    ip: req.headers.get('x-forwarded-for'),
  });
  if (!authResult.ok) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers },
    );
  }

  const sb = admin();
  try {
    // Tablo dashboard'dan oluşturulmadan da çalışsın diye saved_items'a
    // yazıyoruz: item_type='product' (check constraint izinli), item_id
    // 'fb_{designId}' ile unique. extra_data feedback payload'ını taşıyor.
    // İleride design_feedback tablosu oluşturulursa migration kolay.
    const row: Record<string, unknown> = {
      user_id: userId,
      item_type: 'product',
      item_id: `fb_${designId}`,
      title: `feedback:${rating}`,
      subtitle: body.theme ?? null,
      image_url: body.afterUrl ?? null,
      extra_data: {
        kind: 'design_feedback',
        rating,
        design_id: designId,
        room: body.room ?? null,
        theme: body.theme ?? null,
        palette: body.palette ?? null,
        layout: body.layout ?? null,
        after_url: body.afterUrl ?? null,
        extra: body.extraData ?? null,
        ts: new Date().toISOString(),
      },
    };
    const { error } = await sb
      .from('saved_items')
      .upsert(row, { onConflict: 'user_id,item_type,item_id' });
    if (error) throw error;
    return NextResponse.json({ ok: true }, { headers });
  } catch (err) {
    const detail =
      err instanceof Error
        ? { message: err.message }
        : err && typeof err === 'object'
          ? err
          : { value: String(err) };
    console.error('[feedback] error', { userId, designId, rating, detail });
    const msg =
      err instanceof Error
        ? err.message
        : (err as { message?: string })?.message ?? JSON.stringify(detail);
    return NextResponse.json({ error: msg, detail }, { status: 500, headers });
  }
}
