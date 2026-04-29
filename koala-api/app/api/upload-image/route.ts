import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, isOriginAllowed, isBodyTooLarge, checkRateLimit } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';

// TODO[2026-Q3]: legacy mode kaldır — verifyAuthHeader.legacy=true → 401 yap.

// Generic image upload proxy — Flutter `before` bytes'ını supabase storage'a
// yüklemek için. Kart detayında BeforeAfter render'ı için gerekli.
// Body: { bytes_b64, kind?: 'before'|'after', userId? }
// Response: { url }

export const runtime = 'nodejs';
export const maxDuration = 30;

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const BUCKET = 'design-uploads';

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

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }
  if (isBodyTooLarge(req, 12)) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413, headers });
  }
  if (!checkRateLimit(req, 'upload-image', 30)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers },
    );
  }

  let body: { bytes_b64?: string; kind?: string; userId?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  const { bytes_b64, kind = 'before', userId = 'anon' } = body;
  if (!bytes_b64) {
    return NextResponse.json(
      { error: 'bytes_b64 required' },
      { status: 400, headers },
    );
  }

  // ─── AUTH (dual-mode) ─────────────────────────────────────────
  // userId 'anon' ise expectedUid yok (anonim upload, dosyayı kullanıcı
  // klasörüne taşımıyoruz). Authorization header gönderilmişse yine verify
  // edip uid'i log'lamak için çağırıyoruz.
  const expectedUid = userId && userId !== 'anon' ? userId : undefined;
  const authResult = await verifyAuthHeader(req, expectedUid);
  logAuthOutcome('upload-image', authResult, {
    userId,
    ip: req.headers.get('x-forwarded-for'),
  });
  if (!authResult.ok) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers },
    );
  }

  try {
    const buf = Buffer.from(bytes_b64, 'base64');
    const sb = admin();
    // Bucket yoksa oluştur (idempotent).
    try {
      await sb.storage.createBucket(BUCKET, { public: true });
    } catch (_) {
      /* exists */
    }
    const filename = `${userId}/${kind}-${Date.now()}-${Math.random()
      .toString(36)
      .slice(2, 8)}.jpg`;
    const { error } = await sb.storage.from(BUCKET).upload(filename, buf, {
      contentType: 'image/jpeg',
      upsert: false,
      cacheControl: '2592000',
    });
    if (error) throw error;
    const { data } = sb.storage.from(BUCKET).getPublicUrl(filename);
    return NextResponse.json({ url: data.publicUrl }, { headers });
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'unknown';
    console.error('[upload-image] error', { kind, userId, msg });
    return NextResponse.json({ error: msg }, { status: 500, headers });
  }
}
