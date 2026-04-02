# WF1: Email Sender

Tetikleyici: Schedule — her 5 dakikada bir (`*/5 * * * *`)

## Adimlar

1. **[Supabase Node]** Kuyruktan email cek:
   ```sql
   SELECT id, user_id, title, body, payload
   FROM outbound_queue
   WHERE status = 'pending' AND channel = 'email' AND send_after <= now()
   ORDER BY created_at ASC LIMIT 3
   ```

2. **[IF Node]** Bossa → bitir

3. **[SplitInBatches Node]** batch size: 1

4. **[HTTP Request Node]** Resend API:
   - POST `https://api.resend.com/emails`
   - Headers: `Authorization: Bearer {{RESEND_API_KEY}}`
   - Body:
     ```json
     {
       "from": "Koala <noreply@evlumba.com>",
       "to": "{{$json.payload.email}}",
       "subject": "{{$json.title}}",
       "html": "<basit template - payload.template'e gore>"
     }
     ```
   - Timeout: 5 saniye

5. **[Supabase Node]** Basarili → `status='sent'`, `processed_at=now()`
   Hata → `attempts+1`, IF `attempts >= 3` → `status='failed'`

6. **[Wait Node]** 1 saniye (rate limit)

## Notlar
- Max 3 email per execution (RAM koruma)
- Cogu calisma bos doner (kuyruk bossa)
- ~30MB RAM per execution
