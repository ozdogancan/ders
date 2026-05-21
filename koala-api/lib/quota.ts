// Quota helpers — server-side authoritative gate for free-tier features.
//
// Feature limits (free tier):
//   restyle      → 2 / month         (period: YYYY-MM)
//   save         → 3 / lifetime      (period: 'lifetime' — actually counted via
//                                     saved_items row count, NOT incremented here)
//   chat         → 5 / day           (period: YYYY-MM-DD UTC)
//   designer_dm  → 1 / lifetime      (per-designer; deferred to v1.1)
//
// Pro users bypass all limits.

import { koalaAdmin } from './supabase/koala';
import { getProStatus, type Feature } from './billing';

export const FEATURE_LIMITS: Record<Feature, number> = {
  restyle: 2,
  save: 3,
  chat: 3,
  designer_dm: 1,
  swipe: 10,
};

export function featureLimit(feature: Feature): number {
  return FEATURE_LIMITS[feature];
}

export function currentPeriod(feature: Feature): string {
  const d = new Date();
  if (feature === 'chat' || feature === 'swipe') {
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
  }
  if (feature === 'save' || feature === 'designer_dm') {
    return 'lifetime';
  }
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

export async function isProUser(userId: string): Promise<boolean> {
  try {
    const status = await getProStatus(userId);
    return status.isPro;
  } catch (e) {
    console.warn('[quota.isProUser] error', e);
    return false;
  }
}

export interface QuotaResult {
  allowed: boolean;
  isPro: boolean;
  used: number;
  limit: number;
}

/**
 * Check + atomically increment the quota counter for (userId, feature, period).
 * Pro users bypass — returns allowed:true without writes.
 *
 * NOTE: Not strictly atomic — race condition window is tiny (~ms) and free
 * tier traffic is low. Acceptable for v1. Promote to a SQL function if abuse
 * appears.
 */
export async function checkAndIncrementQuota(opts: {
  userId: string;
  feature: Feature;
  /** designer_dm only: per-conversation bucket — overrides period to this id,
   *  limit becomes 1 (one free reply per conversation). */
  conversationId?: string;
}): Promise<QuotaResult> {
  const { userId, feature } = opts;
  const pro = await isProUser(userId);
  if (pro) {
    return { allowed: true, isPro: true, used: 0, limit: -1 };
  }
  // designer_dm + conversationId → per-conversation lifetime gate.
  // Re-uses billing_quota_usage table with period = conversationId; PK is
  // composite (user_id, feature, period) so this slots in without migration.
  const usePerConv = feature === 'designer_dm' && !!opts.conversationId;
  const limit = usePerConv ? 1 : featureLimit(feature);
  const period = usePerConv ? opts.conversationId! : currentPeriod(feature);
  const sb = koalaAdmin();

  const { data: row } = await sb
    .from('billing_quota_usage')
    .select('count')
    .eq('user_id', userId)
    .eq('feature', feature)
    .eq('period', period)
    .maybeSingle();
  const current = (row?.count as number | undefined) ?? 0;

  if (current >= limit) {
    return { allowed: false, isPro: false, used: current, limit };
  }

  const next = current + 1;
  // Try update first — if no row, insert.
  const { data: upd, error: updErr } = await sb
    .from('billing_quota_usage')
    .update({ count: next })
    .eq('user_id', userId)
    .eq('feature', feature)
    .eq('period', period)
    .select('count');
  if (updErr) {
    console.warn('[quota.checkAndIncrement] update error', updErr.message);
  }
  if (!upd || upd.length === 0) {
    const { error: insErr } = await sb.from('billing_quota_usage').insert({
      user_id: userId,
      feature,
      period,
      count: next,
    });
    if (insErr) {
      console.warn('[quota.checkAndIncrement] insert error', insErr.message);
    }
  }
  return { allowed: true, isPro: false, used: next, limit };
}

/** Read-only: returns current usage for a feature without incrementing. */
export async function getUsage(
  userId: string,
  feature: Feature,
): Promise<number> {
  const sb = koalaAdmin();
  const period = currentPeriod(feature);
  const { data } = await sb
    .from('billing_quota_usage')
    .select('count')
    .eq('user_id', userId)
    .eq('feature', feature)
    .eq('period', period)
    .maybeSingle();
  return (data?.count as number | undefined) ?? 0;
}

/** Count user's saved_items rows (any type) — for save quota check. */
export async function countSavedItems(userId: string): Promise<number> {
  const sb = koalaAdmin();
  const { count } = await sb
    .from('saved_items')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId);
  return count ?? 0;
}
