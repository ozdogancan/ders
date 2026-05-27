import { NextRequest, NextResponse } from 'next/server';
import crypto from 'node:crypto';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const maxDuration = 60;

/**
 * GET / POST /api/cron/backfill-embeddings
 *
 * `koala_cards.embedding` (vector(1408)) sütunu için backfill cron'u.
 * Embedding modeli: Google Vertex AI `multimodalembedding@001` → 1408 dim.
 *
 * Auth: `Authorization: Bearer $CRON_SECRET`. Vercel cron header'ı bunu
 * otomatik gönderir.
 *
 * Davranış:
 *  - Her çağrıda en fazla 20 kart işlenir (`is_published=true AND embedding IS NULL`).
 *  - Vertex AI Service Account JSON env (`VERTEX_SERVICE_ACCOUNT_JSON` veya
 *    `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`) yoksa graceful abort — 200 + reason.
 *  - 429 / quota hatası → geri kalan batch'i bırakır, kısmi sonuç döner.
 *  - Hata olan kart'ta `embedding` null bırakılır, retry sonraki cron'da.
 *
 * vercel.json'da daily 04:00 UTC olarak schedule'lı.
 */

const VERTEX_LOCATION = 'us-central1';
const VERTEX_MODEL = 'multimodalembedding@001';
const EMBED_DIM = 1408;
const MAX_PER_RUN = 20;

interface SaJson {
  client_email: string;
  private_key: string;
  project_id: string;
}

interface CardRow {
  id: string;
  cdn_url: string | null;
  original_url: string | null;
  thumbnail_url: string | null;
}

function parseServiceAccount(): SaJson | null {
  const raw =
    process.env.VERTEX_SERVICE_ACCOUNT_JSON ||
    process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON ||
    '';
  if (!raw) return null;
  let txt = raw.trim();
  if (!txt.startsWith('{')) {
    try {
      txt = Buffer.from(txt, 'base64').toString('utf8');
    } catch {
      return null;
    }
  }
  try {
    const parsed = JSON.parse(txt) as SaJson;
    if (!parsed.client_email || !parsed.private_key) return null;
    return parsed;
  } catch {
    return null;
  }
}

// Cache access token across invocations within same isolate (max ~50min).
let _tokenCache: { token: string; expiresAt: number } | null = null;

