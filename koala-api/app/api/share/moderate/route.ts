// POST /api/share/moderate
//
// IG-tarzı kullanıcı paylaşım akışı için moderation gate'i.
// Gemini Vision (analyze-room ile aynı model) ile:
//   1) is_room — bu bir iç mekan oda fotoğrafı mı?
//   2) inappropriate — NSFW / şiddet / uygunsuz içerik var mı?
//
// Body: { imageUrl?: string, image?: string (data: URL veya https URL), userId? }
// Response:
//   { ok: true } veya
//   { ok: false, reason: 'not_a_room' | 'inappropriate' | 'analysis_failed', detail? }
//
// NOT: analyze-room route'undan farklı olarak burada full style payload
// üretmiyoruz — sadece gate kararını dönüyoruz. Daha hızlı, daha ucuz.

import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 30;

const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    is_room: {
      type: 'boolean',
      description:
        'true if the photo shows the interior of an indoor room. false for selfies, outdoor scenes, food, screenshots, random object close-ups.',
    },
    inappropriate: {
      type: 'boolean',
      description:
        'true if photo contains NSFW, nudity, sexual, violence, gore, hate symbols, illegal substances, or other clearly inappropriate content.',
    },
    inappropriate_reason: {
      type: 'string',
      description:
        "One of: 'none' | 'nsfw' | 'violence' | 'hate' | 'other'. Use 'none' for safe content.",
    },
    confidence: {
      type: 'number',
      description: '0.0-1.0 confidence in this assessment',
    },
  },
  required: ['is_room', 'inappropriate', 'inappropriate_reason', 'confidence'],
};

const PROMPT = `Bu görseli iki kritere göre değerlendir ve JSON dön.

1) is_room: SADECE bir iç mekân oda fotoğrafı mı? (salon, yatak odası, mutfak,
   banyo, yemek odası, çalışma odası, çocuk odası, hol, koridor, balkon iç
   görünümü). Selfie/portre, dış mekân/sokak/manzara, yiyecek close-up, ekran
   görüntüsü, rastgele nesne close-up → false.

2) inappropriate: Görselde NSFW (çıplaklık, cinsel içerik), şiddet/kan/gore,
   nefret sembolleri, yasadışı madde reklamı veya açıkça uygunsuz içerik var
   mı? Yoksa false ve inappropriate_reason='none'.

Sadece JSON dön, başka metin yok.`;

interface ModerationResult {
  is_room: boolean;
  inappropriate: boolean;
  inappropriate_reason: string;
  confidence: number;
}

function buildImagePart(image: string): Record<string, unknown> {
  if (image.startsWith('data:')) {
    const m = image.match(/^data:([^;]+);base64,(.*)$/);
    if (!m) throw new Error('invalid_data_url');
    return { inlineData: { mimeType: m[1], data: m[2] } };
  }
  if (/^https?:\/\//i.test(image)) {
    return { fileData: { mimeType: 'image/jpeg', fileUri: image } };
  }
  throw new Error('invalid_image_url');
}

async function callGemini(image: string, apiKey: string): Promise<ModerationResult> {
  const imagePart = buildImagePart(image);
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: PROMPT }, imagePart] }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: 'application/json',
        responseSchema: RESPONSE_SCHEMA,
      },
    }),
  });

  if (!r.ok) {
    const txt = await r.text();
    throw new Error(`gemini ${r.status}: ${txt.slice(0, 300)}`);
  }

  const j = await r.json();
  const text: string = j?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
  if (!text) throw new Error('gemini: empty response');

  const parsed = JSON.parse(text) as Record<string, unknown>;
  const conf = Number(parsed.confidence);
  return {
    is_room: parsed.is_room === true,
    inappropriate: parsed.inappropriate === true,
    inappropriate_reason: String(parsed.inappropriate_reason ?? 'none').toLowerCase(),
    confidence: Number.isFinite(conf) ? Math.max(0, Math.min(1, conf)) : 0.7,
  };
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ ok: false, reason: 'forbidden' }, { status: 403, headers: cors });
  }
  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json({ ok: false, reason: 'payload_too_large' }, { status: 413, headers: cors });
  }
  if (!checkRateLimit(req, 'share-moderate', 20)) {
    return NextResponse.json(
      { ok: false, reason: 'rate_limited' },
      { status: 429, headers: cors },
    );
  }

  let body: { imageUrl?: string; image?: string; userId?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, reason: 'invalid_json' }, { status: 400, headers: cors });
  }

  const image = (body.image || body.imageUrl || '').trim();
  if (!image) {
    return NextResponse.json({ ok: false, reason: 'missing_image' }, { status: 400, headers: cors });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { ok: false, reason: 'gemini_key_missing' },
      { status: 500, headers: cors },
    );
  }

  let result: ModerationResult;
  try {
    result = await callGemini(image, apiKey);
  } catch (e) {
    return NextResponse.json(
      {
        ok: false,
        reason: 'analysis_failed',
        detail: e instanceof Error ? e.message : String(e),
      },
      { status: 502, headers: cors },
    );
  }

  if (result.inappropriate) {
    return NextResponse.json(
      {
        ok: false,
        reason: 'inappropriate',
        detail: result.inappropriate_reason,
        confidence: result.confidence,
      },
      { headers: cors },
    );
  }

  if (!result.is_room) {
    return NextResponse.json(
      {
        ok: false,
        reason: 'not_a_room',
        confidence: result.confidence,
      },
      { headers: cors },
    );
  }

  return NextResponse.json({ ok: true, confidence: result.confidence }, { headers: cors });
}
