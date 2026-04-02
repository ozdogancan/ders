# Koala Backend Mimarisi

## Sorumluluk Paylasimi

| Akis | Tetikleyici | Islem | Sorumlu |
|------|------------|-------|---------|
| Mesaj push | koala_direct_messages INSERT | DB trigger → outbound_queue → DB Webhook → Edge Function → FCM | Supabase (trigger + Edge Function) |
| Hosgeldin email | users INSERT | DB trigger → outbound_queue (5dk delay) → n8n poll → Resend | Supabase trigger + n8n |
| Engagement push | fn_engagement_push() RPC | DB fonksiyonu → outbound_queue → Edge Function → FCM | n8n tetikler, Supabase yapar |
| Haftalik ozet | fn_weekly_digest() RPC | DB fonksiyonu → outbound_queue → n8n poll → Resend | n8n tetikler, Supabase yapar |
| Gunluk temizlik | fn_daily_cleanup() RPC | DB fonksiyonu (DELETE/UPDATE) | n8n tetikler |
| Populer icerik | fn_compute_popular() RPC | DB fonksiyonu (INSERT/UPDATE popular_content) | n8n tetikler |
| Saglik raporu | fn_health_report() RPC | DB fonksiyonu (COUNT sorgulari) | n8n tetikler |

## Akis Diyagramlari

### Push Notification (<1sn)
```
Mesaj INSERT
  → trg_message_push (DB trigger)
    → outbound_queue INSERT (channel='fcm_push')
      → DB Webhook
        → send-push Edge Function
          → FCM API → Kullanicinin telefonu
```

### Email (5dk poll)
```
users INSERT / fn_weekly_digest() / fn_engagement_push()
  → outbound_queue INSERT (channel='email', send_after=...)
    → n8n WF1 (her 5dk poll)
      → Resend API → Kullanicinin emaili
```

### Cron (gunluk 03:00)
```
n8n WF2 Schedule
  → fn_daily_cleanup() RPC
  → fn_compute_popular() RPC
  → fn_engagement_push() RPC
  → fn_weekly_digest() RPC (sadece Pazartesi)
  → fn_health_report() RPC
```

## n8n Workflow'lari
- **WF1 Email Sender**: her 5dk, outbound_queue'dan email gonder (max 3 per run)
- **WF2 Daily Scheduler**: her gun 03:00, DB fonksiyonlarini sirayla cagir

## Supabase Edge Functions
- **send-push**: outbound_queue INSERT webhook → FCM push gonderim

## Onemli Kurallar
- n8n HICBIR push gondermez (Edge Function yapar)
- n8n HICBIR karar mantigi calistirmaz (DB fonksiyonlari yapar)
- n8n sadece poll + RPC tetikleyici
- Tum is mantigi DB tarafinda (trigger + fonksiyon)
