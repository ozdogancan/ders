import { NextRequest, NextResponse } from 'next/server';
import { evlumbaAdmin } from '@/lib/supabase/evlumba-admin';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const maxDuration = 60;

/**
 * POST /api/admin/backfill-embeddings
 *
 * Designer projelerini (evlumba.designer_projects) tek tek alıp
 * Al-Tutor (koala) tarafındaki `koala_marketplace_embeddings` tablosuna
 * image + text embedding'leri ile doldurur.
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>` header'ı zorunlu. Vercel
 * cron çağrıları otomatik olarak bu header'ı ekler.
 *
 * Body (opsiyonel JSON):
 *   {
 *     batch_size?: number,   // default 5  — her batch'te paralel proje sayısı
 *     max_batches?: number,  // default 3  — sequential batch sayısı
 *     force?: boolean,       // default false — true ise zaten embed edilmişleri de yeniden işler
 *   }
 *
 * Toplam: batch_size * max_batches proje işlenir (varsayılan 15) — 60s timeout altında kalır.
 *
 * Response:
 *   {
 *     processed, succeeded, failed, skipped, latency_ms,
 *     errors: [{ project_id, error }]
 *   }
 *
 * Idempotent — aynı çağrıyı arka arkaya yapmak no-op'a yaklaşır
 * (force=false ise `koala_marketplace_embeddings`'te kayıtlı projeler skip edilir).
 */

interface BackfillBody {
  batch_size?: number;
  max_batches?: number;
  force?: boolean;
}

interface DesignerProjectRow {
  id: string;
  cover_image_url: string | null;
  tags: string[] | null;
  project_type: string | null;
  color_palette: string[] | null;
  title: string | null;
}

interface ProjectError {
  project_id: string;
  error: string;
}

export async function POST(req: NextRequest) {
  const t0 = Date.now();

  // ─── Auth ────────────────────────────────────────────────────────────
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret) {
    return NextResponse.json(
      { error: 'cron_secret_missing' },
      { status: 500 },
    );
  }
  const authHeader = req.headers.get('authorization') || '';
  const expected = `Bearer ${cronSecret}`;
  if (authHeader !== expected) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  // ─── Parse body (opsiyonel) ──────────────────────────────────────────
  let body: BackfillBody = {};
  try {
    const text = await req.text();
    if (text) body = JSON.parse(text) as BackfillBody;
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400 });
  }

  const batchSize = Math.max(1, Math.min(body.batch_size ?? 5, 20));
  const maxBatches = Math.max(1, Math.min(body.max_batches ?? 3, 10));
  const force = !!body.force;

  const limit = batchSize * maxBatches;

  // ─── Internal base URL (match-designers ile aynı pattern) ────────────
  const baseUrl = process.env.VERCEL_URL
    ? `https://${process.env.VERCEL_URL}`
    : 'http://localhost:3000';

  // ─── 1) evlumba.designer_projects'ten aday projeler ──────────────────
  const evlumba = evlumbaAdmin();
  const { data: projectsRaw, error: projErr } = await evlumba
    .from('designer_projects')
    .select('id, cover_image_url, tags, project_type, color_palette, title')
    .not('cover_image_url', 'is', null)
    .eq('is_published', true)
    .limit(limit);

  if (projErr) {
    return NextResponse.json(
      { error: 'evlumba_query_failed', detail: projErr.message },
      { status: 502 },
    );
  }

  const projects = (projectsRaw ?? []) as DesignerProjectRow[];

  if (projects.length === 0) {
    return NextResponse.json({
      processed: 0,
      succeeded: 0,
      failed: 0,
      skipped: 0,
      latency_ms: Date.now() - t0,
      errors: [],
    });
  }

  // ─── 2) Al-Tutor'da zaten embed edilenleri çek ───────────────────────
  const koala = koalaAdmin();
  let alreadyEmbeddedIds = new Set<string>();
  if (!force) {
    const projectIds = projects.map((p) => p.id);
    const { data: existing, error: exErr } = await koala
      .from('koala_marketplace_embeddings')
      .select('project_id')
      .in('project_id', projectIds);

    if (exErr) {
      return NextResponse.json(
        { error: 'koala_query_failed', detail: exErr.message },
        { status: 502 },
      );
    }
    alreadyEmbeddedIds = new Set(
      (existing ?? []).map((r: { project_id: string }) => r.project_id),
    );
  }

  const pending = projects.filter((p) => !alreadyEmbeddedIds.has(p.id));
  const skipped = projects.length - pending.length;

  // ─── 3) Sequential batches, parallel within batch ────────────────────
  let succeeded = 0;
  let failed = 0;
  const errors: ProjectError[] = [];

  for (let i = 0; i < pending.length; i += batchSize) {
    const chunk = pending.slice(i, i + batchSize);

    const results = await Promise.all(
      chunk.map((project) => processProject(project, baseUrl)),
    );

    for (const r of results) {
      if (r.ok) {
        succeeded++;
      } else {
        failed++;
        errors.push({ project_id: r.projectId, error: r.error });
        // Hata durumu da DB'ye yansıt (last_error + retry_count++)
        await markFailure(koala, r.projectId, r.error);
      }
    }
  }

  return NextResponse.json({
    processed: pending.length,
    succeeded,
    failed,
    skipped,
    latency_ms: Date.now() - t0,
    errors,
  });
}

