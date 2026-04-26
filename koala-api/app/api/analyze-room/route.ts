import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 30;

/**
 * POST /api/analyze-room
 *
 * Single-call room analyzer. One Gemini Vision pass returns:
 *  - is_room (boolean) — gate
 *  - room_type / style / colors / mood / caption — restyle inputs
 *  - quality_score + issues[] — soft band UI hint (RESERVED, not used to block)
 *  - style_tags / materials / dominant_colors / room_type_guess / confidence
 *    — new contract for swipe-deck + restyle prompt enrichment
 *
 * Design notes:
 *  - **No CLIP gate**. CLIP zero-shot on labels false-rejected real living
 *    rooms; cost (one extra image embed + 6 text embeds) for negative
 *    return. Gemini's own room_type_guess is the gate.
 *  - **Quality is conservative**. We default `quality_score=0.85` and only
 *    set `issues` when Gemini explicitly flags severe problems. We do NOT
 *    trigger the hint sheet for normal photos.
 *  - **Backwards compatible**. Returns BOTH the legacy shape (is_room,
 *    quality_score, issues, room_type, style, colors, caption, mood) AND
 *    the new shape (valid, style:{...}, gate). Flutter `analyze()` and
 *    `analyzeRoom()` both work without re-deploying clients.
 */

const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

// ─── Gemini structured-output schema ──────────────────────────────────
const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    is_room: {
      type: 'boolean',
      description:
        'true if the photo shows the interior of an indoor room (living room, bedroom, kitchen, bath, hall, office, dining, kids). false ONLY for selfies, outdoor scenes, food close-ups, screenshots, or random object close-ups.',
    },
    room_type: {
      type: 'string',
      description:
        'living_room | bedroom | kitchen | bathroom | dining_room | office | kids_room | hall | other',
    },
    style: {
      type: 'string',
      description: "single Turkish word: 'minimalist', 'bohem', 'modern', 'klasik', 'iskandinav', 'rustik', etc.",
    },
    style_tags: {
      type: 'array',
      items: { type: 'string' },
      description: 'up to 3 short Turkish style descriptors',
    },
    mood: {
      type: 'string',
      description: 'single Turkish word: dingin | sıcak | enerjik | samimi | lüks | modern',
    },
    materials: {
      type: 'array',
      items: { type: 'string' },
      description: 'up to 3 dominant Turkish material names: ahşap, kadife, pirinç, mermer',
    },
    colors: {
      type: 'string',
      description:
        "comma-separated 'name (#HEX)' pairs, English names, 3-5 colors. Example: 'cream (#F5F1EA), oak (#C4A27B), sage (#A3B18A)'",
    },
    dominant_colors: {
      type: 'array',
      items: { type: 'string' },
      description: '3-5 hex strings like #D4C4B0',
    },
    caption: {
      type: 'string',
      description: 'short Turkish scene description, one sentence',
    },
    room_type_guess: {
      type: 'string',
      description: 'Turkish label: Salon | Yatak Odası | Mutfak | Banyo | Yemek Odası | Çalışma | Çocuk Odası | Hol',
    },
    confidence: {
      type: 'number',
      description: '0.0-1.0 — overall confidence in this analysis',
    },
    severe_issue: {
      type: 'string',
      description:
        "ONE of: 'none' | 'too_dark' | 'blurry' | 'low_resolution'. Use 'none' unless the image is genuinely unusable for design analysis. Do NOT flag a normally-lit room as too_dark. Do NOT flag a slightly cluttered room. We are very conservative here.",
    },
  },
  required: [
    'is_room',
    'room_type',
    'style',
    'mood',
    'colors',
    'caption',
    'style_tags',
    'dominant_colors',
    'materials',
    'room_type_guess',
    'confidence',
    'severe_issue',
  ],
};

const PROMPT = `Bu görseli analiz et. JSON şemasına göre dön.

KURALLAR:
- is_room: SADECE selfie, dış mekan, yiyecek close-up, ekran görüntüsü veya rastgele nesne close-up'larında false. Tipik bir oda fotoğrafı (salon, yatak, mutfak, banyo, hol, ofis, yemek, çocuk odası, koridor, balkon iç görünümü) → true.
- severe_issue: ÇOK MUHAFAZAKAR ol. Normal aydınlatılmış bir oda 'none' olmalı. Sadece şunlarda flag:
  • too_dark: Gerçekten siyah/zorlukla seçilen → too_dark
  • blurry: Hareket bulanıklığı görünür → blurry
  • low_resolution: Pikselleşmiş veya çok küçük → low_resolution
  Sadece bir köşesi görünüyor, eşyalar çok = HALA 'none'. Birkaç insan kadrajda = HALA 'none'.
- style: Türkçe tek kelime. Stilden emin değilsen 'modern' yaz.
- colors: 3-5 ana renk, İngilizce isim + #HEX hex format.
- confidence: Kendi analizine 0.0-1.0 güven puanı.
- room_type: snake_case (living_room, bedroom, kitchen vs.).

Sadece JSON dön, başka metin yok.`;

