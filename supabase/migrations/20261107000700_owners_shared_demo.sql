-- Fellow owners, a sign-up list for owners, and ONE shared demo group for everyone.
-- Run after 20261107000600_loan_rules.sql.

-- ========== 1. MORE THAN ONE OWNER ==========
-- Owners can add, promote, demote and remove admins and other owners.
-- Two people can never be removed: the founder (danmclaston@gmail.com), and you yourself (ask another owner).
create function public.is_founder(p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from auth.users where id = p_user and lower(email) = 'danmclaston@gmail.com');
$$;

-- Invites can now be for "owner" too.
alter table public.platform_admin_invites add column role text not null default 'admin' check (role in ('owner','admin'));

create or replace function public.make_owner_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) = 'danmclaston@gmail.com' then
    insert into public.platform_admins(user_id, role) values (new.id, 'owner') on conflict (user_id) do update set role = 'owner';
  elsif exists(select 1 from public.platform_admin_invites where email = lower(trim(new.email))) then
    insert into public.platform_admins(user_id, role, added_by)
      select new.id, role, invited_by from public.platform_admin_invites where email = lower(trim(new.email))
      on conflict do nothing;
    perform public.add_platform_audit('ADMIN_JOINED', lower(new.email) || ' signed up and became ' ||
      (select role from public.platform_admin_invites where email = lower(trim(new.email))), lower(new.email));
    delete from public.platform_admin_invites where email = lower(trim(new.email));
  end if;
  return new;
end $$;

drop function public.add_platform_admin(text);
create function public.add_platform_admin(p_email text, p_role text default 'admin') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(coalesce(p_email,''))); v_user uuid;
begin
  perform public.require_platform_owner();
  if p_role not in ('owner','admin') then raise exception 'Choose owner or admin.'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid email.'; end if;
  select id into v_user from auth.users where lower(email) = v_email;
  if v_user is not null then
    if exists(select 1 from platform_admins where user_id = v_user) then raise exception 'This person is already on the team. Use Make owner or Make admin.'; end if;
    insert into platform_admins(user_id, role, added_by) values (v_user, p_role, auth.uid());
    perform public.add_platform_audit('ADD_' || upper(p_role), v_email);
    return jsonb_build_object('status', 'added', 'email', v_email, 'role', p_role);
  end if;
  insert into platform_admin_invites(email, invited_by, role) values (v_email, auth.uid(), p_role)
    on conflict (email) do update set role = excluded.role, invited_by = excluded.invited_by;
  perform public.add_platform_audit('INVITE_' || upper(p_role), v_email || ' (not signed up yet)');
  return jsonb_build_object('status', 'invited', 'email', v_email, 'role', p_role);
end $$;

-- Owner <-> admin.
create function public.set_platform_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
declare a platform_admins; v_email text;
begin
  perform public.require_platform_owner();
  if p_role not in ('owner','admin') then raise exception 'Choose owner or admin.'; end if;
  select * into a from platform_admins where user_id = p_user;
  if a.user_id is null then raise exception 'Add this person first.'; end if;
  if a.role = p_role then return; end if;
  if p_role = 'admin' and public.is_founder(p_user) then raise exception 'The founder always stays owner.'; end if;
  if p_role = 'admin' and p_user = auth.uid() then raise exception 'Ask another owner to change your own role.'; end if;
  select email into v_email from auth.users where id = p_user;
  update platform_admins set role = p_role where user_id = p_user;
  perform public.add_platform_audit(case when p_role = 'owner' then 'MAKE_OWNER' else 'MAKE_ADMIN' end, coalesce(v_email, p_user::text));
end $$;

