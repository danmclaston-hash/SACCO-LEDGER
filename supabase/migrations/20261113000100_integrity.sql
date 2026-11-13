-- Integrity fixes. Each one closes a way trust could be broken.
-- 1. Two-step sign-in: platform powers work only after an authenticator app code (aal2).
-- 2. The platform team cannot put anyone into a circle (themselves included) unless that circle's admin agrees.
-- 3. Officers cannot take over a member's account: email accounts reset only by a link to the member's own email;
--    phone accounts need two different officers, and the reset signs the account out everywhere.
-- 4. The shared demo no longer shows visitors each other's real names.
-- 5. Online payments are switched off until a lawyer confirms the rules. Nothing was connected.
-- Run after 20261113000000_circle_invites.sql.

-- ========== 1. Two-step sign-in for the platform team ==========
-- aal2 = signed in with password AND a code from an authenticator app.
create function public.mfa_ok() returns boolean language sql stable set search_path = public as $$
  select coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2';
$$;

create or replace function public.is_platform_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from platform_admins where user_id = auth.uid()) and public.mfa_ok();
$$;

create or replace function public.is_platform_owner() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from platform_admins where user_id = auth.uid() and role = 'owner') and public.mfa_ok();
$$;

-- For the app: am I on the platform team, and is my two-step sign-in done?
create function public.my_platform_status() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'team', exists(select 1 from platform_admins where user_id = auth.uid()),
    'role', (select role from platform_admins where user_id = auth.uid()),
    'two_step', public.mfa_ok());
$$;

-- ========== 2. Platform invitations wait for the circle's admin ==========
alter table public.circle_invites drop constraint circle_invites_status_check;
alter table public.circle_invites add constraint circle_invites_status_check
  check (status in ('awaiting_circle','pending','accepted','declined','cancelled','refused'));
create index circle_invites_awaiting on public.circle_invites(org_id) where status = 'awaiting_circle';

create or replace function public.my_invite_by_code(p_code text, p_lock boolean default false) returns public.circle_invites
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
  if ci.status = 'awaiting_circle' then raise exception 'This invitation is waiting for the circle''s admin to agree. Try again later.'; end if;
  if ci.status = 'refused' then raise exception 'The circle''s admin did not agree to this invitation.'; end if;
  if ci.status = 'accepted' then raise exception 'This invitation was already used.'; end if;
  if ci.status = 'declined' then raise exception 'This invitation was turned down. Ask for a new one.'; end if;
  if ci.status = 'cancelled' then raise exception 'This invitation was cancelled. Ask for a new one.'; end if;
  if ci.expires_at <= now() then raise exception 'This invitation has expired. Ask for a new one.'; end if;
  if ci.email <> public.my_email() then
    raise exception 'This invitation was sent to %. Sign in with that account to open it.', public.mask_email(ci.email);
  end if;
  return ci;
end $$;

create or replace function public.invite_to_circle(p_org uuid, p_email text, p_role text, p_message text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(coalesce(p_email,'')));
  v_role text := coalesce(nullif(trim(p_role),''), 'member');
  v_mine text; v_platform boolean := public.is_platform_admin();
  o organizations; v_user uuid; v_name text; v_code text; v_id uuid; v_via text; v_exp timestamptz; v_status text;
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

  update circle_invites set status = 'cancelled', responded_at = now()
  where org_id = p_org and email = v_email and status in ('pending','awaiting_circle');

  v_via := case when v_mine in ('org_admin','secretary') then 'group' else 'platform' end;
  -- The platform team never decides who is in a circle. The circle's own admin agrees first.
  v_status := case when v_via = 'platform' then 'awaiting_circle' else 'pending' end;
  v_name := coalesce(
    (select full_name from members where org_id = p_org and user_id = auth.uid() and is_active),
    nullif(trim((select full_name from profiles where user_id = auth.uid())), ''),
    'The SACCO Ledger team');
  loop
    v_code := public.new_code();
    exit when not exists(select 1 from circle_invites where code = v_code) and not exists(select 1 from members where invite_code = v_code);
  end loop;
  insert into circle_invites(org_id, code, email, role, message, invited_by, invited_by_name, via, status)
  values (p_org, v_code, v_email, v_role, nullif(trim(p_message),''), auth.uid(), v_name, v_via, v_status)
  returning id, expires_at into v_id, v_exp;
  perform public.add_audit(p_org, 'INVITE_TO_CIRCLE', 'invite', v_id::text,
    public.mask_email(v_email) || ' invited as ' || v_role
      || case when v_via = 'platform' then ' by the platform team, waiting for the circle admin to agree' else '' end, v_name);
  return jsonb_build_object('id', v_id, 'code', v_code, 'email', v_email, 'role', v_role, 'expires_at', v_exp,
    'has_account', v_user is not null, 'org_name', o.name, 'status', v_status);
