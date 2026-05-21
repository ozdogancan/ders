// Google Play Developer API access token helper.
// Uses a service-account JSON (env GOOGLE_PLAY_SERVICE_ACCOUNT_JSON, raw or base64)
// to mint a short-lived JWT and exchange it for an OAuth2 access token.
//
// Token cached in-process for ~50 minutes (Google issues 1-hour tokens).
//
// Owner setup:
//  1. Google Play Console → Setup → API access → link a new GCP project.
//  2. Create a service account with role "Service Account User" + grant it
//     access in Play Console (View financial data, Manage orders & subscriptions).
//  3. Download the service-account JSON key.
//  4. Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON env on Vercel (paste raw JSON or base64).

import { createSign } from 'node:crypto';

const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

let _cachedToken: { token: string; expiresAt: number } | null = null;
let _sa: ServiceAccount | null = null;

function loadServiceAccount(): ServiceAccount {
  if (_sa) return _sa;
  const raw = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON env var not set');
  }
  let jsonStr = raw.trim();
  // Accept base64-encoded JSON for Vercel env (avoids newline escaping issues).
  if (!jsonStr.startsWith('{')) {
    try {
      jsonStr = Buffer.from(jsonStr, 'base64').toString('utf-8');
    } catch {
      throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is neither JSON nor base64');
    }
  }
  const parsed = JSON.parse(jsonStr) as ServiceAccount;
  if (!parsed.client_email || !parsed.private_key) {
    throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON missing client_email/private_key');
  }
  _sa = parsed;
  return parsed;
}

function base64UrlEncode(input: Buffer | string): string {
  const buf = typeof input === 'string' ? Buffer.from(input, 'utf-8') : input;
  return buf.toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function signJwt(sa: ServiceAccount): string {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: SCOPE,
    aud: sa.token_uri || TOKEN_URL,
    exp: now + 3600,
    iat: now,
  };
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signer = createSign('RSA-SHA256');
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign(sa.private_key);
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

export async function getPlayAccessToken(): Promise<string> {
  const now = Date.now();
  if (_cachedToken && _cachedToken.expiresAt > now + 60_000) {
    return _cachedToken.token;
  }
  const sa = loadServiceAccount();
  const jwt = signJwt(sa);
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: jwt,
  });
  const res = await fetch(sa.token_uri || TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => '');
    throw new Error(`Google token exchange failed: ${res.status} ${txt.slice(0, 200)}`);
  }
  const json = (await res.json()) as { access_token: string; expires_in: number };
  _cachedToken = {
    token: json.access_token,
    expiresAt: now + json.expires_in * 1000,
  };
  return json.access_token;
}

/** Looks up a Play subscription purchase. Returns the raw API payload. */
export async function getSubscriptionPurchase(opts: {
  packageName: string;
  productId: string;
  purchaseToken: string;
}): Promise<{
  expiryTimeMillis?: string;
  paymentState?: number;
  autoRenewing?: boolean;
  cancelReason?: number;
  startTimeMillis?: string;
  acknowledgementState?: number;
  raw: Record<string, unknown>;
}> {
  const token = await getPlayAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(opts.packageName)}` +
    `/purchases/subscriptions/${encodeURIComponent(opts.productId)}/tokens/${encodeURIComponent(opts.purchaseToken)}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => '');
    throw new Error(`Play purchases.subscriptions.get failed: ${res.status} ${txt.slice(0, 200)}`);
  }
  const json = (await res.json()) as Record<string, unknown>;
  return {
    expiryTimeMillis: json.expiryTimeMillis as string | undefined,
    paymentState: json.paymentState as number | undefined,
    autoRenewing: json.autoRenewing as boolean | undefined,
    cancelReason: json.cancelReason as number | undefined,
    startTimeMillis: json.startTimeMillis as string | undefined,
    acknowledgementState: json.acknowledgementState as number | undefined,
    raw: json,
  };
}

/** Map a productId to plan name. Throws if unknown. */
export function planFromProductId(productId: string): 'weekly' | 'monthly' | 'yearly' {
  switch (productId) {
    case 'koala_pro_weekly_v1':
      return 'weekly';
    case 'koala_pro_monthly_v1':
      return 'monthly';
    case 'koala_pro_yearly_v1':
      return 'yearly';
    default:
      throw new Error(`Unknown productId: ${productId}`);
  }
}
