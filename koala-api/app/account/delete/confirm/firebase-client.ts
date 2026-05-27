'use client';

// Minimal client-side Firebase init used only by the account deletion confirm
// page. Uses public NEXT_PUBLIC_FIREBASE_* env vars — never service-account
// secrets. Singleton-guarded for HMR.

import { initializeApp, getApps, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';

let _app: FirebaseApp | null = null;
let _auth: Auth | null = null;

function readConfig() {
  return {
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
    authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
    messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
    storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  };
}

export function getClientAuth(): Auth | null {
  if (typeof window === 'undefined') return null;
  if (_auth) return _auth;

  const cfg = readConfig();
  if (!cfg.apiKey || !cfg.authDomain || !cfg.projectId || !cfg.appId) {
    return null;
  }

  if (!_app) {
    const existing = getApps();
    _app = existing.length > 0 ? existing[0]! : initializeApp(cfg);
  }
  _auth = getAuth(_app);
  return _auth;
}
