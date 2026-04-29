// Firebase Admin SDK singleton — server-side ID token verification için.
//
// Env var'lar (Vercel Production / Preview):
//   FIREBASE_ADMIN_PROJECT_ID
//   FIREBASE_ADMIN_CLIENT_EMAIL
//   FIREBASE_ADMIN_PRIVATE_KEY  (newline'lar `\n` literal olarak escape'li)
//
// Bunlar set edilmezse veya init başarısız olursa singleton `null` kalır;
// caller (auth-verify) bu durumu legacy-mode fallback olarak yorumlar.
//
// Bu sayede env var'lar Vercel'a eklenmeden önce de deploy çalışır,
// her istek "AUTH_LEGACY admin-not-configured" log'lar.

import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { Auth, getAuth } from 'firebase-admin/auth';

let cachedApp: App | null = null;
let cachedAuth: Auth | null = null;
let initFailed = false;
let initFailReason: string | null = null;

function tryInit(): App | null {
  if (cachedApp) return cachedApp;
  if (initFailed) return null;

  // Re-use existing app (HMR / parallel cold starts).
  const apps = getApps();
  if (apps.length > 0) {
    cachedApp = apps[0]!;
    return cachedApp;
  }

  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL;
  const rawKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY;

  if (!projectId || !clientEmail || !rawKey) {
    initFailed = true;
    initFailReason = 'env-missing';
    return null;
  }

  // Vercel env editor literal `\n` saklıyor — gerçek newline'a çevir.
  const privateKey = rawKey.replace(/\\n/g, '\n');

  try {
    cachedApp = initializeApp({
      credential: cert({ projectId, clientEmail, privateKey }),
    });
    return cachedApp;
  } catch (e) {
    initFailed = true;
    initFailReason = e instanceof Error ? e.message : String(e);
    console.warn('[firebase-admin] init failed:', initFailReason);
    return null;
  }
}

export function getAdminAuth(): Auth | null {
  if (cachedAuth) return cachedAuth;
  const app = tryInit();
  if (!app) return null;
  try {
    cachedAuth = getAuth(app);
    return cachedAuth;
  } catch (e) {
    initFailed = true;
    initFailReason = e instanceof Error ? e.message : String(e);
    return null;
  }
}

export function adminInitFailReason(): string | null {
  return initFailReason;
}
