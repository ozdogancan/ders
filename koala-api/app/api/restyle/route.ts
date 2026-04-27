import { NextRequest, NextResponse } from 'next/server';
import { put } from '@vercel/blob';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

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

    // Upload to Vercel Blob. Fall back to base64-only on failure so the
    // request still succeeds (mobile client can render either way).
    let blobUrl: string | null = null;
    const tUpload = Date.now();
    try {
      const filename = `restyle/${Date.now()}-${Math.random().toString(36).slice(2, 10)}.png`;
      const blob = await put(filename, buffer, {
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
