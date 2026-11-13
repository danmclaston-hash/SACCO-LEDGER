-- Lock the platform view.
-- Before: the platform team (owners and admins) could open any circle and read everything its officers read.
-- Now: the platform team sees only totals for each circle. To look inside, the circle's own admin must open a
-- 24-hour "support window". Every look is written into that circle's audit trail, and the admin can close the window any time.
-- Circle admins and members still cannot see any other circle: access is checked by membership, circle by circle.

create table public.support_access (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  granted_by uuid not null references auth.users(id),
  granted_by_name text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz
);
create index on public.support_access(org_id, expires_at);
alter table public.support_access enable row level security;
revoke all on public.support_access from anon, public, authenticated;

-- FIX: "not an officer" used to come back as unknown (null) for someone outside the circle, and several checks
-- read unknown as "allowed". It now always answers yes or no.
create or replace function public.is_officer(p_org uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.org_role(p_org) in ('org_admin','treasurer','secretary','loan_officer','auditor','platform_admin'), false);
$$;

-- Is there an open support window for this circle right now?
create function public.support_open(p_org uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from support_access where org_id = p_org and ended_at is null and expires_at > now());
$$;

-- The one door. A member gets their own role. The platform team gets look-only access only while the circle's window is open.
create or replace function public.org_role(p_org uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select role from members where org_id = p_org and user_id = auth.uid() and is_active limit 1),
                  case when public.is_platform_admin() and public.support_open(p_org) then 'platform_admin' end);
$$;

-- Circles I can open: my own, plus circles that opened a support window for the platform team.
create or replace function public.my_memberships() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) from (
    select to_jsonb(o) || jsonb_build_object('my_role', m.role, 'my_member_id', m.id, 'my_name', m.full_name) as x
    from members m join organizations o on o.id = m.org_id where m.user_id = auth.uid() and m.is_active
    union all
    select to_jsonb(o) || jsonb_build_object('my_role','platform_admin','my_member_id',null,'my_name','Platform Admin')
    from organizations o where public.is_platform_admin() and public.support_open(o.id)
      and not exists (select 1 from members m where m.org_id = o.id and m.user_id = auth.uid() and m.is_active)
  ) s;
$$;

-- Circle admin opens the window. Hours are 1 to 24.
create function public.open_support_window(p_org uuid, p_hours int default 24) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare me members; v_exp timestamptz;
begin
  me := public.require_role(p_org, array['org_admin']);
  if (select is_demo from organizations where id = p_org) then raise exception 'The demo is open to everyone already.'; end if;
  p_hours := least(greatest(coalesce(p_hours, 24), 1), 24);
  update support_access set ended_at = now() where org_id = p_org and ended_at is null;
  v_exp := now() + make_interval(hours => p_hours);
  insert into support_access(org_id, granted_by, granted_by_name, expires_at) values (p_org, auth.uid(), me.full_name, v_exp);
  perform public.add_audit(p_org, 'SUPPORT_WINDOW_OPENED', 'support', null,
    'The platform team may look at this circle for ' || p_hours || ' hour' || case when p_hours = 1 then '' else 's' end, me.full_name);
  return v_exp;
end $$;

