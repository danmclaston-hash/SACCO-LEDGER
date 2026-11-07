-- Online payments (Flutterwave or Pesapal) and platform administrators.
-- Run after 20261107000300_goals.sql.
--
-- Rule 1 still holds: the platform NEVER holds money. Each group connects ITS OWN gateway account,
-- so money lands in the group's account. We only keep proof that the gateway itself confirmed.
--
-- Why this is stronger than typing a transaction ID:
--   our server makes the reference, the gateway reports the result, and our server asks the gateway
--   again before anything posts. Nobody types the ID, so nobody can mistype or invent one.

-- ========== 1. TWO NEW CHANNELS ==========
alter table public.payment_records drop constraint payment_records_channel_check;
alter table public.payment_records add constraint payment_records_channel_check
  check (channel in ('mtn_momo','airtel_money','bank','cash','flutterwave','pesapal'));

-- ========== 2. EACH GROUP'S OWN GATEWAY ACCOUNT ==========
-- The keys are encrypted by the server function before they reach the database.
-- No app or browser can read this table, not even officers. Only the server function can.
create table public.gateway_accounts (
  org_id uuid primary key references public.organizations(id),
  gateway text not null check (gateway in ('flutterwave','pesapal')),
  mode text not null default 'test' check (mode in ('test','live')),
  key_hint text,                 -- last 4 characters, safe to show
  creds_enc text not null,       -- encrypted keys (AES-GCM). The plain keys are never stored
  ipn_id text,                   -- Pesapal's id for our notification address
  enabled boolean not null default true,
  updated_by uuid references public.members(id),
  updated_at timestamptz not null default now()
);

-- One row per "Pay online" attempt. It becomes a payment record only after the gateway confirms.
create table public.gateway_payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid not null references public.members(id),
  purpose text not null check (purpose in ('shares','savings','fine','loan_repayment','emergency_contribution')),
  amount bigint not null check (amount > 0),
  currency text not null,
  loan_id uuid references public.loans(id),
  goal_id uuid references public.savings_goals(id),
  note text,
  gateway text not null check (gateway in ('flutterwave','pesapal')),
  mode text not null check (mode in ('test','live')),
  tx_ref text not null unique,   -- made by us, sent to the gateway. Nobody types it
  status text not null default 'created' check (status in ('created','waiting','paid','failed','needs_review')),
  checkout_url text,
  gateway_order_id text,         -- Pesapal order tracking id
  gateway_tx_id text,            -- the gateway's own transaction id
  gateway_ref text,              -- network receipt (e.g. MTN confirmation code)
  paid_amount bigint,
  paid_currency text,
  method text,
  verified_at timestamptz,
  verify_note text,
  payment_id uuid references public.payment_records(id),
  created_by uuid not null references public.members(id),
  created_at timestamptz not null default now()
);
create unique index gateway_payments_one_tx on public.gateway_payments(org_id, gateway, gateway_tx_id) where gateway_tx_id is not null;
create index gateway_payments_org on public.gateway_payments(org_id, created_at desc);

alter table public.gateway_accounts enable row level security;
alter table public.gateway_payments enable row level security;
revoke all on public.gateway_accounts from anon, public, authenticated;
revoke all on public.gateway_payments from anon, public;
revoke insert, update, delete, truncate on public.gateway_payments from authenticated;
grant select on public.gateway_payments to authenticated;
create policy read_officer_or_self on public.gateway_payments for select
  using (public.is_officer(org_id) or member_id = (public.my_member(org_id)).id or created_by = (public.my_member(org_id)).id);

-- ----- Called by the server function only (it has checked who the person is) -----

