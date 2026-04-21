import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Evlumba service-role client.
 * SADECE server-side kullanılır, RLS'i bypass eder.
 * Shadow-user oluşturma + conversation/message insert için.
 */

let _admin: SupabaseClient | null = null;

export function evlumbaAdmin(): SupabaseClient {
  if (_admin) return _admin;

  const url = process.env.EVLUMBA_SUPABASE_URL;
  const key = process.env.EVLUMBA_SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error(
      'EVLUMBA_SUPABASE_URL and EVLUMBA_SUPABASE_SERVICE_ROLE_KEY must be set',
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

/**
 * Her Koala kullanıcısına karşılık gelen bir Evlumba auth user'ı bulur veya oluşturur.
 * Email varsa onu kullanır, yoksa deterministik bir placeholder üretir.
 *
 * Return: Evlumba auth.users.id (UUID)
 */
export async function ensureShadowUser(params: {
  firebaseUid: string;
  email?: string | null;
  displayName?: string | null;
  avatarUrl?: string | null;
}): Promise<string> {
  const { firebaseUid, email, displayName, avatarUrl } = params;

  // Firebase'de email varsa onu kullan, yoksa koala-bridge altında fake bir email
  const shadowEmail =
    email?.trim().toLowerCase() ||
    `koala-${firebaseUid}@bridge.koalatutor.com`;

  const admin = evlumbaAdmin();

  // 1) Email'e göre user var mı?
  //    listUsers ile filter desteklemiyor — tek tek aramak yerine
  //    getUserByEmail çağrısı yok, bu yüzden önce signUp dener fail olursa lookup.
  //    Supabase Admin API: /auth/v1/admin/users?email=... filter ediyor.
  const { data: existing, error: listErr } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000, // basic protection; email unique bu yüzden maksimum 1 dönmeli
  });
  if (listErr) {
    throw new Error(`Evlumba listUsers failed: ${listErr.message}`);
  }

  let userId: string | null = null;
  const match = existing?.users?.find(
    (u) => (u.email || '').toLowerCase() === shadowEmail,
  );

  if (match) {
    userId = match.id;
  } else {
    // 2) Yoksa oluştur — email auto-confirmed
    const { data: created, error: createErr } =
      await admin.auth.admin.createUser({
        email: shadowEmail,
        email_confirm: true,
        user_metadata: {
          source: 'koala',
          firebase_uid: firebaseUid,
          display_name: displayName ?? null,
        },
      });
    if (createErr || !created?.user) {
      throw new Error(
        `Evlumba createUser failed: ${createErr?.message ?? 'no user returned'}`,
      );
    }
    userId = created.user.id;
  }

  // 3) profiles upsert — role='homeowner' zorunlu (can_message_pair için)
  const { error: profErr } = await admin.from('profiles').upsert(
    {
      id: userId,
      role: 'homeowner',
      full_name: displayName?.trim() || null,
      avatar_url: avatarUrl?.trim() || null,
    },
    { onConflict: 'id', ignoreDuplicates: false },
  );
  if (profErr) {
    // Non-fatal — profile eksik olsa bile conversation çalışabilir ama RLS
    // can_message_pair başarısız olur. Bu yüzden hata fırlat.
    throw new Error(`Evlumba profile upsert failed: ${profErr.message}`);
  }

  return userId;
}

/**
 * Koala kullanıcısının karşılığı olan homeowner_id'yi bul/oluştur.
 * Bu sürümde her zaman shadow user yolu kullanılır — gerçek Evlumba
 * hesabı ile eşleştirme (`findAllHomeownerIds`) yalnızca backup branch'te
 * var. Bridge route API uyumluluğu için tutuluyor.
 */
export async function resolveHomeownerId(params: {
  firebaseUid: string;
  email?: string | null;
  displayName?: string | null;
  avatarUrl?: string | null;
}): Promise<{ homeownerId: string; source: 'shadow' }> {
  const shadowId = await ensureShadowUser(params);
  return { homeownerId: shadowId, source: 'shadow' };
}

/**
 * (homeowner_id, designer_id) için mevcut conversation'ı bul veya oluştur.
 */
export async function findOrCreateConversation(params: {
  homeownerId: string;
  designerId: string;
}): Promise<string> {
  const { homeownerId, designerId } = params;
  const admin = evlumbaAdmin();

  const { data: existing, error: selErr } = await admin
    .from('conversations')
    .select('id')
    .eq('homeowner_id', homeownerId)
    .eq('designer_id', designerId)
    .maybeSingle();

  if (selErr) {
    throw new Error(`Evlumba conversation select failed: ${selErr.message}`);
  }
  if (existing?.id) return existing.id as string;

  const { data: created, error: insErr } = await admin
    .from('conversations')
    .insert({ homeowner_id: homeownerId, designer_id: designerId })
    .select('id')
    .single();

  if (insErr || !created?.id) {
    throw new Error(
      `Evlumba conversation insert failed: ${insErr?.message ?? 'no id'}`,
    );
  }
  return created.id as string;
}

/**
 * Mesaj insert et — sender_id = Koala user'ın shadow user id'si.
 */
export async function insertMessage(params: {
  conversationId: string;
  senderId: string;
  body: string;
}): Promise<string> {
  const { conversationId, senderId, body } = params;
  const admin = evlumbaAdmin();

  const { data, error } = await admin
    .from('messages')
    .insert({
      conversation_id: conversationId,
      sender_id: senderId,
      body,
    })
    .select('id')
    .single();

  if (error || !data?.id) {
    throw new Error(
      `Evlumba message insert failed: ${error?.message ?? 'no id'}`,
    );
  }
  return data.id as string;
}
