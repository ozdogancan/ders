import { NextRequest, NextResponse } from 'next/server';
import { put } from '@vercel/blob';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';
import { verifyAuthHeader } from '@/lib/auth-verify';
import { checkAndIncrementQuota } from '@/lib/quota';

export const runtime = 'nodejs';
export const maxDuration = 60;

/**
 * POST /api/restyle
 *
 * Gemini 2.5 Flash Image (nano-banana) üzerinden mekan restyle.
 * - Tek senkron HTTP — polling yok, Fluid Compute'la mükemmel uyum.
 * - ~3-8 sn latency, ~$0.039/görsel.
 * - Oda geometrisini korur, stili değiştirir.
 *
 * Required env vars:
 *   - GEMINI_API_KEY: Google Gemini API key.
 *   - BLOB_READ_WRITE_TOKEN: Vercel Blob token. Auto-provisioned once Blob
 *     is enabled on the project; `vercel env pull` brings it to local dev.
 *
 * Body kontratı (Flutter client ile geriye uyumlu):
 *   { image: string (data URL veya base64), room: string, theme: string, customPrompt?: string }
 * Response:
 *   {
 *     url: string,          // Vercel Blob public URL (preferred by client)
 *     bytes: number,
 *     model: string,
 *     output?: string,      // DEPRECATED: base64 data URL, one-release bw-compat
 *   } | { error, detail }
 *
 * Sprint 2 migration: image is uploaded to Vercel Blob; `output` field remains
 * for one release so existing Flutter clients keep working. Remove once client
 * ships the `url`-based loader.
 */

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const MODEL = 'gemini-2.5-flash-image';
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