create or replace function public.remove_platform_admin(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a platform_admins; v_email text;
begin
  perform public.require_platform_owner();
  select * into a from platform_admins where user_id = p_user;
  if a.user_id is null then raise exception 'This person is not on the team.'; end if;
  if public.is_founder(p_user) then raise exception 'The founder cannot be removed.'; end if;
  if p_user = auth.uid() then raise exception 'Ask another owner to remove you.'; end if;
  select email into v_email from auth.users where id = p_user;
  delete from platform_admins where user_id = p_user;
  perform public.add_platform_audit('REMOVE_' || upper(a.role), coalesce(v_email, p_user::text));
end $$;

-- Team list plus everyone who signed up, newest first, so owners can pick people without typing.
create or replace function public.list_platform_admins() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  return jsonb_build_object(
    'me_owner', public.is_platform_owner(),
    'admins', (select coalesce(jsonb_agg(jsonb_build_object('user_id', a.user_id, 'email', u.email, 'name', p.full_name,
        'role', a.role, 'added_at', a.created_at, 'added_by', b.email, 'is_me', a.user_id = auth.uid(), 'is_founder', public.is_founder(a.user_id))
        order by a.role desc, a.created_at), '[]'::jsonb)
      from platform_admins a join auth.users u on u.id = a.user_id
      left join profiles p on p.user_id = a.user_id left join auth.users b on b.id = a.added_by),
    'invites', (select coalesce(jsonb_agg(jsonb_build_object('email', i.email, 'role', i.role, 'invited_at', i.created_at) order by i.created_at), '[]'::jsonb)
      from platform_admin_invites i),
    'people', (select coalesce(jsonb_agg(x order by (x->>'joined_at') desc), '[]'::jsonb) from (
        select jsonb_build_object('user_id', u.id, 'email', u.email, 'name', p.full_name,
          'joined_at', u.created_at, 'last_sign_in', u.last_sign_in_at,
          'groups', (select count(*) from members m where m.user_id = u.id and m.is_active),
          'role', a.role) as x
        from auth.users u left join profiles p on p.user_id = u.id left join platform_admins a on a.user_id = u.id
        order by u.created_at desc limit 200) s),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('who', h.actor_email, 'action', h.action, 'details', h.details, 'at', h.created_at)
        order by h.seq desc), '[]'::jsonb) from (select * from platform_audit order by seq desc limit 30) h));
end $$;

-- ========== 2. ONE SHARED DEMO GROUP ==========
-- Everyone who taps "Try with demo data" joins the same demo as an Auditor:
-- they can see every screen and number, but cannot change the demo. To try changing things,
-- they create their own group. The first demo ever made is the shared one.
alter function public.seed_demo(text) rename to seed_demo_create;
revoke all on function public.seed_demo_create(text) from public, anon, authenticated;

create function public.shared_demo() returns uuid language sql stable security definer set search_path = public as $$
  select id from organizations where is_demo order by created_at limit 1;
$$;

create function public.join_demo(p_org uuid, p_user uuid, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from members where org_id = p_org and user_id = p_user) then
    update members set is_active = true where org_id = p_org and user_id = p_user;
    return;
  end if;
  insert into members(org_id, user_id, member_no, full_name, role, consent_at)
  values (p_org, p_user, (select coalesce(max(member_no),0) + 1 from members where org_id = p_org),
    coalesce(nullif(trim(p_name),''), 'Demo visitor'), 'auditor', now());
  perform public.add_audit(p_org, 'JOIN_DEMO', 'member', p_user::text, 'Joined the shared demo to look around',
    coalesce(nullif(trim(p_name),''), 'Demo visitor'));
end $$;

