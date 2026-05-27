// GET /api/cron/comeback-push
//
// Daily Vercel Cron: scans koala_user_last_seen for users in the D1 / D7 / D14
// / D30 comeback windows and sends a segmented push via /api/push/send.
//
// Auth: `Authorization: Bearer $CRON_SECRET` (same pattern as escalate-stale).
// Trigger: Vercel Cron, daily at 10:00 UTC (see vercel.json).
//
// SEGMENTS (last_seen_at delta, hours):
//   D1   : 24h – 48h    + !d1_sent   →  "Tarzını keşfetmeye devam et …"      open_home
//   D7   :  6d – 8d     + !d7_sent   →  "Bu hafta {style} stili öne çıktı …" open_home
//   D14  : 13d – 15d    + !d14_sent  →  "Pro'yu denemedin — 7 gün ücretsiz"  open_paywall
//   D30  : 29d – 31d    + !d30_sent  →  "Seni özledik — %30 indirim"         open_paywall
//   TRIAL: first_seen 3d ago + !pro_trial_sent + likes >= 5 + isPro=false
//          → "Sen tarzını biliyorsun — Pro ile sınırsızca dene"             open_paywall
//
// FREQUENCY CAP: weekly_sent_count < 2 per ISO week. Counter resets when
// weekly_sent_week changes (current ISO week number).

import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';

export const runtime = 'nodejs';
export const maxDuration = 300;
export const dynamic = 'force-dynamic';

function authorized(req: NextRequest): boolean {
  const s = process.env.CRON_SECRET;
  return !!s && req.headers.get('authorization') === `Bearer ${s}`;
}

type Segment = 'd1' | 'd7' | 'd14' | 'd30' | 'trial';

interface LastSeenRow {
  uid: string;
  last_seen_at: string;
  first_seen_at: string | null;
  push_token: string | null;
  d1_sent: boolean | null;
  d7_sent: boolean | null;
  d14_sent: boolean | null;
  d30_sent: boolean | null;
  pro_trial_sent: boolean | null;
  weekly_sent_count: number | null;
  weekly_sent_week: number | null;
  opted_out: boolean | null;
}

// ISO week number (1-53) — keeps counter aligned with calendar weeks.
function isoWeek(d: Date): number {
  const target = new Date(d.valueOf());
  const dayNr = (d.getUTCDay() + 6) % 7;
  target.setUTCDate(target.getUTCDate() - dayNr + 3);
  const firstThursday = new Date(Date.UTC(target.getUTCFullYear(), 0, 4));
  const diff = target.valueOf() - firstThursday.valueOf();
  return 1 + Math.round(diff / (7 * 24 * 3600 * 1000));
}

function hoursAgo(ts: string): number {
  return (Date.now() - new Date(ts).getTime()) / (1000 * 60 * 60);
}

function pickSegment(row: LastSeenRow): Segment | null {
  const h = hoursAgo(row.last_seen_at);
  // Windows are *exclusive* on the boundary the user JUST entered so we don't
  // catch them mid-flight: e.g. D7 = strictly between 6d and 8d.
  if (h >= 24 && h < 48 && !row.d1_sent) return 'd1';
  if (h >= 144 && h < 192 && !row.d7_sent) return 'd7';       // 6d-8d
  if (h >= 312 && h < 360 && !row.d14_sent) return 'd14';     // 13d-15d
  if (h >= 696 && h < 744 && !row.d30_sent) return 'd30';     // 29d-31d
  return null;
}

function tryTrialNudge(row: LastSeenRow, likeCount: number, isPro: boolean): boolean {
  if (row.pro_trial_sent) return false;
  if (isPro) return false;
  if (likeCount < 5) return false;
  if (!row.first_seen_at) return false;
  const ageHours = (Date.now() - new Date(row.first_seen_at).getTime()) / (1000 * 60 * 60);
  // 3-5 day window so we don't miss anyone if a cron run is skipped.
  return ageHours >= 72 && ageHours <= 120;
}

interface PushPayload {
  title: string;
  body: string;
  data: Record<string, string>;
}

