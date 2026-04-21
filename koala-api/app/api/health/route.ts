import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'GET, OPTIONS'),
  });
}

/**
 * GET /api/health
 * Returns service health status. Used by Flutter connectivity check.
 */
export async function GET(req: NextRequest) {
  const headers = corsHeaders(req.headers.get('origin'), 'GET, OPTIONS');

  const geminiOk = !!process.env.GEMINI_API_KEY;
  const supabaseOk = !!process.env.SUPABASE_URL;

  return NextResponse.json({
    status: geminiOk ? 'ok' : 'degraded',
    services: {
      gemini: geminiOk ? 'configured' : 'missing_key',
      supabase: supabaseOk ? 'configured' : 'missing_url',
    },
    timestamp: new Date().toISOString(),
  }, { headers });
}