create function public.seed_demo(p_my_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_name text;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  perform pg_advisory_xact_lock(hashtext('shared_demo'));
  v_org := public.shared_demo();
  if v_org is null then
    v_org := public.seed_demo_create(p_my_name);       -- very first time: build it (maker is its admin)
    update organizations set name = 'Twekembe Savings Group (Shared Demo)' where id = v_org;
    return v_org;
  end if;
  -- Use their real name if they have one, so others can see who is looking around.
  select coalesce(p.full_name, nullif(trim(p_my_name),'')) into v_name from (select 1) x left join profiles p on p.user_id = auth.uid();
  if v_name is null or v_name ilike '%demo admin%' then
    v_name := split_part((select email from auth.users where id = auth.uid()), '@', 1);
  end if;
  perform public.join_demo(v_org, auth.uid(), v_name);
  return v_org;
end $$;
revoke all on function public.seed_demo(text) from public, anon;
grant execute on function public.seed_demo(text) to authenticated;

-- ========== 3. MERGE EXISTING DEMO COPIES INTO THE SHARED ONE ==========
-- Demo groups hold only made-up people and money. Their records are normally permanent,
-- so the permanent-record guards are paused for demo groups ONLY, inside this one update, then switched back on.
do $$
declare v_keep uuid; v_drop uuid[]; r record;
begin
  select id into v_keep from organizations where is_demo order by created_at limit 1;
  if v_keep is null then return; end if;
  update organizations set name = 'Twekembe Savings Group (Shared Demo)' where id = v_keep;
  select array_agg(id) into v_drop from organizations where is_demo and id <> v_keep;
  if v_drop is null then return; end if;

  -- Real people in the extra copies join the shared one, so nobody loses their way in.
  for r in select distinct m.user_id, m.full_name from members m where m.org_id = any(v_drop) and m.user_id is not null loop
    perform public.join_demo(v_keep, r.user_id, case when r.full_name ilike '%demo admin%'
      then split_part((select email from auth.users where id = r.user_id), '@', 1) else r.full_name end);
  end loop;

  alter table public.journals disable trigger journals_no_change;
  alter table public.journal_lines disable trigger journal_lines_no_change;
  alter table public.loan_repayments disable trigger loan_repayments_no_change;
  alter table public.shareout_payouts disable trigger shareout_payouts_no_change;
  alter table public.audit_log disable trigger audit_log_no_change;
  alter table public.loan_fee_waivers disable trigger loan_fee_waivers_no_change;

  delete from attendance where meeting_id in (select id from meetings where org_id = any(v_drop));
  delete from loan_repayments where org_id = any(v_drop);
  delete from shareout_payouts where org_id = any(v_drop);
  delete from loan_fee_waivers where org_id = any(v_drop);
  delete from gateway_payments where org_id = any(v_drop);
  delete from payment_records where org_id = any(v_drop);
  delete from emergency_claims where org_id = any(v_drop);
  delete from loans where org_id = any(v_drop);
  delete from journal_lines where org_id = any(v_drop);
  update journals set reversal_of = null where org_id = any(v_drop) and reversal_of is not null;
  delete from journals where org_id = any(v_drop);
  delete from meetings where org_id = any(v_drop);
  delete from savings_goals where org_id = any(v_drop);
  delete from audit_log where org_id = any(v_drop);
  delete from gateway_accounts where org_id = any(v_drop);
  delete from members where org_id = any(v_drop);
  delete from organizations where id = any(v_drop);

  alter table public.journals enable trigger journals_no_change;
  alter table public.journal_lines enable trigger journal_lines_no_change;
  alter table public.loan_repayments enable trigger loan_repayments_no_change;
  alter table public.shareout_payouts enable trigger shareout_payouts_no_change;
  alter table public.audit_log enable trigger audit_log_no_change;
  alter table public.loan_fee_waivers enable trigger loan_fee_waivers_no_change;

  perform public.add_platform_audit('MERGE_DEMOS', 'Kept one shared demo, removed ' || array_length(v_drop, 1) || ' extra demo copies', 'System');
end $$;

-- ========== WHO MAY CALL WHAT ==========
revoke all on function public.is_founder(uuid) from public, anon, authenticated;
revoke all on function public.shared_demo() from public, anon, authenticated;
revoke all on function public.join_demo(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.add_platform_admin(text, text) from public, anon;
revoke all on function public.set_platform_role(uuid, text) from public, anon;
grant execute on function public.add_platform_admin(text, text) to authenticated;
grant execute on function public.set_platform_role(uuid, text) to authenticated;
