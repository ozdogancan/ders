-- Push retention strategy — last_seen tracking + comeback notification flags.
--
-- Powers the daily Vercel Cron job (koala-api /api/cron/comeback-push) that
-- sends D1 / D7 / D14 / D30 comeback nudges and a Pro trial reminder at D3.
-- Writes are SERVER-ONLY via the service role (koala-api). Direct read/write
-- from anon / authenticated client is denied — the app never touches this
-- table directly; it only triggers a side-effecting upsert via the /api/user/touch
-- endpoint (or piggybacked on /api/billing/status).
--
-- Frequency cap: weekly_sent_count must stay < 2 per ISO week. The cron resets
-- the counter whenever weekly_sent_week changes (current ISO week).

CREATE TABLE IF NOT EXISTS public.koala_user_last_seen (
  uid                text PRIMARY KEY,
  last_seen_at       timestamptz NOT NULL DEFAULT now(),
  first_seen_at      timestamptz NOT NULL DEFAULT now(),
  push_token         text,
  d1_sent            boolean DEFAULT false,
  d7_sent            boolean DEFAULT false,
  d14_sent           boolean DEFAULT false,
  d30_sent           boolean DEFAULT false,
  pro_trial_sent     boolean DEFAULT false,
  weekly_sent_count  int     DEFAULT 0,
  weekly_sent_week   int     DEFAULT 0,
  opted_out          boolean DEFAULT false,
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Cron query: active rows ordered by last_seen_at, scanned for D1/D7/D14/D30 windows.
CREATE INDEX IF NOT EXISTS idx_koala_user_last_seen_active
  ON public.koala_user_last_seen (last_seen_at)
  WHERE opted_out = false;

-- ────────────────────────────────────────────────────────────────────────────
-- RLS: server-only. The service_role bypasses RLS automatically; anon and
-- authenticated roles get NO policy → all direct access is denied.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.koala_user_last_seen ENABLE ROW LEVEL SECURITY;

-- Explicit deny is implicit when RLS is enabled with zero policies for a role.
-- We add a no-op SELECT policy gated to service_role for documentation clarity.
DROP POLICY IF EXISTS koala_user_last_seen_service_all ON public.koala_user_last_seen;
CREATE POLICY koala_user_last_seen_service_all
  ON public.koala_user_last_seen
  AS PERMISSIVE
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- updated_at trigger so background scans can tell when row last mutated.
CREATE OR REPLACE FUNCTION public._koala_user_last_seen_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_koala_user_last_seen_touch
  ON public.koala_user_last_seen;
CREATE TRIGGER trg_koala_user_last_seen_touch
  BEFORE UPDATE ON public.koala_user_last_seen
  FOR EACH ROW EXECUTE FUNCTION public._koala_user_last_seen_touch();