function buildPayload(segment: Segment, topStyle: string | null): PushPayload {
  const style = topStyle && topStyle.trim().length > 0 ? topStyle.trim() : 'modern';
  switch (segment) {
    case 'd1':
      return {
        title: 'Koala 🐨',
        body: 'Tarzını keşfetmeye devam et — bugün 24 yeni tasarım eklendi 🐨',
        data: { action_type: 'open_home', segment: 'd1' },
      };
    case 'd7':
      return {
        title: 'Bu haftanın trendi',
        body: `Bu hafta ${style} stili öne çıktı — bakar mısın?`,
        data: { action_type: 'open_home', segment: 'd7' },
      };
    case 'd14':
      return {
        title: 'Pro\'yu denedin mi?',
        body: 'Pro\'yu denemedin — 7 gün ücretsiz başlat ✨',
        data: { action_type: 'open_paywall', segment: 'd14' },
      };
    case 'd30':
      return {
        title: 'Seni özledik 🐨',
        body: 'Seni özledik 🐨 Bu hafta sana özel %30 indirim — kuponu al',
        data: { action_type: 'open_paywall', segment: 'd30' },
      };
    case 'trial':
      return {
        title: 'Sen tarzını biliyorsun',
        body: 'Sen tarzını biliyorsun — Pro ile sınırsızca dene 🔮',
        data: { action_type: 'open_paywall', segment: 'trial' },
      };
  }
}

// Best-effort lookup of the user's top liked style. Failures fall back to null.
async function getTopStyle(uid: string): Promise<string | null> {
  try {
    const admin = koalaAdmin();
    // koala_user_profiles.taste_profile is a jsonb with the swipe-derived
    // style scores. Shape varies, so we read defensively.
    const { data } = await admin
      .from('koala_user_profiles')
      .select('taste_profile')
      .eq('uid', uid)
      .maybeSingle();
    const tp = (data as { taste_profile?: unknown } | null)?.taste_profile;
    if (!tp || typeof tp !== 'object') return null;
    const scores = (tp as Record<string, unknown>).styles ?? tp;
    if (!scores || typeof scores !== 'object') return null;
    let best: { key: string; val: number } | null = null;
    for (const [k, v] of Object.entries(scores as Record<string, unknown>)) {
      const num = typeof v === 'number' ? v : Number(v);
      if (!Number.isFinite(num)) continue;
      if (!best || num > best.val) best = { key: k, val: num };
    }
    return best?.key ?? null;
  } catch {
    return null;
  }
}

async function getLikeCount(uid: string): Promise<number> {
  try {
    const admin = koalaAdmin();
    const { count } = await admin
      .from('koala_likes')
      .select('uid', { count: 'exact', head: true })
      .eq('uid', uid);
    return count ?? 0;
  } catch {
    return 0;
  }
}

async function getIsPro(uid: string): Promise<boolean> {
  try {
    const admin = koalaAdmin();
    const { data } = await admin
      .from('pro_subscriptions')
      .select('status, pro_until')
      .eq('uid', uid)
      .maybeSingle();
    if (!data) return false;
    const row = data as { status?: string | null; pro_until?: string | null };
    if (row.status !== 'active') return false;
    if (!row.pro_until) return true;
    return new Date(row.pro_until).getTime() > Date.now();
  } catch {
    return false;
  }
}

async function sendPush(uid: string, payload: PushPayload): Promise<boolean> {
  const base = process.env.NEXT_PUBLIC_BASE_URL || process.env.VERCEL_URL || '';
  const url = base.startsWith('http')
    ? `${base}/api/push/send`
    : base
      ? `https://${base}/api/push/send`
      : '/api/push/send';
  const secret = process.env.PUSH_SEND_SECRET ?? '';
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Push-Secret': secret,
      },
      body: JSON.stringify({
        userId: uid,
        title: payload.title,
        body: payload.body,
        data: payload.data,
      }),
    });
    if (!res.ok) {
      console.warn('[comeback-push] push/send failed', uid, res.status);
      return false;
    }
    const json = (await res.json().catch(() => ({}))) as { sent?: number };
    return (json.sent ?? 0) > 0;
  } catch (e) {
    console.warn('[comeback-push] push/send error', uid, e);
    return false;
  }
}

