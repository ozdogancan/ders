import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { getSubscriptionPurchase, planFromProductId } from '@/lib/google-play';
import { grantPro, revokePro } from '@/lib/billing';

/**
 * POST /api/billing/play-webhook
 * Receives Google Pub/Sub push notifications for Real-Time Developer
 * Notifications (RTDN) from Play Billing.
 *
 * Pub/Sub envelope:
 *   { message: { data: <base64 JSON>, attributes, messageId, publishTime }, subscription }
 *
 * Decoded `data` (RTDN):
 *   { version, packageName, eventTimeMillis,
 *     subscriptionNotification?: { version, notificationType, purchaseToken, subscriptionId },
 *     oneTimeProductNotification?, voidedPurchaseNotification?, testNotification? }
 *
 * Always returns 200 (even on error) so Pub/Sub doesn't retry-storm. Errors
 * are logged. Pub/Sub JWT auth verification is required in production —
 * configure GOOGLE_PUBSUB_AUDIENCE env to enable strict mode.
 *
 * Owner setup:
 *   1. In Google Cloud Console, create a Pub/Sub topic (e.g. "play-billing").
 *   2. Add a push subscription pointing to:
 *        https://koala-api-olive.vercel.app/api/billing/play-webhook
 *      with "Enable authentication" enabled (audience = the URL above).
 *   3. In Play Console → Monetisation setup → set the topic name.
 */

// Notification types — Play docs:
// 1=RECOVERED, 2=RENEWED, 3=CANCELED, 4=PURCHASED, 5=ON_HOLD, 6=IN_GRACE_PERIOD,
// 7=RESTARTED, 8=PRICE_CHANGE_CONFIRMED, 9=DEFERRED, 10=PAUSED, 11=PAUSE_SCHEDULE_CHANGED,
// 12=REVOKED, 13=EXPIRED, 20=PENDING_PURCHASE_CANCELED
const TYPE_GRANT = new Set([1, 2, 4, 7]); // recover/renew/purchase/restart
const TYPE_REVOKE = new Set([3, 5, 12, 13]); // cancel/on-hold/revoke/expire

interface PubSubEnvelope {
  message?: {
    data?: string;
    attributes?: Record<string, string>;
    messageId?: string;
    publishTime?: string;
  };
  subscription?: string;
}

interface SubscriptionNotification {
  version?: string;
  notificationType?: number;
  purchaseToken?: string;
  subscriptionId?: string;
}

interface RTDN {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: SubscriptionNotification;
  testNotification?: { version?: string };
  oneTimeProductNotification?: Record<string, unknown>;
  voidedPurchaseNotification?: Record<string, unknown>;
}

