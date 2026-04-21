import { NextRequest } from 'next/server';

// ─── CORS ────────────────────────────────────────────────────
// Exact match only — startsWith is vulnerable to subdomain spoofing
// e.g. "https://koalatutor.com.evil.com" would bypass startsWith check

const PRODUCTION_ORIGINS = [
  'https://www.koalatutor.com',
  'https://koalatutor.com',
];

const DEV_ORIGINS = [
  'http://localhost:3000',
  'http://localhost:8080',
];

const IS_PRODUCTION = process.env.NODE_ENV === 'production';

const ALLOWED_ORIGINS = IS_PRODUCTION
  ? PRODUCTION_ORIGINS
  : [...PRODUCTION_ORIGINS, ...DEV_ORIGINS];

export function corsHeaders(
  origin: string | null,
  methods = 'POST, OPTIONS'
) {
  // Exact match — no startsWith
  const allowedOrigin =
    origin && ALLOWED_ORIGINS.includes(origin)
      ? origin
      : ALLOWED_ORIGINS[0];

  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': methods,
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

// ─── Rate Limiting ───────────────────────────────────────────
// In-memory per-IP, resets every window. Separate buckets per endpoint.

interface RateBucket {
  count: number;
  resetAt: number;
}

const buckets = new Map<string, Map<string, RateBucket>>();

export function checkRateLimit(
  req: NextRequest,
  endpoint: string,
  limit = 30,
  windowMs = 60_000
): boolean {
  const ip =
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  const key = `${endpoint}:${ip}`;

  if (!buckets.has(endpoint)) {
    buckets.set(endpoint, new Map());
  }
  const bucket = buckets.get(endpoint)!;
  const now = Date.now();
  const entry = bucket.get(key);

  if (!entry || now > entry.resetAt) {
    bucket.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }
  if (entry.count >= limit) return false;
  entry.count++;
  return true;
}

// ─── Origin Validation ──────────────────────────────────────
// Returns true if the request origin is allowed

export function isOriginAllowed(req: NextRequest): boolean {
  const origin = req.headers.get('origin');
  // No origin header = same-origin or non-browser request (allow)
  if (!origin) return true;
  return ALLOWED_ORIGINS.includes(origin);
}

// ─── Body Size Check ────────────────────────────────────────
// Reject oversized payloads before parsing (MB)

export function isBodyTooLarge(
  req: NextRequest,
  maxMB = 10
): boolean {
  const contentLength = req.headers.get('content-length');
  if (!contentLength) return false;
  return parseInt(contentLength, 10) > maxMB * 1024 * 1024;
}
