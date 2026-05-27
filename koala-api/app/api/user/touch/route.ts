// POST /api/user/touch
//
// "I'm here" beacon — called once per app launch after auth resolves. Updates
// koala_user_last_seen.last_seen_at and optionally registers/refreshes the
// FCM push token. Powers the comeback push cron (D1/D7/D14/D30).
//
// Auth: Bearer Firebase ID token (preferred) or X-User-Id legacy header.
// Body (optional): { "fcm_token": "..." }
//
// Always returns 200 with { ok: true } on success — clients should NOT retry
// on failure (best-effort retention signal, not critical-path).

import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import { touchUserLastSeen } from '@/lib/last-seen';

export const runtime = 'nodejs';
export const maxDuration = 10;
export const dynamic = 'force-dynamic';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

export async function POST(req: NextRequest) {
  const headers = {
    ...corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
    'Cache-Control': 'no-store',
  };

  const authResult = await verifyAuthHeader(req);
  const xUserId = req.headers.get('x-user-id');
  logAuthOutcome('user/touch', authResult, { userId: xUserId });

  // Same dual-mode pattern as /api/billing/status: degrade to X-User-Id if
  // token verify fails. Retention tracking must not break on token hiccups.
  if (!authResult.ok && !xUserId) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers },
    );
  }
  const uid = authResult.uid ?? xUserId ?? null;
  if (!uid) {
    return NextResponse.json({ ok: false, reason: 'no-uid' }, { headers });
  }

  // Body parse — completely optional.
  let pushToken: string | null = null;
  try {
    const body = (await req.json()) as { fcm_token?: unknown; device?: { fcm_token?: unknown } } | null;
    const raw =
      (body && typeof body.fcm_token === 'string' && body.fcm_token) ||
      (body && body.device && typeof body.device.fcm_token === 'string' && body.device.fcm_token) ||
      null;
    if (raw && raw.trim().length > 0) pushToken = raw.trim();
  } catch {
    // No body — that's fine.
  }

  await touchUserLastSeen({ uid, pushToken });
  return NextResponse.json({ ok: true }, { headers });
}
