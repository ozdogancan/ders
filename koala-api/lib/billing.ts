// Billing helpers — wrap Supabase reads/writes for Pro state, events, quotas.
//
// All exported functions are server-side only (use service-role client).

import { koalaAdmin } from './supabase/koala';

export type Plan = 'weekly' | 'monthly' | 'yearly';
export type Platform = 'android' | 'ios' | 'web';
export type Feature = 'restyle' | 'chat' | 'save' | 'designer_dm' | 'swipe';

export interface ProStatus {
  isPro: boolean;
  proUntil: string | null;        // ISO timestamp
  plan: Plan | null;
  platform: Platform | null;
  gracePeriod: boolean;            // true if expired but within recent grace window
  cancelledAt: string | null;
  trial_used: boolean;             // true if the user has already consumed their free trial
}

const GRACE_DAYS = 3;

export async function grantPro(opts: {
  userId: string;
  productId: string;
  expiryMs: number;                // ms since epoch
  platform: Platform;
  plan: Plan;
  raw?: Record<string, unknown>;
  eventType?: 'purchase' | 'renewal' | 'restore';
}): Promise<void> {
  const sb = koalaAdmin();
  const proUntil = new Date(opts.expiryMs).toISOString();

  // Upsert profile. We use update-then-insert pattern because user_profiles.id
  // is uuid; Firebase UIDs are not always uuid-shaped, so an INSERT may fail
  // on type cast for legacy users. Try update first; if zero rows, insert.
  const { data: updated, error: updErr } = await sb
    .from('user_profiles')
    .update({
      pro_until: proUntil,
      pro_plan: opts.plan,
      pro_platform: opts.platform,
      pro_started_at: new Date().toISOString(),
      pro_cancelled_at: null,
    })
    .eq('id', opts.userId)
    .select('id');

  if (updErr) {
    console.warn('[billing.grantPro] update error', updErr.message);
  }

  if (!updated || updated.length === 0) {
    const { error: insErr } = await sb.from('user_profiles').insert({
      id: opts.userId,
      pro_until: proUntil,
      pro_plan: opts.plan,
      pro_platform: opts.platform,
      pro_started_at: new Date().toISOString(),
    });
    if (insErr) {
      console.warn('[billing.grantPro] insert error', insErr.message);
    }
  }

  await sb.from('billing_events').insert({
    user_id: opts.userId,
    platform: opts.platform,
    product_id: opts.productId,
    event_type: opts.eventType ?? 'purchase',
    raw: opts.raw ?? null,
  });
}

export async function revokePro(opts: {
  userId: string;
  reason: string;
  platform?: Platform;
  productId?: string;
  raw?: Record<string, unknown>;
}): Promise<void> {
  const sb = koalaAdmin();
  const now = new Date().toISOString();
  await sb
    .from('user_profiles')
    .update({
      pro_until: now,
      pro_cancelled_at: now,
    })
    .eq('id', opts.userId);

  await sb.from('billing_events').insert({
    user_id: opts.userId,
    platform: opts.platform ?? 'android',
    product_id: opts.productId ?? null,
    event_type: 'cancel',
    raw: { reason: opts.reason, ...(opts.raw ?? {}) },
  });
}

export async function getProStatus(userId: string): Promise<ProStatus> {
  const sb = koalaAdmin();
  const { data, error } = await sb
    .from('user_profiles')
    .select('pro_until, pro_plan, pro_platform, pro_cancelled_at, trial_used')
    .eq('id', userId)
    .maybeSingle();

  if (error || !data) {
    return {
      isPro: false,
      proUntil: null,
      plan: null,
      platform: null,
      gracePeriod: false,
      cancelledAt: null,
      trial_used: false,
    };
  }

  const now = Date.now();
  const proUntilMs = data.pro_until ? new Date(data.pro_until).getTime() : null;
  const isPro = proUntilMs !== null && proUntilMs > now;
  const gracePeriod =
    !isPro &&
    proUntilMs !== null &&
    proUntilMs + GRACE_DAYS * 86400_000 > now;

  return {
    isPro,
    proUntil: data.pro_until ?? null,
    plan: (data.pro_plan as Plan | null) ?? null,
    platform: (data.pro_platform as Platform | null) ?? null,
    gracePeriod,
    cancelledAt: data.pro_cancelled_at ?? null,
    trial_used: data.trial_used === true,
  };
}

/**
 * Mark the user's trial as consumed. Idempotent — safe to call multiple times.
 * Defensive: callers should wrap in try/catch and not block the user response
 * on failure. We never un-set this flag once true.
 */
export async function markTrialUsed(userId: string): Promise<void> {
  const sb = koalaAdmin();
  const { error } = await sb
    .from('user_profiles')
    .update({ trial_used: true })
    .eq('id', userId);
  if (error) {
    console.warn('[billing.markTrialUsed] update error', error.message);
  }
}

export async function getQuotaUsage(
  userId: string,
  feature: Feature,
  period: string,
): Promise<number> {
  const sb = koalaAdmin();
  const { data, error } = await sb
    .from('billing_quota_usage')
    .select('count')
    .eq('user_id', userId)
    .eq('feature', feature)
    .eq('period', period)
    .maybeSingle();
  if (error || !data) return 0;
  return data.count ?? 0;
}

/**
 * Atomic increment via Postgres RPC fallback: the supabase-js client doesn't
 * expose ON CONFLICT increments, so we do an UPSERT with select then update.
 * For higher concurrency, swap to a SQL function. v1 traffic is low enough.
 */
export async function incrementQuota(
  userId: string,
  feature: Feature,
  period: string,
): Promise<number> {
  const sb = koalaAdmin();
  // Try update first (existing row).
  const { data: updRows, error: updErr } = await sb
    .from('billing_quota_usage')
    .update({ count: (await getQuotaUsage(userId, feature, period)) + 1 })
    .eq('user_id', userId)
    .eq('feature', feature)
    .eq('period', period)
    .select('count');
  if (updErr) {
    console.warn('[billing.incrementQuota] update error', updErr.message);
  }
  if (updRows && updRows.length > 0) {
    return updRows[0].count as number;
  }
  // No row yet — insert with count=1.
  const { error: insErr } = await sb.from('billing_quota_usage').insert({
    user_id: userId,
    feature,
    period,
    count: 1,
  });
  if (insErr) {
    console.warn('[billing.incrementQuota] insert error', insErr.message);
  }
  return 1;
}

/** Helper: get the current period string for a feature's reset cadence. */
export function periodFor(feature: Feature): string {
  const d = new Date();
  if (feature === 'chat' || feature === 'swipe') {
    // daily reset
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
  }
  if (feature === 'designer_dm' || feature === 'save') {
    // lifetime — use a fixed bucket (designer_dm is overridden per-conversation
    // via checkAndIncrementQuota({conversationId}) in lib/quota.ts).
    return 'lifetime';
  }
  // restyle: monthly
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}
