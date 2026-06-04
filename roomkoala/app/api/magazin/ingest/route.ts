import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const SB_URL = "https://xgefjepaqnghaotqybpi.supabase.co";

type IncomingPost = {
  slug: string;
  title: string;
  dek: string;
  category: string;
  date: string;
  readingMinutes: number;
  sourceName: string;
  sourceUrl: string;
  sections: { heading?: string; paragraphs: string[] }[];
  tags?: string[];
};

/**
 * n8n günlük içerik motoru bu endpoint'i çağırır.
 * Gizli işler (Supabase service_role ile Storage upload + row insert) burada,
 * sunucu tarafında olur. n8n yalnızca Gemini + bu POST'u yapar → hafif & güvenli.
 *
 * Body: { post: IncomingPost, imageBase64: string }
 * Header: x-ingest-secret: <MAGAZIN_INGEST_SECRET>
 */
export async function POST(req: NextRequest) {
  const SR = process.env.SUPABASE_SERVICE_ROLE;
  const SECRET = process.env.MAGAZIN_INGEST_SECRET;
  if (!SR || !SECRET) {
    return NextResponse.json({ error: "server not configured" }, { status: 500 });
  }
  if (req.headers.get("x-ingest-secret") !== SECRET) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { post?: IncomingPost; imageBase64?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  const post = body.post;
  if (!post?.slug || !post.title || !Array.isArray(post.sections)) {
    return NextResponse.json({ error: "invalid post" }, { status: 400 });
  }

  let hero = "";
  // 1) Görsel varsa Supabase Storage'a yükle
  if (body.imageBase64) {
    const bytes = Buffer.from(body.imageBase64, "base64");
    const path = `${post.slug}.png`;
    const up = await fetch(`${SB_URL}/storage/v1/object/magazin/${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${SR}`,
        "Content-Type": "image/png",
        "x-upsert": "true",
      },
      body: bytes,
    });
    if (!up.ok) {
      return NextResponse.json(
        { error: "upload failed", detail: await up.text() },
        { status: 502 }
      );
    }
    hero = `${SB_URL}/storage/v1/object/public/magazin/${path}`;
  }

  // 2) Satırı ekle (service_role → RLS bypass)
  const ins = await fetch(`${SB_URL}/rest/v1/magazin_posts`, {
    method: "POST",
    headers: {
      apikey: SR,
      Authorization: `Bearer ${SR}`,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=minimal",
    },
    body: JSON.stringify({
      slug: post.slug,
      title: post.title,
      dek: post.dek,
      category: post.category,
      date: post.date,
      reading_minutes: post.readingMinutes,
      hero,
      source_name: post.sourceName,
      source_url: post.sourceUrl,
      sections: post.sections,
      tags: post.tags ?? [],
    }),
  });
  if (!ins.ok) {
    return NextResponse.json(
      { error: "insert failed", detail: await ins.text() },
      { status: 502 }
    );
  }

  return NextResponse.json({ ok: true, slug: post.slug, hero });
}
