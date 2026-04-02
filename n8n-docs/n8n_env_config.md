# n8n Environment Config

## Environment Variables
```
EXECUTIONS_MODE=regular
EXECUTIONS_TIMEOUT=30
EXECUTIONS_TIMEOUT_MAX=60
N8N_CONCURRENCY_PRODUCTION_LIMIT=1
N8N_PAYLOAD_SIZE_MAX=1
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=72
NODE_OPTIONS=--max-old-space-size=384
```

## Schedule Haritasi (UTC+3)
```
03:00  WF2 Daily Scheduler (~40sn)
*/5dk  WF1 Email Sender (~10sn, cogu bos doner)
```

## Kaynak Butcesi
```
n8n process:     ~200MB RAM
WF1 execution:   ~30MB (3 email max)
WF2 execution:   ~50MB (RPC cagrilari)
Toplam peak:     ~280MB
Sunucu:          1GB RAM + 1GB Swap = guvenli
```

## Mimari Ozet
```
PUSH:  DB trigger → outbound_queue → DB Webhook → Edge Function → FCM (<1sn)
EMAIL: DB trigger/RPC → outbound_queue → n8n poll (5dk) → Resend API
CRON:  n8n gunluk 03:00 → DB fonksiyonlarini RPC ile tetikle
```

n8n sadece 2 workflow calistiriyor. Tum is mantigi DB fonksiyonlarinda.
