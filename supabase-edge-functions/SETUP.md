# Edge Function Kurulumu

## Deploy:
```bash
supabase functions deploy send-push
supabase functions deploy ai-proxy
```

## Environment Variables (Supabase Dashboard > Edge Functions > Secrets):
- `SUPABASE_URL` (otomatik var)
- `SUPABASE_SERVICE_ROLE_KEY` (otomatik var)
- `FCM_SERVER_KEY` — Firebase Console > Project Settings > Cloud Messaging > Server Key
- `GEMINI_API_KEY` — Google AI Studio > API Keys
- `GEMINI_MODEL` — default: gemini-2.5-flash

## send-push: FCM Push Notification
- **Trigger:** Database Webhook on outbound_queue INSERT
- **Webhook kurlumu:** Supabase Dashboard > Database > Webhooks
  - Table: outbound_queue, Events: INSERT, Function: send-push
- **Akis:** mesaj → DB trigger → outbound_queue → Webhook → Edge Function → FCM

## ai-proxy: Gemini API Proxy
- **Trigger:** Flutter client dogrudan cagirir
- **URL:** `https://<project>.supabase.co/functions/v1/ai-proxy`
- **Headers:** `x-user-id: <firebase-uid>`
- **Body:** `{ messages: [...], image_base64?: string, stream?: boolean }`
- **Rate limit:** 30 istek/saat per kullanici
- **Akis:** Flutter → Edge Function → Gemini API (API key gizli)

## Test:
```bash
# Push test
curl -X POST https://<project>.supabase.co/functions/v1/send-push \
  -H "Content-Type: application/json" \
  -d '{"record": {"id":"test","channel":"fcm_push","user_id":"uid","title":"Test","body":"Merhaba","payload":{},"attempts":0}}'

# AI proxy test
curl -X POST https://<project>.supabase.co/functions/v1/ai-proxy \
  -H "Content-Type: application/json" \
  -H "x-user-id: test-uid" \
  -d '{"messages": [{"role":"user","content":"Merhaba"}]}'
```