end $$;

-- The circle's admin says yes or no to an invitation the platform team asked for.
create function public.decide_platform_invite(p_invite uuid, p_agree boolean) returns void
language plpgsql security definer set search_path = public as $$
declare ci circle_invites; me members;
begin
  select * into ci from circle_invites where id = p_invite for update;
  if ci.id is null or ci.status <> 'awaiting_circle' then raise exception 'This invitation is not waiting for a decision.'; end if;
  me := public.require_role(ci.org_id, array['org_admin']);
  if p_agree then
    update circle_invites set status = 'pending', expires_at = now() + interval '14 days' where id = ci.id;
  else
    update circle_invites set status = 'refused', responded_at = now() where id = ci.id;
  end if;
  perform public.add_audit(ci.org_id, case when p_agree then 'AGREE_PLATFORM_INVITE' else 'REFUSE_PLATFORM_INVITE' end, 'invite', ci.id::text,
    public.mask_email(ci.email) || ' as ' || ci.role || ', asked by ' || coalesce(ci.invited_by_name, 'the platform team'), me.full_name);
end $$;

create or replace function public.list_circle_invites(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.org_role(p_org),'') not in ('org_admin','secretary','platform_admin') then
    raise exception 'Only this circle''s admin or secretary can see its invitations.';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', ci.id, 'email', ci.email, 'role', ci.role, 'invited_by', ci.invited_by_name, 'via', ci.via, 'message', ci.message,
      'status', case when ci.status = 'pending' and ci.expires_at <= now() then 'expired' else ci.status end,
      'code', case when ci.status = 'pending' and ci.expires_at > now() then ci.code end,
      'created_at', ci.created_at, 'expires_at', ci.expires_at, 'responded_at', ci.responded_at) order by ci.created_at desc), '[]'::jsonb)
    from (select * from circle_invites where org_id = p_org order by created_at desc limit 50) ci);
end $$;

create or replace function public.cancel_circle_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ci circle_invites;
begin
  select * into ci from circle_invites where id = p_invite for update;
  if ci.id is null or ci.status not in ('pending','awaiting_circle') then raise exception 'This invitation is not open.'; end if;
  if ci.invited_by is distinct from auth.uid() and coalesce(public.org_role(ci.org_id),'') not in ('org_admin','platform_admin') then
    raise exception 'Only the person who sent it, or the circle admin, can cancel it.';
  end if;
  update circle_invites set status = 'cancelled', responded_at = now() where id = ci.id;
  perform public.add_audit(ci.org_id, 'CANCEL_INVITE', 'invite', ci.id::text, public.mask_email(ci.email),
    coalesce((public.my_member(ci.org_id)).full_name, nullif(trim((select full_name from profiles where user_id = auth.uid())), ''), 'The SACCO Ledger team'));
end $$;

-- ========== 3. No account takeover by officers ==========
alter table public.members add column reset_asked_by uuid references public.members(id), add column reset_asked_at timestamptz;

create function public.is_phone_account(p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select lower(email) like '%@phone.saccoledger.app' from auth.users where id = p_user), false);
$$;

