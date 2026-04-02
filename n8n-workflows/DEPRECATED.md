# DEPRECATED — Bu klasordeki JSON dosyalari artik kullanilmiyor

K iterasyonu ile mimari degisti:
- PUSH: DB trigger → outbound_queue → Supabase Edge Function → FCM
- EMAIL: DB trigger/RPC → outbound_queue → n8n poll → Resend API
- CRON: n8n → DB fonksiyonlarini RPC ile tetikle

Yeni mimari icin bkz:
- `n8n-docs/` — Aktif workflow dokumantasyonu
- `supabase-edge-functions/` — Push gonderim
- `koala-db/019-023` — Trigger ve fonksiyonlar

Bu klasordeki wf-*.json dosyalari referans olarak korunmustur.
Yeni ortamda IMPORT ETMEYIN.