async function getAccessToken(sa: SaJson): Promise<string> {
  if (_tokenCache && _tokenCache.expiresAt > Date.now() + 60_000) {
    return _tokenCache.token;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const b64url = (obj: object) =>
    Buffer.from(JSON.stringify(obj))
      .toString('base64')
      .replace(/=/g, '')
      .replace(/\+/g, '-')
      .replace(/\//g, '_');
  const unsigned = `${b64url(header)}.${b64url(claim)}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsigned);
  const signature = signer
    .sign(sa.private_key)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  const jwt = `${unsigned}.${signature}`;

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    throw new Error(`token_exchange_failed:${resp.status}:${await resp.text()}`);
  }
  const j = (await resp.json()) as { access_token: string; expires_in: number };
  _tokenCache = {
    token: j.access_token,
    expiresAt: Date.now() + j.expires_in * 1000,
  };
  return j.access_token;
}

async function fetchImageAsBase64(url: string): Promise<string> {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`img_fetch_${r.status}`);
  const buf = Buffer.from(await r.arrayBuffer());
  // Vertex multimodalembedding ~20MB limit; çoğu cdn_url küçük WebP.
  return buf.toString('base64');
}

async function embedImage(
  token: string,
  projectId: string,
  imageUrl: string,
): Promise<{ embedding: number[] } | { error: string; status: number }> {
  const base64 = await fetchImageAsBase64(imageUrl);
  const endpoint =
    `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/` +
    `${projectId}/locations/${VERTEX_LOCATION}/publishers/google/models/` +
    `${VERTEX_MODEL}:predict`;
  const resp = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      instances: [{ image: { bytesBase64Encoded: base64 } }],
      parameters: { dimension: EMBED_DIM },
    }),
  });
  if (!resp.ok) {
    return { error: await resp.text(), status: resp.status };
  }
  const j = (await resp.json()) as {
    predictions?: Array<{ imageEmbedding?: number[] }>;
  };
  const emb = j.predictions?.[0]?.imageEmbedding;
  if (!emb || emb.length !== EMBED_DIM) {
    return { error: `bad_dim:${emb?.length ?? 0}`, status: 500 };
  }
  return { embedding: emb };
}

interface Outcome {
  card_id: string;
  ok: boolean;
  error?: string;
}

async function handle(req: NextRequest): Promise<NextResponse> {
  const t0 = Date.now();

  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret) {
    return NextResponse.json(
      { error: 'cron_secret_missing' },
      { status: 500 },
    );
  }
  const auth = req.headers.get('authorization') || '';
  if (auth !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const sa = parseServiceAccount();
  if (!sa) {
    return NextResponse.json({
      ok: false,
      aborted: true,
      reason: 'service_account_missing',
      hint:
        'Set VERTEX_SERVICE_ACCOUNT_JSON (or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) ' +
        'env var with a JSON or base64 GCP service account that has ' +
        'aiplatform.user role.',
      latency_ms: Date.now() - t0,
    });
  }

  const koala = koalaAdmin();
  const { data: rows, error } = await koala
    .from('koala_cards')
    .select('id, cdn_url, original_url, thumbnail_url')
    .eq('is_published', true)
    .is('embedding', null)
    .limit(MAX_PER_RUN);

  if (error) {
    return NextResponse.json(
      { error: 'select_failed', detail: error.message },
      { status: 502 },
    );
  }

  const candidates = (rows ?? []) as CardRow[];
  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      succeeded: 0,
      failed: 0,
      latency_ms: Date.now() - t0,
    });
  }

  let token: string;
  try {
    token = await getAccessToken(sa);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return NextResponse.json(
      { error: 'token_failed', detail: msg },
      { status: 502 },
    );
  }

  const outcomes: Outcome[] = [];
  let succeeded = 0;
  let failed = 0;
  let quotaExhausted = false;

  for (const card of candidates) {
    if (quotaExhausted) break;
    const url = card.cdn_url || card.original_url || card.thumbnail_url;
    if (!url) {
      outcomes.push({ card_id: card.id, ok: false, error: 'no_image_url' });
      failed++;
      continue;
    }
    try {
      const res = await embedImage(token, sa.project_id, url);
      if ('error' in res) {
        if (res.status === 429 || res.error.includes('Quota')) {
          quotaExhausted = true;
          outcomes.push({
            card_id: card.id,
            ok: false,
            error: `rate_limited:${res.status}`,
          });
          failed++;
          break;
        }
        outcomes.push({
          card_id: card.id,
          ok: false,
          error: `vertex_${res.status}:${res.error.slice(0, 200)}`,
        });
        failed++;
        continue;
      }
      // pgvector accepts string literal: '[v1,v2,...]'
      const vecLiteral = `[${res.embedding.join(',')}]`;
      const { error: upErr } = await koala
        .from('koala_cards')
        .update({ embedding: vecLiteral })
        .eq('id', card.id);
      if (upErr) {
        outcomes.push({
          card_id: card.id,
          ok: false,
          error: `update_${upErr.message}`,
        });
        failed++;
        continue;
      }
      succeeded++;
      outcomes.push({ card_id: card.id, ok: true });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      outcomes.push({ card_id: card.id, ok: false, error: msg.slice(0, 200) });
      failed++;
    }
  }

  return NextResponse.json({
    ok: true,
    processed: outcomes.length,
    succeeded,
    failed,
    quota_exhausted: quotaExhausted,
    latency_ms: Date.now() - t0,
    outcomes,
  });
}

export async function GET(req: NextRequest) {
  return handle(req);
}

export async function POST(req: NextRequest) {
  return handle(req);
}
