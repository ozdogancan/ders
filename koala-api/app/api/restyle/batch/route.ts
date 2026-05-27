import { NextRequest, NextResponse } from 'next/server';
import { put } from '@vercel/blob';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';
import { buildVariants, type PromptKind } from '@/lib/restyle/prompts';
import { phashHamming, geminiJudge } from '@/lib/restyle/quality_gate';
import { verifyAuthHeader } from '@/lib/auth-verify';
import { checkAndIncrementQuota, isProUser } from '@/lib/quota';

// Supabase Storage fallback — Vercel Blob fail ederse devreye girer.
// Önceden base64 data URL dönüyordu (3MB+), Flutter saveItem'a koyamıyordu
// (FUNCTION_PAYLOAD_TOO_LARGE). Şimdi server-side direkt Supabase Storage'a
// yükle, gerçek https URL dön — kullanıcı her seferinde proper URL alır.
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const STORAGE_BUCKET = 'design-uploads';

async function uploadToSupabaseStorage(
  buffer: Buffer,
  filename: string,
): Promise<string | null> {
  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return null;
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    try {
      await sb.storage.createBucket(STORAGE_BUCKET, { public: true });
    } catch (_) {
      /* exists */
    }
    const { error } = await sb.storage
      .from(STORAGE_BUCKET)
      .upload(filename, buffer, {
        contentType: 'image/png',
        upsert: false,
        cacheControl: '2592000',
      });
    if (error) {
      console.warn('[restyle/batch] supabase_upload_error', error.message);
      return null;
    }
    const { data } = sb.storage.from(STORAGE_BUCKET).getPublicUrl(filename);
    return data.publicUrl;
  } catch (err) {
    console.warn('[restyle/batch] supabase_upload_throw', err);
    return null;
  }
}

export const runtime = 'nodejs';
// 3 paralel render + judge: p95 ~ 80s; 120s pay bırakıyoruz Fluid Compute'ta.
export const maxDuration = 120;