function buildPrompt(room: string, theme: string, customPrompt?: string): string {
  const base =
    `Restyle this ${room} photo in ${theme} style. ` +
    `Strictly preserve the room's layout, walls, windows, ceiling, floor plan, ` +
    `and overall perspective. Only change furniture, decor, color palette, and materials ` +
    `to match the ${theme} aesthetic. Photorealistic interior photography, ` +
    `natural daylight, 8k sharpness, editorial quality. No people, no text, no watermarks.`;
  return customPrompt ? `${base} Additional instructions: ${customPrompt}` : base;
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

  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413, headers });
  }

  if (!checkRateLimit(req, 'restyle', 10)) {
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

  let body: { image?: string; room?: string; theme?: string; customPrompt?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  let { image } = body;
  const { room, theme, customPrompt } = body;

  // Auth + quota gate. Authorization is MANDATORY — no body.userId fallback.
  // Legacy clients without an Authorization header are still admitted (auth.ok
  // === true && auth.legacy === true) for the rollout window, but quota is
  // skipped for them deliberately (they have no verified identity to charge).
  // Once Vercel logs show AUTH_LEGACY at zero this branch goes away.
  const auth = await verifyAuthHeader(req);
  if (!auth.ok) {
    return NextResponse.json({ error: 'auth_required', reason: auth.reason }, { status: 401, headers });
  }
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
    // P1.4 — Loss-leader analytics: if this was the user's FIRST successful
    // restyle (q.used flipped 0→1 for this period AND the user is not Pro),
    // log it to analytics_events so we can track the "free first" funnel.
    if (!q.isPro && q.used === 1) {
      try {
        const { koalaAdmin } = await import('@/lib/supabase/koala');
        await koalaAdmin().from('analytics_events').insert({
          user_id: auth.uid,
          event_name: 'restyle_free_used',
          event_data: { room, theme, source: 'wizard_finish' },
          platform: 'server',
        });
      } catch (e) {
        // analytics best-effort — never fail the restyle on logging error
        console.warn('[restyle] analytics_events insert failed', e instanceof Error ? e.message : e);
      }
    }
  }

  if (!image || !room || !theme) {
    return NextResponse.json(
      { error: 'image, room, theme required' },
      { status: 400, headers }
    );
  }

  // base64/dataURL normalize — mimeType + data bölümlerini ayır.
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

  const prompt = buildPrompt(room, theme, customPrompt);

  const requestBody = {
    contents: [
      {
        role: 'user',
        parts: [
          { inline_data: { mime_type: mimeType, data: b64Data } },
          { text: prompt },
        ],
      },
    ],
    generationConfig: {
      // Modele hem görsel hem text üretebildiğini söylüyoruz ama sadece görseli dönüyor
      // gibi davransın — response'ta sadece inline_data part'ını alıyoruz.
      responseModalities: ['IMAGE'],
      temperature: 0.9,
    },
  };

  const t0 = Date.now();
  try {
    const res = await fetch(`${ENDPOINT}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody),
    });

    if (!res.ok) {
      const detail = await res.text();
      console.error('[restyle] gemini_http_error', {
        status: res.status,
        room,
        theme,
        ms: Date.now() - t0,
      });
      return NextResponse.json(
        { error: 'Gemini API error', status: res.status, detail },
        { status: 502, headers }
      );
    }

    const data = await res.json();
    const parts = data?.candidates?.[0]?.content?.parts ?? [];
    const imgPart = parts.find((p: { inlineData?: { data?: string }; inline_data?: { data?: string } }) =>
      p?.inlineData?.data || p?.inline_data?.data
    );
    const outData: string | undefined = imgPart?.inlineData?.data ?? imgPart?.inline_data?.data;

    if (!outData) {
      // Gemini bazen text-only döner (prompt reddi vb.). Logla ve 502 dön.
      console.error('[restyle] no_image_in_response', {
        room,
        theme,
        finishReason: data?.candidates?.[0]?.finishReason,
        ms: Date.now() - t0,
      });
      return NextResponse.json(
        { error: 'No image in response', raw: data },
        { status: 502, headers }
      );
    }

    const output = `data:image/png;base64,${outData}`;
    const buffer = Buffer.from(outData, 'base64');
    const bytes = buffer.byteLength;

    // Try 1: Vercel Blob. Try 2: Supabase Storage fallback (server-side).
    // Try 3: base64 data URL (last resort — saveItem strips this).
    let blobUrl: string | null = null;
    const tUpload = Date.now();
    const filename = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}.png`;
    try {
      const blob = await put(`restyle/${filename}`, buffer, {
        access: 'public',
        contentType: 'image/png',
      });
      blobUrl = blob.url;
      console.log('[restyle] blob_uploaded', {
        url: blobUrl,
        ms_upload: Date.now() - tUpload,
      });
    } catch (uploadErr) {
      console.error('[restyle] blob_upload_failed', {
        ms_upload: Date.now() - tUpload,
        detail: uploadErr instanceof Error ? uploadErr.message : 'Unknown error',
      });
    }
    // Supabase Storage fallback — Vercel Blob başarısız olursa.
    if (!blobUrl) {
      try {
        const { createClient } = await import('@supabase/supabase-js');
        const SUPABASE_URL = process.env.SUPABASE_URL || '';
        const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
        if (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY) {
          const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
            auth: { autoRefreshToken: false, persistSession: false },
          });
          try {
            await sb.storage.createBucket('design-uploads', { public: true });
          } catch (_) {
            /* exists */
          }
          const { error: upErr } = await sb.storage
            .from('design-uploads')
            .upload(`restyle-after/${filename}`, buffer, {
              contentType: 'image/png',
              upsert: false,
              cacheControl: '2592000',
            });
          if (!upErr) {
            const { data } = sb.storage
              .from('design-uploads')
              .getPublicUrl(`restyle-after/${filename}`);
            blobUrl = data.publicUrl;
            console.log('[restyle] supabase_uploaded', { url: blobUrl });
          }
        }
      } catch (_) {
        /* fallback also failed */
      }
    }

    console.log('[restyle] ok', {
      room,
      theme,
      ms: Date.now() - t0,
      bytes,
      blob: blobUrl ? 'ok' : 'fallback_base64',
    });

    // Backward-compatible response: include `output` (data URL) for one release
    // so existing Flutter clients keep working. New clients should prefer `url`.
    const responseBody: {
      url: string | null;
      bytes: number;
      model: string;
      output: string;
    } = {
      url: blobUrl,
      bytes,
      model: MODEL,
      output,
    };
    return NextResponse.json(responseBody, { headers });
  } catch (error) {
    console.error('[restyle] exception', {
      room,
      theme,
      ms: Date.now() - t0,
      detail: error instanceof Error ? error.message : 'Unknown error',
    });
    return NextResponse.json(
      {
        error: 'Restyle failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500, headers }
    );
  }
}
