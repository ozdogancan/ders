import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const maxDuration = 30;

const MOONDREAM_API_KEY = process.env.MOONDREAM_API_KEY || '';
const MOONDREAM_BASE = 'https://api.moondream.ai/v1';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

// Moondream API helper
async function moondreamQuery(
  imageDataUrl: string,
  question: string
): Promise<string> {
  const res = await fetch(`${MOONDREAM_BASE}/query`, {
    method: 'POST',
    headers: {
      'X-Moondream-Auth': `Key ${MOONDREAM_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      image_url: imageDataUrl,
      question,
      stream: false,
    }),
  });
  if (!res.ok) throw new Error(`Moondream query failed: ${res.status}`);
  const data = await res.json();
  return data.answer || '';
}

async function moondreamCaption(imageDataUrl: string): Promise<string> {
  const res = await fetch(`${MOONDREAM_BASE}/caption`, {
    method: 'POST',
    headers: {
      'X-Moondream-Auth': `Key ${MOONDREAM_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      image_url: imageDataUrl,
      length: 'long',
      stream: false,
    }),
  });
  if (!res.ok) throw new Error(`Moondream caption failed: ${res.status}`);
  const data = await res.json();
  return data.caption || '';
}

interface DetectedObject {
  label: string;
  x_min: number;
  y_min: number;
  x_max: number;
  y_max: number;
}

async function moondreamDetect(
  imageDataUrl: string,
  object: string
): Promise<DetectedObject[]> {
  const res = await fetch(`${MOONDREAM_BASE}/detect`, {
    method: 'POST',
    headers: {
      'X-Moondream-Auth': `Key ${MOONDREAM_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      image_url: imageDataUrl,
      object,
    }),
  });
  if (!res.ok) return [];
  const data = await res.json();
  return (data.objects || []).map((o: Record<string, number>) => ({
    label: object,
    ...o,
  }));
}

/**
 * POST /api/analyze-room
 *
 * Moondream vision AI ile oda fotoğrafı analizi.
 * Oda tipi, stil, renkler, mobilyalar ve genel açıklama döndürür.
 *
 * Body: {
 *   image: string  // base64 encoded image (without data URL prefix, or with)
 * }
 *
 * Response: {
 *   caption: string,
 *   room_type: string,
 *   style: string,
 *   colors: string,
 *   furniture: DetectedObject[],
 *   mood: string,
 * }
 */
export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);

  if (!isOriginAllowed(req)) {
    return NextResponse.json(
      { error: 'Forbidden' },
      { status: 403, headers }
    );
  }

  if (isBodyTooLarge(req, 15)) {
    return NextResponse.json(
      { error: 'Payload too large' },
      { status: 413, headers }
    );
  }

  // Photo analysis is heavy — tight rate limit
  if (!checkRateLimit(req, 'analyze-room', 10)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers }
    );
  }

  if (!MOONDREAM_API_KEY) {
    return NextResponse.json(
      { error: 'Moondream API key not configured' },
      { status: 500, headers }
    );
  }

  try {
    const body = await req.json();
    let { image } = body as { image?: string };

    if (!image) {
      return NextResponse.json(
        { error: 'image field required (base64)' },
        { status: 400, headers }
      );
    }

    // Ensure data URL format
    if (!image.startsWith('data:')) {
      image = `data:image/jpeg;base64,${image}`;
    }

    // Run queries in parallel for speed
    const [caption, roomType, style, colors, mood, furniture] =
      await Promise.all([
        moondreamCaption(image),
        moondreamQuery(
          image,
          'What type of room is this? Answer with just the room type: living room, bedroom, kitchen, bathroom, hallway, office, or other.'
        ),
        moondreamQuery(
          image,
          'What interior design style is this room? Answer concisely: modern, minimalist, scandinavian, industrial, bohemian, classic, luxury, japandi, rustic, or eclectic.'
        ),
        moondreamQuery(
          image,
          'What are the dominant colors in this room? List 3-5 colors with their approximate hex codes, format: color_name (#hex)'
        ),
        moondreamQuery(
          image,
          'Describe the mood and atmosphere of this room in one sentence.'
        ),
        // Detect common furniture
        Promise.all([
          moondreamDetect(image, 'sofa'),
          moondreamDetect(image, 'chair'),
          moondreamDetect(image, 'table'),
          moondreamDetect(image, 'bed'),
          moondreamDetect(image, 'lamp'),
          moondreamDetect(image, 'cabinet'),
        ]).then((results) => results.flat()),
      ]);

    return NextResponse.json(
      {
        caption,
        room_type: roomType.trim(),
        style: style.trim(),
        colors: colors.trim(),
        mood: mood.trim(),
        furniture,
      },
      { headers }
    );
  } catch (error) {
    console.error('Moondream analyze-room error:', error);
    return NextResponse.json(
      {
        error: 'Room analysis failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500, headers }
    );
  }
}
