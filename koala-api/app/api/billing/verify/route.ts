import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import { getSubscriptionPurchase, planFromProductId } from '@/lib/google-play';
import { grantPro, markTrialUsed } from '@/lib/billing';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

/**
 * POST /api/billing/verify
 * Body: { platform, productId, purchaseToken, firebaseIdToken?, userId? }
 *
 * Verifies an Android Play Billing purchase against the Play Developer API,
 * then grants Pro on success. Returns the new ProStatus.
 *
 * Auth: Bearer firebase-id-token (preferred). Legacy mode falls back to
 * userId in body — same dual-mode pattern other endpoints use.
 */
export async function POST(req: NextRequest) {
  const headers = corsHeaders(req.headers.get('origin'), 'POST, OPTIONS');

  let body: {
    platform?: string;
    productId?: string;
    purchaseToken?: string;
    userId?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400, headers });
  }

  const { platform, productId, purchaseToken, userId: bodyUserId } = body;

  if (!platform || !productId || !purchaseToken) {
    return NextResponse.json(
      { error: 'missing_fields', need: ['platform', 'productId', 'purchaseToken'] },
      { status: 400, headers },
    );
  }

  if (platform !== 'android') {
    return NextResponse.json(
      { error: 'platform_not_supported_v1', platform },
      { status: 400, headers },
    );
  }

  // Auth — dual-mode: Authorization header OR userId in body.
  const authResult = await verifyAuthHeader(req);
  logAuthOutcome('billing/verify', authResult, { userId: bodyUserId ?? null });
  if (!authResult.ok) {
    return NextResponse.json({ error: 'unauthorized', reason: authResult.reason }, { status: 401, headers });
  }
  const userId = authResult.uid ?? bodyUserId;
  if (!userId) {
    return NextResponse.json({ error: 'missing_user_id' }, { status: 400, headers });
  }

  let plan: 'weekly' | 'monthly' | 'yearly';
  try {
    plan = planFromProductId(productId);
  } catch {
    return NextResponse.json({ error: 'unknown_product', productId }, { status: 400, headers });
  }

  const packageName = process.env.ANDROID_PACKAGE_NAME || 'com.evlumba.koala';

  let purchase;
  try {
    purchase = await getSubscriptionPurchase({ packageName, productId, purchaseToken });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn('[billing/verify] play api error', msg);
    return NextResponse.json({ error: 'play_lookup_failed', detail: msg.slice(0, 200) }, { status: 502, headers });
  }

  const expiryMs = purchase.expiryTimeMillis ? Number(purchase.expiryTimeMillis) : 0;
  if (!expiryMs || expiryMs < Date.now()) {
    return NextResponse.json(
      { error: 'expired_or_invalid', expiryMs },
      { status: 400, headers },
    );
  }

  // paymentState: 0 = pending, 1 = received, 2 = free trial, 3 = pending deferred upgrade.
  // Accept 1 and 2 (trial counts as paid).
  if (purchase.paymentState !== undefined && purchase.paymentState !== 1 && purchase.paymentState !== 2) {
    return NextResponse.json(
      { error: 'payment_pending', paymentState: purchase.paymentState },
      { status: 400, headers },
    );
  }

  await grantPro({
    userId,
    productId,
    expiryMs,
    platform: 'android',
    plan,
    raw: { purchaseToken, ...purchase.raw },
    eventType: 'purchase',
  });

  // Mark trial as used. Play's paymentState === 2 explicitly indicates a free
  // trial period; we also defensively set the flag on any successful verify
  // because once a user has had any paid purchase, we don't want to offer a
  // trial again. Idempotent — safe to call repeatedly. Wrapped so a failure
  // here never blocks the success response to the client.
  try {
    await markTrialUsed(userId);
  } catch (e) {
    console.warn('[billing/verify] markTrialUsed failed', e instanceof Error ? e.message : String(e));
  }

  return NextResponse.json(
    {
      isPro: true,
      proUntil: new Date(expiryMs).toISOString(),
      plan,
      platform: 'android',
    },
    { headers },
  );
}
