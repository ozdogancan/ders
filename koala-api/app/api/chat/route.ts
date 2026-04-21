import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const maxDuration = 300;

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
// gemini-2.5-flash-lite: stabil, hızlı (~3s), ucuz, image+tools sorunsuz
const GEMINI_MODEL = 'gemini-2.5-flash-lite';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

/**
 * POST /api/chat
 * Proxies requests to Gemini API, keeping the API key server-side.
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

  if (isBodyTooLarge(req, 10)) {
    return NextResponse.json(
      { error: 'Payload too large' },
      { status: 413, headers }
    );
  }

  if (!checkRateLimit(req, 'chat', 30)) {
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
    const { contents, tools, generationConfig, stream, system_instruction, tool_config } = body;

    if (!contents || !Array.isArray(contents)) {
      return NextResponse.json(
        { error: 'Invalid request: contents array required' },
        { status: 400, headers }
      );
    }

    const action = stream ? 'streamGenerateContent' : 'generateContent';
    const streamSuffix = stream ? '&alt=sse' : '';
    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(GEMINI_MODEL)}:${action}?key=${GEMINI_API_KEY}${streamSuffix}`;

    const payload: Record<string, unknown> = { contents };
    if (tools) payload.tools = tools;
    if (system_instruction) payload.system_instruction = system_instruction;
    if (tool_config) payload.tool_config = tool_config;

    // generationConfig — flash-lite'da thinking yok
    const safeConfig = { ...(generationConfig || {}), temperature: 0.7 };
    delete safeConfig.responseMimeType;
    delete safeConfig.thinkingConfig;
    payload.generationConfig = safeConfig;

    const payloadJson = JSON.stringify(payload);
    const payloadSizeMB = (payloadJson.length / (1024 * 1024)).toFixed(2);
    console.log(`Chat proxy: model=${GEMINI_MODEL}, action=${action}, payload=${payloadSizeMB}MB`);

    // Tek retry — lite zaten stabil, uzun retry gereksiz
    let geminiResponse: Response | null = null;
    for (let attempt = 1; attempt <= 2; attempt++) {
      geminiResponse = await fetch(geminiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: payloadJson,
      });
      if (geminiResponse.status < 500 && geminiResponse.status !== 429) break;
      console.warn(`Chat proxy: attempt ${attempt} → ${geminiResponse.status}`);
      if (attempt < 2) await new Promise(r => setTimeout(r, 1500));
    }

    if (!geminiResponse) {
      return NextResponse.json({ error: 'AI service unavailable' }, { status: 503, headers });
    }

    if (stream && geminiResponse.body) {
      const responseHeaders = new Headers(headers);
      responseHeaders.set('Content-Type', 'text/event-stream');
      responseHeaders.set('Cache-Control', 'no-cache');
      responseHeaders.set('Connection', 'keep-alive');

      return new Response(geminiResponse.body, {
        status: geminiResponse.status,
        headers: responseHeaders,
      });
    }

    const data = await geminiResponse.json();

    if (geminiResponse.status >= 300) {
      console.error('Gemini API error:', geminiResponse.status, JSON.stringify(data).slice(0, 500));
      return NextResponse.json(
        { error: 'AI service error', status: geminiResponse.status },
        { status: geminiResponse.status, headers }
      );
    }

    return NextResponse.json(data, { headers });
  } catch (error) {
    console.error('Chat proxy error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500, headers }
    );
  }
}
