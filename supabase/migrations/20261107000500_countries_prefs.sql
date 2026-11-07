-- Countries (Uganda, Kenya, Tanzania, Rwanda) and personal app preferences.
-- Run after 20261107000400_online_payments.sql.

-- ========== 1. A GROUP'S COUNTRY ==========
-- Sets the phone code (+256, +254, +255, +250). Money stays in the group's currency.
alter table public.organizations add column country_code text not null default 'UG'
  check (country_code in ('UG','KE','TZ','RW'));
update public.organizations set country_code = case currency_code
  when 'KES' then 'KE' when 'TZS' then 'TZ' when 'RWF' then 'RW' else 'UG' end;

create function public.set_org_country(p_org uuid, p_country text) returns void
language plpgsql security definer set search_path = public as $$
declare me members;
begin
  me := public.require_role(p_org, array['org_admin']);
  if p_country not in ('UG','KE','TZ','RW') then raise exception 'Choose Uganda, Kenya, Tanzania or Rwanda.'; end if;
  update organizations set country_code = p_country where id = p_org;
  perform public.add_audit(p_org, 'SET_COUNTRY', 'organization', p_org::text, p_country, me.full_name);
end $$;

-- ========== 2. PERSONAL PREFERENCES ==========
-- country: phone code at sign-in. show_tips: the (i) explanations. tour_done: welcome tour finished or skipped.
alter table public.profiles add column prefs jsonb not null default '{}'::jsonb;

create function public.update_my_prefs(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if p ? 'country' then
    if p->>'country' not in ('UG','KE','TZ','RW') then raise exception 'Unknown country.'; end if;
    v := v || jsonb_build_object('country', p->>'country');
  end if;
  if p ? 'show_tips' then v := v || jsonb_build_object('show_tips', (p->>'show_tips')::boolean); end if;
  if p ? 'tour_done' then v := v || jsonb_build_object('tour_done', (p->>'tour_done')::boolean); end if;
  insert into profiles(user_id) values (auth.uid()) on conflict (user_id) do nothing;
  update profiles set prefs = prefs || v, updated_at = now() where user_id = auth.uid();
end $$;

create or replace function public.get_my_account() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); p profiles;
begin
  if v_uid is null then raise exception 'Please sign in first.'; end if;
  select * into p from profiles where user_id = v_uid;
  return jsonb_build_object(
    'sign_in_id', (select email from auth.users where id = v_uid),
    'full_name', coalesce(p.full_name, (select full_name from members where user_id = v_uid order by joined_at limit 1)),
    'phone', coalesce(p.phone, (select phone from members where user_id = v_uid and phone is not null order by joined_at limit 1)),
    'avatar', p.avatar,
    'theme', coalesce(p.theme, 'system'),
    'text_scale', coalesce(p.text_scale, 1.00),
    'language', coalesce(p.language, 'en'),
    'prefs', coalesce(p.prefs, '{}'::jsonb),
    'is_platform_admin', public.is_platform_admin(),
    'memberships', (select coalesce(jsonb_agg(jsonb_build_object(
        'org_id', o.id, 'org_name', o.name, 'member_no', m.member_no, 'role', m.role, 'is_active', m.is_active,
        'consent_at', m.consent_at, 'joined_at', m.joined_at) order by o.name), '[]'::jsonb)
      from members m join organizations o on o.id = m.org_id where m.user_id = v_uid),
    'sign_ins', (select coalesce(jsonb_agg(jsonb_build_object('platform', s.platform, 'device', s.device, 'at', s.created_at) order by s.created_at desc), '[]'::jsonb)
      from (select * from sign_in_events where user_id = v_uid order by created_at desc limit 20) s),
    'deletion_request', (select to_jsonb(d) - 'user_id' - 'handled_by' from deletion_requests d where d.user_id = v_uid order by requested_at desc limit 1));
end $$;

revoke all on function public.set_org_country(uuid, text) from public, anon;
revoke all on function public.update_my_prefs(jsonb) from public, anon;
grant execute on function public.set_org_country(uuid, text) to authenticated;
grant execute on function public.update_my_prefs(jsonb) to authenticated;
