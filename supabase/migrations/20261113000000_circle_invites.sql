-- My circles and circle invitations.
-- 1. Every person sees the circles they are in, with their role in each.
-- 2. A circle's admin or secretary, or the platform team, invites a person by email.
--    The person sees the invitation in the app, or opens a link with its code, reads the circle's
--    details and chooses to join. Their name and phone come from their own profile, and they can fix them first.
-- Nobody is ever added to a circle without saying yes. Every step is in the circle's audit trail.
-- Run after 20261110000000_look.sql.

create table public.circle_invites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  code text not null unique,
  email text not null check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role text not null default 'member' check (role in ('org_admin','treasurer','secretary','loan_officer','auditor','member')),
  message text check (message is null or length(message) <= 280),
  invited_by uuid references auth.users(id),
  invited_by_name text,
  via text not null check (via in ('group','platform')),
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  member_id uuid references public.members(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  responded_at timestamptz
);
create index circle_invites_email on public.circle_invites(email) where status = 'pending';
create index circle_invites_org on public.circle_invites(org_id, created_at desc);
create index circle_invites_by on public.circle_invites(invited_by, created_at desc);

-- Only the functions below may touch invitations.
alter table public.circle_invites enable row level security;
revoke all on public.circle_invites from anon, public, authenticated;

create function public.my_email() returns text language sql stable security definer set search_path = public as $$
  select lower(email) from auth.users where id = auth.uid();
$$;

-- "da•••@gmail.com": enough to recognise your own address, not enough to learn someone else's.
create function public.mask_email(p text) returns text language sql immutable set search_path = public as $$
  select left(split_part(p, '@', 1), 2) || '•••@' || split_part(p, '@', 2);
$$;

-- What a person sees about an invitation: the circle, who asked, and as what.
create function public.invite_view(ci public.circle_invites) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', ci.id, 'code', ci.code, 'role', ci.role, 'message', ci.message,
    'invited_by', coalesce(ci.invited_by_name, 'The circle'), 'via', ci.via,
    'created_at', ci.created_at, 'expires_at', ci.expires_at,
    'org_id', o.id, 'org_name', o.name, 'edition', o.edition, 'currency_code', o.currency_code,
    'country_code', o.country_code, 'cycle_number', o.cycle_number,
    'people', (select count(*) from members m where m.org_id = o.id and m.is_active),
    'admin_name', (select m.full_name from members m where m.org_id = o.id and m.role = 'org_admin' and m.is_active order by m.member_no limit 1))
  from organizations o where o.id = ci.org_id;
$$;

-- Finds a pending invitation by its code and checks it belongs to the signed-in person. Raises the reason if not.
create function public.my_invite_by_code(p_code text, p_lock boolean default false) returns public.circle_invites
language plpgsql security definer set search_path = public as $$
declare ci circle_invites;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if p_lock then
    select * into ci from circle_invites where code = upper(trim(coalesce(p_code,''))) for update;
  else
    select * into ci from circle_invites where code = upper(trim(coalesce(p_code,'')));
  end if;
  if ci.id is null then return null; end if;
  if ci.status = 'accepted' then raise exception 'This invitation was already used.'; end if;
  if ci.status = 'declined' then raise exception 'This invitation was turned down. Ask for a new one.'; end if;
  if ci.status = 'cancelled' then raise exception 'This invitation was cancelled. Ask for a new one.'; end if;
  if ci.expires_at <= now() then raise exception 'This invitation has expired. Ask for a new one.'; end if;
  if ci.email <> public.my_email() then
    raise exception 'This invitation was sent to %. Sign in with that account to open it.', public.mask_email(ci.email);
  end if;
  return ci;
end $$;

