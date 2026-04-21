# Koala API

Next.js API backend for the Koala interior design app.

- **Production**: https://koala-api-olive.vercel.app
- **Mobile client**: https://github.com/ozdogancan/ders (Flutter)
- **Deploy**: Vercel auto-deploys from `master` branch on push

## Health check

```bash
curl https://koala-api-olive.vercel.app/api/health
```

## Local dev

```bash
cp .env.example .env.local  # fill in keys
npm install
npm run dev
```

Required env vars (set in Vercel dashboard for prod):
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- `EVLUMBA_URL`, `EVLUMBA_SERVICE_ROLE_KEY`
- `GEMINI_API_KEY`
