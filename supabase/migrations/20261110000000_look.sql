-- A person can pick how the app looks: 'emerald' (green and gold) or 'passbook' (ink blue on paper).
-- Saved with their other preferences, so it follows them to any phone.
-- Run after 20261107000800_real_emails.sql.

create or replace function public.update_my_prefs(p jsonb) returns void
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
  if p ? 'look' then
    if p->>'look' not in ('emerald','passbook') then raise exception 'Unknown look.'; end if;
    v := v || jsonb_build_object('look', p->>'look');
  end if;
  insert into profiles(user_id) values (auth.uid()) on conflict (user_id) do nothing;
  update profiles set prefs = prefs || v, updated_at = now() where user_id = auth.uid();
end $$;

revoke all on function public.update_my_prefs(jsonb) from public, anon;
grant execute on function public.update_my_prefs(jsonb) to authenticated;