-- Saves a group's gateway. p_user is the signed-in person the server function checked.
create function public.save_gateway_account(p_org uuid, p_user uuid, p_gateway text, p_mode text, p_hint text, p_creds_enc text, p_ipn_id text)
returns void language plpgsql security definer set search_path = public as $$
declare me members;
begin
  select * into me from members where org_id = p_org and user_id = p_user and is_active;
  if me.id is null or me.role not in ('org_admin','treasurer') then
    raise exception 'Only the group admin or treasurer can connect a payment gateway.';
  end if;
  -- Test keys move pretend money. Pretend money must never enter a real group's books.
  if p_mode = 'test' and not (select is_demo from organizations where id = p_org) then
    raise exception 'Test keys work only in a demo group. Use live keys for a real group.';
  end if;
  insert into gateway_accounts(org_id, gateway, mode, key_hint, creds_enc, ipn_id, enabled, updated_by, updated_at)
  values (p_org, p_gateway, p_mode, p_hint, p_creds_enc, p_ipn_id, true, me.id, now())
  on conflict (org_id) do update set gateway = excluded.gateway, mode = excluded.mode, key_hint = excluded.key_hint,
    creds_enc = excluded.creds_enc, ipn_id = excluded.ipn_id, enabled = true, updated_by = me.id, updated_at = now();
  perform public.add_audit(p_org, 'CONNECT_GATEWAY', 'gateway', p_gateway, p_gateway || ' (' || p_mode || ') key ending ' || coalesce(p_hint,'?'), me.full_name);
end $$;

-- Who may manage the gateway? Used by the server function before it checks keys with the gateway.
create function public.can_manage_gateway(p_org uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from members where org_id = p_org and user_id = p_user and is_active and role in ('org_admin','treasurer'));
$$;