-- ========== Invite ==========
create function public.invite_to_circle(p_org uuid, p_email text, p_role text, p_message text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(coalesce(p_email,'')));
  v_role text := coalesce(nullif(trim(p_role),''), 'member');
  v_mine text; v_platform boolean := public.is_platform_admin();
  o organizations; v_user uuid; v_name text; v_code text; v_id uuid; v_via text; v_exp timestamptz;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  select * into o from organizations where id = p_org;
  if o.id is null then raise exception 'Circle not found.'; end if;
  if o.is_demo then raise exception 'The shared demo cannot take invitations. Invite people to a real circle.'; end if;
  select role into v_mine from members where org_id = p_org and user_id = auth.uid() and is_active;
  if coalesce(v_mine,'') not in ('org_admin','secretary') and not v_platform then
    raise exception 'Only this circle''s admin or secretary can invite people.';
  end if;
  if v_role not in ('org_admin','treasurer','secretary','loan_officer','auditor','member') then raise exception 'Pick a role.'; end if;
  if v_role <> 'member' and coalesce(v_mine,'') <> 'org_admin' and not v_platform then
    raise exception 'Only the circle admin can invite someone as an officer.';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid email.'; end if;
  if length(coalesce(p_message,'')) > 280 then raise exception 'Keep the message under 280 letters.'; end if;
  select id into v_user from auth.users where lower(email) = v_email;
  if v_user is not null and exists(select 1 from members where org_id = p_org and user_id = v_user and is_active) then
    raise exception 'This person is already in this circle.';
  end if;
  if (select count(*) from circle_invites where invited_by = auth.uid() and created_at > now() - interval '1 day') >= 50 then
    raise exception 'That is a lot of invitations for one day. Try again tomorrow.';
  end if;

  -- A new invitation replaces an older one to the same person, so only one link works.
  update circle_invites set status = 'cancelled', responded_at = now() where org_id = p_org and email = v_email and status = 'pending';

  v_via := case when v_mine in ('org_admin','secretary') then 'group' else 'platform' end;
  v_name := coalesce(
    (select full_name from members where org_id = p_org and user_id = auth.uid() and is_active),
    nullif(trim((select full_name from profiles where user_id = auth.uid())), ''),
    'The SACCO Ledger team');
  loop
    v_code := public.new_code();
    exit when not exists(select 1 from circle_invites where code = v_code) and not exists(select 1 from members where invite_code = v_code);
  end loop;
  insert into circle_invites(org_id, code, email, role, message, invited_by, invited_by_name, via)
  values (p_org, v_code, v_email, v_role, nullif(trim(p_message),''), auth.uid(), v_name, v_via)
  returning id, expires_at into v_id, v_exp;
  perform public.add_audit(p_org, 'INVITE_TO_CIRCLE', 'invite', v_id::text,
    public.mask_email(v_email) || ' invited as ' || v_role || case when v_via = 'platform' then ' by the platform team' else '' end, v_name);
  return jsonb_build_object('id', v_id, 'code', v_code, 'email', v_email, 'role', v_role, 'expires_at', v_exp,
    'has_account', v_user is not null, 'org_name', o.name);
end $$;

-- ========== The invited person ==========
-- My open invitations, newest first. Circles I am already in are left out.
create function public.my_invites() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_email text := public.my_email();
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  return (select coalesce(jsonb_agg(public.invite_view(ci) order by ci.created_at desc), '[]'::jsonb)
    from circle_invites ci
    where ci.email = v_email and ci.status = 'pending' and ci.expires_at > now()
      and not exists(select 1 from members m where m.org_id = ci.org_id and m.user_id = auth.uid() and m.is_active));
end $$;

-- One invitation from its code (typed, or from a link). Null when no invitation has this code.
create function public.invite_details(p_code text) returns jsonb language plpgsql security definer set search_path = public as $$
declare ci circle_invites;
begin
  ci := public.my_invite_by_code(p_code);
  if ci.id is null then return null; end if;
  return public.invite_view(ci) || jsonb_build_object('already_member',
    exists(select 1 from members m where m.org_id = ci.org_id and m.user_id = auth.uid() and m.is_active));
end $$;

