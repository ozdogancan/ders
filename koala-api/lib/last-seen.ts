// Shared helper: upsert koala_user_last_seen row.
//
// Called from:
//   - /api/user/touch         (explicit, with fcm_token in body)
//   - /api/billing/status     (piggyback side-effect, every app launch)
//
// Fail-safe: never throws — the caller's primary purpose (status check,
// auth flow) MUST NOT break because retention tracking had a hiccup.

import { koalaAdmin } from '@/lib/supabase/koala';

interface TouchInput {
  uid: string;
  pushToken?: string | null;
}

export async function touchUserLastSeen(input: TouchInput): Promise<void> {
  const uid = (input.uid ?? '').trim();
  if (!uid) return;

  const pushToken =
    typeof input.pushToken === 'string' && input.pushToken.trim().length > 0
      ? input.pushToken.trim()
      : null;

  try {
    const admin = koalaAdmin();

    // Build row carefully: don't overwrite push_token with null if the call
    // didn't include one. Only update push_token when we actually have one.
    const row: Record<string, unknown> = {
      uid,
      last_seen_at: new Date().toISOString(),
      // Reset the dN_sent flags so the user becomes eligible for the next
      // window after they come back. Without this, a returning D1 user would
      // never receive a D7 nudge if they go cold again.
      d1_sent: false,
      d7_sent: false,
      d14_sent: false,
      d30_sent: false,
    };
    if (pushToken) {
      row.push_token = pushToken;
    }

    const { error } = await admin
      .from('koala_user_last_seen')
      .upsert(row, { onConflict: 'uid' });

    if (error) {
      console.warn('[last-seen] upsert failed', { uid, error: error.message });
    }
  } catch (e) {
    console.warn('[last-seen] unexpected error', {
      uid,
      error: e instanceof Error ? e.message : String(e),
    });
  }
}
