// POST /api/admin/seed-coachmark-images — generate the 6 coachmark step images.
//
// One-off admin endpoint. For each step id (home/chat/paylas/ai/profile/bell)
// generates a 1024x1024 image with gemini-3.1-flash-image-preview, optimizes
// to WebP via sharp, uploads to the existing public `koala-seed` Storage
// bucket at: coachmark/{stepId}-v1.webp
//
// Auth: `?token=<ADMIN_TOKEN>` query param (matches env var).
//
// curl example:
//   curl -X POST 'https://koala-api-olive.vercel.app/api/admin/seed-coachmark-images?token=$ADMIN_TOKEN'
//
// Response: { ok: true, urls: { home, chat, paylas, ai, profile, bell } }

import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';

export const runtime = 'nodejs';
export const maxDuration = 300;
export const dynamic = 'force-dynamic';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const IMAGE_MODEL = 'gemini-3.1-flash-image-preview';
const BUCKET = 'koala-seed';

const STEPS: Record<string, string> = {
  home:
    'An elegant living room hero shot, swipe gesture indicator overlay, ' +
    'two hands gently swiping a stylized card design left/right, warm ' +
    'natural lighting, magazine quality, no text, no faces.',
  chat:
    'A cozy interior design studio with two stylized chat bubbles floating ' +
    'gently, soft champagne palette, sense of warm conversation, no faces ' +
    'visible, premium editorial photography.',
  paylas:
    'A bright modern apartment with a phone in foreground capturing a room ' +
    'photo, soft sun rays, sense of inspiration, no faces, magazine ' +
    'photography style, warm tones.',
  ai:
    'A sophisticated interior design wall with stylized AI sparkles and ' +
    'tools (paint swatches, mood board, style icons) floating in soft ' +
    'purple light, premium editorial photography, no text, no faces.',
  profile:
    'A serene minimalist interior with a framed photo wall, sense of ' +
    'identity and belonging, soft natural lighting, no faces, premium ' +
    'magazine quality.',
  bell:
    'A warm cozy bedroom with a small soft glow of a notification (a ' +
    'single small circular gold light on a nightstand), evening lighting, ' +
    'intimate atmosphere, no text, no faces.',
};

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

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const urls: Record<string, string> = {};
  const errors: Record<string, string> = {};

  for (const [stepId, prompt] of Object.entries(STEPS)) {
    try {
      const raw = await generateImage(prompt);

      // 1024x1024 square cover. quality 82.
      const out = await sharp(raw)
        .resize({ width: 1024, height: 1024, fit: 'cover', position: 'attention' })
        .webp({ quality: 82 })
        .toBuffer();

      const objectPath = `coachmark/${stepId}-v1.webp`;
      const up = await sb.storage
        .from(BUCKET)
        .upload(objectPath, out, {
          contentType: 'image/webp',
          upsert: true,
          cacheControl: '3600',
        });
      if (up.error) throw new Error(`upload: ${up.error.message}`);

      urls[stepId] = sb.storage.from(BUCKET).getPublicUrl(objectPath).data.publicUrl;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`[admin/seed-coachmark-images] ${stepId} failed`, msg);
      errors[stepId] = msg;
    }
  }

  if (Object.keys(errors).length > 0) {
    return NextResponse.json(
      { ok: false, urls, errors },
      { status: 500 },
    );
  }
  return NextResponse.json({ ok: true, urls });
}

export async function POST(req: NextRequest) {
  return handle(req);
}

// Also allow GET for easy manual triggering from a browser.
export async function GET(req: NextRequest) {
  return handle(req);
}
