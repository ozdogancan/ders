// POST /api/admin/grant-pro — manually grant Pro to a user.
//
// Auth: `Authorization: Bearer <ADMIN_TOKEN>` (shared secret env var).
//
// curl example:
//   curl -X POST https://koala-api-olive.vercel.app/api/admin/grant-pro \
//     -H "Authorization: Bearer $ADMIN_TOKEN" \
//     -H "Content-Type: application/json" \
//     -d '{"userId": "FIREBASE_UID", "durationDays": 30, "plan": "monthly"}'
//
// Body: { userId, durationDays?, plan? }
//   durationDays default 30, plan default 'monthly'.
// Response: { ok: true, proUntil: ISO } | { error }

import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, isOriginAllowed } from '@/lib/security';
import { grantPro, type Plan } from '@/lib/billing';

export const runtime = 'nodejs';
export const maxDuration = 30;

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin, 'POST, OPTIONS');

  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }

  const adminToken = process.env.ADMIN_TOKEN;
  if (!adminToken) {
    return NextResponse.json(
      { error: 'admin_token_not_configured' },
      { status: 500, headers },
    );
  }
  const authHeader = req.headers.get('authorization') ?? '';
  if (authHeader !== `Bearer ${adminToken}`) {
    return NextResponse.json(
      { error: 'unauthorized' },
      { status: 401, headers },
    );
  }

  let body: {
    userId?: string;
    durationDays?: number;
    plan?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers });
  }

  const userId = (body.userId ?? '').trim();
  if (!userId) {
    return NextResponse.json(
      { error: 'userId required' },
      { status: 400, headers },
    );
  }
  const durationDays = Number.isFinite(body.durationDays)
    ? Math.max(1, Math.min(3650, Math.floor(body.durationDays as number)))
    : 30;
  const plan: Plan =
    body.plan === 'weekly' || body.plan === 'yearly' || body.plan === 'monthly'
      ? body.plan
      : 'monthly';

  const expiryMs = Date.now() + durationDays * 86400_000;
  try {
    await grantPro({
      userId,
      productId: `manual_grant_${plan}`,
      expiryMs,
      platform: 'android',
      plan,
      eventType: 'purchase',
      raw: { source: 'admin_grant', durationDays },
    });
    return NextResponse.json(
      { ok: true, proUntil: new Date(expiryMs).toISOString(), plan, durationDays },
      { headers },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[admin/grant-pro] error', msg);
    return NextResponse.json(
      { error: 'grant_failed', detail: msg },
      { status: 500, headers },
    );
  }
}