interface RawAnalysis {
  is_room: boolean;
  room_type: string;
  style: string;
  style_tags: string[];
  mood: string;
  materials: string[];
  colors: string;
  dominant_colors: string[];
  caption: string;
  room_type_guess: string;
  confidence: number;
  severe_issue: string;
}

function asStringArr(v: unknown, max: number): string[] {
  return Array.isArray(v)
    ? (v as unknown[])
        .map((x) => String(x).trim())
        .filter((x) => x.length > 0)
        .slice(0, max)
    : [];
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

async function callGemini(image: string, apiKey: string): Promise<RawAnalysis> {
  const imagePart = buildImagePart(image);
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: PROMPT }, imagePart] }],
      generationConfig: {
        temperature: 0.2,
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

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`gemini: non-JSON response: ${text.slice(0, 200)}`);
  }
  const p = parsed as Record<string, unknown>;

  const conf = Number(p.confidence);
  return {
    is_room: p.is_room === true,
    room_type: String(p.room_type ?? '').trim(),
    style: String(p.style ?? '').trim(),
    style_tags: asStringArr(p.style_tags, 3),
    mood: String(p.mood ?? '').trim(),
    materials: asStringArr(p.materials, 3),
    colors: String(p.colors ?? '').trim(),
    dominant_colors: asStringArr(p.dominant_colors, 5),
    caption: String(p.caption ?? '').trim(),
    room_type_guess: String(p.room_type_guess ?? '').trim(),
    confidence: Number.isFinite(conf) ? Math.max(0, Math.min(1, conf)) : 0.7,
    severe_issue: String(p.severe_issue ?? 'none').trim().toLowerCase(),
  };
}

// ─── Handlers ─────────────────────────────────────────────────────────
export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));
  const t0 = Date.now();

  let body: { image?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers: cors });
  }

  const image = body.image?.trim();
  if (!image) {
    return NextResponse.json({ error: 'missing_image' }, { status: 400, headers: cors });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: 'gemini_key_missing' },
      { status: 500, headers: cors },
    );
  }

  let raw: RawAnalysis;
  try {
    raw = await callGemini(image, apiKey);
  } catch (e) {
    return NextResponse.json(
      {
        error: 'analysis_failed',
        detail: e instanceof Error ? e.message : String(e),
      },
      { status: 502, headers: cors },
    );
  }

  // ─── Quality band — VERY conservative ───────────────────────────────
  // Default 0.85 (good band). Only drop on actual severe_issue from Gemini.
  // We deliberately do NOT include "partial_view" / "cluttered_with_people"
  // — those false-fired on perfectly fine photos.
  const issues: string[] = [];
  let qualityScore = 0.85;
  if (raw.severe_issue && raw.severe_issue !== 'none') {
    issues.push(raw.severe_issue);
    qualityScore = 0.5;
  }

  // ─── Build response: legacy shape + new shape in one payload ────────
  const valid = raw.is_room;

  const payload: Record<string, unknown> = {
    // Legacy contract (Flutter `analyze()`)
    is_room: raw.is_room,
    room_type: raw.room_type,
    style: raw.style,
    colors: raw.colors,
    caption: raw.caption,
    mood: raw.mood,
    quality_score: qualityScore,
    issues,

    // New contract (Flutter `analyzeRoom()`)
    valid,
    gate: {
      top_label: raw.is_room ? 'interior of a room' : 'not_a_room',
      top_score: raw.confidence,
    },
    latency_ms: Date.now() - t0,
  };

  if (valid) {
    payload.style = raw.style; // overwrite to be safe
    payload.style_obj = {
      style_tags: raw.style_tags,
      mood: raw.mood,
      materials: raw.materials,
      dominant_colors: raw.dominant_colors,
      room_type_guess: raw.room_type_guess,
      confidence: raw.confidence,
    };
    // Flutter `analyzeRoom()` reads `j['style']` as a Map — but legacy
    // `analyze()` reads `j['style']` as a string. Conflict resolution:
    // expose the map under `style_hints`, leave `style` as the legacy
    // string, and adapt the client to prefer `style_hints` if present.
    payload.style_hints = payload.style_obj;
    delete payload.style_obj;
  } else {
    payload.reason = 'not_a_room';
    payload.confidence = raw.confidence;
  }

  return NextResponse.json(payload, { headers: cors });
}
