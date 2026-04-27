import { NextRequest, NextResponse } from 'next/server';
import { evlumbaAdmin } from '@/lib/supabase/evlumba-admin';
import { corsHeaders } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 15;

/**
 * GET /api/swipe-deck?room_type=Yatak%20Odası&limit=12
 *
 * Lightweight deck source for the in-app "zevkimi keşfet" swipe screen.
 * Returns up to N published designer projects with cover image, tags and
 * color palette — JUST enough to render a swipeable card. No similarity,
 * no embeddings, no enrichment — this is a deliberately cheap path so the
 * deck loads in <500ms even on a cold lambda.
 *
 * room_type filter: best-effort, mirrors the match-designers route. The
 * evlumba.designer_projects table has no `room_type` column, so we match
 * against `project_type` (Turkish room labels) or any tag. If nothing
 * matches we fall through to the unfiltered set so the deck is never
 * empty when there ARE published projects.
 */

interface SwipeCard {
  id: string;
  cover_url: string;
  tags: string[];
  color_palette: string[];
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'GET, OPTIONS'),
  });
}

export async function GET(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'), 'GET, OPTIONS');
  const t0 = Date.now();

  const url = new URL(req.url);
  const roomType = url.searchParams.get('room_type')?.trim() || null;
  const rawLimit = parseInt(url.searchParams.get('limit') ?? '12', 10);
  const limit = Math.min(Math.max(Number.isFinite(rawLimit) ? rawLimit : 12, 1), 24);

  const evl = evlumbaAdmin();

  // Pull a small over-fetch (3x) so room filter + shuffle still leaves enough
  // unique cards. supabase REST hard-cap of 100 rows is well below this.
  const overFetch = Math.min(limit * 3, 60);

  const { data, error } = await evl
    .from('designer_projects')
    .select('id, cover_image_url, tags, color_palette, project_type')
    .eq('is_published', true)
    .not('cover_image_url', 'is', null)
    .limit(overFetch);

  if (error) {
    return NextResponse.json(
      { error: 'fetch_failed', detail: error.message },
      { status: 502, headers: cors },
    );
  }

  const rowsRaw = (data ?? []) as Array<{
    id: string;
    cover_image_url: string | null;
    tags: string[] | null;
    color_palette: string[] | null;
    project_type: string | null;
  }>;

  // room filter (best-effort)
  const norm = (s: string | null) =>
    (s ?? '').toLocaleLowerCase('tr-TR').trim();
  const target = roomType ? norm(roomType) : null;

  const filtered = (() => {
    if (!target) return rowsRaw;
    const hits = rowsRaw.filter(
      (r) =>
        norm(r.project_type) === target ||
        (r.tags ?? []).some((t) => norm(t) === target),
    );
    return hits.length > 0 ? hits : rowsRaw;
  })();

  // Shuffle (Fisher–Yates) and trim. Deck variety > determinism here.
  const shuffled = filtered.slice();
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const a = shuffled[i]!;
    const b = shuffled[j]!;
    shuffled[i] = b;
    shuffled[j] = a;
  }

  const cards: SwipeCard[] = shuffled.slice(0, limit).map((r) => ({
    id: r.id,
    cover_url: r.cover_image_url ?? '',
    tags: Array.isArray(r.tags) ? r.tags.slice(0, 4) : [],
    color_palette: Array.isArray(r.color_palette)
      ? r.color_palette.slice(0, 5)
      : [],
  }));

  return NextResponse.json(
    {
      cards,
      total: cards.length,
      latency_ms: Date.now() - t0,
    },
    { headers: cors },
  );
}
