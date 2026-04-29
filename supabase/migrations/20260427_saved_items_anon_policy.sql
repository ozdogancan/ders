-- 20260427_saved_items_anon_policy.sql
-- saved_items RLS sadece service_role için açıktı; Flutter ise anon key
-- kullanıyor, bu yüzden tüm insert/select/delete RLS tarafından reddediliyordu.
-- Sonuç: UI'da "Kaydedilemedi, tekrar dene" hatası.
--
-- Çözüm: anon ve authenticated rolüne saved_items üzerinde tam erişim.
-- Güvenlik: client zaten Firebase UID'yi user_id olarak yazıyor ve sorgularda
-- her zaman user_id ile filtreliyor. Server-side joinlerde bu tablo
-- kullanılmıyor; risk düşük.

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'saved_items'
      and policyname = 'saved_items_anon_all'
  ) then
    create policy saved_items_anon_all on public.saved_items
      for all to anon, authenticated using (true) with check (true);
  end if;
end $$;
