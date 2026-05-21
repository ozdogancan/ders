import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import { getProStatus } from '@/lib/billing';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'GET, OPTIONS'),
  });
}

/**
 * GET /api/billing/status
 * Auth: Bearer firebase-id-token, or X-User-Id header (legacy).
 * Returns: { isPro, proUntil, plan, platform, gracePeriod, cancelledAt }
 */
export async function GET(req: NextRequest) {
  const headers = {
    ...corsHeaders(req.headers.get('origin'), 'GET, OPTIONS'),
    'Cache-Control': 'private, no-cache',
  };

  const authResult = await verifyAuthHeader(req);
  const xUserId = req.headers.get('x-user-id');
  logAuthOutcome('billing/status', authResult, { userId: xUserId });

  if (!authResult.ok) {
    return NextResponse.json({ error: 'unauthorized', reason: authResult.reason }, { status: 401, headers });
  }
  const userId = authResult.uid ?? xUserId ?? null;
  if (!userId) {
    return NextResponse.json(
      { isPro: false, proUntil: null, plan: null, platform: null, gracePeriod: false, cancelledAt: null },
      { headers },
    );
  }

  const status = await getProStatus(userId);
  return NextResponse.json(status, { headers });
}
