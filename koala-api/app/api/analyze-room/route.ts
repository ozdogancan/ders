import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const maxDuration = 30;

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.0-flash-exp';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

interface AnalyzeResult {
  caption: string;
  room_type: string;
  style: string;
  colors: string;
  mood: string;
  furniture: { label: string }[];
  is_room: boolean;
}

function extractJSON(text: string): Record<string, unknown> | null {
  // Gemini sometimes wraps JSON in ```json ... ```
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const raw = fenced ? fenced[1] : text;
  try {
    return JSON.parse(raw.trim());
  } catch {
    // Last resort: find first { ... }
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try {
      return JSON.parse(m[0]);
    } catch {
      return null;
    }
  }
}

/**
 * POST /api/analyze-room
 *
 * Gemini Vision ile oda fotoğrafı analizi.
 * Body: { image: string (base64 ya da data URL) }
 * Response: { caption, room_type, style, colors, mood, furniture[], is_room }
 */
export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }
  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413, headers });
  }
  if (!checkRateLimit(req, 'analyze-room', 10)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers }
    );
  }
  if (!GEMINI_API_KEY) {
    return NextResponse.json(
      { error: 'Gemini API key not configured' },
      { status: 500, headers }
    );
  }

  let body: { image?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  let { image } = body;
  if (!image) {
    return NextResponse.json(
      { error: 'image field required (base64)' },
      { status: 400, headers }
    );
  }

  // Normalize: strip data URL prefix for Gemini inlineData
  let mimeType = 'image/jpeg';
  if (image.startsWith('data:')) {
    const match = image.match(/^data:([^;]+);base64,(.*)$/);
    if (match) {
      mimeType = match[1];
      image = match[2];
    }
  }

  const prompt = `Analiz et ve SADECE aşağıdaki JSON formatında cevap ver. Türkçe.

{
  "is_room": boolean,
  "caption": "tek cümle açıklama",
  "room_type": "living room|bedroom|kitchen|bathroom|dining room|office|hallway|other",
  "style": "modern|minimalist|scandinavian|industrial|bohemian|classic|luxury|japandi|rustic|vintage|eclectic",
  "colors": "3-5 hakim renk, format: 'renk_adı (#hexcode), renk_adı (#hexcode)'",
  "mood": "atmosfer açıklaması tek cümle",
  "furniture": ["mobilya_adı", "mobilya_adı"]
}

Kurallar:
- "is_room" false olur eğer fotoğraf bir iç mekan DEĞİLSE (selfie, insan, dış mekan, hayvan, yemek, belge vb.).
- "is_room" true olursa diğer tüm alanlar doldurulur.
- is_room false ise caption kullanıcıya nazikçe ne gördüğünü söylesin ("Bu bir selfie gibi görünüyor").
- Renk hex'leri gerçekten fotoğraftaki renklerden alınmalı, uydurma yok.
- Sadece JSON döndür, başka metin yok, markdown yok.`;

  try {
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
    const geminiRes = await fetch(apiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              { inlineData: { mimeType, data: image } },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.2,
          responseMimeType: 'application/json',
        },
      }),
    });

    if (!geminiRes.ok) {
      const txt = await geminiRes.text();
      return NextResponse.json(
        { error: 'Gemini analysis failed', detail: `${geminiRes.status}: ${txt.slice(0, 300)}` },
        { status: 502, headers }
      );
    }

    const data = await geminiRes.json();
    const text: string =
      data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    const parsed = extractJSON(text);
    if (!parsed) {
      return NextResponse.json(
        { error: 'Gemini returned invalid JSON', detail: text.slice(0, 300) },
        { status: 502, headers }
      );
    }

    const result: AnalyzeResult = {
      is_room: Boolean(parsed.is_room),
      caption: String(parsed.caption ?? '').trim(),
      room_type: String(parsed.room_type ?? 'other').trim(),
      style: String(parsed.style ?? '').trim(),
      colors: String(parsed.colors ?? '').trim(),
      mood: String(parsed.mood ?? '').trim(),
      furniture: Array.isArray(parsed.furniture)
        ? (parsed.furniture as unknown[]).map((x) => ({ label: String(x) }))
        : [],
    };

    return NextResponse.json(result, { headers });
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Room analysis failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500, headers }
    );
  }
}
