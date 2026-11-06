-- My Account: each person's own profile, look, sign-in history, data export and deletion request.
-- Run after 20261106000000_init.sql. Paste into Supabase > SQL Editor > Run.
-- Same rule as before: apps cannot touch tables, only these checked functions.

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text check (full_name is null or length(trim(full_name)) >= 2),
  phone text,
  avatar text check (avatar is null or length(avatar) <= 200000), -- small JPEG as base64, about 150 KB at most
  theme text not null default 'system' check (theme in ('system','light','dark')),
  text_scale numeric(3,2) not null default 1.00 check (text_scale between 0.85 and 1.60),
  language text not null default 'en' check (language in ('en','lg','sw')),
  updated_at timestamptz not null default now()
);

-- Written by the app after each sign-in. Shows the person where their account was used.
create table public.sign_in_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (length(platform) <= 40),
  device text check (device is null or length(device) <= 200),
  created_at timestamptz not null default now()
);
create index sign_in_events_user on public.sign_in_events(user_id, created_at desc);

-- Money records are never deleted: groups must keep proof. A request closes the account and
-- removes personal extras (photo, phone, profile); the names on past records stay.
create table public.deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text,
  status text not null default 'pending' check (status in ('pending','cancelled','done')),
  requested_at timestamptz not null default now(),
  handled_by uuid references auth.users(id),
  handled_at timestamptz,
  handled_note text
);
create unique index one_open_deletion_request on public.deletion_requests(user_id) where status = 'pending';

create function public.get_my_account() returns jsonb
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
    'is_platform_admin', public.is_platform_admin(),
    'memberships', (select coalesce(jsonb_agg(jsonb_build_object(
        'org_id', o.id, 'org_name', o.name, 'member_no', m.member_no, 'role', m.role, 'is_active', m.is_active,
        'consent_at', m.consent_at, 'joined_at', m.joined_at) order by o.name), '[]'::jsonb)
      from members m join organizations o on o.id = m.org_id where m.user_id = v_uid),
    'sign_ins', (select coalesce(jsonb_agg(jsonb_build_object('platform', s.platform, 'device', s.device, 'at', s.created_at) order by s.created_at desc), '[]'::jsonb)
      from (select * from sign_in_events where user_id = v_uid order by created_at desc limit 20) s),
    'deletion_request', (select to_jsonb(d) - 'user_id' - 'handled_by' from deletion_requests d where d.user_id = v_uid order by requested_at desc limit 1));
end $$;