create function public.gateway_payment_started(p_id uuid, p_url text, p_order text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update gateway_payments set status = 'waiting', checkout_url = p_url, gateway_order_id = p_order
   where id = p_id and status = 'created';
end $$;

-- The gateway answered. Only called after our server asked the gateway's verify API itself.
-- Safe to call twice: the second call changes nothing.
create function public.settle_gateway_payment(p_id uuid, p_ok boolean, p_tx_id text, p_ref text, p_paid bigint,
  p_currency text, p_method text, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g gateway_payments; pm payment_records; v_j uuid; v_name text; v_who text; v_err text;
begin
  select * into g from gateway_payments where id = p_id for update;
  if g.id is null then raise exception 'Online payment not found.'; end if;
  if g.status in ('paid','needs_review') then return to_jsonb(g); end if;
  v_who := initcap(g.gateway) || ' (checked by server)';
  select full_name into v_name from members where id = g.member_id;

  if not p_ok then
    update gateway_payments set status = 'failed', verified_at = now(), verify_note = coalesce(p_note, 'Not paid')
     where id = g.id returning * into g;
    return to_jsonb(g);
  end if;
  if coalesce(trim(p_tx_id),'') = '' then raise exception 'A paid result must carry the gateway transaction id.'; end if;

  -- Always keep a payment record, so the proof is never lost.
  begin
    insert into payment_records(org_id, member_id, purpose, amount, channel, external_ref, loan_id, note, idempotency_key,
                                submitted_by, goal_id)
    values (g.org_id, g.member_id, g.purpose, p_paid, g.gateway, upper(trim(p_tx_id)), g.loan_id,
            coalesce(g.note || ' • ', '') || 'Paid online' || coalesce(' by ' || p_method, '') || coalesce(', receipt ' || p_ref, ''),
            'GW-' || g.id::text, g.created_by, g.goal_id)
    returning * into pm;
  exception when unique_violation then
    update gateway_payments set status = 'needs_review', verified_at = now(), gateway_ref = p_ref,
      paid_amount = p_paid, paid_currency = p_currency, method = p_method,
      verify_note = 'Gateway transaction ' || p_tx_id || ' was already recorded in this group. An officer must check.'
     where id = g.id returning * into g;
    perform public.add_audit(g.org_id, 'ONLINE_PAYMENT_DUPLICATE', 'gateway_payment', g.id::text, g.gateway || ' txn ' || p_tx_id, v_who);
    return to_jsonb(g);
  end;
  perform public.add_audit(g.org_id, 'ONLINE_PAYMENT_VERIFIED', 'payment', pm.id::text,
    g.purpose || ' ' || p_paid || ' ' || coalesce(p_currency,'') || ' for ' || coalesce(v_name,'?') || ' via ' || g.gateway ||
    ' txn ' || p_tx_id || coalesce(' receipt ' || p_ref, '') || coalesce(' method ' || p_method, ''), v_who);

  -- Wrong money? Keep it pending: a person must look. Right money? Post it now.
  if p_currency is distinct from g.currency or p_paid <> g.amount then
    v_err := 'Paid ' || p_paid || ' ' || coalesce(p_currency,'?') || ' but expected ' || g.amount || ' ' || g.currency || '. An officer must check.';
  else
    begin
      v_j := public.apply_payment(pm, v_who);
      update payment_records set status = 'confirmed', reviewed_at = now(), journal_id = v_j,
        review_note = 'Verified by ' || initcap(g.gateway) || ' (txn ' || p_tx_id || ')'
       where id = pm.id returning * into pm;
    exception when others then
      v_err := 'Money arrived but could not post: ' || sqlerrm || ' An officer must check.';
    end;
  end if;

  update gateway_payments set status = case when v_err is null then 'paid' else 'needs_review' end, verified_at = now(),
    gateway_tx_id = p_tx_id, gateway_ref = p_ref, paid_amount = p_paid, paid_currency = p_currency, method = p_method,
    verify_note = v_err, payment_id = pm.id
   where id = g.id returning * into g;
  return to_jsonb(g);
end $$;

-- ----- Called by people in the app -----

-- Is online payment on for this group? Members see yes/no. Officers also see which key is in use.
create function public.gateway_status(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a gateway_accounts;
begin
  perform public.require_member_or_platform(p_org);
  select * into a from gateway_accounts where org_id = p_org;
  if a.org_id is null then return jsonb_build_object('enabled', false); end if;
  return jsonb_build_object('enabled', a.enabled, 'gateway', a.gateway, 'mode', a.mode) ||
    case when public.is_officer(p_org) then jsonb_build_object('key_hint', a.key_hint, 'updated_at', a.updated_at,
      'updated_by', (select full_name from members where id = a.updated_by)) else '{}'::jsonb end;
end $$;

create function public.disable_gateway(p_org uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me members;
begin
  me := public.require_role(p_org, array['org_admin','treasurer']);
  update gateway_accounts set enabled = false, updated_by = me.id, updated_at = now() where org_id = p_org;
  if not found then raise exception 'No payment gateway is connected.'; end if;
  perform public.add_audit(p_org, 'DISCONNECT_GATEWAY', 'gateway', null, 'Online payments switched off', me.full_name);
end $$;

-- Starts an online payment. Same rules as recording by hand: your own money, or an officer for a member.
create function public.create_gateway_payment(p_org uuid, p_member uuid, p_purpose text, p_amount bigint,
  p_loan uuid, p_goal uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me members; a gateway_accounts; g gateway_payments; m members; o organizations;
begin
  me := public.my_member(p_org);
  if me.id is null then raise exception 'You are not an active member of this group.'; end if;
  select * into a from gateway_accounts where org_id = p_org and enabled;
  if a.org_id is null then raise exception 'Online payment is not switched on for this group.'; end if;
  if p_purpose not in ('shares','savings','fine','loan_repayment','emergency_contribution') then
    raise exception 'Only money coming in can be paid online.';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Enter a valid amount.'; end if;
  if p_member <> me.id and me.role not in ('org_admin','treasurer','secretary') then
    raise exception 'You can only pay for yourself.';
  end if;
  select * into m from members where id = p_member and org_id = p_org and is_active;
  if m.id is null then raise exception 'That member is not active in this group.'; end if;
  if p_purpose = 'loan_repayment' and not exists(select 1 from loans where id = p_loan and org_id = p_org and member_id = p_member and status = 'active') then
    raise exception 'Choose an active loan for this member.';
  end if;
  perform public.check_goal(p_org, p_goal, p_purpose);
  select * into o from organizations where id = p_org;
  insert into gateway_payments(org_id, member_id, purpose, amount, currency, loan_id, goal_id, note, gateway, mode, tx_ref, created_by)
  values (p_org, p_member, p_purpose, p_amount, o.currency_code, case when p_purpose = 'loan_repayment' then p_loan end,
          p_goal, nullif(trim(p_note),''), a.gateway, a.mode,
          'SL-' || upper(replace(gen_random_uuid()::text, '-', '')), me.id)
  returning * into g;
  perform public.add_audit(p_org, 'START_ONLINE_PAYMENT', 'gateway_payment', g.id::text,
    p_purpose || ' ' || p_amount || ' for ' || m.full_name || ' via ' || a.gateway || ' ref ' || g.tx_ref, me.full_name);
  return to_jsonb(g) || jsonb_build_object('member_name', m.full_name, 'member_phone', m.phone, 'org_name', o.name,
    'member_email', (select email from auth.users where id = m.user_id));
end $$;

create function public.list_gateway_payments(p_org uuid, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select (to_jsonb(g) - 'checkout_url') || jsonb_build_object('member_name', m.full_name,
             'checkout_url', case when g.status = 'waiting' then g.checkout_url end) as x
    from gateway_payments g join members m on m.id = g.member_id
    where g.org_id = p_org and (v_off or g.member_id = v_me or g.created_by = v_me)
    order by g.created_at desc limit least(coalesce(p_limit, 50), 200)) s);
end $$;

-- The app may ask "is it paid yet?" only for payments it can see. The server function uses this first.
create function public.can_see_gateway_payment(p_id uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from gateway_payments g join members me on me.org_id = g.org_id and me.user_id = p_user and me.is_active
    where g.id = p_id and (me.id in (g.member_id, g.created_by) or me.role in ('org_admin','treasurer','secretary','loan_officer','auditor')));
$$;

-- ========== 3. PLATFORM ADMINISTRATORS (people who run the whole platform) ==========
alter table public.platform_admins add column role text not null default 'admin' check (role in ('owner','admin'));
alter table public.platform_admins add column added_by uuid references auth.users(id);
update public.platform_admins set role = 'owner'
 where user_id in (select id from auth.users where lower(email) = 'danmclaston@gmail.com');

-- An email added before that person has signed up. They become admin the moment they sign up.
create table public.platform_admin_invites (
  email text primary key check (email = lower(trim(email)) and email like '%@%'),
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- Every change of who is admin, sealed like the group audit trail.
create table public.platform_audit (
  seq bigint primary key,
  actor_user_id uuid,
  actor_email text not null,
  action text not null,
  details text not null default '',
  created_at timestamptz not null default now(),
  prev_hash text not null,
  hash text not null
);
create trigger platform_audit_no_change before update or delete on public.platform_audit for each row execute function public.block_change();
create trigger platform_audit_no_truncate before truncate on public.platform_audit for each statement execute function public.block_change();

alter table public.platform_admin_invites enable row level security;
alter table public.platform_audit enable row level security;
revoke all on public.platform_admin_invites from anon, public, authenticated;
revoke all on public.platform_audit from anon, public, authenticated;

create function public.add_platform_audit(p_action text, p_details text, p_actor_email text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_prev text; v_seq bigint; v_at timestamptz := clock_timestamp(); v_who text;
begin
  perform pg_advisory_xact_lock(hashtext('platform_audit'));
  select hash, seq into v_prev, v_seq from platform_audit order by seq desc limit 1;
  v_prev := coalesce(v_prev, 'GENESIS'); v_seq := coalesce(v_seq, 0) + 1;
  v_who := coalesce(p_actor_email, (select email from auth.users where id = auth.uid()), 'System');
  insert into platform_audit(seq, actor_user_id, actor_email, action, details, created_at, prev_hash, hash)
  values (v_seq, auth.uid(), v_who, p_action, coalesce(p_details,''), v_at, v_prev,
    encode(sha256(convert_to(concat_ws('|', v_prev, v_seq::text, v_who, p_action, coalesce(p_details,''),
      to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')), 'UTF8')), 'hex'));
end $$;

create function public.is_platform_owner() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from platform_admins where user_id = auth.uid() and role = 'owner');
$$;

create function public.require_platform_owner() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_owner() then raise exception 'Only the platform owner can change administrators.'; end if;
end $$;

-- New sign-up: the owner email becomes owner; an invited email becomes admin.
create or replace function public.make_owner_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) = 'danmclaston@gmail.com' then
    insert into public.platform_admins(user_id, role) values (new.id, 'owner') on conflict (user_id) do update set role = 'owner';
  elsif exists(select 1 from public.platform_admin_invites where email = lower(trim(new.email))) then
    insert into public.platform_admins(user_id, role, added_by)
      select new.id, 'admin', invited_by from public.platform_admin_invites where email = lower(trim(new.email))
      on conflict do nothing;
    delete from public.platform_admin_invites where email = lower(trim(new.email));
    perform public.add_platform_audit('ADMIN_JOINED', lower(new.email) || ' signed up and became administrator', lower(new.email));
  end if;
  return new;
end $$;

create function public.list_platform_admins() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  return jsonb_build_object(
    'me_owner', public.is_platform_owner(),
    'admins', (select coalesce(jsonb_agg(jsonb_build_object('user_id', a.user_id, 'email', u.email, 'name', p.full_name,
        'role', a.role, 'added_at', a.created_at, 'added_by', b.email, 'is_me', a.user_id = auth.uid())
        order by a.role desc, a.created_at), '[]'::jsonb)
      from platform_admins a join auth.users u on u.id = a.user_id
      left join profiles p on p.user_id = a.user_id left join auth.users b on b.id = a.added_by),
    'invites', (select coalesce(jsonb_agg(jsonb_build_object('email', i.email, 'invited_at', i.created_at) order by i.created_at), '[]'::jsonb)
      from platform_admin_invites i),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('who', h.actor_email, 'action', h.action, 'details', h.details, 'at', h.created_at)
        order by h.seq desc), '[]'::jsonb) from (select * from platform_audit order by seq desc limit 30) h));
end $$;

-- Search people who have signed up, by email or name. Shows only what is needed to pick someone.
create function public.search_users(p_q text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q text := '%' || lower(trim(coalesce(p_q,''))) || '%';
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  if length(trim(coalesce(p_q,''))) < 2 then raise exception 'Type at least 2 letters.'; end if;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('user_id', u.id, 'email', u.email, 'name', p.full_name,
             'is_admin', exists(select 1 from platform_admins a where a.user_id = u.id)) as x
    from auth.users u left join profiles p on p.user_id = u.id
    where lower(u.email) like q or lower(coalesce(p.full_name,'')) like q
    order by u.email limit 20) s);
end $$;

-- Add by email. Already signed up: admin now. Not yet: they become admin when they sign up.
-- They choose their own password. Nobody else ever knows it.
create function public.add_platform_admin(p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(coalesce(p_email,''))); v_user uuid;
begin
  perform public.require_platform_owner();
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid email.'; end if;
  select id into v_user from auth.users where lower(email) = v_email;
  if v_user is not null then
    if exists(select 1 from platform_admins where user_id = v_user) then raise exception 'This person is already an administrator.'; end if;
    insert into platform_admins(user_id, role, added_by) values (v_user, 'admin', auth.uid());
    perform public.add_platform_audit('ADD_ADMIN', v_email);
    return jsonb_build_object('status', 'added', 'email', v_email);
  end if;
  insert into platform_admin_invites(email, invited_by) values (v_email, auth.uid()) on conflict (email) do nothing;
  perform public.add_platform_audit('INVITE_ADMIN', v_email || ' (not signed up yet)');
  return jsonb_build_object('status', 'invited', 'email', v_email);
end $$;

create function public.remove_platform_admin(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a platform_admins; v_email text;
begin
  perform public.require_platform_owner();
  select * into a from platform_admins where user_id = p_user;
  if a.user_id is null then raise exception 'This person is not an administrator.'; end if;
  if a.role = 'owner' then raise exception 'The owner cannot be removed.'; end if;
  select email into v_email from auth.users where id = p_user;
  delete from platform_admins where user_id = p_user;
  perform public.add_platform_audit('REMOVE_ADMIN', coalesce(v_email, p_user::text));
end $$;

create function public.cancel_admin_invite(p_email text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_platform_owner();
  delete from platform_admin_invites where email = lower(trim(p_email));
  if not found then raise exception 'No invite for that email.'; end if;
  perform public.add_platform_audit('CANCEL_INVITE', lower(trim(p_email)));
end $$;

-- ========== WHO MAY CALL WHAT ==========
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('save_gateway_account','can_manage_gateway','gateway_payment_started','settle_gateway_payment','can_see_gateway_payment',
    'gateway_status','disable_gateway','create_gateway_payment','list_gateway_payments',
    'add_platform_audit','is_platform_owner','require_platform_owner','make_owner_admin',
    'list_platform_admins','search_users','add_platform_admin','remove_platform_admin','cancel_admin_invite') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('save_gateway_account','can_manage_gateway','gateway_payment_started','settle_gateway_payment','can_see_gateway_payment') then
      -- Server function only. It checked the person's sign-in first.
      execute format('grant execute on function %s to service_role', f.sig);
    elsif f.proname in ('gateway_status','disable_gateway','create_gateway_payment','list_gateway_payments',
                        'is_platform_owner','list_platform_admins','search_users','add_platform_admin','remove_platform_admin','cancel_admin_invite') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
grant select, insert, update on public.gateway_accounts, public.gateway_payments to service_role;
