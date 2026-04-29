import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 60;

/**
 * POST /api/embed-image
 *
 * Replicate üzerinden CLIP ViT-L/14 görsel embedding üretir → 768 dim vektör.
 * Hem n8n nightly backfill hem `/api/match-designers` (kullanıcı restyle çıktısı)
 * tarafından çağrılır. Tek nokta — model değişirse buradan değişir.
 *
 * Body: { image: string }
 *   - data URL ("data:image/jpeg;base64,...") veya https URL
 *
 * Response: { embedding: number[768], model: string, latency_ms: number }
 *
 * Maliyet: Replicate per-prediction ~$0.0002, ortalama 1.5s.
 */

const REPLICATE_VERSION =
  // andreasjansson/clip-features — ViT-L/14, 768 dim, 224x224
  '75b33f253f7714a281ad3e9b28f63e3232d583716ef6718f2e46641077ea040a';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));
  const t0 = Date.now();

  // Replicate is a paid API — guard hard.
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers: cors });
  }
  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413, headers: cors });
  }
  if (!checkRateLimit(req, 'embed-image', 20)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers: cors },
    );
  }

  let body: { image?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: 'invalid_json' },
      { status: 400, headers: cors },
    );
  }

  const image = body.image?.trim();
  if (!image) {
    return NextResponse.json(
      { error: 'missing_image' },
      { status: 400, headers: cors },
    );
  }

  const apiKey = process.env.REPLICATE_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: 'replicate_key_missing' },
      { status: 500, headers: cors },
    );
  }

  try {
    // Replicate sync API — `Prefer: wait` ile tek atışta sonuç al.
    // CLIP yeterince hızlı ki sync güvenli (~1-2s).
    const resp = await fetch('https://api.replicate.com/v1/predictions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        Prefer: 'wait=30',
      },
      body: JSON.stringify({
        version: REPLICATE_VERSION,
        input: { inputs: image },
      }),
    });

    const j: any = await resp.json().catch(() => ({}));

    if (!resp.ok) {
      return NextResponse.json(
        { error: 'replicate_error', detail: j?.detail ?? resp.statusText },
        { status: 502, headers: cors },
      );
    }

    // Response shape: { output: [{ input: <url>, embedding: [...] }] }
    const out = j.output;
    let embedding: number[] | undefined;
    if (Array.isArray(out) && out[0]?.embedding) {
      embedding = out[0].embedding;
    } else if (Array.isArray(out) && typeof out[0] === 'number') {
      embedding = out;
    }

    if (!embedding || embedding.length === 0) {
      return NextResponse.json(
        {
          error: 'no_embedding',
          detail: `unexpected output shape: ${JSON.stringify(out).slice(0, 200)}`,
          status: j.status,
        },
        { status: 502, headers: cors },
      );
    }

    if (embedding.length !== 768) {
      return NextResponse.json(
        {
          error: 'dim_mismatch',
          detail: `expected 768, got ${embedding.length}`,
        },
        { status: 502, headers: cors },
      );
    }

    return NextResponse.json(
      {
        embedding,
        model: 'clip-vit-l-14',
        latency_ms: Date.now() - t0,
      },
      { headers: cors },
    );
  } catch (e: any) {
    return NextResponse.json(
      { error: 'unhandled', detail: e?.message ?? String(e) },
      { status: 500, headers: cors },
    );
  }
}
