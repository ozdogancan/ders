# WF3: Error Alert (Opsiyonel)

## Amac
Herhangi bir WF hata verdiginde admin'e bildirim gonder.

## Tetikleyici
n8n Error Trigger node — tum workflow'lar icin otomatik

## Adimlar
1. **[Error Trigger]** — WF hata verdiginde cagirilir
2. **[Supabase Node]** koala_notifications INSERT:
   ```json
   {
     "user_id": "ADMIN_USER_ID",
     "type": "system",
     "title": "n8n Workflow Hatasi",
     "body": "{{$json.workflow.name}}: {{$json.error.message}}"
   }
   ```
3. **[HTTP Request]** Resend API ile admin'e email:
   - to: admin@evlumba.com
   - subject: "[ALERT] n8n: {{workflow_name}} failed"
   - body: error details

## Notlar
- Bu WF her zaman aktif olmali
- Error Trigger n8n'in built-in ozelligidir
- RAM etkisi minimal (~10MB per execution)

---

# WF4: Health Ping (Opsiyonel)

## Tetikleyici
Schedule — her 30 dakikada bir

## Adimlar
1. **[HTTP Request]** n8n healthz ping: GET http://localhost:5678/healthz
2. **[Supabase Node]** SELECT 1 FROM users LIMIT 1 (connection test)
3. **[Code Node]** process.memoryUsage() logla
4. **[IF]** RSS > 800MB → admin notification INSERT
5. **[IF]** Supabase fail → admin email alert

## Notlar
- Toplam sure: <5sn
- RAM: ~20MB
