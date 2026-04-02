-- ═══════════════════════════════════════════════════════════
-- 018_outbound_queue.sql — Dışarıya gönderilecek mesaj kuyruğu
-- DB trigger doldurur, Edge Function (push) ve n8n (email) tüketir
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.outbound_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel TEXT NOT NULL CHECK (channel IN ('fcm_push', 'email', 'sms')),
  user_id TEXT NOT NULL,
  title TEXT,
  body TEXT,
  payload JSONB,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 3,
  last_error TEXT,
  send_after TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ
);

CREATE INDEX idx_outbound_pending ON outbound_queue(status, send_after) WHERE status = 'pending';
CREATE INDEX idx_outbound_cleanup ON outbound_queue(status, processed_at) WHERE status IN ('sent', 'failed');

ALTER TABLE public.outbound_queue ENABLE ROW LEVEL SECURITY;

-- Trigger'lar (SECURITY DEFINER) INSERT yapabilsin, client okuyamasın
CREATE POLICY "outbound_queue_anon_insert" ON public.outbound_queue FOR INSERT WITH CHECK (true);
CREATE POLICY "outbound_queue_anon_read" ON public.outbound_queue FOR SELECT USING (false);

COMMENT ON TABLE public.outbound_queue IS 'Dışarıya gönderilecek mesaj kuyruğu. DB trigger doldurur, Edge Function (push) ve n8n (email) tüketir.';
