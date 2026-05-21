// FCM HTTP v1 push sender — firebase-admin tabanlı.
//
// ESKİ DURUM: supabase-edge-functions/send-push legacy `fcm.googleapis.com/fcm/send`
// endpoint'ini kullanıyordu. Google bu endpoint'i Haziran 2024'te kapattı (404).
//
// YENİ DURUM: firebase-admin SDK + FCM HTTP v1. firebase-admin zaten
// `lib/firebase-admin.ts` içinde ID token verify için init ediliyor — aynı
// singleton App'i REUSE ediyoruz, yeniden init ETMİYORUZ.
//
// Gereken env var'lar (Vercel Production / Preview):
//   FIREBASE_ADMIN_PROJECT_ID
//   FIREBASE_ADMIN_CLIENT_EMAIL
//   FIREBASE_ADMIN_PRIVATE_KEY  (newline'lar `\n` literal escape'li)
// Bunlar zaten auth verify için set edilmiş olmalı; push gönderimi için de
// AYNI credential yeterli (messaging scope service account'ta dahil).

import { getMessaging, type Messaging } from 'firebase-admin/messaging';
import { getAdminApp, adminInitFailReason } from './firebase-admin';
import { koalaAdmin } from './supabase/koala';

let cachedMessaging: Messaging | null = null;

function getAdminMessaging(): Messaging | null {
  if (cachedMessaging) return cachedMessaging;
  const app = getAdminApp();
  if (!app) return null;
  try {
    cachedMessaging = getMessaging(app);
    return cachedMessaging;
  } catch (e) {
    console.warn('[push] getMessaging failed:', e instanceof Error ? e.message : String(e));
    return null;
  }
}

/** `data.type` → Android notification channel id eşlemesi. */
function channelForType(type: string | undefined): string {
  if (!type) return 'koala_general';
  if (type.includes('message') || type.includes('chat')) return 'koala_messages';
  if (type.includes('design')) return 'koala_design';
  return 'koala_general';
}

export interface SendPushInput {
  userId: string;
  title: string;
  body: string;
  /** FCM data payload — tüm değerler string olmalı. */
  data?: Record<string, string>;
}

export interface SendPushResult {
  sent: number;
  failed: number;
  /** Token bulunamadıysa true. */
  noToken?: boolean;
  /** firebase-admin init edilemediyse / messaging alınamadıysa hata. */
  error?: string;
}

/**
 * Bir kullanıcıya kayıtlı tüm aktif cihaz token'larına push gönderir.
 *
 *  - Token'ları `koala_push_tokens` tablosundan çeker (user_id eşleşmesi).
 *  - `sendEachForMulticast` ile tek seferde gönderir.
 *  - `registration-token-not-registered` / `invalid-argument` dönen
 *    stale token'ları tablodan SİLER.
 */
export async function sendPushToUser(input: SendPushInput): Promise<SendPushResult> {
  const messaging = getAdminMessaging();
  if (!messaging) {
    return {
      sent: 0,
      failed: 0,
      error: `firebase-admin-not-configured:${adminInitFailReason() ?? 'unknown'}`,
    };
  }

  const supabase = koalaAdmin();

  // Kullanıcının aktif token'larını çek (CLAUDE.md: limit ile sınırla).
  const { data: tokenRows, error: tokenErr } = await supabase
    .from('koala_push_tokens')
    .select('device_token')
    .eq('user_id', input.userId)
    .eq('is_active', true)
    .order('last_used_at', { ascending: false })
    .limit(20);

  if (tokenErr) {
    return { sent: 0, failed: 0, error: `token-query-failed:${tokenErr.message}` };
  }

  const tokens = (tokenRows ?? [])
    .map((r) => r.device_token as string)
    .filter((t): t is string => typeof t === 'string' && t.length > 0);

  if (tokens.length === 0) {
    return { sent: 0, failed: 0, noToken: true };
  }

  const channelId = channelForType(input.data?.type);

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: input.title, body: input.body },
    data: input.data,
    android: {
      priority: 'high',
      notification: {
        channelId,
        color: '#6C63FF',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  });

  // Geçersiz token'ları topla.
  const staleTokens: string[] = [];
  response.responses.forEach((res, idx) => {
    if (res.success) return;
    const code = res.error?.code ?? '';
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-argument' ||
      code === 'messaging/invalid-registration-token'
    ) {
      const t = tokens[idx];
      if (t) staleTokens.push(t);
    }
  });

  // Stale token'ları sil (best-effort).
  if (staleTokens.length > 0) {
    const { error: delErr } = await supabase
      .from('koala_push_tokens')
      .delete()
      .eq('user_id', input.userId)
      .in('device_token', staleTokens);
    if (delErr) {
      console.warn('[push] stale token cleanup failed:', delErr.message);
    } else {
      console.log(`[push] removed ${staleTokens.length} stale token(s) for ${input.userId}`);
    }
  }

  return {
    sent: response.successCount,
    failed: response.failureCount,
  };
}