-- A joining code for someone not yet in the app: admin or secretary, as before.
-- A password reset for someone already in the app:
--   email account -> refused, they use the link sent to their own email;
--   phone account -> one officer asks, a DIFFERENT officer agrees, and only then a code is made. It works for one day.
create or replace function public.new_member_code(p_member uuid) returns text language plpgsql security definer set search_path = public as $$
declare t members; me members; v_code text; v_asker text;
begin
  select * into t from members where id = p_member for update;
  if t.id is null then raise exception 'Member not found.'; end if;
  if t.user_id is null then
    me := public.require_role(t.org_id, array['org_admin','secretary']);
    v_code := public.new_code();
    update members set invite_code = v_code, invite_expires_at = now() + interval '14 days', code_attempts = 0 where id = t.id;
    perform public.add_audit(t.org_id, 'NEW_MEMBER_CODE', 'member', t.id::text, 'Joining code issued for ' || t.full_name, me.full_name);
    return v_code;
  end if;
  if not public.is_phone_account(t.user_id) then
    raise exception '% signs in with email. They tap "Forgot password?" on the sign-in screen and get a link in their own email. Officers cannot reset it.', t.full_name;
  end if;
  me := public.require_role(t.org_id, array['org_admin','secretary','treasurer']);
  if me.id = t.id then raise exception 'You cannot reset your own password here. Ask two other officers.'; end if;
  if t.reset_asked_by is null or t.reset_asked_at < now() - interval '1 day' then
    if me.role not in ('org_admin','secretary') then raise exception 'Only the admin or the secretary can ask for a password reset.'; end if;
    update members set reset_asked_by = me.id, reset_asked_at = now() where id = t.id;
    perform public.add_audit(t.org_id, 'ASK_PASSWORD_RESET', 'member', t.id::text,
      'Asked to reset the password of ' || t.full_name || '. A second officer must agree.', me.full_name);
    return null;
  end if;
  if t.reset_asked_by = me.id then raise exception 'A different officer must agree to this reset.'; end if;
  select full_name into v_asker from members where id = t.reset_asked_by;
  v_code := public.new_code();
  update members set invite_code = v_code, invite_expires_at = now() + interval '1 day', code_attempts = 0,
    reset_asked_by = null, reset_asked_at = null where id = t.id;
  perform public.add_audit(t.org_id, 'AGREE_PASSWORD_RESET', 'member', t.id::text,
    'Agreed with ' || coalesce(v_asker,'?') || ': reset code for ' || t.full_name || ', works for one day', me.full_name);
  return v_code;
end $$;

