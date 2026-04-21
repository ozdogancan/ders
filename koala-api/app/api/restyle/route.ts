import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const maxDuration = 60;

const REPLICATE_API_KEY = process.env.REPLICATE_API_KEY || '';
const REPLICATE_BASE = 'https://api.replicate.com/v1';
// RoomGPT'nin kullandığı ControlNet-Hough MLSD modeli. Mimari çizgileri
// koruyup sadece yüzeyleri yeniden render eder.
const MODEL_VERSION = '854e8727697a057c525cdb45ab037f64ecca770a1769cc52287c2e56472a247b';

function buildPrompt(room: string, theme: string): string {
  return `a ${theme} ${room}, professional interior photography, 8k, sharp, detailed, natural light`;
}

function buildNegativePrompt(): string {
  return 'lowres, blurry, low quality, deformed, text, watermark, people, person';
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

/**
 * POST /api/restyle
 *
 * Replicate ControlNet-Hough üzerinden mekan restyle.
 * Key sunucuda tutulur; Flutter bu endpoint'e base64 resim gönderir.
 *
 * Body: { image: string (data URL ya da base64), room: string, theme: string }
 * Response: { output: string (URL) } veya { error, detail }
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

  if (!checkRateLimit(req, 'restyle', 10)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers }
    );
  }

  if (!REPLICATE_API_KEY) {
    return NextResponse.json(
      { error: 'Replicate API key not configured' },
      { status: 500, headers }
    );
  }

  let body: { image?: string; room?: string; theme?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  let { image } = body;
  const { room, theme } = body;

  if (!image || !room || !theme) {
    return NextResponse.json(
      { error: 'image, room, theme required' },
      { status: 400, headers }
    );
  }

  if (!image.startsWith('data:')) {
    image = `data:image/jpeg;base64,${image}`;
  }

  try {
    // 1) Prediction oluştur
    const createRes = await fetch(`${REPLICATE_BASE}/predictions`, {
      method: 'POST',
      headers: {
        Authorization: `Token ${REPLICATE_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        version: MODEL_VERSION,
        input: {
          image,
          prompt: buildPrompt(room, theme),
          a_prompt: 'best quality, extremely detailed, photo from Pinterest, interior, cinematic photo, ultra-detailed, ultra-realistic, award-winning',
          n_prompt: buildNegativePrompt(),
          num_samples: '1',
          image_resolution: '512',
          detect_resolution: 512,
          ddim_steps: 20,
          scale: 9,
          seed: Math.floor(Math.random() * 1_000_000),
          eta: 0,
          value_threshold: 0.1,
          distance_threshold: 0.1,
        },
      }),
    });

    if (!createRes.ok) {
      const text = await createRes.text();
      return NextResponse.json(
        { error: 'Replicate create failed', detail: text },
        { status: 502, headers }
      );
    }

    const created = await createRes.json();
    const pollUrl: string | undefined = created?.urls?.get;
    if (!pollUrl) {
      return NextResponse.json(
        { error: 'Replicate response malformed' },
        { status: 502, headers }
      );
    }

    // 2) 50 saniye bütçe ile 1.5s aralıklarla yokla
    const deadline = Date.now() + 50_000;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 1500));
      const pollRes = await fetch(pollUrl, {
        headers: { Authorization: `Token ${REPLICATE_API_KEY}` },
      });
      if (!pollRes.ok) continue;
      const poll = await pollRes.json();
      const status = poll?.status;
      if (status === 'succeeded') {
        const output = Array.isArray(poll.output) ? poll.output[1] ?? poll.output[0] : poll.output;
        return NextResponse.json({ output }, { headers });
      }
      if (status === 'failed' || status === 'canceled') {
        return NextResponse.json(
          { error: 'Replicate prediction failed', detail: poll?.error || status },
          { status: 502, headers }
        );
      }
    }

    return NextResponse.json(
      { error: 'Replicate prediction timed out' },
      { status: 504, headers }
    );
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Restyle failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500, headers }
    );
  }
}
