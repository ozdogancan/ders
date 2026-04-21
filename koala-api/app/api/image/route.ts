import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const maxDuration = 60;

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const IMAGE_MODEL = 'gemini-2.5-flash-preview-image-generation';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

/**
 * POST /api/image
 * Proxies image generation requests to Gemini image model.
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

  // Image generation is expensive — tighter rate limit
  if (!checkRateLimit(req, 'image', 10)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers }
    );
  }

  if (!GEMINI_API_KEY) {
    return NextResponse.json(
      { error: 'Server configuration error' },
      { status: 500, headers }
    );
  }

  try {
    const body = await req.json();
    const { contents, generationConfig } = body;

    if (!contents || !Array.isArray(contents)) {
      return NextResponse.json(
        { error: 'Invalid request: contents array required' },
        { status: 400, headers }
      );
    }

    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${IMAGE_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

    const payload: Record<string, unknown> = { contents };
    if (generationConfig) {
      payload.generationConfig = generationConfig;
    } else {
      payload.generationConfig = { responseModalities: ['TEXT', 'IMAGE'] };
    }

    const geminiResponse = await fetch(geminiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    const data = await geminiResponse.json();

    if (geminiResponse.status >= 300) {
      console.error('Gemini Image API error:', geminiResponse.status, JSON.stringify(data).slice(0, 500));
      return NextResponse.json(
        { error: 'Image generation error', status: geminiResponse.status },
        { status: geminiResponse.status, headers }
      );
    }

    return NextResponse.json(data, { headers });
  } catch (error) {
    console.error('Image proxy error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500, headers }
    );
  }
}