-- The code works only for phone accounts, and using it signs the account out on every device.
create or replace function public.reset_password_with_code(p_email text, p_code text, p_new_password text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_user uuid; t members;
begin
  if length(coalesce(p_new_password,'')) < 6 then raise exception 'Password must have at least 6 characters.'; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is not null and not public.is_phone_account(v_user) then
    raise exception 'This account signs in with email. Tap "Forgot password?" and use the link we send to your email.';
  end if;
  if v_user is not null then
    select * into t from members where user_id = v_user and invite_code is not null order by invite_expires_at desc limit 1 for update;
  end if;
  if t.id is null or t.invite_expires_at <= now() or t.code_attempts >= 5 then
    raise exception 'This code is wrong or has expired. Ask your group secretary for a new one.';
  end if;
  if t.invite_code <> upper(trim(p_code)) then
    update members set code_attempts = code_attempts + 1 where id = t.id;
    return false;
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')) where id = v_user;
  delete from auth.sessions where user_id = v_user;
  update members set invite_code = null, invite_expires_at = null, code_attempts = 0 where id = t.id;
  perform public.add_audit(t.org_id, 'RESET_PASSWORD', 'member', t.id::text, t.full_name || ' reset password with a code and was signed out everywhere', t.full_name);
  return true;
end $$;

-- Old officer-made codes for people already in the app stop working now.
update public.members set invite_code = null, invite_expires_at = null, code_attempts = 0 where user_id is not null and invite_code is not null;

-- ========== 4. Shared demo: visitors are anonymous ==========
create or replace function public.join_demo(p_org uuid, p_user uuid, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare v_no int;
begin
  if exists(select 1 from members where org_id = p_org and user_id = p_user) then
    update members set is_active = true where org_id = p_org and user_id = p_user;
    return;
  end if;
  select coalesce(max(member_no),0) + 1 into v_no from members where org_id = p_org;
  -- Visitors never see each other's real names: everyone is "Demo visitor" plus a number.
  insert into members(org_id, user_id, member_no, full_name, role, consent_at)
  values (p_org, p_user, v_no, 'Demo visitor ' || v_no, 'auditor', now());
  perform public.add_audit(p_org, 'JOIN_DEMO', 'member', p_user::text, 'A visitor joined the shared demo', 'Demo visitor ' || v_no);
end $$;

update public.members m set full_name = case when m.role = 'org_admin' then 'Demo admin' else 'Demo visitor ' || m.member_no end
from public.organizations o
where o.id = m.org_id and o.is_demo and m.user_id is not null;

-- No real names go into the demo at all, not even the first person who built it.
create or replace function public.seed_demo(p_my_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  perform pg_advisory_xact_lock(hashtext('shared_demo'));
  v_org := public.shared_demo();
  if v_org is null then
    v_org := public.seed_demo_create('Demo admin');
    update organizations set name = 'Twekembe Savings Group (Shared Demo)' where id = v_org;
    return v_org;
  end if;
  perform public.join_demo(v_org, auth.uid(), null);
  return v_org;
end $$;

-- Old "joined the demo" lines carry real names and cannot be changed (the trail is sealed), so they are no longer shown in demos.
create or replace function public.list_audit(p_org uuid, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_officer(p_org) then raise exception 'Only officers can read the audit trail.'; end if;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select to_jsonb(a) as x from audit_log a
    where a.org_id = p_org and not (a.action = 'JOIN_DEMO' and (select is_demo from organizations where id = p_org))
    order by a.seq desc limit p_limit) s);
end $$;
create or replace function public.global_search(p_org uuid, p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid; q text;
begin
  perform public.require_member_or_platform(p_org);
  if length(trim(coalesce(p_q,''))) < 2 then return '[]'::jsonb; end if;
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  q := '%' || replace(replace(replace(trim(p_q),'\','\\'),'%','\%'),'_','\_') || '%';
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    (select jsonb_build_object('kind','member','id',m.id,'title',m.full_name,'subtitle','Member M' || m.member_no || ' - ' || m.role || case when v_off then coalesce(' - ' || m.phone,'') else '' end,'at',m.joined_at) x
       from members m where m.org_id = p_org and (m.full_name ilike q or 'M' || m.member_no ilike q or (v_off and (m.phone ilike q or m.national_id ilike q))) limit 10)
    union all
    (select jsonb_build_object('kind','journal','id',j.id,'title','#' || j.journal_number || ' ' || j.description,'subtitle',replace(j.type,'_',' ') || ' - by ' || j.actor_name || coalesce(' - ID ' || j.external_ref,''),'at',j.created_at)
       from journals j where j.org_id = p_org and (j.description ilike q or j.external_ref ilike q or j.type ilike q or '#' || j.journal_number ilike q or j.actor_name ilike q)
         and (v_off or exists(select 1 from journal_lines l where l.journal_id = j.id and l.member_id = v_me)) order by j.journal_number desc limit 15)
    union all
    (select jsonb_build_object('kind','payment','id',p.id,'title',replace(p.purpose,'_',' ') || ' ' || to_char(p.amount,'FM999,999,999,999') || ' - ' || coalesce(m.full_name,'group'),'subtitle',replace(p.channel,'_',' ') || ' - ' || p.status || coalesce(' - ID ' || p.external_ref,''),'at',p.submitted_at)
       from payment_records p left join members m on m.id = p.member_id where p.org_id = p_org and (p.external_ref ilike q or p.purpose ilike q or p.note ilike q or p.status ilike q or p.channel ilike q or m.full_name ilike q)
         and (v_off or p.member_id = v_me or p.submitted_by = v_me) order by p.submitted_at desc limit 15)
    union all
    (select jsonb_build_object('kind','loan','id',l.id,'title',l.loan_number || ' - ' || m.full_name,'subtitle',replace(l.status,'_',' ') || ' - principal ' || to_char(l.principal,'FM999,999,999,999'),'at',l.requested_at)
       from loans l join members m on m.id = l.member_id where l.org_id = p_org and (l.loan_number ilike q or m.full_name ilike q or l.status ilike q or l.purpose ilike q or l.resolution_ref ilike q)
         and (v_off or l.member_id = v_me) limit 10)
    union all
    (select jsonb_build_object('kind','meeting','id',mt.id,'title','Meeting #' || mt.meeting_number,'subtitle',mt.status || ' - ' || mt.meeting_date || coalesce(' - ' || left(mt.minutes,60),''),'at',mt.opened_at)
       from meetings mt where mt.org_id = p_org and ('meeting #' || mt.meeting_number ilike q or mt.minutes ilike q or mt.meeting_date::text ilike q or mt.status ilike q) limit 10)
    union all
    (select jsonb_build_object('kind','emergency','id',c.id,'title','Emergency claim - ' || m.full_name,'subtitle',c.status || ' - ' || to_char(c.amount,'FM999,999,999,999') || ' - ' || c.reason,'at',c.requested_at)
       from emergency_claims c join members m on m.id = c.member_id where c.org_id = p_org and (c.reason ilike q or m.full_name ilike q or c.status ilike q)
         and (v_off or c.member_id = v_me) limit 10)
    union all
    (select jsonb_build_object('kind','audit','id',a.id,'title',a.action,'subtitle',a.actor_name || ' - ' || left(a.details,80),'at',a.created_at)
       from audit_log a where v_off and a.org_id = p_org
         and not (a.action = 'JOIN_DEMO' and (select is_demo from organizations where id = p_org)) and (a.action ilike q or a.actor_name ilike q or a.details ilike q) order by a.seq desc limit 10)
  ) s);
end $$;

-- ========== 5. Online payments: off until a lawyer confirms ==========
-- Holding a group's gateway keys and starting payments may need a Bank of Uganda licence, and the keys can also send money out.
-- To turn it on again, a reviewed change edits this one function.
create function public.online_payments_allowed() returns boolean language sql immutable set search_path = public as $$ select false $$;

create function public.online_payments_paused() returns trigger language plpgsql set search_path = public as $$
begin
  if public.online_payments_allowed() then return new; end if;
  -- Switching a gateway off, and settling a payment that already started, still work.
  if tg_table_name = 'gateway_accounts' and tg_op = 'UPDATE' and not new.enabled then return new; end if;
  if tg_table_name = 'gateway_payments' and tg_op = 'UPDATE' then return new; end if;
  raise exception 'Online payments are switched off for now. Pay with MoMo or Airtel to the group''s number and record the transaction ID.';
end $$;
create trigger gateway_accounts_paused before insert or update on public.gateway_accounts for each row execute function public.online_payments_paused();
create trigger gateway_payments_paused before insert or update on public.gateway_payments for each row execute function public.online_payments_paused();
update public.gateway_accounts set enabled = false where enabled;

-- ========== Locks on the new functions ==========
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('mfa_ok','my_platform_status','decide_platform_invite','is_phone_account','online_payments_allowed','online_payments_paused') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    if f.proname in ('my_platform_status','decide_platform_invite') then
      execute format('grant execute on function %s to authenticated', f.sig);
    else
      execute format('revoke all on function %s from authenticated', f.sig);
    end if;
  end loop;
end $$;
