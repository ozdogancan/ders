import { NextRequest, NextResponse } from 'next/server';
import { evlumbaAdmin } from '@/lib/supabase/evlumba-admin';
import { koalaAdmin } from '@/lib/supabase/koala';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 60;

/**
 * POST /api/match-designers
 *
 * Pro Match — kullanıcının restyle çıktısını evlumba portfolyolarıyla
 * semantik olarak eşleştirip top-K mimar/proje önerisi döner.
 *
 * Dual-DB architecture:
 *   - Al-Tutor (SUPABASE_URL): koala_marketplace_embeddings — vektörler.
 *   - Evlumba (EVLUMBA_SUPABASE_URL): designer_projects, designer_project_images,
 *     profiles — read-only enrichment.
 *
 * Akış:
 *   1. Kullanıcı görselini /api/embed-image (CLIP 768)
 *   2. Niyet metnini (theme + room) /api/embed-text (Gemini 768)
 *   3. Al-Tutor'dan tüm embedding'leri çek (60s module-level cache).
 *   4. Node-side weighted cosine similarity, top rpcK proje seç.
 *   5. Evlumba'dan projects + images + profiles paralel enrichment.
 *   6. room_type / city Node-side filtre.
 *   7. Designer dedupe — her mimar tek kart, kalanı related_projects.
 */

interface DesignerMatch {
  similarity: number;
  designer: {
    id: string;
    name: string | null;
    avatar_url: string | null;
    city: string | null;
    specialty: string | null;
    slug: string | null;
    rating: number | null;
    review_count: number | null;
    response_time: string | null;
    starting_from: number | null;
    is_verified: boolean;
    instagram: string | null;
  };
  project: {
    id: string;
    title: string | null;
    type: string | null;
    location: string | null;
    cover_url: string | null;
    gallery_urls: string[];
    tags: string[];
    color_palette: string[] | null;
  };
  /** Aynı mimarın diğer ucu eşleşen projeleri (similarity desc). */
  related_projects: Array<{ id: string; title: string | null; cover_url: string | null; similarity: number }>;
}

interface Embedding {
  project_id: string;
  image_embedding: number[];
  text_embedding: number[];
}

// ─── Module-level embedding cache (60s TTL) ───────────────────────────
const CACHE_TTL_MS = 60_000;
let embeddingCache: { rows: Embedding[]; fetchedAt: number } | null = null;

function parseEmbedding(v: unknown): number[] | null {
  if (Array.isArray(v)) return v.map((x) => Number(x));
  if (typeof v === 'string') {
    // pgvector text format: "[0.1,0.2,...]"
    try {
      const parsed = JSON.parse(v);
      if (Array.isArray(parsed)) return parsed.map((x) => Number(x));
    } catch {
      return null;
    }
  }
  return null;
}