-- Say yes. Name and phone default to the person's profile.
-- If the circle already wrote this person down by phone (no account yet), that record is theirs: it keeps their history.
create function public.accept_circle_invite(p_code text, p_name text, p_phone text, p_consent boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare ci circle_invites; v_name text; v_phone text; m members; v_no int; v_id uuid; v_how text;
begin
  if not coalesce(p_consent, false) then raise exception 'Please accept the data notice first.'; end if;
  ci := public.my_invite_by_code(p_code, true);
  if ci.id is null then raise exception 'This code is wrong or has expired. Ask for a new one.'; end if;
  v_name := trim(coalesce(nullif(trim(p_name),''), (select full_name from profiles where user_id = auth.uid()), ''));
  if length(v_name) < 2 then raise exception 'Write your name.'; end if;
  v_phone := public.normalize_phone(coalesce(nullif(trim(p_phone),''), (select phone from profiles where user_id = auth.uid())));

  perform pg_advisory_xact_lock(hashtext('member' || ci.org_id::text));
  select * into m from members where org_id = ci.org_id and user_id = auth.uid();
  if m.id is not null then
    if m.is_active then raise exception 'You are already in this circle.'; end if;
    update members set is_active = true, role = ci.role, full_name = v_name, consent_at = now() where id = m.id;
    v_id := m.id; v_how := 'came back';
  else
    if v_phone is not null then
      select * into m from members where org_id = ci.org_id and phone = v_phone;
    end if;
    if m.id is not null then
      if m.user_id is not null then
        raise exception 'Another member of this circle already uses this phone number. Change the phone, or ask the circle''s secretary.';
      end if;
      update members set user_id = auth.uid(), is_active = true, consent_at = now(), invite_code = null, invite_expires_at = null,
        role = case when ci.role = 'member' then role else ci.role end
      where id = m.id;
      v_id := m.id; v_how := 'linked their account to their existing record';
    else
      select coalesce(max(member_no),0) + 1 into v_no from members where org_id = ci.org_id;
      insert into members(org_id, member_no, full_name, phone, role, user_id, consent_at)
      values (ci.org_id, v_no, v_name, v_phone, ci.role, auth.uid(), now())
      returning id into v_id;
      v_how := 'joined';
    end if;
  end if;

  update circle_invites set status = 'accepted', responded_at = now(), member_id = v_id where id = ci.id;
  perform public.add_audit(ci.org_id, 'JOIN_BY_INVITE', 'member', v_id::text,
    v_name || ' ' || v_how || ' as ' || ci.role || ' (invited by ' || coalesce(ci.invited_by_name, 'the circle') || ')', v_name);
  return ci.org_id;
end $$;

create function public.decline_circle_invite(p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare ci circle_invites;
begin
  ci := public.my_invite_by_code(p_code, true);
  if ci.id is null then raise exception 'This code is wrong or has expired.'; end if;
  update circle_invites set status = 'declined', responded_at = now() where id = ci.id;
  perform public.add_audit(ci.org_id, 'DECLINE_INVITE', 'invite', ci.id::text, public.mask_email(ci.email) || ' said no, thank you', public.mask_email(ci.email));
end $$;

-- ========== The circle's side ==========
-- Invitations of one circle, for its admin and secretary (and the platform team).
create function public.list_circle_invites(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.org_role(p_org),'') not in ('org_admin','secretary','platform_admin') then
    raise exception 'Only this circle''s admin or secretary can see its invitations.';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', ci.id, 'email', ci.email, 'role', ci.role, 'invited_by', ci.invited_by_name, 'via', ci.via,
      'status', case when ci.status = 'pending' and ci.expires_at <= now() then 'expired' else ci.status end,
      'code', case when ci.status = 'pending' and ci.expires_at > now() then ci.code end,
      'created_at', ci.created_at, 'expires_at', ci.expires_at, 'responded_at', ci.responded_at) order by ci.created_at desc), '[]'::jsonb)
    from (select * from circle_invites where org_id = p_org order by created_at desc limit 50) ci);
end $$;

create function public.cancel_circle_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ci circle_invites;
begin
  select * into ci from circle_invites where id = p_invite for update;
  if ci.id is null or ci.status <> 'pending' then raise exception 'This invitation is not open.'; end if;
  if ci.invited_by is distinct from auth.uid() and coalesce(public.org_role(ci.org_id),'') not in ('org_admin','platform_admin') then
    raise exception 'Only the person who sent it, or the circle admin, can cancel it.';
  end if;
  update circle_invites set status = 'cancelled', responded_at = now() where id = ci.id;
  perform public.add_audit(ci.org_id, 'CANCEL_INVITE', 'invite', ci.id::text, public.mask_email(ci.email),
    coalesce((public.my_member(ci.org_id)).full_name, nullif(trim((select full_name from profiles where user_id = auth.uid())), ''), 'The SACCO Ledger team'));
end $$;

-- ========== My circles ==========
-- Same as before, plus how many people each circle has and when I joined, for the My circles page.
create or replace function public.my_memberships() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) from (
    select to_jsonb(o) || jsonb_build_object('my_role', m.role, 'my_member_id', m.id, 'my_name', m.full_name, 'joined_at', m.joined_at,
        'people', (select count(*) from members p where p.org_id = o.id and p.is_active)) as x
    from members m join organizations o on o.id = m.org_id where m.user_id = auth.uid() and m.is_active
    union all
    select to_jsonb(o) || jsonb_build_object('my_role','platform_admin','my_member_id',null,'my_name','Platform Admin',
        'people', (select count(*) from members p where p.org_id = o.id and p.is_active))
    from organizations o where public.is_platform_admin()
      and not exists (select 1 from members m where m.org_id = o.id and m.user_id = auth.uid() and m.is_active)
  ) s;
$$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('my_email','mask_email','invite_view','my_invite_by_code','invite_to_circle','my_invites','invite_details',
    'accept_circle_invite','decline_circle_invite','list_circle_invites','cancel_circle_invite','my_memberships') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    if f.proname in ('my_email','mask_email','invite_view','my_invite_by_code') then
      execute format('revoke all on function %s from authenticated', f.sig);
    else
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
