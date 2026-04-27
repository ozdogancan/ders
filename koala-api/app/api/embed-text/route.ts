import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 30;

/**
 * POST /api/embed-text
 *
 * Gemini text-embedding-004 → 768 dim vektör.
 * Türkçe ve İngilizce karışık metin destekler — proje tags + room_type +
 * color_palette + budget_level concat'i için ideal.
 *
 * Body: { text: string, task_type?: 'RETRIEVAL_DOCUMENT' | 'RETRIEVAL_QUERY' }
 *
 * task_type semantik:
 *   - RETRIEVAL_DOCUMENT (default n8n için) → indekslenecek doküman
 *   - RETRIEVAL_QUERY    (match endpoint için) → arama sorgusu
 * İkisi farklı uzaylar değil, aynı uzayda farklı asimetrik prompt'lardır —
 * doğru kullanılırsa cosine kalitesi belirgin artar.
 *
 * Response: { embedding: number[768], model: string, latency_ms: number }
 *
 * Maliyet: Gemini text-embedding-004 free tier'da bol — 1500 RPM, gün limiti yok.
 */

type TaskType = 'RETRIEVAL_DOCUMENT' | 'RETRIEVAL_QUERY' | 'SEMANTIC_SIMILARITY';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));
  const t0 = Date.now();

  let body: { text?: string; task_type?: TaskType };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: 'invalid_json' },
      { status: 400, headers: cors },
    );
  }

  const text = body.text?.trim();
  if (!text) {
    return NextResponse.json(
      { error: 'missing_text' },
      { status: 400, headers: cors },
    );
  }
  if (text.length > 8000) {
    return NextResponse.json(
      { error: 'text_too_long', detail: 'max 8000 chars' },
      { status: 400, headers: cors },
    );
  }

  const taskType: TaskType = body.task_type ?? 'RETRIEVAL_DOCUMENT';

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: 'gemini_key_missing' },
      { status: 500, headers: cors },
    );
  }

  try {
    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'models/text-embedding-004',
          content: { parts: [{ text }] },
          taskType,
          // outputDimensionality optional; default 768.
        }),
      },
    );

    const j: any = await resp.json().catch(() => ({}));

    if (!resp.ok) {
      console.error('[embed-text] gemini error', resp.status, j?.error);
      return NextResponse.json(
        {
          error: 'gemini_error',
          status: resp.status,
          detail: j?.error?.message ?? resp.statusText,
        },
        { status: 502, headers: cors },
      );
    }

    const embedding: number[] | undefined = j?.embedding?.values;
    if (!embedding || embedding.length === 0) {
      return NextResponse.json(
        {
          error: 'no_embedding',
          detail: `unexpected shape: ${JSON.stringify(j).slice(0, 200)}`,
        },
        { status: 502, headers: cors },
      );
    }
    if (embedding.length !== 768) {
      return NextResponse.json(
        { error: 'dim_mismatch', detail: `expected 768, got ${embedding.length}` },
        { status: 502, headers: cors },
      );
    }

    return NextResponse.json(
      {
        embedding,
        model: 'gemini-text-embedding-004',
        task_type: taskType,
        latency_ms: Date.now() - t0,
      },
      { headers: cors },
    );
  } catch (e: any) {
    console.error('[embed-text] unhandled', e);
    return NextResponse.json(
      { error: 'unhandled', detail: e?.message ?? String(e) },
      { status: 500, headers: cors },
    );
  }
}
