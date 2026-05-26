-- koala_user_profiles: avatar_url kolonu + upsert RPC'ye avatar parametresi.
-- Bucket: `avatars` (zaten mevcut, public read, anon insert/update policy var).
-- Path konvansiyonu: {firebase_uid}/avatar.webp (upsert ile overwrite).

alter table public.koala_user_profiles
  add column if not exists avatar_url text;

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
    display_name = excluded.display_name,
    about = excluded.about,
    contact_info = excluded.contact_info,
    avatar_url = case when p_set_avatar then excluded.avatar_url
                      else koala_user_profiles.avatar_url end,
    updated_at = now();
  return jsonb_build_object('ok', true);
end; $function$;
