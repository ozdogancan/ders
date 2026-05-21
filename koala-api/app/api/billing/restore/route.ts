import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import { koalaAdmin } from '@/lib/supabase/koala';
import { grantPro, markTrialUsed } from '@/lib/billing';
import { planFromProductId, getSubscriptionPurchase } from '@/lib/google-play';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin'), 'POST, OPTIONS'),
  });
}

/**
 * POST /api/billing/restore
 * Body: {} (auth via header)
 *
 * Looks up the most recent purchase event for this user, re-validates it
 * against Play, and re-grants Pro if still active. Used after reinstall
 * or sign-in on a new device.
 */
export async function POST(req: NextRequest) {
  const headers = corsHeaders(req.headers.get('origin'), 'POST, OPTIONS');

  const authResult = await verifyAuthHeader(req);
  let bodyUserId: string | undefined;
  try {
    const body = await req.json().catch(() => ({}));
    bodyUserId = body?.userId;
  } catch { /* ignore */ }
  logAuthOutcome('billing/restore', authResult, { userId: bodyUserId ?? null });

  if (!authResult.ok) {
    return NextResponse.json({ error: 'unauthorized', reason: authResult.reason }, { status: 401, headers });
  }
  const userId = authResult.uid ?? bodyUserId;
  if (!userId) {
    return NextResponse.json({ restored: false, reason: 'no_user_id' }, { status: 400, headers });
  }

  const sb = koalaAdmin();
  const { data: events, error } = await sb
    .from('billing_events')
    .select('product_id, raw, platform')
    .eq('user_id', userId)
    .eq('event_type', 'purchase')
    .order('received_at', { ascending: false })
    .limit(1);

  if (error) {
    console.warn('[billing/restore] query error', error.message);
    return NextResponse.json({ restored: false, reason: 'db_error' }, { status: 500, headers });
  }
  if (!events || events.length === 0) {
    return NextResponse.json({ restored: false, reason: 'no_history' }, { headers });
  }

  const event = events[0];
  const productId = event.product_id as string | null;
  const raw = (event.raw ?? {}) as Record<string, unknown>;
  const purchaseToken = raw.purchaseToken as string | undefined;

  if (!productId || !purchaseToken) {
    return NextResponse.json({ restored: false, reason: 'incomplete_event' }, { headers });
  }

  let plan: 'weekly' | 'monthly' | 'yearly';
  try {
    plan = planFromProductId(productId);
  } catch {
    return NextResponse.json({ restored: false, reason: 'unknown_product' }, { headers });
  }

  const packageName = process.env.ANDROID_PACKAGE_NAME || 'com.evlumba.koala';
  let purchase;
  try {
    purchase = await getSubscriptionPurchase({ packageName, productId, purchaseToken });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn('[billing/restore] play lookup failed', msg);
    return NextResponse.json({ restored: false, reason: 'play_lookup_failed' }, { headers });
  }

  const expiryMs = purchase.expiryTimeMillis ? Number(purchase.expiryTimeMillis) : 0;
  if (!expiryMs || expiryMs < Date.now()) {
    return NextResponse.json({ restored: false, reason: 'expired' }, { headers });
  }

  await grantPro({
    userId,
    productId,
    expiryMs,
    platform: 'android',
    plan,
    raw: { purchaseToken, ...purchase.raw },
    eventType: 'restore',
  });

  // If a user is restoring a paying subscription, their trial obviously already
  // happened. Idempotent flag write — never block the success response on it.
  try {
    await markTrialUsed(userId);
  } catch (e) {
    console.warn('[billing/restore] markTrialUsed failed', e instanceof Error ? e.message : String(e));
  }

  return NextResponse.json(
    { restored: true, isPro: true, proUntil: new Date(expiryMs).toISOString(), plan, platform: 'android' },
    { headers },
  );
}
