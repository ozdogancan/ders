// Authorization: Bearer <Firebase ID Token> header verification.
//
// DUAL-MODE ROLLOUT (TODO[2026-Q3] strict yapılacak):
//   Eski Android sürümü (1.0.79+83) Play Store'da canlı; o sürüm
//   Authorization header GÖNDERMİYOR. Server token zorunlu kılarsa tüm eski
//   Android kullanıcıları kırılır. Bu yüzden:
//     - Authorization yoksa → ok=true, legacy=true (çağrı geçer, log düşer)
//     - Authorization varsa → verify et; uid mismatch / invalid → ok=false
//
// Bir sonraki release cycle'da Vercel logs'unda "AUTH_LEGACY" sayısı düşünce
// legacy=true → 401 yapılacak.

import { getAdminAuth, adminInitFailReason } from './firebase-admin';

export interface VerifyResult {
  ok: boolean;
  uid?: string;
  reason?: string;
  /** Legacy davranış uygulandı (header yok ya da admin init configured değil). */
  legacy?: boolean;
}

export async function verifyAuthHeader(
  req: Request,
  expectedUid?: string,
): Promise<VerifyResult> {
  const authHeader =
    req.headers.get('authorization') ?? req.headers.get('Authorization');

  // 1) Header yoksa → legacy mode (eski mobil sürümler için)
  if (!authHeader) {
    return { ok: true, legacy: true, reason: 'no-token' };
  }

  // 2) "Bearer <token>" parse et
  const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
  if (!match) {
    // Authorization gönderilmiş ama format bozuk — legacy değil, hatalı istek.
    return { ok: false, reason: 'malformed-authorization' };
  }
  const token = match[1]!.trim();
  if (!token) {
    return { ok: false, reason: 'empty-token' };
  }

  // 3) Admin SDK init edemiyorsa → legacy davran (env vars Vercel'a eklenene kadar
  //    geçici durum; tüm istekler "AUTH_LEGACY admin-not-configured" log'lar).
  const auth = getAdminAuth();
  if (!auth) {
    return {
      ok: true,
      legacy: true,
      reason: `admin-not-configured:${adminInitFailReason() ?? 'unknown'}`,
    };
  }

  // 4) Token verify
  try {
    const decoded = await auth.verifyIdToken(token);
    if (expectedUid && decoded.uid !== expectedUid) {
      return { ok: false, reason: 'uid-mismatch', uid: decoded.uid };
    }
    return { ok: true, uid: decoded.uid };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, reason: `invalid-token:${msg.slice(0, 80)}` };
  }
}

/**
 * Kısa logger — endpoint'ler için tek satır.
 * Legacy ve mismatch durumlarında stderr'e log düşer; Vercel log explorer'dan
 * "AUTH_LEGACY" / "AUTH_FAIL" filtre ile metrik çıkarılabilir.
 */
export function logAuthOutcome(
  route: string,
  result: VerifyResult,
  ctx: { userId?: string | null; ip?: string | null } = {},
): void {
  if (result.ok && result.legacy) {
    console.warn('AUTH_LEGACY', {
      route,
      reason: result.reason,
      userId: ctx.userId ?? null,
      ip: ctx.ip ?? null,
    });
  } else if (!result.ok) {
    console.warn('AUTH_FAIL', {
      route,
      reason: result.reason,
      userId: ctx.userId ?? null,
    });
  }
}
