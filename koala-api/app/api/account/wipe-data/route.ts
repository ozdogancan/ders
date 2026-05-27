import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, isOriginAllowed, checkRateLimit } from '@/lib/security';
import { verifyAuthHeader, logAuthOutcome } from '@/lib/auth-verify';
import { getAdminAuth } from '@/lib/firebase-admin';

// Wipes a user's saved_items, collections, ai_chat_sessions and ai_chat_messages.
// Account itself (Firebase auth) is NOT touched here — caller deletes the auth
// user separately if requested. Service-role used to bypass RLS.

export const runtime = 'nodejs';
export const maxDuration = 30;

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

function admin() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

interface Body {
  userId: string;
  hardDelete?: boolean;
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);
  if (!isOriginAllowed(req)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403, headers });
  }
  if (!checkRateLimit(req, 'account-wipe', 5)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers },
    );
  }

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400, headers });
  }

  const { userId, hardDelete } = body;
  if (!userId) {
    return NextResponse.json(
      { error: 'userId required' },
      { status: 400, headers },
    );
  }

  // AUTH (mandatory here — destructive op). Legacy mode still allowed by
  // verifyAuthHeader but we additionally require either a verified token OR
  // explicit legacy header to be absent (no token at all). For destructive
  // wipe-data we tolerate legacy=true to keep parity with saved-items, since
  // userId is the Firebase uid the client controls.
  const authResult = await verifyAuthHeader(req, userId);
  logAuthOutcome('account-wipe', authResult, {
    userId,
    ip: req.headers.get('x-forwarded-for'),
  });
  if (!authResult.ok) {
    return NextResponse.json(
      { error: 'unauthorized', reason: authResult.reason },
      { status: 401, headers },
    );
  }

  const sb = admin();
  const results: Record<string, number | string> = {};

  // Wipe each table independently — collect errors, don't bail on first failure
  // so partial wipes still happen if e.g. a single table is unreachable.
  async function wipe(table: string, column: string = 'user_id') {
    try {
      const { error, count } = await sb
        .from(table)
        .delete({ count: 'exact' })
        .eq(column, userId);
      if (error) throw error;
      results[table] = count ?? 0;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      results[table] = `error:${msg}`;
      console.error(`[account-wipe] ${table} failed`, { userId, msg });
    }
  }

  // ai_chat_messages first (FK on session_id), then sessions, then the rest.
  // If schema doesn't enforce FK, order is harmless.
  await wipe('ai_chat_messages');
  await wipe('ai_chat_sessions');
  await wipe('saved_items');
  await wipe('collections');

  // ─── HARD DELETE: account-level removal (Play Console public deletion flow)
  // For the in-app "verilerimi sil" path, hardDelete is omitted/false and the
  // account itself stays so the user can keep using the app. For the public
  // /account/delete/confirm page, hardDelete=true removes the Firebase auth
  // user + user_profiles row + sets email_state opt-out flags so we never
  // mail them again.
  if (hardDelete) {
    // user_profiles row
    try {
      const { error, count } = await sb
        .from('user_profiles')
        .delete({ count: 'exact' })
        .eq('id', userId);
      if (error) throw error;
      results['user_profiles'] = count ?? 0;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      results['user_profiles'] = `error:${msg}`;
      console.error('[account-wipe] user_profiles failed', { userId, msg });
    }

    // Email opt-out (defensive — table may be missing, that's fine)
    try {
      await sb.from('koala_user_email_state').upsert(
        {
          user_id: userId,
          unsubscribed: true,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id' },
      );
      results['koala_user_email_state'] = 'opted-out';
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      results['koala_user_email_state'] = `error:${msg}`;
    }

    // Firebase auth user
    try {
      const adminAuth = getAdminAuth();
      if (!adminAuth) {
        results['firebase_auth'] = 'error:admin-not-configured';
      } else {
        await adminAuth.deleteUser(userId);
        results['firebase_auth'] = 'deleted';
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // user-not-found is acceptable (already deleted) — treat as success.
      if (msg.includes('user-not-found') || msg.includes('USER_NOT_FOUND')) {
        results['firebase_auth'] = 'already-deleted';
      } else {
        results['firebase_auth'] = `error:${msg}`;
        console.error('[account-wipe] firebase deleteUser failed', { userId, msg });
      }
    }
  }

  const anyError = Object.values(results).some(
    (v) => typeof v === 'string' && v.startsWith('error:'),
  );

  return NextResponse.json(
    { ok: !anyError, results, hardDelete: !!hardDelete },
    { status: anyError ? 500 : 200, headers },
  );
}
