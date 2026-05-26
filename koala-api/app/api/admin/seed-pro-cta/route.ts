// POST /api/admin/seed-pro-cta — generate the Pro CTA hero image (Gemini Flash Image).
//
// One-off admin endpoint. Generates a single 16:9 hero image with
// gemini-3.1-flash-image-preview, optimizes to WebP via sharp, and uploads
// to the existing public `koala-seed` Storage bucket at:
//   pro-cta/hero-v1.webp
//
// Auth: `?token=<ADMIN_TOKEN>` query param (matches env var).
//
// curl example:
//   curl -X POST 'https://koala-api-olive.vercel.app/api/admin/seed-pro-cta?token=$ADMIN_TOKEN'
//
// Response: { ok: true, url: '<public webp url>' } | { error }

import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';

export const runtime = 'nodejs';
export const maxDuration = 120;
export const dynamic = 'force-dynamic';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const IMAGE_MODEL = 'gemini-3.1-flash-image-preview';
const BUCKET = 'koala-seed';
const OBJECT_PATH = 'pro-cta/hero-v1.webp';

const PROMPT =
  'A professional interior designer at work in a luxurious modern living ' +
  'room, sketching plans on a tablet, soft natural light, premium magazine ' +
  'cover quality, warm golden hour color palette, no text, no faces clearly ' +
  'visible (or stylized from behind), depth of field, premium editorial ' +
  'photography style.';

async function generateImage(prompt: string): Promise<Buffer> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/` +
    `${IMAGE_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
    }),
  });
  const data = await res.json();
  if (res.status >= 300) {
    throw new Error(`gemini ${res.status}: ${JSON.stringify(data).slice(0, 200)}`);
  }
  const parts: Array<{ inlineData?: { data?: string } }> =
    data?.candidates?.[0]?.content?.parts ?? [];
  const img = parts.find((p) => p?.inlineData?.data);
  if (!img?.inlineData?.data) throw new Error('no image in gemini response');
  return Buffer.from(img.inlineData.data, 'base64');
}

async function handle(req: NextRequest) {
  const adminToken = process.env.ADMIN_TOKEN;
  if (!adminToken) {
    return NextResponse.json(
      { error: 'admin_token_not_configured' },
      { status: 500 },
    );
  }
  const token = new URL(req.url).searchParams.get('token');
  if (token !== adminToken) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  try {
    const raw = await generateImage(PROMPT);

    // 1024x576 (16:9) cover. quality 82.
    const out = await sharp(raw)
      .resize({ width: 1024, height: 576, fit: 'cover', position: 'attention' })
      .webp({ quality: 82 })
      .toBuffer();

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const up = await sb.storage
      .from(BUCKET)
      .upload(OBJECT_PATH, out, {
        contentType: 'image/webp',
        upsert: true,
        cacheControl: '3600',
      });
    if (up.error) throw new Error(`upload: ${up.error.message}`);

    const url = sb.storage.from(BUCKET).getPublicUrl(OBJECT_PATH).data.publicUrl;
    return NextResponse.json({ ok: true, url, prompt: PROMPT });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[admin/seed-pro-cta] error', msg);
    return NextResponse.json(
      { error: 'generate_failed', detail: msg },
      { status: 500 },
    );
  }
}

export async function POST(req: NextRequest) {
  return handle(req);
}

// Also allow GET for easy manual triggering from a browser.
export async function GET(req: NextRequest) {
  return handle(req);
}
