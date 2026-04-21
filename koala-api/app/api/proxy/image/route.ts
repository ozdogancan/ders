import { NextRequest, NextResponse } from 'next/server';

export const maxDuration = 15;

/**
 * Image proxy for Flutter web CORS issues.
 * SerpAPI thumbnails come from encrypted-tbn0.gstatic.com which blocks
 * cross-origin requests from Flutter web's CanvasKit renderer.
 *
 * GET /api/proxy/image?url=https://encrypted-tbn0.gstatic.com/...
 */
export async function GET(req: NextRequest) {
  const url = req.nextUrl.searchParams.get('url');

  if (!url) {
    return NextResponse.json({ error: 'url parameter required' }, { status: 400 });
  }

  // Only allow image domains we trust
  const allowed = [
    'encrypted-tbn0.gstatic.com',
    'encrypted-tbn1.gstatic.com',
    'encrypted-tbn2.gstatic.com',
    'encrypted-tbn3.gstatic.com',
    'lh3.googleusercontent.com',
    'shopping-phinf.google.com',
  ];

  try {
    const parsed = new URL(url);
    if (!allowed.some((d) => parsed.hostname === d)) {
      return NextResponse.json({ error: 'Domain not allowed' }, { status: 403 });
    }

    const res = await fetch(url, {
      signal: AbortSignal.timeout(8000),
      headers: { 'User-Agent': 'KoalaBot/1.0' },
    });

    if (!res.ok) {
      return new NextResponse(null, { status: res.status });
    }

    const contentType = res.headers.get('content-type') || 'image/jpeg';
    const buffer = await res.arrayBuffer();

    return new NextResponse(buffer, {
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'public, max-age=86400, s-maxage=86400',
        'Access-Control-Allow-Origin': '*',
      },
    });
  } catch {
    return new NextResponse(null, { status: 502 });
  }
}