create function public.update_my_profile(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r record; v_name text; v_phone text;
begin
  if v_uid is null then raise exception 'Please sign in first.'; end if;
  if p ? 'full_name' and length(trim(coalesce(p->>'full_name',''))) < 2 then raise exception 'Name needs at least 2 letters.'; end if;
  if p ? 'phone' and coalesce(p->>'phone','') <> '' and length(public.normalize_phone(p->>'phone')) not between 11 and 13 then
    raise exception 'Phone looks wrong. Use a number like 0772 123456.';
  end if;
  insert into profiles(user_id) values (v_uid) on conflict (user_id) do nothing;
  update profiles set
    full_name = case when p ? 'full_name' then trim(p->>'full_name') else full_name end,
    phone = case when p ? 'phone' then public.normalize_phone(p->>'phone') else phone end,
    avatar = case when p ? 'avatar' then nullif(p->>'avatar','') else avatar end,
    theme = coalesce(p->>'theme', theme),
    text_scale = coalesce((p->>'text_scale')::numeric, text_scale),
    language = coalesce(p->>'language', language),
    updated_at = now()
  where user_id = v_uid;
  -- Optional: copy my new name and phone onto my member card in every group. Each group's audit trail shows it.
  if coalesce((p->>'apply_to_groups')::boolean, false) then
    select full_name, phone into v_name, v_phone from profiles where user_id = v_uid;
    for r in select * from members where user_id = v_uid and is_active loop
      begin
        update members set full_name = coalesce(v_name, full_name), phone = coalesce(v_phone, phone) where id = r.id;
      exception when unique_violation then
        raise exception 'Another member of % already uses this phone number.', (select name from organizations where id = r.org_id);
      end;
      perform public.add_audit(r.org_id, 'UPDATE_OWN_DETAILS', 'member', r.id::text,
        'Was: ' || r.full_name || coalesce(' / ' || r.phone, '') || '. Now: ' || coalesce(v_name, r.full_name) || coalesce(' / ' || v_phone, ''),
        coalesce(v_name, r.full_name));
    end loop;
  end if;
end $$;

create function public.record_sign_in(p_platform text, p_device text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into sign_in_events(user_id, platform, device) values (auth.uid(), left(coalesce(p_platform,'unknown'),40), left(p_device,200));
  -- Keep only the latest 50 per person.
  delete from sign_in_events where user_id = auth.uid() and id not in
    (select id from sign_in_events where user_id = auth.uid() order by created_at desc limit 50);
end $$;

-- Everything the platform holds about me, in one file.
create function public.export_my_data() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Please sign in first.'; end if;
  return jsonb_build_object(
    'exported_at', now(),
    'note', 'SACCO Ledger keeps records only. It never held your money.',
    'account', public.get_my_account() - 'avatar',
    'groups', (select coalesce(jsonb_agg(jsonb_build_object(
        'group', o.name,
        'member', to_jsonb(m) - 'invite_code' - 'invite_expires_at' - 'code_attempts' - 'user_id',
        'statement', public.member_statement(o.id, m.id),
        'payment_records', (select coalesce(jsonb_agg(to_jsonb(x) - 'idempotency_key' order by x.submitted_at), '[]'::jsonb) from payment_records x where x.member_id = m.id or x.submitted_by = m.id),
        'loans', (select coalesce(jsonb_agg(to_jsonb(l) order by l.requested_at), '[]'::jsonb) from loans l where l.member_id = m.id),
        'emergency_claims', (select coalesce(jsonb_agg(to_jsonb(c) order by c.requested_at), '[]'::jsonb) from emergency_claims c where c.member_id = m.id)
      ) order by o.name), '[]'::jsonb)
      from members m join organizations o on o.id = m.org_id where m.user_id = v_uid and m.is_active));
end $$;

create function public.request_account_deletion(p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if exists(select 1 from deletion_requests where user_id = auth.uid() and status = 'pending') then
    raise exception 'You already asked. We will handle it soon.';
  end if;
  insert into deletion_requests(user_id, reason) values (auth.uid(), nullif(trim(p_reason),''));
end $$;

create function public.cancel_account_deletion() returns void
language plpgsql security definer set search_path = public as $$
begin
  update deletion_requests set status = 'cancelled', handled_at = now() where user_id = auth.uid() and status = 'pending';
end $$;

create function public.list_deletion_requests() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(d) || jsonb_build_object(
      'sign_in_id', (select email from auth.users where id = d.user_id),
      'name', (select coalesce(p.full_name, (select full_name from members where user_id = d.user_id limit 1)) from (select 1) z left join profiles p on p.user_id = d.user_id),
      'groups', (select count(*) from members where user_id = d.user_id and is_active)) order by d.requested_at desc), '[]'::jsonb)
    from deletion_requests d where d.status = 'pending' or d.handled_at > now() - interval '30 days');
end $$;

-- Closes the account: leaves every group, removes photo, phone and profile. Money records stay as proof.
create function public.complete_account_deletion(p_request uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare d deletion_requests; r record;
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  select * into d from deletion_requests where id = p_request for update;
  if d.id is null or d.status <> 'pending' then raise exception 'This request is not pending.'; end if;
  for r in select * from members where user_id = d.user_id loop
    update members set is_active = false, user_id = null, phone = null, national_id = null, next_of_kin_name = null, next_of_kin_phone = null where id = r.id;
    perform public.add_audit(r.org_id, 'ACCOUNT_DELETED', 'member', r.id::text, 'Member closed their account. Past records kept as proof.', 'Platform Admin');
  end loop;
  delete from profiles where user_id = d.user_id;
  delete from sign_in_events where user_id = d.user_id;
  update deletion_requests set status = 'done', handled_by = auth.uid(), handled_at = now(), handled_note = nullif(trim(p_note),'') where id = d.id;
end $$;

do $$
declare t text; f record;
begin
  foreach t in array array['profiles','sign_in_events','deletion_requests'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, public, authenticated', t);
  end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('get_my_account','update_my_profile','record_sign_in','export_my_data','request_account_deletion','cancel_account_deletion','list_deletion_requests','complete_account_deletion') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