-- Circle admin closes it early.
create function public.close_support_window(p_org uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me members;
begin
  me := public.require_role(p_org, array['org_admin']);
  if public.support_open(p_org) then
    update support_access set ended_at = now() where org_id = p_org and ended_at is null;
    perform public.add_audit(p_org, 'SUPPORT_WINDOW_CLOSED', 'support', null, 'The platform team can no longer look at this circle', me.full_name);
  end if;
end $$;

-- Officers see whether the window is open.
create function public.support_window_status(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s support_access;
begin
  if not public.is_officer(p_org) or public.org_role(p_org) = 'platform_admin' then raise exception 'Only this circle''s officers can see this.'; end if;
  select * into s from support_access where org_id = p_org and ended_at is null and expires_at > now() order by created_at desc limit 1;
  return jsonb_build_object('open', s.id is not null, 'expires_at', s.expires_at, 'opened_by', s.granted_by_name);
end $$;

-- The platform team calls this when it opens a circle. It writes the look into the circle's audit trail
-- (once per person every 10 minutes, so a busy session does not flood the record).
create function public.note_support_look(p_org uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not public.is_platform_admin() then raise exception 'Platform team only.'; end if;
  if not public.support_open(p_org) then raise exception 'This circle has not opened a support window.'; end if;
  if exists(select 1 from members where org_id = p_org and user_id = auth.uid() and is_active) then return; end if;
  if exists(select 1 from audit_log where org_id = p_org and action = 'PLATFORM_LOOK' and actor_user_id = auth.uid() and created_at > now() - interval '10 minutes') then return; end if;
  v_name := coalesce(nullif(trim((select full_name from profiles where user_id = auth.uid())), ''), 'Platform team');
  perform public.add_audit(p_org, 'PLATFORM_LOOK', 'support', null, 'Platform team member opened this circle (look only)', v_name || ' (platform team)');
end $$;

-- Totals only. No names, phones, ID numbers or personal balances. Shows if a support window is open.
create or replace function public.platform_overview() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'edition',o.edition,'currency_code',o.currency_code,'cycle_number',o.cycle_number,
      'licence_type',o.licence_type,'licence_number',o.licence_number,'licence_expiry',o.licence_expiry,'is_demo',o.is_demo,
      'members',(select count(*) from members where org_id=o.id and is_active),
      'journals',(select count(*) from journals where org_id=o.id),
      'pending',(select count(*) from payment_records where org_id=o.id and status='pending'),
      'support_until',(select max(expires_at) from support_access s where s.org_id=o.id and s.ended_at is null and s.expires_at > now()),
      'created_at',o.created_at) order by o.created_at desc),'[]'::jsonb) from organizations o);
end $$;

-- The platform team still sees (and can cancel) the invitations it sent itself. Other circles' invitations stay private.
create or replace function public.list_circle_invites(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_own boolean := coalesce(public.org_role(p_org) in ('org_admin','secretary'), false);
begin
  if not v_own and not public.is_platform_admin() then
    raise exception 'Only this circle''s admin or secretary can see its invitations.';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', ci.id, 'email', ci.email, 'role', ci.role, 'invited_by', ci.invited_by_name, 'via', ci.via, 'message', ci.message,
      'status', case when ci.status = 'pending' and ci.expires_at <= now() then 'expired' else ci.status end,
      'code', case when ci.status = 'pending' and ci.expires_at > now() then ci.code end,
      'created_at', ci.created_at, 'expires_at', ci.expires_at, 'responded_at', ci.responded_at) order by ci.created_at desc), '[]'::jsonb)
    from (select * from circle_invites where org_id = p_org and (v_own or invited_by = auth.uid()) order by created_at desc limit 50) ci);
end $$;

create or replace function public.cancel_circle_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ci circle_invites;
begin
  select * into ci from circle_invites where id = p_invite for update;
  if ci.id is null or ci.status not in ('pending','awaiting_circle') then raise exception 'This invitation is not open.'; end if;
  if ci.invited_by is distinct from auth.uid() and coalesce(public.org_role(ci.org_id),'') <> 'org_admin' then
    raise exception 'Only the person who sent it, or the circle admin, can cancel it.';
  end if;
  update circle_invites set status = 'cancelled', responded_at = now() where id = ci.id;
  perform public.add_audit(ci.org_id, 'CANCEL_INVITE', 'invite', ci.id::text, public.mask_email(ci.email),
    coalesce((public.my_member(ci.org_id)).full_name, nullif(trim((select full_name from profiles where user_id = auth.uid())), ''), 'The SACCO Ledger team'));
end $$;

-- Who may call what
revoke all on function public.support_open(uuid), public.open_support_window(uuid,int), public.close_support_window(uuid),
  public.support_window_status(uuid), public.note_support_look(uuid) from public, anon;
grant execute on function public.open_support_window(uuid,int), public.close_support_window(uuid),
  public.support_window_status(uuid), public.note_support_look(uuid) to authenticated;
