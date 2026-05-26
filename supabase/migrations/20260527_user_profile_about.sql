-- Fix: koala_user_profile_upsert overload ambiguity.
--
-- Tablo `koala_user_profiles` zaten `about` kolonuna sahip; sorun RPC
-- tarafında: hem 4-arg eski sürüm hem 6-arg yeni sürüm (avatar parametreli)
-- DB'de aynı anda mevcut. PostgREST `(p_uid, p_display_name, p_about,
-- p_contact)` çağrısında hangi overload'ı seçeceğine karar veremiyor
-- (PGRST203). Bu yüzden "Profili düzenle" sheet'i "Kaydedilemedi, tekrar
-- dene" hatası veriyor.
--
-- Çözüm: eski 4-arg overload'ı drop'la, yalnız 6-arg sürüm kalsın
-- (p_avatar_url + p_set_avatar DEFAULT'lu, geriye uyumlu).

drop function if exists public.koala_user_profile_upsert(
  text, text, text, jsonb
);

-- 6-arg sürümü idempotent tekrar oluştur (DB'de zaten var ama güvenli).
create or replace function public.koala_user_profile_upsert(
  p_uid text,
  p_display_name text,
  p_about text,
  p_contact jsonb,
  p_avatar_url text default null,
  p_set_avatar boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if p_uid is null or p_uid = '' then
    return jsonb_build_object('error','missing_uid');
  end if;
  insert into koala_user_profiles
    (uid, display_name, about, contact_info, avatar_url, updated_at)
  values
    (p_uid, p_display_name, p_about, coalesce(p_contact, '{}'::jsonb),
     case when p_set_avatar then p_avatar_url else null end,
     now())
  on conflict (uid) do update set
    display_name = coalesce(excluded.display_name,
                            koala_user_profiles.display_name),
    about = coalesce(excluded.about, koala_user_profiles.about),
    contact_info = coalesce(excluded.contact_info,
                            koala_user_profiles.contact_info),
    avatar_url = case when p_set_avatar then excluded.avatar_url
                      else koala_user_profiles.avatar_url end,
    updated_at = now();
  return jsonb_build_object('ok', true);
end; $function$;
