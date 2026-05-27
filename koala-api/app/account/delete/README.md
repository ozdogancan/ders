# Public account deletion flow

Google Play 2024 mandates a public web URL where users can request account deletion **without installing/launching the app.** This folder implements that flow.

## Public URL (paste into Play Console)

```
https://koala-api-olive.vercel.app/account/delete
```

If a custom domain is wired up (e.g. `https://koalatutor.com/account/delete`), prefer the prettier domain. Update this README when that happens.

### Where it goes in Play Console

`Play Console → Your app → Policy → App content → Data deletion → Provide a URL to your data deletion process → Add a URL`

There are two URL slots:
- **Account deletion URL**: paste the URL above.
- **Other options** (optional): leave blank — our flow deletes both account + data in one step.

## Flow architecture

```
[user]
  │ visits /account/delete
  ▼
  Public Next.js page (Server + Client form)
  │ enters email + reason + 2 ack checkboxes
  ▼
  POST /api/account/delete-request
  │ - validates email format
  │ - Firebase Admin: getUserByEmail (silently OK if not found)
  │ - Firebase Admin: generateSignInWithEmailLink → /account/delete/confirm
  │ - Nodemailer (Gmail SMTP via koala_bridge_config.gmail_app_password) sends mail
  │ - returns ok:true ALWAYS (no account-existence leak)
  ▼
[user opens email, clicks "Hesabımı kalıcı olarak sil"]
  │
  ▼
  /account/delete/confirm?email=...
  Client component:
  │ - firebase/auth.isSignInWithEmailLink()  → verifies link
  │ - signInWithEmailLink()                  → real auth, gets uid + idToken
  │ - POST /api/account/wipe-data { userId, hardDelete: true }
  │   with Authorization: Bearer <idToken>
  ▼
  /api/account/wipe-data hardDelete branch:
  - deletes ai_chat_messages / ai_chat_sessions / saved_items / collections (existing soft-wipe)
  - deletes user_profiles row
  - upserts koala_user_email_state { unsubscribed: true }
  - calls admin.auth().deleteUser(uid) — Firebase auth user removed
  ▼
  User sees "Hesabın silindi. Görüşürüz 🐨"
```

## Soft-delete vs hard-delete

The same endpoint `/api/account/wipe-data` powers two paths:

| Caller                                   | Body                                  | Effect                                        |
| ---------------------------------------- | ------------------------------------- | --------------------------------------------- |
| In-app "Verilerimi sil" (`profile_screen.dart:218`) | `{ userId }` (no hardDelete)          | Soft wipe — content gone, account stays       |
| Public `/account/delete/confirm` page    | `{ userId, hardDelete: true }`        | Hard delete — content + profile + Firebase auth user gone |

## Data Safety form (Play Console)

When filling out the Data Safety form, list these data categories Koala collects and what's deleted in the hard-delete path:

| Category            | Stored                                       | Deleted on hard-delete? |
| ------------------- | -------------------------------------------- | ----------------------- |
| Email address       | Firebase Auth + `user_profiles.email`         | Yes                     |
| Name                | Firebase Auth + `user_profiles.display_name` | Yes                     |
| Profile photo       | Firebase Auth photoURL                       | Yes                     |
| FCM push token      | `user_profiles.fcm_token`                    | Yes (row deletion)      |
| AI-generated designs | `saved_items`, `collections`                 | Yes                     |
| Chat history        | `ai_chat_sessions`, `ai_chat_messages`       | Yes                     |
| Designer messages   | Evlumba bridge (separate platform)           | Soft-anonymized via Evlumba flow |
| Billing / Pro       | `user_profiles.pro_until`                    | Yes (row deletion)      |
| Email opt-out state | `koala_user_email_state.unsubscribed=true`   | Kept (tombstone, prevents future mail)  |

### Retention period

- All hard-deleted rows: **immediate, permanent.**
- Tombstone email opt-out: kept indefinitely (lawful basis: prevent re-mailing).
- Backups: Supabase point-in-time recovery retains data up to **7 days** in PITR window; backups age out automatically.

## ASO / Play Console submission checklist

1. ✅ Public URL live: `https://koala-api-olive.vercel.app/account/delete`
2. ✅ URL is reachable without login (no auth wall, no redirect to app).
3. ✅ URL returns `text/html` and is crawlable (robots may noindex, no problem).
4. ☐ Verify Firebase env vars on Vercel:
   - `FIREBASE_ADMIN_PROJECT_ID`, `FIREBASE_ADMIN_CLIENT_EMAIL`, `FIREBASE_ADMIN_PRIVATE_KEY` (server)
   - `NEXT_PUBLIC_FIREBASE_API_KEY`, `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`, `NEXT_PUBLIC_FIREBASE_PROJECT_ID`, `NEXT_PUBLIC_FIREBASE_APP_ID` (client)
5. ☐ Firebase Console → Authentication → Sign-in method → **Email link (passwordless sign-in)** must be enabled.
6. ☐ Firebase Console → Authentication → Settings → Authorized domains → add `koala-api-olive.vercel.app`.
7. ☐ Smoke test: submit form, receive email, click link, confirm "Hesabın silindi" page.
8. ☐ Play Console → App content → **Data deletion**: paste URL, save, submit for review.
9. ☐ Play Console → **Data Safety**: ensure every category above is declared with "deleted on request: yes."
10. ☐ Update privacy policy link to reference this URL: *"Hesabını ve tüm verilerini kalıcı olarak silmek için: https://koala-api-olive.vercel.app/account/delete"*

## Required env vars

Server-side (already required by other routes):
- `FIREBASE_ADMIN_PROJECT_ID`
- `FIREBASE_ADMIN_CLIENT_EMAIL`
- `FIREBASE_ADMIN_PRIVATE_KEY`
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

Client-side (new — must be added to Vercel before this flow works):
- `NEXT_PUBLIC_FIREBASE_API_KEY`
- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
- `NEXT_PUBLIC_FIREBASE_APP_ID`
- `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` (optional)
- `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET` (optional)

Pull values from Firebase Console → Project Settings → General → "Your apps" → Web app config.

SMTP credential reused from existing cron pattern:
- Table: `koala_bridge_config`
- Key: `gmail_app_password`
- From: `info@evlumba.com`

## Optional: track delete reasons

The endpoint best-effort inserts into `koala_account_delete_requests (user_id, email, reason, requested_at)` if the table exists. To enable analytics:

```sql
create table if not exists koala_account_delete_requests (
  id bigserial primary key,
  user_id text not null,
  email text not null,
  reason text,
  requested_at timestamptz not null default now()
);
```

If the table is missing the insert is silently skipped — no error surfaces to the user.