export async function GET(req: NextRequest) {
  if (!authorized(req)) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = koalaAdmin();
  const now = new Date();
  const currentWeek = isoWeek(now);

  // Pull the candidate set in one shot. Range covers D1 lower bound (24h) back
  // through D30 upper bound (~32d) — anyone older never gets re-engaged here.
  // Cap at 500 rows per run to stay under the 1GB RAM ceiling on the n8n box…
  // wait, this is Vercel — but keeping the batch small still helps maxDuration.
  const oldest = new Date(now.getTime() - 32 * 24 * 3600 * 1000).toISOString();
  const newest = new Date(now.getTime() - 23 * 3600 * 1000).toISOString();

  const { data: rows, error } = await admin
    .from('koala_user_last_seen')
    .select(
      'uid,last_seen_at,first_seen_at,push_token,d1_sent,d7_sent,d14_sent,d30_sent,pro_trial_sent,weekly_sent_count,weekly_sent_week,opted_out',
    )
    .eq('opted_out', false)
    .not('push_token', 'is', null)
    .lte('last_seen_at', newest)
    .gte('last_seen_at', oldest)
    .limit(500);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  const list = (rows ?? []) as LastSeenRow[];

  // Also pull trial-window candidates (first_seen 3-5d ago, push_token set,
  // not yet sent). They might be outside the last_seen oldest window if active.
  const trialOldest = new Date(now.getTime() - 5 * 24 * 3600 * 1000).toISOString();
  const trialNewest = new Date(now.getTime() - 3 * 24 * 3600 * 1000).toISOString();
  const { data: trialRows } = await admin
    .from('koala_user_last_seen')
    .select(
      'uid,last_seen_at,first_seen_at,push_token,d1_sent,d7_sent,d14_sent,d30_sent,pro_trial_sent,weekly_sent_count,weekly_sent_week,opted_out',
    )
    .eq('opted_out', false)
    .eq('pro_trial_sent', false)
    .not('push_token', 'is', null)
    .lte('first_seen_at', trialNewest)
    .gte('first_seen_at', trialOldest)
    .limit(500);

  // Dedupe by uid (a user can appear in both lists).
  const byUid = new Map<string, LastSeenRow>();
  for (const r of list) byUid.set(r.uid, r);
  for (const r of (trialRows ?? []) as LastSeenRow[]) {
    if (!byUid.has(r.uid)) byUid.set(r.uid, r);
  }

  let scanned = 0;
  let sent = 0;
  let capped = 0;
  let skipped = 0;
  const errors: Array<{ uid: string; error: string }> = [];

  for (const row of byUid.values()) {
    scanned++;
    try {
      // Reset weekly counter at week rollover.
      let weekCount = row.weekly_sent_count ?? 0;
      if ((row.weekly_sent_week ?? 0) !== currentWeek) weekCount = 0;
      if (weekCount >= 2) {
        capped++;
        continue;
      }

      const segment = pickSegment(row);
      let chosen: Segment | null = segment;

      // If no comeback segment matched, see if they qualify for the trial nudge.
      if (!chosen) {
        const likeCount = await getLikeCount(row.uid);
        const isPro = await getIsPro(row.uid);
        if (tryTrialNudge(row, likeCount, isPro)) {
          chosen = 'trial';
        }
      }

      if (!chosen) {
        skipped++;
        continue;
      }

      const topStyle = chosen === 'd7' ? await getTopStyle(row.uid) : null;
      const payload = buildPayload(chosen, topStyle);
      const ok = await sendPush(row.uid, payload);
      if (!ok) {
        skipped++;
        continue;
      }

      const patch: Record<string, unknown> = {
        weekly_sent_count: weekCount + 1,
        weekly_sent_week: currentWeek,
      };
      if (chosen === 'd1') patch.d1_sent = true;
      else if (chosen === 'd7') patch.d7_sent = true;
      else if (chosen === 'd14') patch.d14_sent = true;
      else if (chosen === 'd30') patch.d30_sent = true;
      else if (chosen === 'trial') patch.pro_trial_sent = true;

      const { error: upErr } = await admin
        .from('koala_user_last_seen')
        .update(patch)
        .eq('uid', row.uid);
      if (upErr) throw new Error(upErr.message);

      sent++;
    } catch (e) {
      errors.push({
        uid: row.uid,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return NextResponse.json({ scanned, sent, capped, skipped, errors });
}