function cosine(a: number[], b: number[]): number {
  const len = Math.min(a.length, b.length);
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < len; i++) {
    const av = a[i]!;
    const bv = b[i]!;
    dot += av * bv;
    na += av * av;
    nb += bv * bv;
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));
  const t0 = Date.now();

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers: cors });
  }
  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413, headers: cors });
  }
  if (!checkRateLimit(req, 'match-designers', 15)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers: cors },
    );
  }

  let body: {
    image?: string;
    room_type?: string;
    theme?: string;
    city?: string;
    match_count?: number;
    image_weight?: number;
    text_weight?: number;
  };
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

  const k = Math.min(Math.max(body.match_count ?? 8, 1), 20);
  const roomType = body.room_type?.trim() || null;
  const theme = body.theme?.trim() || null;
  const city = body.city?.trim() || null;
  const imageWeight = typeof body.image_weight === 'number' ? body.image_weight : 0.7;
  const textWeight = typeof body.text_weight === 'number' ? body.text_weight : 0.3;

  // ─── 1) Paralel embed (image + text) ────────────────────────────────
  const textParts = [theme, roomType, 'iç mimar tarzı'].filter(Boolean);
  const queryText = textParts.join(' · ');

  const baseUrl =
    process.env.VERCEL_URL
      ? `https://${process.env.VERCEL_URL}`
      : 'http://localhost:3000';

  const tEmb0 = Date.now();
  const [imageEmbResp, textEmbResp] = await Promise.all([
    fetch(`${baseUrl}/api/embed-image`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image }),
    }),
    fetch(`${baseUrl}/api/embed-text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: queryText, task_type: 'RETRIEVAL_QUERY' }),
    }),
  ]);

  // Embed başarısız olursa (Replicate kredisi bitti, dim mismatch vs.)
  // sheet boş kalmasın — fallback path'e düş: theme + room_type ile basit
  // popularity-based listing dön. Kullanıcı yine somut bir mimar listesi
  // görür, sadece "tasarımına benzer" yerine "bu kategoride iyi olanlar".
  let imageEmb: number[] | null = null;
  let textEmb: number[] | null = null;
  let embedFailReason: string | null = null;

  if (imageEmbResp.ok && textEmbResp.ok) {
    imageEmb = (await imageEmbResp.json()).embedding as number[];
    textEmb = (await textEmbResp.json()).embedding as number[];
  } else {
    const ie = imageEmbResp.ok
      ? null
      : await imageEmbResp.json().catch(() => ({}));
    const te = textEmbResp.ok
      ? null
      : await textEmbResp.json().catch(() => ({}));
    embedFailReason =
      ie?.detail?.toString().slice(0, 120) ??
      te?.detail?.toString().slice(0, 120) ??
      'embed_unavailable';
    console.warn('[match-designers] embed_failed_fallback', {
      image_status: imageEmbResp.status,
      text_status: textEmbResp.status,
      reason: embedFailReason,
    });
  }
  const embed_ms = Date.now() - tEmb0;

  // ─── 2) Embeddings: Al-Tutor'dan al, 60s cache ──────────────────────
  let cacheStatus: 'hit' | 'miss' = 'miss';
  let rows: Embedding[];
  const now = Date.now();
  if (embeddingCache && now - embeddingCache.fetchedAt < CACHE_TTL_MS) {
    rows = embeddingCache.rows;
    cacheStatus = 'hit';
  } else {
    const koala = koalaAdmin();
    const { data, error } = await koala
      .from('koala_marketplace_embeddings')
      .select('project_id, image_embedding, text_embedding');

    if (error) {
      return NextResponse.json(
        { error: 'embeddings_fetch_failed', detail: error.message },
        { status: 502, headers: cors },
      );
    }

    rows = [];
    for (const r of data ?? []) {
      const img = parseEmbedding((r as any).image_embedding);
      const txt = parseEmbedding((r as any).text_embedding);
      if (!img || !txt) continue;
      rows.push({
        project_id: (r as any).project_id,
        image_embedding: img,
        text_embedding: txt,
      });
    }
    embeddingCache = { rows, fetchedAt: now };
  }

  // ─── 3) Project ID seçimi ───────────────────────────────────────────
  // Üç yoldan biri:
  //   (a) embeddings + Replicate çalışıyor → cosine similarity
  //   (b) embeddings dolu ama Replicate yok → similarity yok, embeddings
  //       satırlarını fallback liste olarak kullan
  //   (c) embeddings BOŞ → evlumba'dan direkt proje listesi çek (popularity)
  const tCos0 = Date.now();
  let topProjectIds: string[] = [];
  const simMap = new Map<string, number>();

  if (rows.length > 0 && imageEmb && textEmb) {
    // (a) similarity path
    const scored: Array<{ project_id: string; similarity: number }> = [];
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i]!;
      const sIm = cosine(imageEmb, row.image_embedding);
      const sTx = cosine(textEmb, row.text_embedding);
      scored.push({
        project_id: row.project_id,
        similarity: imageWeight * sIm + textWeight * sTx,
      });
    }
    scored.sort((a, b) => b.similarity - a.similarity);
    const rpcK = Math.min(k * 3, 30);
    topProjectIds = scored.slice(0, rpcK).map((s) => s.project_id);
    for (const s of scored) {
      if (!simMap.has(s.project_id)) simMap.set(s.project_id, s.similarity);
    }
  } else if (rows.length > 0) {
    // (b) embeddings var, similarity yok
    topProjectIds = rows.map((r) => r.project_id);
    for (const id of topProjectIds) simMap.set(id, 0);
  } else {
    // (c) embeddings boş — evlumba'dan popularity-based liste çek
    const evlBootstrap = evlumbaAdmin();
    const { data: bootstrap, error: bErr } = await evlBootstrap
      .from('designer_projects')
      .select('id')
      .limit(60);
    if (bErr) {
      console.error('[match-designers] bootstrap_fetch_failed', bErr.message);
      return NextResponse.json(
        { error: 'bootstrap_fetch_failed', detail: bErr.message },
        { status: 502, headers: cors },
      );
    }
    topProjectIds = (bootstrap ?? []).map((r: any) => r.id as string);
    for (const id of topProjectIds) simMap.set(id, 0);
  }
  const cosine_ms = Date.now() - tCos0;

  if (topProjectIds.length === 0) {
    console.warn('[match-designers] no_projects_anywhere');
    return NextResponse.json(
      {
        matches: [],
        total: 0,
        latency_ms: Date.now() - t0,
        cache: cacheStatus,
        embed_ms,
        cosine_ms,
        evlumba_ms: 0,
        match_mode: 'popularity',
      },
      { headers: cors },
    );
  }

  // ─── 4) Evlumba enrichment (paralel) ────────────────────────────────
  const evl = evlumbaAdmin();
  const tEvl0 = Date.now();

  const { data: projectRows, error: projErr } = await evl
    .from('designer_projects')
    .select('id, designer_id, title, project_type, location, cover_image_url, tags, color_palette')
    .in('id', topProjectIds);

  if (projErr) {
    return NextResponse.json(
      { error: 'projects_fetch_failed', detail: projErr.message },
      { status: 502, headers: cors },
    );
  }

  const projectsRaw = (projectRows ?? []) as Array<{
    id: string;
    designer_id: string;
    title: string | null;
    project_type: string | null;
    location: string | null;
    cover_image_url: string | null;
    tags: string[] | null;
    color_palette: string[] | null;
  }>;

  // Map cover_image_url → cover_url (Flutter contract uses cover_url)
  const projects = projectsRaw.map((p) => ({
    id: p.id,
    designer_id: p.designer_id,
    title: p.title,
    project_type: p.project_type,
    location: p.location,
    cover_url: p.cover_image_url,
    tags: p.tags,
    color_palette: p.color_palette,
  }));

  // room_type column doesn't exist in evlumba.designer_projects.
  // Best-effort filter: match against project_type (Turkish room labels)
  // or tags. If no match, fall through to unfiltered set so we still return results.
  const roomFilteredProjects = (() => {
    if (!roomType) return projects;
    const norm = (s: string | null) =>
      (s ?? '').toLocaleLowerCase('tr-TR').trim();
    const target = norm(roomType);
    const filtered = projects.filter(
      (p) =>
        norm(p.project_type) === target ||
        (p.tags ?? []).some((t) => norm(t) === target),
    );
    return filtered.length > 0 ? filtered : projects;
  })();

  const designerIdsAll = Array.from(
    new Set(roomFilteredProjects.map((p) => p.designer_id).filter(Boolean)),
  );

  if (designerIdsAll.length === 0 || roomFilteredProjects.length === 0) {
    return NextResponse.json(
      {
        matches: [],
        total: 0,
        latency_ms: Date.now() - t0,
        cache: cacheStatus,
        embed_ms,
        cosine_ms,
        evlumba_ms: Date.now() - tEvl0,
      },
      { headers: cors },
    );
  }

  const filteredProjectIds = roomFilteredProjects.map((p) => p.id);

  const [profilesRes, galleryRes] = await Promise.all([
    evl
      .from('profiles')
      .select(
        'id, full_name, avatar_url, city, specialty, slug, google_rating, google_review_count, response_time, starting_from, is_verified, instagram',
      )
      .in('id', designerIdsAll),
    evl
      .from('designer_project_images')
      .select('project_id, image_url, sort_order')
      .in('project_id', filteredProjectIds)
      .order('sort_order', { ascending: true }),
  ]);

  const evlumba_ms = Date.now() - tEvl0;

  const profileMap = new Map<string, any>();
  for (const p of profilesRes.data ?? []) profileMap.set((p as any).id, p);

  const galleryMap = new Map<string, string[]>();
  for (const img of galleryRes.data ?? []) {
    const pid = (img as any).project_id as string;
    const url = (img as any).image_url as string | null;
    const arr = galleryMap.get(pid) ?? [];
    if (url) arr.push(url);
    galleryMap.set(pid, arr);
  }

  // city filtresi (designer üzerinde)
  const cityOk = (designerId: string): boolean => {
    if (!city) return true;
    const profile = profileMap.get(designerId);
    return profile?.city === city;
  };

  // ─── 5) Designer dedupe ─────────────────────────────────────────────
  // Project id -> similarity (filtrelenmiş projeler için, similarity desc)
  const projectsWithSim = roomFilteredProjects
    .map((p) => ({ project: p, similarity: simMap.get(p.id) ?? 0 }))
    .sort((a, b) => b.similarity - a.similarity);

  const byDesigner = new Map<string, typeof projectsWithSim>();
  for (const entry of projectsWithSim) {
    const dId = entry.project.designer_id;
    if (!dId) continue;
    if (!cityOk(dId)) continue;
    const list = byDesigner.get(dId) ?? [];
    list.push(entry);
    byDesigner.set(dId, list);
  }

  // Sort: similarity varsa ona göre, yoksa designer rating'ine göre.
  const designerOrder = [...byDesigner.entries()]
    .map(([id, list]) => {
      const profile = profileMap.get(id);
      const rating = Number(profile?.google_rating ?? 0);
      const reviewCount = Number(profile?.google_review_count ?? 0);
      return {
        id,
        best: list[0]!.similarity,
        rating,
        reviewCount,
      };
    })
    .sort((a, b) => {
      if (b.best !== a.best) return b.best - a.best;
      if (b.rating !== a.rating) return b.rating - a.rating;
      return b.reviewCount - a.reviewCount;
    })
    .slice(0, k)
    .map((x) => x.id);

  // ─── 6) Compose final matches ───────────────────────────────────────
  const matches: DesignerMatch[] = [];
  for (const dId of designerOrder) {
    const list = byDesigner.get(dId)!;
    const main = list[0]!;
    const profile = profileMap.get(dId);
    const mainProject = main.project;
    const mainGallery = galleryMap.get(mainProject.id) ?? [];

    matches.push({
      similarity: main.similarity,
      designer: {
        id: dId,
        name: profile?.full_name ?? null,
        avatar_url: profile?.avatar_url ?? null,
        city: profile?.city ?? null,
        specialty: profile?.specialty ?? null,
        slug: profile?.slug ?? null,
        rating: profile?.google_rating ?? null,
        review_count: profile?.google_review_count ?? null,
        response_time: profile?.response_time ?? null,
        starting_from: profile?.starting_from ?? null,
        is_verified: !!profile?.is_verified,
        instagram: profile?.instagram ?? null,
      },
      project: {
        id: mainProject.id,
        title: mainProject.title,
        type: mainProject.project_type,
        location: mainProject.location,
        cover_url: mainProject.cover_url,
        gallery_urls: mainGallery.slice(0, 4),
        tags: Array.isArray(mainProject.tags) ? mainProject.tags : [],
        color_palette: Array.isArray(mainProject.color_palette) ? mainProject.color_palette : null,
      },
      related_projects: list.slice(1, 4).map((p) => ({
        id: p.project.id,
        title: p.project.title,
        cover_url: p.project.cover_url,
        similarity: p.similarity,
      })),
    });
  }

  const matchMode =
    rows.length > 0 && imageEmb && textEmb ? 'similarity' : 'popularity';
  console.log('[match-designers] ok', {
    mode: matchMode,
    matches: matches.length,
    latency_ms: Date.now() - t0,
    embed_fail: embedFailReason,
  });

  return NextResponse.json(
    {
      matches,
      total: matches.length,
      latency_ms: Date.now() - t0,
      cache: cacheStatus,
      embed_ms,
      cosine_ms,
      evlumba_ms,
      match_mode: matchMode,
      ...(embedFailReason ? { embed_fail: embedFailReason } : {}),
    },
    { headers: cors },
  );
}
