// GET /api/quota/usage
// Returns current free-tier quota usage for the authenticated user.
//
// Auth: `Authorization: Bearer <Firebase ID Token>` + X-User-Id fallback.
// Response: {
//   isPro: boolean,
//   restyle: { used, limit, period },
//   save:    { used, limit, period: 'lifetime' },   // counted via saved_items rows
//   chat:    { used, limit, period }
// }

import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, isOriginAllowed } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import {
  countSavedItems,
  currentPeriod,
  featureLimit,
  getUsage,
  isProUser,
} from '@/lib/quota';

export const runtime = 'nodejs';
export const maxDuration = 15;

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'GET, OPTIONS'),
  });
}

export async function GET(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin, 'GET, OPTIONS');

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }

  const headerUid = req.headers.get('x-user-id');
  const auth = await verifyAuthHeader(req);
  logAuthOutcome('quota/usage', auth, { userId: headerUid });
  if (!auth.ok) {
    return NextResponse.json(
      { error: 'unauthorized', reason: auth.reason },
      { status: 401, headers },
    );
  }
  const userId = auth.uid ?? headerUid;
  if (!userId) {
    return NextResponse.json(
      { error: 'no_user_id' },
      { status: 400, headers },
    );
  }

  try {
    const [pro, restyleUsed, chatUsed, saveCount] = await Promise.all([
      isProUser(userId),
      getUsage(userId, 'restyle'),
      getUsage(userId, 'chat'),
      countSavedItems(userId),
    ]);
    return NextResponse.json(
      {
        isPro: pro,
        restyle: {
          used: restyleUsed,
          limit: featureLimit('restyle'),
          period: currentPeriod('restyle'),
        },
        save: {
          used: saveCount,
          limit: featureLimit('save'),
          period: 'lifetime',
        },
        chat: {
          used: chatUsed,
          limit: featureLimit('chat'),
          period: currentPeriod('chat'),
        },
      },
      { headers },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[quota/usage] error', msg);
    return NextResponse.json(
      { error: 'usage_failed', detail: msg },
      { status: 500, headers },
    );
  }
}
