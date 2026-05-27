-- Convert SECURITY DEFINER views to SECURITY INVOKER.
-- Definer views run with the view-owner's privileges, bypassing RLS of the
-- caller. Invoker mode makes the view honor the caller's RLS, which is the
-- correct default for user-facing aggregates over user-owned rows.

ALTER VIEW public.v_user_pro_status SET (security_invoker = on);
ALTER VIEW public.v_designer_stats  SET (security_invoker = on);