async function verifyPubSubJwt(req: NextRequest): Promise<boolean> {
  // Soft-mode: if GOOGLE_PUBSUB_AUDIENCE is unset, skip verification (dev/initial setup).
  // In production, MUST be set to the webhook URL so Google signs tokens for it.
  const audience = process.env.GOOGLE_PUBSUB_AUDIENCE;
  if (!audience) {
    console.warn('[play-webhook] GOOGLE_PUBSUB_AUDIENCE not set — skipping JWT verify');
    return true;
  }
  const auth = req.headers.get('authorization');
  if (!auth?.startsWith('Bearer ')) return false;
  const token = auth.slice(7);
  // Verify by calling Google's tokeninfo endpoint (simplest, no extra deps).
  // Production hardening: cache JWKs and verify locally to avoid per-request latency.
  try {
    const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(token)}`);
    if (!res.ok) return false;
    const info = (await res.json()) as { aud?: string; iss?: string; email?: string };
    if (info.aud !== audience) return false;
    if (info.iss !== 'https://accounts.google.com' && info.iss !== 'accounts.google.com') return false;
    return true;
  } catch (e) {
    console.warn('[play-webhook] jwt verify exception', e);
    return false;
  }
}

export async function POST(req: NextRequest) {
  const verified = await verifyPubSubJwt(req);
  if (!verified) {
    console.warn('[play-webhook] Pub/Sub JWT verification failed');
    return NextResponse.json({ ok: false, reason: 'unauthorized' }, { status: 200 });
  }

  let envelope: PubSubEnvelope;
  try {
    envelope = await req.json();
  } catch {
    return NextResponse.json({ ok: false, reason: 'invalid_json' }, { status: 200 });
  }

  const dataB64 = envelope.message?.data;
  if (!dataB64) {
    return NextResponse.json({ ok: true, ignored: 'no_data' });
  }

  let notification: RTDN;
  try {
    notification = JSON.parse(Buffer.from(dataB64, 'base64').toString('utf-8'));
  } catch {
    return NextResponse.json({ ok: false, reason: 'invalid_b64_json' }, { status: 200 });
  }

  // Test notifications: just ack.
  if (notification.testNotification) {
    console.log('[play-webhook] test notification received');
    return NextResponse.json({ ok: true, test: true });
  }

  const sub = notification.subscriptionNotification;
  if (!sub?.purchaseToken || !sub.subscriptionId || sub.notificationType === undefined) {
    // We don't handle one-time / voided in Phase 1 — just ack.
    return NextResponse.json({ ok: true, ignored: 'unsupported_notification' });
  }

  const packageName = notification.packageName || process.env.ANDROID_PACKAGE_NAME || 'com.evlumba.koala';

  // Look up the latest state.
  let purchase;
  try {
    purchase = await getSubscriptionPurchase({
      packageName,
      productId: sub.subscriptionId,
      purchaseToken: sub.purchaseToken,
    });
  } catch (e) {
    console.warn('[play-webhook] play lookup failed', e instanceof Error ? e.message : String(e));
    // Ack anyway so Pub/Sub doesn't retry-storm. We'll catch up via /verify or /restore.
    return NextResponse.json({ ok: true, lookup_failed: true });
  }

  // We need the userId to map to. Play API returns `obfuscatedExternalAccountId`
  // if set at purchase time (recommended). Fallback: scan billing_events by purchaseToken.
  const externalId = (purchase.raw.obfuscatedExternalAccountId ??
    (purchase.raw as Record<string, unknown>).externalAccountId) as string | undefined;

  let userId = externalId;
  if (!userId) {
    const sb = koalaAdmin();
    const { data: prior } = await sb
      .from('billing_events')
      .select('user_id')
      .filter('raw->>purchaseToken', 'eq', sub.purchaseToken)
      .order('received_at', { ascending: false })
      .limit(1);
    userId = prior?.[0]?.user_id as string | undefined;
  }
  if (!userId) {
    console.warn('[play-webhook] cannot resolve userId for token', sub.purchaseToken.slice(0, 12));
    return NextResponse.json({ ok: true, ignored: 'no_user_mapping' });
  }

  let plan: 'weekly' | 'monthly' | 'yearly';
  try {
    plan = planFromProductId(sub.subscriptionId);
  } catch {
    return NextResponse.json({ ok: true, ignored: 'unknown_product' });
  }

  const expiryMs = purchase.expiryTimeMillis ? Number(purchase.expiryTimeMillis) : 0;
  const ntype = sub.notificationType;

  if (TYPE_REVOKE.has(ntype) && (!expiryMs || expiryMs < Date.now())) {
    await revokePro({
      userId,
      reason: `rtdn_type_${ntype}`,
      platform: 'android',
      productId: sub.subscriptionId,
      raw: { notificationType: ntype, ...purchase.raw },
    });
  } else if (TYPE_GRANT.has(ntype) && expiryMs > Date.now()) {
    await grantPro({
      userId,
      productId: sub.subscriptionId,
      expiryMs,
      platform: 'android',
      plan,
      raw: { notificationType: ntype, purchaseToken: sub.purchaseToken, ...purchase.raw },
      eventType: ntype === 4 ? 'purchase' : 'renewal',
    });
  } else {
    // grace period / paused / price-change — log only, no state change
    const sb = koalaAdmin();
    await sb.from('billing_events').insert({
      user_id: userId,
      platform: 'android',
      product_id: sub.subscriptionId,
      event_type: ntype === 6 ? 'grace_start' : 'rtdn_other',
      raw: { notificationType: ntype, ...purchase.raw },
    });
  }

  return NextResponse.json({ ok: true, processed: ntype });
}
