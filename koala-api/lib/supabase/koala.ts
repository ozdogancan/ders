import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Koala service-role client.
 * Server-side only — bypasses RLS. Used for:
 *   - conversation ensure (client RLS races bypass)
 *   - bridge fallback updates (last_message sync)
 */

let _admin: SupabaseClient | null = null;

export function koalaAdmin(): SupabaseClient {
  if (_admin) return _admin;

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error(
      'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set',
    );
  }

  _admin = createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  return _admin;
}

/** Back-compat alias used by bridge route. */
export const koalaService = new Proxy({} as SupabaseClient, {
  get(_t, prop) {
    const c = koalaAdmin() as unknown as Record<string | symbol, unknown>;
    return c[prop];
  },
});
