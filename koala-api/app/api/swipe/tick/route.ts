import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed } from '@/lib/security';
import { verifyAuthHeader } from '@/lib/auth-verify';
import { checkAndIncrementQuota } from '@/lib/quota';

export const runtime = 'nodejs';
export const maxDuration = 10;

/**
 * POST /api/swipe/tick
 *
 * Per-swipe quota tick. Client calls this on every swipe commit (one card =
 * one tick). Daily limit 10 on free tier; Pro bypasses.
 *
 * Why a separate endpoint instead of gating /api/swipe-deck?
 *   swipe-deck returns a BATCH of up to 24 cards per call. Charging 1 quota
 *   per fetch would let a free user swipe 24 cards/day instead of 10, or
 *   conversely block them after 10 fetches (=240 cards). Per-swipe ticks
 *   keep the client-promised "10/day" honest.
 *
 * Legacy clients (no Authorization header) are not gated — same dual-mode
 * pattern as /api/chat.
 */
export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers: cors });
  }
  if (!checkRateLimit(req, 'swipe-tick', 120)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers: cors },
    );
  }

  try {
    const auth = await verifyAuthHeader(req);
    const headerUid = req.headers.get('x-user-id');
    const userId = auth.uid ?? headerUid;
    if (!userId || auth.legacy) {
      // Legacy / unauthenticated clients pass through (cannot enforce).
      return NextResponse.json({ ok: true, legacy: true }, { headers: cors });
    }
    const q = await checkAndIncrementQuota({ userId, feature: 'swipe' });
    if (!q.allowed) {
      return NextResponse.json(
        {
          error: 'quota_exceeded',
          feature: 'swipe',
          code: 'SWIPE_QUOTA',
          used: q.used,
          limit: q.limit,
        },
        { status: 402, headers: cors },
      );
    }
    return NextResponse.json(
      { ok: true, used: q.used, limit: q.limit, isPro: q.isPro },
      { headers: cors },
    );
  } catch (e) {
    console.warn('[swipe/tick] error', e);
    // Fail-open: never block swipe UX on a quota bug.
    return NextResponse.json({ ok: true, soft_error: true }, { headers: cors });
  }
}