// ─── Helpers ───────────────────────────────────────────────────────────

type ProcessResult =
  | { ok: true; projectId: string }
  | { ok: false; projectId: string; error: string };

async function processProject(
  project: DesignerProjectRow,
  baseUrl: string,
): Promise<ProcessResult> {
  try {
    if (!project.cover_image_url) {
      return { ok: false, projectId: project.id, error: 'missing_cover_image_url' };
    }

    // Text input
    const textParts: string[] = [
      project.title ?? '',
      project.project_type ?? '',
      ...(project.tags ?? []),
      ...((project.color_palette ?? []).map((c) => `renk:${c}`)),
    ].filter(Boolean);
    const textInput = textParts.join(' · ');

    // Paralel image + text embed
    const [imageResp, textResp] = await Promise.all([
      fetch(`${baseUrl}/api/embed-image`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: project.cover_image_url }),
      }),
      fetch(`${baseUrl}/api/embed-text`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: textInput || project.id,
          task_type: 'RETRIEVAL_DOCUMENT',
        }),
      }),
    ]);

    // Rate-limit graceful handling
    if (imageResp.status === 429 || textResp.status === 429) {
      return { ok: false, projectId: project.id, error: 'rate_limited' };
    }

    if (!imageResp.ok) {
      const j = (await imageResp.json().catch(() => ({}))) as {
        error?: string;
      };
      return {
        ok: false,
        projectId: project.id,
        error: `embed_image_failed:${j.error ?? imageResp.status}`,
      };
    }
    if (!textResp.ok) {
      const j = (await textResp.json().catch(() => ({}))) as { error?: string };
      return {
        ok: false,
        projectId: project.id,
        error: `embed_text_failed:${j.error ?? textResp.status}`,
      };
    }

    const imageJson = (await imageResp.json()) as { embedding: number[] };
    const textJson = (await textResp.json()) as { embedding: number[] };

    // Upsert into Al-Tutor
    const koala = koalaAdmin();
    const { error: upErr } = await koala
      .from('koala_marketplace_embeddings')
      .upsert(
        {
          project_id: project.id,
          image_embedding: imageJson.embedding,
          text_embedding: textJson.embedding,
          text_input: textInput,
          cover_image_url: project.cover_image_url,
          tags: project.tags,
          project_type: project.project_type,
          color_palette: project.color_palette,
          title: project.title,
          last_error: null,
          retry_count: 0,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'project_id' },
      );

    if (upErr) {
      return {
        ok: false,
        projectId: project.id,
        error: `upsert_failed:${upErr.message}`,
      };
    }

    return { ok: true, projectId: project.id };
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, projectId: project.id, error: `unhandled:${msg}` };
  }
}

async function markFailure(
  koala: ReturnType<typeof koalaAdmin>,
  projectId: string,
  errorMsg: string,
): Promise<void> {
  try {
    // retry_count'u artırmak için önce mevcut satırı oku.
    const { data: existing } = await koala
      .from('koala_marketplace_embeddings')
      .select('retry_count')
      .eq('project_id', projectId)
      .maybeSingle();

    const prevRetry =
      (existing as { retry_count: number | null } | null)?.retry_count ?? 0;

    await koala.from('koala_marketplace_embeddings').upsert(
      {
        project_id: projectId,
        last_error: errorMsg.slice(0, 500),
        retry_count: prevRetry + 1,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'project_id' },
    );
  } catch {
    // Failure-marking failure — yutuyoruz, batch akışı bozulmasın.
  }
}
