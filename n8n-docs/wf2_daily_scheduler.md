# WF2: Daily Scheduler

Tetikleyici: Schedule — her gun 03:00 (`0 3 * * *`)

## Adimlar

1. **[Supabase Node]** RPC: `SELECT fn_daily_cleanup()` (timeout: 10sn)
2. **[Wait]** 5sn
3. **[Supabase Node]** RPC: `SELECT fn_compute_popular()` (timeout: 10sn)
4. **[Wait]** 5sn
5. **[Supabase Node]** RPC: `SELECT fn_engagement_push()` (timeout: 10sn)
6. **[IF]** Bugun Pazartesi mi?
   - TRUE: **[Supabase]** RPC: `SELECT fn_weekly_digest()`
7. **[Wait]** 5sn
8. **[Supabase Node]** RPC: `SELECT fn_health_report()`
9. **[IF]** Herhangi tablo > 50000 satir?
   - TRUE: admin'e `koala_notifications` INSERT
10. **[Supabase]** `analytics_events` INSERT:
    ```json
    {"event": "daily_scheduler", "metadata": "<tum sonuclar>"}
    ```

## Error Handling
Her adimda Error Handler: hata olursa logla, sonraki adima devam et.

## Notlar
- Toplam sure: ~40sn
- ~50MB RAM per execution
- Tum is DB tarafinda yapiliyor (RPC), n8n sadece tetikliyor