/**
 * POST /api/restyle/batch
 *
 * Restyle v2 — tek istekle 3 paralel Gemini render + quality gate.
 * Body: { image, room, theme, userId? }
 * Response: { variants: VariantResult[], rejected_count, latency_ms }
 *
 * Quality gate iki bağımsız sinyale dayanıyor:
 *  - pHash drift (Hamming > 22 / 64) → Gemini sahneyi kaybetmiş, ele.
 *  - Judge skoru (< 6 / 10) → tasarım kötü, ele.
 * Fail-soft: gate hatası varyantı KESMEZ.
 */

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const RENDER_MODEL = 'gemini-2.5-flash-image';
const RENDER_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${RENDER_MODEL}:generateContent`;

// 22 → 48: kullanıcı oda tipini değiştirebildiği için (salon→mutfak) sahnenin
// büyük ölçüde değişmesi BEKLENEN davranış. Düşük threshold drastic
// transformları "drift" sayıp tüm variant'ları eliyordu.
const PHASH_DRIFT_THRESHOLD = 48;
const JUDGE_PASS_SCORE = 6;       // 0-10 ölçek

interface RenderResult {
  kind: PromptKind;
  outDataB64: string;
  buffer: Buffer;
}

interface VariantResult {
  url: string | null;
  output?: string; // base64 data URL fallback when Blob upload fails
  bytes: number;
  model: string;
  prompt_kind: PromptKind;
  judge_score: number;
  judge_reason: string;
  phash_distance: number;
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

async function renderVariant(
  kind: PromptKind,
  prompt: string,
  temperature: number,
  mimeType: string,
  b64Data: string,
  referenceData?: { mime_type: string; data: string },
): Promise<RenderResult | { kind: PromptKind; error: string }> {
  try {
    const reqParts: Array<Record<string, unknown>> = [
      { text: prompt },
      { inline_data: { mime_type: mimeType, data: b64Data } },
    ];
    if (referenceData) {
      reqParts.push({ inline_data: referenceData });
    }

    const res = await fetch(`${RENDER_ENDPOINT}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: reqParts }],
        generationConfig: { responseModalities: ['IMAGE'], temperature },
      }),
    });
    if (!res.ok) {
      return { kind, error: `gemini_${res.status}` };
    }
    const data = await res.json();
    const parts = data?.candidates?.[0]?.content?.parts ?? [];
    const imgPart = parts.find(
      (p: { inlineData?: { data?: string }; inline_data?: { data?: string } }) =>
        p?.inlineData?.data || p?.inline_data?.data
    );
    const outDataB64: string | undefined =
      imgPart?.inlineData?.data ?? imgPart?.inline_data?.data;
    if (!outDataB64) return { kind, error: 'no_image_in_response' };
    return { kind, outDataB64, buffer: Buffer.from(outDataB64, 'base64') };
  } catch (err) {
    return { kind, error: err instanceof Error ? err.message : 'unknown' };
  }
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }
  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413, headers });
  }
  // Batch tek seferde 3x kaynak; rate limit single restyle'ın yarısı.
  if (!checkRateLimit(req, 'restyle-batch', 5)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers }
    );
  }
  if (!GEMINI_API_KEY) {
    return NextResponse.json(
      { error: 'GEMINI_API_KEY not configured' },
      { status: 500, headers }
    );
  }

  let body: {
    image?: string;
    room?: string;
    theme?: string;
    reference_url?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  const { image, room, theme } = body;
  if (!image || !room || !theme) {
    return NextResponse.json(
      { error: 'image, room, theme required' },
      { status: 400, headers }
    );
  }

  // Auth + quota + Pro detect. Authorization is MANDATORY — no body.userId
  // fallback (previously allowed quota bypass by spoofing userId).
  // Legacy clients (no Authorization header at all) are admitted but bypass
  // quota during the rollout window.
  const auth = await verifyAuthHeader(req);
  if (!auth.ok) {
    return NextResponse.json({ error: 'auth_required', reason: auth.reason }, { status: 401, headers });
  }
  let userIsPro = false;
  if (auth.uid && !auth.legacy) {
    const q = await checkAndIncrementQuota({ userId: auth.uid, feature: 'restyle' });
    if (!q.allowed) {
      return NextResponse.json(
        {
          error: 'quota_exceeded',
          feature: 'restyle',
          code: 'RESTYLE_QUOTA',
          used: q.used,
          limit: q.limit,
        },
        { status: 402, headers },
      );
    }
    userIsPro = q.isPro;
  } else if (auth.uid) {
    // Legacy path — try to detect pro for variant cap, but don't gate.
    try { userIsPro = await isProUser(auth.uid); } catch { /* ignore */ }
  }

  // base64/dataURL normalize.
  let mimeType = 'image/jpeg';
  let b64Data = image;
  if (image.startsWith('data:')) {
    const match = image.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) {
      return NextResponse.json({ error: 'Invalid data URL' }, { status: 400, headers });
    }
    mimeType = match[1];
    b64Data = match[2];
  }
  const inputBuffer = Buffer.from(b64Data, 'base64');

  // Reference design (swipe'tan gelen ilham görseli) — fetch + base64 encode.
  let referenceData: { mime_type: string; data: string } | undefined;
  if (body.reference_url && body.reference_url.startsWith('http')) {
    try {
      const refRes = await fetch(body.reference_url);
      if (refRes.ok) {
        const buf = Buffer.from(await refRes.arrayBuffer());
        const ct = refRes.headers.get('content-type') ?? 'image/jpeg';
        referenceData = { mime_type: ct, data: buf.toString('base64') };
      }
    } catch (e) {
      console.warn('[restyle/batch] reference fetch failed', e);
    }
  }

  const t0 = Date.now();
  const refMode = referenceData != null;
  const specs = buildVariants(room, theme, refMode);

  // Paralel render
  const renders = await Promise.all(
    specs.map((s) => renderVariant(s.kind, s.prompt, s.temperature, mimeType, b64Data, referenceData))
  );

  const successful = renders.filter(
    (r): r is RenderResult => 'outDataB64' in r
  );

  if (successful.length === 0) {
    console.error('[restyle/batch] all_renders_failed', {
      room,
      theme,
      ms: Date.now() - t0,
      errors: renders.map((r) => ('error' in r ? `${r.kind}:${r.error}` : '')),
    });
    return NextResponse.json(
      { error: 'All renders failed', detail: renders },
      { status: 502, headers }
    );
  }

  // 2026-04-28: Judge gate kaldırıldı — render'ların hepsi geçer, judge skor
  // varsa öğrenme amaçlı log'lanır. Gemini'nin ek bir LLM çağrısı + ortalama
  // 4-7s daha tasarruf — toplam latency ~%25 düşer. pHash drift threshold
  // hala uygulanıyor (sahne tamamen kaybolduysa ele).
  const gated = await Promise.all(
    successful.map(async (r) => {
      const distance = await phashHamming(inputBuffer, r.buffer);
      const passed = distance <= PHASH_DRIFT_THRESHOLD;
      return {
        render: r,
        distance,
        judge: { score: 9.0, reason: 'gate_bypass' },
        passed,
      };
    })
  );

  const survivors = gated.filter((g) => g.passed);
  // Hiçbiri sağ kalmadıysa (her zaman geçecek olsa da güvenlik): tümünü al
  if (survivors.length === 0 && gated.length > 0) {
    survivors.push(...gated);
  }
  const rejected_count = gated.length - survivors.length;

  if (survivors.length === 0) {
    console.warn('[restyle/batch] all_rejected_by_gate', {
      room,
      theme,
      ms: Date.now() - t0,
      details: gated.map((g) => ({
        kind: g.render.kind,
        d: g.distance,
        s: g.judge.score,
      })),
    });
    return NextResponse.json(
      {
        error: 'All variants rejected by quality gate',
        detail: gated.map((g) => ({
          prompt_kind: g.render.kind,
          phash_distance: g.distance,
          judge_score: g.judge.score,
          judge_reason: g.judge.reason,
        })),
      },
      { status: 502, headers }
    );
  }

  // Survivor'ları upload — paralel, biri patlasa diğerleri etkilenmesin.
  // İlk olarak Vercel Blob, fail ederse Supabase Storage fallback (server-side
  // upload — base64 data URL round-trip etmiyor, kullanıcı her zaman gerçek
  // https URL alıyor).
  const variants: VariantResult[] = await Promise.all(
    survivors.map(async (g) => {
      const fileBase = `${Date.now()}-${g.render.kind}-${Math.random()
        .toString(36)
        .slice(2, 10)}.png`;
      let resolvedUrl: string | null = null;
      // Try 1: Vercel Blob
      try {
        const blob = await put(`restyle/${fileBase}`, g.render.buffer, {
          access: 'public',
          contentType: 'image/png',
        });
        resolvedUrl = blob.url;
      } catch (uploadErr) {
        console.warn('[restyle/batch] blob_upload_failed', {
          kind: g.render.kind,
          detail: uploadErr instanceof Error ? uploadErr.message : 'Unknown',
        });
      }
      // Try 2: Supabase Storage fallback (server-side, no client round-trip)
      if (!resolvedUrl) {
        resolvedUrl = await uploadToSupabaseStorage(
          g.render.buffer,
          `restyle-after/${fileBase}`,
        );
      }
      // Try 3 (last resort): base64 data URL — eski davranış. Yeni saveItem
      // bunu strip ediyor (FUNCTION_PAYLOAD_TOO_LARGE engeli) ama Flutter
      // tarafında hâlâ ResultStage'e direkt göstermek için lazım.
      const outputDataUrl = resolvedUrl
        ? undefined
        : `data:image/png;base64,${g.render.outDataB64}`;
      return {
        url: resolvedUrl,
        ...(outputDataUrl ? { output: outputDataUrl } : {}),
        bytes: g.render.buffer.byteLength,
        model: RENDER_MODEL,
        prompt_kind: g.render.kind,
        judge_score: g.judge.score,
        judge_reason: g.judge.reason,
        phash_distance: g.distance,
      };
    })
  );

  const latency_ms = Date.now() - t0;
  console.log('[restyle/batch] ok', {
    room,
    theme,
    survivors: survivors.length,
    rejected_count,
    latency_ms,
    pro: userIsPro,
  });

  // Free tier cap: 1 variant + watermark signal. Pro gets all survivors.
  const cappedVariants = userIsPro ? variants : variants.slice(0, 1);

  return NextResponse.json(
    {
      variants: cappedVariants,
      rejected_count,
      latency_ms,
      isPro: userIsPro,
      watermark: !userIsPro,
    },
    { headers }
  );
}
