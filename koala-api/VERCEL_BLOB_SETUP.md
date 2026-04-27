# Vercel Blob Setup

The `/api/restyle` endpoint uploads generated images to Vercel Blob and
returns a public URL instead of a multi-megabyte base64 data URL. This
cuts mobile response size from ~2 MB to ~200 B and enables HTTP caching
on the Flutter client.

## 3-Step Setup

### 1. Enable Blob on the project

Dashboard → your project → **Storage** → **Create Database** → select
**Blob** → give it a name (e.g. `koala-restyle-blob`) → **Create**.

Or via CLI from `koala-api/`:

```bash
vercel link            # if not already linked
vercel storage create blob
```

### 2. Env var pulls automatically

Once Blob is connected to the project, Vercel auto-provisions
`BLOB_READ_WRITE_TOKEN` on **all environments** (Production, Preview,
Development). No manual entry required.

For local development, pull it into `.env.local`:

```bash
vercel env pull .env.local
```

Verify it landed:

```bash
grep BLOB_READ_WRITE_TOKEN .env.local
```

### 3. Redeploy

The new token is only injected at build time, so trigger a redeploy:

```bash
vercel deploy --prod
```

## Verification

After deploy, hit `/api/restyle` and check the response:

- `url` should be a `https://*.public.blob.vercel-storage.com/restyle/...png` URL.
- Server logs should include `[restyle] blob_uploaded { url, ms_upload }`.
- If `url` is `null`, upload fell back to base64 — check logs for
  `[restyle] blob_upload_failed`.

## Rollback

If Blob misbehaves, the endpoint falls back to returning `output`
(base64 data URL) with `url: null`, so the Flutter client keeps working.
