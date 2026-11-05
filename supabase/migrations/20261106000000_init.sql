-- SACCO Ledger database. Paste this whole file into Supabase > SQL Editor > Run.
-- Rule 1: the platform NEVER holds money. It only records what groups did with their own money.
-- Rule 2: money rows are append-only. A mistake is fixed by a reversing journal, never an edit.
-- Rule 3: every amount is a whole number in minor units (UGX 1 = 1; KES 1 = 100).
-- Rule 4: apps cannot write to tables. They call the functions below, which check who is asking.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ========== TABLES ==========
create table public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) >= 2),
  edition text not null default 'tier_1_vsla' check (edition in ('tier_1_vsla','tier_2_sacco','tier_3_intelligent')),
  currency_code text not null default 'UGX' check (currency_code in ('UGX','KES','TZS','RWF')),
  cycle_number int not null default 1,
  share_price bigint not null default 5000 check (share_price > 0),
  max_loan_multiplier int not null default 3 check (max_loan_multiplier between 1 and 20),
  default_interest_rate_pct int not null default 10 check (default_interest_rate_pct between 0 and 100),
  meeting_quorum_pct int not null default 67 check (meeting_quorum_pct between 1 and 100),
  mtn_merchant_code text,
  airtel_merchant_code text,
  licence_type text,
  licence_number text,
  licence_expiry date,
  is_demo boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  user_id uuid references auth.users(id),
  member_no int not null,
  full_name text not null check (length(trim(full_name)) >= 2),
  phone text,
  national_id text,
  role text not null default 'member' check (role in ('org_admin','treasurer','secretary','loan_officer','auditor','member')),
  is_active boolean not null default true,
  next_of_kin_name text,
  next_of_kin_phone text,
  invite_code text,
  invite_expires_at timestamptz,
  code_attempts int not null default 0,
  consent_at timestamptz,
  joined_at timestamptz not null default now(),
  unique (org_id, member_no),
  unique (org_id, user_id),
  unique (org_id, phone)
);
create unique index members_invite_code_uq on public.members(invite_code) where invite_code is not null;
create index members_user_idx on public.members(user_id);

create table public.accounts (
  code text primary key,
  name text not null,
  category text not null check (category in ('asset','liability','equity','income','expense'))
);
insert into public.accounts values
 ('1010','Cash in group lockbox','asset'),
 ('1020','Group mobile money / bank','asset'),
 ('1050','Loan portfolio','asset'),
 ('2010','Member savings / shares','liability'),
 ('2100','Emergency fund','liability'),
 ('3010','Retained earnings','equity'),
 ('4010','Interest income','income'),
 ('4020','Fines and fees income','income'),
 ('5010','Operating expenses','expense');

create table public.meetings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  meeting_number int not null,
  meeting_date date not null default current_date,
  status text not null default 'open' check (status in ('open','closed')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opened_by uuid references public.members(id),
  closed_by uuid references public.members(id),
  opening_cash bigint not null check (opening_cash >= 0),
  opening_counter1 uuid not null references public.members(id),
  opening_counter2 uuid not null references public.members(id),
  ledger_cash_at_open bigint not null default 0,
  closing_cash bigint,
  closing_counter1 uuid references public.members(id),
  closing_counter2 uuid references public.members(id),
  minutes text,
  unique (org_id, meeting_number),
  check (opening_counter1 <> opening_counter2)
);
create unique index one_open_meeting on public.meetings(org_id) where status = 'open';

create table public.attendance (
  meeting_id uuid not null references public.meetings(id),
  member_id uuid not null references public.members(id),
  present boolean not null default true,
  primary key (meeting_id, member_id)
);

create table public.journals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  journal_number bigint not null,
  idempotency_key text not null,
  type text not null check (type in ('share_purchase','savings_deposit','savings_withdrawal','loan_disbursement','loan_repayment','fine_collection','emergency_contribution','emergency_payout','operating_expense','share_out','reversal')),
  description text not null,
  actor_user_id uuid,
  actor_name text not null,
  meeting_id uuid references public.meetings(id),
  reversal_of uuid references public.journals(id),
  external_ref text,
  channel text,
  cycle_number int not null default 1,
  created_at timestamptz not null default now(),
  unique (org_id, journal_number),
  unique (org_id, idempotency_key)
);
create unique index journals_one_reversal on public.journals(reversal_of) where reversal_of is not null;
create index journals_org_time on public.journals(org_id, created_at desc);

create table public.journal_lines (
  id bigint generated always as identity primary key,
  journal_id uuid not null references public.journals(id),
  org_id uuid not null references public.organizations(id),
  account_code text not null references public.accounts(code),
  member_id uuid references public.members(id),
  debit bigint not null default 0 check (debit >= 0),
  credit bigint not null default 0 check (credit >= 0),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);
create index lines_org_account on public.journal_lines(org_id, account_code);
create index lines_member on public.journal_lines(member_id);
create index lines_journal on public.journal_lines(journal_id);

create table public.payment_records (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid references public.members(id),
  purpose text not null check (purpose in ('shares','savings','fine','loan_repayment','emergency_contribution','withdrawal','expense')),
  amount bigint not null check (amount > 0),
  channel text not null check (channel in ('mtn_momo','airtel_money','bank','cash')),
  external_ref text,
  payer_phone text,
  loan_id uuid,
  note text,
  status text not null default 'pending' check (status in ('pending','confirmed','rejected','reversed')),
  idempotency_key text not null,
  submitted_by uuid not null references public.members(id),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.members(id),
  reviewed_at timestamptz,
  review_note text,
  journal_id uuid references public.journals(id),
  unique (org_id, idempotency_key),
  check (channel = 'cash' or external_ref is not null)
);
-- The same MoMo/Airtel/bank transaction ID can never be claimed twice in one group.
create unique index payments_no_duplicate_ref on public.payment_records(org_id, channel, upper(external_ref))
  where external_ref is not null and status in ('pending','confirmed');
create index payments_org_status on public.payment_records(org_id, status, submitted_at desc);

create table public.loans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid not null references public.members(id),
  loan_number text not null,
  principal bigint not null check (principal > 0),
  interest_rate_pct int not null check (interest_rate_pct between 0 and 100),
  term_months int not null check (term_months between 1 and 60),
  calculation_type text not null default 'flat' check (calculation_type in ('flat','reducing_balance')),
  total_interest bigint not null default 0,
  purpose text,
  status text not null default 'pending_approval' check (status in ('pending_approval','approved','active','paid','rejected')),
  requested_at timestamptz not null default now(),
  requested_by uuid references public.members(id),
  approver_id uuid references public.members(id),
  approved_at timestamptz,
  resolution_ref text,
  witness1_id uuid references public.members(id),
  witness2_id uuid references public.members(id),
  disburser_id uuid references public.members(id),
  disbursed_at timestamptz,
  disbursement_journal_id uuid references public.journals(id),
  rejected_reason text,
  unique (org_id, loan_number)
);
alter table public.payment_records add constraint payments_loan_fk foreign key (loan_id) references public.loans(id);

create table public.loan_repayments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.loans(id),
  org_id uuid not null references public.organizations(id),
  journal_id uuid not null references public.journals(id),
  amount bigint not null check (amount > 0),
  interest_portion bigint not null check (interest_portion >= 0),
  principal_portion bigint not null check (principal_portion >= 0),
  created_at timestamptz not null default now()
);
create index repayments_loan on public.loan_repayments(loan_id);

create table public.emergency_claims (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid not null references public.members(id),
  amount bigint not null check (amount > 0),
  reason text not null check (length(trim(reason)) >= 3),
  status text not null default 'pending' check (status in ('pending','paid','rejected')),
  requested_at timestamptz not null default now(),
  requested_by uuid references public.members(id),
  decided_by uuid references public.members(id),
  decided_at timestamptz,
  decision_note text,
  channel text,
  external_ref text,
  journal_id uuid references public.journals(id)
);

create table public.shareout_payouts (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organizations(id),
  cycle_number int not null,
  member_id uuid not null references public.members(id),
  savings bigint not null,
  payout bigint not null,
  journal_id uuid not null references public.journals(id),
  created_at timestamptz not null default now(),
  unique (org_id, cycle_number, member_id)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organizations(id),
  seq bigint not null,
  actor_user_id uuid,
  actor_name text not null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details text not null default '',
  created_at timestamptz not null default now(),
  prev_hash text not null,
  hash text not null,
  unique (org_id, seq)
);

-- ========== NOTHING CAN BE EDITED OR DELETED IN THE MONEY TABLES ==========
create function public.block_change() returns trigger language plpgsql as $$
begin
  raise exception 'This record is permanent. Post a reversal instead of changing it.';
end $$;

do $$
declare t text;
begin
  foreach t in array array['journals','journal_lines','loan_repayments','shareout_payouts','audit_log'] loop
    execute format('create trigger %1$s_no_change before update or delete on public.%1$I for each row execute function public.block_change()', t);
    execute format('create trigger %1$s_no_truncate before truncate on public.%1$I for each statement execute function public.block_change()', t);
  end loop;
end $$;

-- Every journal must balance when the transaction finishes.
create function public.check_journal_balanced() returns trigger language plpgsql as $$
declare d bigint; c bigint;
begin
  select coalesce(sum(debit),0), coalesce(sum(credit),0) into d, c from public.journal_lines where journal_id = new.journal_id;
  if d <> c or d = 0 then raise exception 'Journal does not balance (debits %, credits %)', d, c; end if;
  return null;
end $$;
create constraint trigger journal_balanced after insert on public.journal_lines
  deferrable initially deferred for each row execute function public.check_journal_balanced();

-- ========== WHO IS ASKING? ==========
create function public.is_platform_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from platform_admins where user_id = auth.uid());
$$;

create function public.my_member(p_org uuid) returns public.members language sql stable security definer set search_path = public as $$
  select * from members where org_id = p_org and user_id = auth.uid() and is_active limit 1;
$$;

create function public.org_role(p_org uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select role from members where org_id = p_org and user_id = auth.uid() and is_active limit 1),
                  case when public.is_platform_admin() then 'platform_admin' end);
$$;

create function public.is_officer(p_org uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.org_role(p_org) in ('org_admin','treasurer','secretary','loan_officer','auditor','platform_admin');
$$;

-- Throws unless the caller is an active member with one of these roles. Returns their row.
create function public.require_role(p_org uuid, p_roles text[]) returns public.members
language plpgsql stable security definer set search_path = public as $$
declare m members;
begin
  m := public.my_member(p_org);
  if m.id is null then raise exception 'You are not an active member of this group.'; end if;
  if not (m.role = any(p_roles)) then
    raise exception 'Your role (%) cannot do this. Needed: %.', m.role, array_to_string(p_roles, ', ');
  end if;
  return m;
end $$;

create function public.require_member_or_platform(p_org uuid) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if public.org_role(p_org) is null then raise exception 'You are not a member of this group.'; end if;
end $$;

-- ========== AUDIT TRAIL (each row seals the one before, so tampering shows) ==========
create function public.audit_hash(p_prev text, p_org uuid, p_seq bigint, p_actor text, p_action text, p_type text, p_id text, p_details text, p_at timestamptz)
returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(concat_ws('|', p_prev, p_org::text, p_seq::text, p_actor, p_action, p_type, coalesce(p_id,''), p_details,
         to_char(p_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')), 'UTF8')), 'hex');
$$;

create function public.add_audit(p_org uuid, p_action text, p_type text, p_id text, p_details text, p_actor text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_prev text; v_seq bigint; v_at timestamptz := clock_timestamp(); v_actor text;
begin
  perform pg_advisory_xact_lock(hashtext('audit' || p_org::text));
  select hash, seq into v_prev, v_seq from audit_log where org_id = p_org order by seq desc limit 1;
  v_prev := coalesce(v_prev, 'GENESIS'); v_seq := coalesce(v_seq, 0) + 1;
  v_actor := coalesce(p_actor, (public.my_member(p_org)).full_name, 'System');
  insert into audit_log(org_id, seq, actor_user_id, actor_name, action, entity_type, entity_id, details, created_at, prev_hash, hash)
  values (p_org, v_seq, auth.uid(), v_actor, p_action, p_type, p_id, coalesce(p_details,''), v_at, v_prev,
          public.audit_hash(v_prev, p_org, v_seq, v_actor, p_action, p_type, p_id, coalesce(p_details,''), v_at));
end $$;

create function public.verify_audit_chain(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r audit_log; v_prev text := 'GENESIS'; v_seq bigint := 0; v_n bigint := 0;
begin
  if not public.is_officer(p_org) then raise exception 'Only officers can verify the audit trail.'; end if;
  for r in select * from audit_log where org_id = p_org order by seq loop
    v_seq := v_seq + 1; v_n := v_n + 1;
    if r.seq <> v_seq or r.prev_hash <> v_prev or
       r.hash <> public.audit_hash(r.prev_hash, r.org_id, r.seq, r.actor_name, r.action, r.entity_type, r.entity_id, r.details, r.created_at) then
      return jsonb_build_object('ok', false, 'broken_at_seq', r.seq, 'checked', v_n);
    end if;
    v_prev := r.hash;
  end loop;
  return jsonb_build_object('ok', true, 'checked', v_n, 'last_hash', v_prev);
end $$;

-- ========== LEDGER CORE ==========
create function public.account_balance(p_org uuid, p_code text) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(debit - credit),0)::bigint from journal_lines where org_id = p_org and account_code = p_code;
$$;

create function public.member_savings(p_member uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(credit - debit),0)::bigint from journal_lines where member_id = p_member and account_code = '2010';
$$;

create function public.channel_account(p_channel text) returns text language sql immutable as $$
  select case when p_channel = 'cash' then '1010' else '1020' end;
$$;

-- p_lines: [{"a":"1010","m":null,"d":100,"c":0}, ...]
create function public.post_journal(p_org uuid, p_key text, p_type text, p_desc text, p_lines jsonb,
  p_meeting uuid default null, p_reversal_of uuid default null, p_ref text default null, p_channel text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_no bigint; v_total bigint; v_name text;
begin
  select id into v_id from journals where org_id = p_org and idempotency_key = p_key;
  if v_id is not null then return v_id; end if;
  perform pg_advisory_xact_lock(hashtext('journal' || p_org::text));
  select coalesce(max(journal_number),0) + 1 into v_no from journals where org_id = p_org;
  v_name := coalesce((public.my_member(p_org)).full_name, 'System');
  insert into journals(org_id, journal_number, idempotency_key, type, description, actor_user_id, actor_name, meeting_id, reversal_of, external_ref, channel, cycle_number)
  values (p_org, v_no, p_key, p_type, p_desc, auth.uid(), v_name, p_meeting, p_reversal_of, p_ref, p_channel, (select cycle_number from organizations where id = p_org)) returning id into v_id;
  insert into journal_lines(journal_id, org_id, account_code, member_id, debit, credit)
  select v_id, p_org, l->>'a', nullif(l->>'m','')::uuid, coalesce((l->>'d')::bigint,0), coalesce((l->>'c')::bigint,0)
  from jsonb_array_elements(p_lines) l where coalesce((l->>'d')::bigint,0) > 0 or coalesce((l->>'c')::bigint,0) > 0;
  select sum(debit) into v_total from journal_lines where journal_id = v_id;
  perform public.add_audit(p_org, 'POST_JOURNAL_' || upper(p_type), 'journal', v_id::text, '#' || v_no || ' ' || p_desc || ' (total ' || coalesce(v_total,0) || ')', v_name);
  return v_id;
end $$;

create function public.line(p_a text, p_m uuid, p_d bigint, p_c bigint) returns jsonb language sql immutable as $$
  select jsonb_build_object('a', p_a, 'm', p_m, 'd', p_d, 'c', p_c);
$$;

-- ========== LOAN MATHS (flat or reducing, whole units, same as the old Kotlin engine) ==========
create function public.calc_schedule(p_principal bigint, p_rate int, p_term int, p_type text, p_start date)
returns table(installment int, due_date date, principal_due bigint, interest_due bigint, total_due bigint, ending_balance bigint)
language plpgsql immutable as $$
declare i int; v_mp bigint := p_principal / p_term; v_pr bigint := p_principal % p_term;
  v_ti bigint; v_mi bigint; v_ir bigint; v_rem bigint := p_principal; v_bal bigint;
begin
  v_ti := floor(p_principal::numeric * p_rate * p_term / 1200)::bigint;
  v_mi := v_ti / p_term; v_ir := v_ti % p_term; v_bal := p_principal + v_ti;
  for i in 1..p_term loop
    installment := i; due_date := p_start + (i * 30);
    principal_due := v_mp + case when i = p_term then v_pr else 0 end;
    if p_type = 'flat' then
      interest_due := v_mi + case when i = p_term then v_ir else 0 end;
      total_due := principal_due + interest_due;
      v_bal := v_bal - total_due; ending_balance := greatest(v_bal,0);
    else
      interest_due := floor(v_rem::numeric * p_rate / 1200)::bigint;
      total_due := principal_due + interest_due;
      v_rem := v_rem - principal_due; ending_balance := greatest(v_rem,0);
    end if;
    return next;
  end loop;
end $$;

create function public.loan_repaid(p_loan uuid, out total bigint, out interest bigint, out principal bigint)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(r.amount),0)::bigint, coalesce(sum(r.interest_portion),0)::bigint, coalesce(sum(r.principal_portion),0)::bigint
  from loan_repayments r
  where r.loan_id = p_loan and not exists (select 1 from journals j where j.reversal_of = r.journal_id);
$$;

create function public.loan_remaining(p_loan uuid) returns bigint language sql stable security definer set search_path = public as $$
  select case when l.status in ('active','paid') then l.principal + l.total_interest - (public.loan_repaid(l.id)).total else 0 end
  from loans l where l.id = p_loan;
$$;

create function public.loan_arrears_days(p_loan uuid) returns int language plpgsql stable security definer set search_path = public as $$
declare l loans; v_paid bigint; v_cum bigint := 0; s record;
begin
  select * into l from loans where id = p_loan;
  if l.status <> 'active' then return 0; end if;
  v_paid := (public.loan_repaid(l.id)).total;
  for s in select * from public.calc_schedule(l.principal, l.interest_rate_pct, l.term_months, l.calculation_type, l.disbursed_at::date) order by installment loop
    v_cum := v_cum + s.total_due;
    if v_cum > v_paid then return greatest(current_date - s.due_date, 0); end if;
  end loop;
  return 0;
end $$;

-- ========== ORGANIZATIONS AND MEMBERS ==========
create function public.new_code() returns text language plpgsql volatile set search_path = public as $$
declare a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea := extensions.gen_random_bytes(8); r text := ''; i int;
begin
  for i in 0..7 loop r := r || substr(a, (get_byte(b,i) % 32) + 1, 1); end loop;
  return r;
end $$;

create function public.normalize_phone(p text) returns text language plpgsql immutable as $$
declare d text;
begin
  if p is null then return null; end if;
  d := regexp_replace(p, '[^0-9]', '', 'g');
  if d = '' then return null; end if;
  if length(d) = 10 and left(d,1) = '0' then d := '256' || substr(d,2); end if;
  if length(d) = 9 then d := '256' || d; end if;
  return d;
end $$;

create function public.create_organization(p_name text, p_edition text, p_currency text, p_share_price bigint,
  p_multiplier int, p_interest int, p_quorum int, p_my_name text, p_my_phone text, p_consent boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_m uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if not coalesce(p_consent,false) then raise exception 'Please accept the data notice first.'; end if;
  insert into organizations(name, edition, currency_code, share_price, max_loan_multiplier, default_interest_rate_pct, meeting_quorum_pct, created_by)
  values (trim(p_name), p_edition, p_currency, p_share_price, p_multiplier, p_interest, p_quorum, auth.uid()) returning id into v_org;
  insert into members(org_id, user_id, member_no, full_name, phone, role, consent_at)
  values (v_org, auth.uid(), 1, trim(p_my_name), public.normalize_phone(p_my_phone), 'org_admin', now()) returning id into v_m;
  perform public.add_audit(v_org, 'CREATE_ORGANIZATION', 'organization', v_org::text, p_name, trim(p_my_name));
  return v_org;
end $$;

create function public.update_organization(p_org uuid, p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare m members;
begin
  m := public.require_role(p_org, array['org_admin']);
  update organizations set
    name = coalesce(nullif(trim(p->>'name'),''), name),
    edition = coalesce(p->>'edition', edition),
    share_price = coalesce((p->>'share_price')::bigint, share_price),
    max_loan_multiplier = coalesce((p->>'max_loan_multiplier')::int, max_loan_multiplier),
    default_interest_rate_pct = coalesce((p->>'default_interest_rate_pct')::int, default_interest_rate_pct),
    meeting_quorum_pct = coalesce((p->>'meeting_quorum_pct')::int, meeting_quorum_pct),
    mtn_merchant_code = case when p ? 'mtn_merchant_code' then nullif(p->>'mtn_merchant_code','') else mtn_merchant_code end,
    airtel_merchant_code = case when p ? 'airtel_merchant_code' then nullif(p->>'airtel_merchant_code','') else airtel_merchant_code end,
    licence_type = case when p ? 'licence_type' then nullif(p->>'licence_type','') else licence_type end,
    licence_number = case when p ? 'licence_number' then nullif(p->>'licence_number','') else licence_number end,
    licence_expiry = case when p ? 'licence_expiry' then nullif(p->>'licence_expiry','')::date else licence_expiry end
  where id = p_org;
  perform public.add_audit(p_org, 'UPDATE_ORGANIZATION', 'organization', p_org::text, p::text);
end $$;

create function public.add_member(p_org uuid, p_name text, p_phone text, p_national_id text, p_role text, p_kin_name text, p_kin_phone text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a members; v_no int; v_id uuid; v_code text := public.new_code();
begin
  a := public.require_role(p_org, array['org_admin','secretary']);
  if p_role <> 'member' and a.role <> 'org_admin' then raise exception 'Only the organization admin can give officer roles.'; end if;
  perform pg_advisory_xact_lock(hashtext('member' || p_org::text));
  select coalesce(max(member_no),0)+1 into v_no from members where org_id = p_org;
  insert into members(org_id, member_no, full_name, phone, national_id, role, next_of_kin_name, next_of_kin_phone, invite_code, invite_expires_at)
  values (p_org, v_no, trim(p_name), public.normalize_phone(p_phone), nullif(trim(p_national_id),''), p_role, nullif(trim(p_kin_name),''), public.normalize_phone(p_kin_phone), v_code, now() + interval '14 days')
  returning id into v_id;
  perform public.add_audit(p_org, 'ADD_MEMBER', 'member', v_id::text, 'M' || v_no || ' ' || trim(p_name) || ' as ' || p_role);
  return jsonb_build_object('member_id', v_id, 'invite_code', v_code);
exception when unique_violation then
  raise exception 'A member with this phone number is already in this group.';
end $$;

create function public.update_member(p_member uuid, p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare t members; a members;
begin
  select * into t from members where id = p_member;
  if t.id is null then raise exception 'Member not found.'; end if;
  a := public.require_role(t.org_id, array['org_admin','secretary']);
  if p ? 'role' and p->>'role' <> t.role and a.role <> 'org_admin' then raise exception 'Only the organization admin can change roles.'; end if;
  if p ? 'role' and t.id = a.id and p->>'role' <> t.role then raise exception 'You cannot change your own role. Ask another admin.'; end if;
  if (p ? 'is_active') and t.id = a.id and (p->>'is_active')::boolean = false then raise exception 'You cannot deactivate yourself.'; end if;
  update members set
    full_name = coalesce(nullif(trim(p->>'full_name'),''), full_name),
    phone = case when p ? 'phone' then public.normalize_phone(p->>'phone') else phone end,
    national_id = case when p ? 'national_id' then nullif(trim(p->>'national_id'),'') else national_id end,
    role = coalesce(p->>'role', role),
    is_active = coalesce((p->>'is_active')::boolean, is_active),
    next_of_kin_name = case when p ? 'next_of_kin_name' then nullif(trim(p->>'next_of_kin_name'),'') else next_of_kin_name end,
    next_of_kin_phone = case when p ? 'next_of_kin_phone' then public.normalize_phone(p->>'next_of_kin_phone') else next_of_kin_phone end
  where id = p_member;
  perform public.add_audit(t.org_id, 'UPDATE_MEMBER', 'member', p_member::text, (p - 'national_id')::text);
end $$;

-- A fresh one-time code: used to link a new phone, or to reset a forgotten password.
create function public.new_member_code(p_member uuid) returns text language plpgsql security definer set search_path = public as $$
declare t members; v_code text := public.new_code();
begin
  select * into t from members where id = p_member;
  if t.id is null then raise exception 'Member not found.'; end if;
  perform public.require_role(t.org_id, array['org_admin','secretary']);
  update members set invite_code = v_code, invite_expires_at = now() + interval '14 days', code_attempts = 0 where id = p_member;
  perform public.add_audit(t.org_id, 'NEW_MEMBER_CODE', 'member', p_member::text, 'Code issued for ' || t.full_name);
  return v_code;
end $$;

create function public.claim_invite(p_code text, p_consent boolean) returns uuid language plpgsql security definer set search_path = public as $$
declare t members;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if not coalesce(p_consent,false) then raise exception 'Please accept the data notice first.'; end if;
  select * into t from members where invite_code = upper(trim(p_code)) and invite_expires_at > now() and user_id is null for update;
  if t.id is null then raise exception 'This code is wrong or has expired. Ask your group secretary for a new one.'; end if;
  update members set user_id = auth.uid(), invite_code = null, invite_expires_at = null, consent_at = now() where id = t.id;
  perform public.add_audit(t.org_id, 'CLAIM_INVITE', 'member', t.id::text, t.full_name || ' linked an account', t.full_name);
  return t.org_id;
end $$;

-- Forgot password without SMS costs: secretary gives a one-time code. Anyone may call, but the code must match.
create function public.reset_password_with_code(p_email text, p_code text, p_new_password text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_user uuid; t members;
begin
  if length(coalesce(p_new_password,'')) < 6 then raise exception 'Password must have at least 6 characters.'; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
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
  update members set invite_code = null, invite_expires_at = null, code_attempts = 0 where id = t.id;
  perform public.add_audit(t.org_id, 'RESET_PASSWORD', 'member', t.id::text, t.full_name || ' reset password with a code', t.full_name);
  return true;
end $$;

create function public.my_memberships() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) from (
    select to_jsonb(o) || jsonb_build_object('my_role', m.role, 'my_member_id', m.id, 'my_name', m.full_name) as x
    from members m join organizations o on o.id = m.org_id where m.user_id = auth.uid() and m.is_active
    union all
    select to_jsonb(o) || jsonb_build_object('my_role','platform_admin','my_member_id',null,'my_name','Platform Admin')
    from organizations o where public.is_platform_admin()
      and not exists (select 1 from members m where m.org_id = o.id and m.user_id = auth.uid() and m.is_active)
  ) s;
$$;

create function public.list_members(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'member_no', m.member_no, 'full_name', m.full_name, 'role', m.role, 'is_active', m.is_active,
      'savings', public.member_savings(m.id),
      'has_account', m.user_id is not null,
      'phone', case when v_off or m.id = v_me then m.phone end,
      'national_id', case when v_off or m.id = v_me then m.national_id end,
      'next_of_kin_name', case when v_off or m.id = v_me then m.next_of_kin_name end,
      'next_of_kin_phone', case when v_off or m.id = v_me then m.next_of_kin_phone end,
      'invite_code', case when public.org_role(p_org) in ('org_admin','secretary') then m.invite_code end,
      'consent_at', case when v_off or m.id = v_me then m.consent_at end,
      'joined_at', m.joined_at) order by m.member_no), '[]'::jsonb)
    from members m where m.org_id = p_org);
end $$;

-- ========== PAYMENT RECORDS (the heart: money moves on MoMo/Airtel/bank/cash, we only keep the record) ==========
create function public.apply_payment(p payment_records, p_reviewer text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_acc text := public.channel_account(p.channel); v_meet uuid; v_j uuid; v_key text := 'PAY-' || p.id::text;
  v_name text; v_loan loans; v_rem bigint; v_int bigint; v_prin bigint; v_paid record; v_cap bigint;
begin
  select id into v_meet from meetings where org_id = p.org_id and status = 'open';
  select full_name into v_name from members where id = p.member_id;
  if p.purpose = 'shares' then
    v_j := public.post_journal(p.org_id, v_key, 'share_purchase', 'Shares bought by ' || v_name,
      jsonb_build_array(public.line(v_acc,null,p.amount,0), public.line('2010',p.member_id,0,p.amount)), v_meet, null, p.external_ref, p.channel);
  elsif p.purpose = 'savings' then
    v_j := public.post_journal(p.org_id, v_key, 'savings_deposit', 'Savings deposit by ' || v_name,
      jsonb_build_array(public.line(v_acc,null,p.amount,0), public.line('2010',p.member_id,0,p.amount)), v_meet, null, p.external_ref, p.channel);
  elsif p.purpose = 'fine' then
    v_j := public.post_journal(p.org_id, v_key, 'fine_collection', 'Fine paid by ' || v_name || coalesce(': ' || p.note,''),
      jsonb_build_array(public.line(v_acc,null,p.amount,0), public.line('4020',p.member_id,0,p.amount)), v_meet, null, p.external_ref, p.channel);
  elsif p.purpose = 'emergency_contribution' then
    v_j := public.post_journal(p.org_id, v_key, 'emergency_contribution', 'Emergency fund contribution by ' || v_name,
      jsonb_build_array(public.line(v_acc,null,p.amount,0), public.line('2100',p.member_id,0,p.amount)), v_meet, null, p.external_ref, p.channel);
  elsif p.purpose = 'loan_repayment' then
    select * into v_loan from loans where id = p.loan_id for update;
    if v_loan.id is null or v_loan.status <> 'active' then raise exception 'This loan is not active.'; end if;
    v_paid := public.loan_repaid(v_loan.id);
    v_rem := v_loan.principal + v_loan.total_interest - v_paid.total;
    if p.amount > v_rem then raise exception 'Payment is bigger than what is left on this loan (%).', v_rem; end if;
    v_int := least(p.amount, v_loan.total_interest - v_paid.interest); -- interest first, then principal
    v_prin := p.amount - v_int;
    v_j := public.post_journal(p.org_id, v_key, 'loan_repayment', 'Repayment for ' || v_loan.loan_number || ' by ' || v_name,
      jsonb_build_array(public.line(v_acc,null,p.amount,0), public.line('1050',p.member_id,0,v_prin), public.line('4010',p.member_id,0,v_int)), v_meet, null, p.external_ref, p.channel);
    insert into loan_repayments(loan_id, org_id, journal_id, amount, interest_portion, principal_portion)
    values (v_loan.id, p.org_id, v_j, p.amount, v_int, v_prin);
    if p.amount = v_rem then update loans set status = 'paid' where id = v_loan.id; end if;
  elsif p.purpose = 'withdrawal' then
    if p.amount > public.member_savings(p.member_id) then raise exception 'Withdrawal is more than this member''s savings.'; end if;
    select coalesce(sum(public.loan_remaining(l.id)),0) into v_cap from loans l where l.member_id = p.member_id and l.status = 'active';
    if v_cap > 0 then raise exception 'This member has an active loan. Clear it before withdrawing savings.'; end if;
    if p.amount > public.account_balance(p.org_id, v_acc) then raise exception 'Not enough money recorded in this channel.'; end if;
    v_j := public.post_journal(p.org_id, v_key, 'savings_withdrawal', 'Savings withdrawal by ' || v_name,
      jsonb_build_array(public.line('2010',p.member_id,p.amount,0), public.line(v_acc,null,0,p.amount)), v_meet, null, p.external_ref, p.channel);
  elsif p.purpose = 'expense' then
    if p.amount > public.account_balance(p.org_id, v_acc) then raise exception 'Not enough money recorded in this channel.'; end if;
    v_j := public.post_journal(p.org_id, v_key, 'operating_expense', 'Expense: ' || coalesce(p.note,'group expense'),
      jsonb_build_array(public.line('5010',null,p.amount,0), public.line(v_acc,null,0,p.amount)), v_meet, null, p.external_ref, p.channel);
  end if;
  return v_j;
end $$;

create function public.record_payment(p_org uuid, p_member uuid, p_purpose text, p_amount bigint, p_channel text,
  p_ref text, p_payer_phone text, p_loan uuid, p_note text, p_idem text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me members; pm payment_records; v_auto boolean := false; v_j uuid; v_officer boolean; v_existing payment_records;
begin
  me := public.my_member(p_org);
  if me.id is null then raise exception 'You are not an active member of this group.'; end if;
  select * into v_existing from payment_records where org_id = p_org and idempotency_key = p_idem;
  if v_existing.id is not null then return to_jsonb(v_existing); end if; -- safe to retry after bad network
  v_officer := me.role in ('org_admin','treasurer','secretary');
  if p_purpose in ('withdrawal','expense') and not me.role in ('org_admin','treasurer') then
    raise exception 'Only the treasurer or admin can record money going out.';
  end if;
  if p_member is not null and p_member <> me.id and not v_officer then
    raise exception 'You can only record your own payments.';
  end if;
  if p_purpose <> 'expense' and p_member is null then raise exception 'Choose a member.'; end if;
  if p_member is not null and not exists(select 1 from members where id = p_member and org_id = p_org and is_active) then
    raise exception 'That member is not active in this group.';
  end if;
  if p_channel <> 'cash' and coalesce(trim(p_ref),'') = '' then
    raise exception 'Enter the transaction ID from the mobile money or bank message.';
  end if;
  if p_purpose = 'loan_repayment' and not exists(select 1 from loans where id = p_loan and org_id = p_org and member_id = p_member and status = 'active') then
    raise exception 'Choose an active loan for this member.';
  end if;
  begin
    insert into payment_records(org_id, member_id, purpose, amount, channel, external_ref, payer_phone, loan_id, note, idempotency_key, submitted_by)
    values (p_org, p_member, p_purpose, p_amount, p_channel, nullif(upper(trim(p_ref)),''), public.normalize_phone(p_payer_phone), p_loan, nullif(trim(p_note),''), p_idem, me.id)
    returning * into pm;
  exception when unique_violation then
    raise exception 'This transaction ID was already recorded in this group.';
  end;
  perform public.add_audit(p_org, 'RECORD_PAYMENT', 'payment', pm.id::text, p_purpose || ' ' || p_amount || ' via ' || p_channel || coalesce(' ref ' || pm.external_ref,''), me.full_name);
  -- Cash handed over during an open meeting is seen by everyone in the room, so it posts at once.
  v_auto := p_channel = 'cash' and v_officer and p_purpose not in ('withdrawal','expense')
            and exists(select 1 from meetings where org_id = p_org and status = 'open');
  if v_auto then
    v_j := public.apply_payment(pm, me.full_name);
    update payment_records set status = 'confirmed', reviewed_by = me.id, reviewed_at = now(), review_note = 'Posted in open meeting', journal_id = v_j
      where id = pm.id returning * into pm;
  end if;
  return to_jsonb(pm);
end $$;

create function public.review_payment(p_payment uuid, p_approve boolean, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pm payment_records; me members; v_j uuid;
begin
  select * into pm from payment_records where id = p_payment for update;
  if pm.id is null then raise exception 'Payment record not found.'; end if;
  me := public.require_role(pm.org_id, array['org_admin','treasurer']);
  if pm.status <> 'pending' then raise exception 'This record was already reviewed.'; end if;
  if me.id = pm.submitted_by then raise exception 'Someone else must review this: you submitted it. (Two people rule)'; end if;
  if me.id = pm.member_id then raise exception 'Someone else must review this: it is your own money. (Two people rule)'; end if;
  if p_approve then
    v_j := public.apply_payment(pm, me.full_name);
    update payment_records set status = 'confirmed', reviewed_by = me.id, reviewed_at = now(), review_note = nullif(trim(p_note),''), journal_id = v_j where id = pm.id returning * into pm;
  else
    if coalesce(trim(p_note),'') = '' then raise exception 'Say why you are rejecting this.'; end if;
    update payment_records set status = 'rejected', reviewed_by = me.id, reviewed_at = now(), review_note = trim(p_note) where id = pm.id returning * into pm;
  end if;
  perform public.add_audit(pm.org_id, case when p_approve then 'CONFIRM_PAYMENT' else 'REJECT_PAYMENT' end, 'payment', pm.id::text, coalesce(p_note,''), me.full_name);
  return to_jsonb(pm);
end $$;

create function public.list_payments(p_org uuid, p_status text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select to_jsonb(p) || jsonb_build_object('member_name', m.full_name, 'submitted_by_name', s.full_name, 'reviewed_by_name', r.full_name, 'loan_number', l.loan_number) as x
    from payment_records p
    left join members m on m.id = p.member_id
    left join members s on s.id = p.submitted_by
    left join members r on r.id = p.reviewed_by
    left join loans l on l.id = p.loan_id
    where p.org_id = p_org and (p_status is null or p.status = p_status) and (v_off or p.member_id = v_me or p.submitted_by = v_me)
    order by p.submitted_at desc limit p_limit) s);
end $$;

-- ========== REVERSALS ==========
create function public.reverse_journal(p_journal uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare j journals; me members; v_lines jsonb; v_id uuid; v_loan loans;
begin
  select * into j from journals where id = p_journal;
  if j.id is null then raise exception 'Journal not found.'; end if;
  me := public.require_role(j.org_id, array['org_admin','treasurer']);
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required for every reversal.'; end if;
  if j.type in ('reversal','share_out') then raise exception 'This kind of journal cannot be reversed.'; end if;
  if exists(select 1 from journals where reversal_of = j.id) then raise exception 'This journal was already reversed.'; end if;
  if j.type = 'loan_disbursement' then
    select * into v_loan from loans where disbursement_journal_id = j.id for update;
    if (public.loan_repaid(v_loan.id)).total > 0 then raise exception 'Reverse the repayments on this loan first.'; end if;
  end if;
  select jsonb_agg(public.line(l.account_code, l.member_id, l.credit, l.debit)) into v_lines from journal_lines l where l.journal_id = j.id;
  v_id := public.post_journal(j.org_id, 'REV-' || j.id::text, 'reversal', 'Reversal of #' || j.journal_number || ': ' || trim(p_reason), v_lines, null, j.id);
  -- Keep the linked records truthful.
  update payment_records set status = 'reversed' where journal_id = j.id;
  if j.type = 'loan_disbursement' then
    update loans set status = 'approved', disbursed_at = null, disburser_id = null, disbursement_journal_id = null where id = v_loan.id;
  elsif j.type = 'loan_repayment' then
    update loans l set status = 'active' from loan_repayments r where r.journal_id = j.id and l.id = r.loan_id and l.status = 'paid';
  elsif j.type = 'emergency_payout' then
    update emergency_claims set status = 'pending', decided_by = null, decided_at = null, journal_id = null where journal_id = j.id;
  end if;
  return v_id;
end $$;

-- ========== MEETINGS ==========
create function public.open_meeting(p_org uuid, p_date date, p_cash bigint, p_c1 uuid, p_c2 uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me members; v_no int; v_id uuid; v_ledger bigint;
begin
  me := public.require_role(p_org, array['org_admin','treasurer','secretary']);
  if p_c1 = p_c2 then raise exception 'Two different people must count the cash.'; end if;
  if (select count(*) from members where id in (p_c1,p_c2) and org_id = p_org and is_active) <> 2 then raise exception 'Both counters must be active members.'; end if;
  if exists(select 1 from meetings where org_id = p_org and status = 'open') then raise exception 'Another meeting is still open. Close it first.'; end if;
  select coalesce(max(meeting_number),0)+1 into v_no from meetings where org_id = p_org;
  v_ledger := public.account_balance(p_org,'1010');
  insert into meetings(org_id, meeting_number, meeting_date, opened_by, opening_cash, opening_counter1, opening_counter2, ledger_cash_at_open)
  values (p_org, v_no, coalesce(p_date,current_date), me.id, p_cash, p_c1, p_c2, v_ledger) returning id into v_id;
  insert into attendance(meeting_id, member_id, present) select v_id, id, false from members where org_id = p_org and is_active;
  perform public.add_audit(p_org, 'OPEN_MEETING', 'meeting', v_id::text, 'Meeting #' || v_no || ' opened. Counted ' || p_cash || ', ledger says ' || v_ledger, me.full_name);
  return v_id;
end $$;

create function public.set_attendance(p_meeting uuid, p_member uuid, p_present boolean) returns void
language plpgsql security definer set search_path = public as $$
declare mt meetings;
begin
  select * into mt from meetings where id = p_meeting;
  if mt.id is null or mt.status <> 'open' then raise exception 'This meeting is not open.'; end if;
  perform public.require_role(mt.org_id, array['org_admin','treasurer','secretary']);
  insert into attendance(meeting_id, member_id, present) values (p_meeting, p_member, p_present)
  on conflict (meeting_id, member_id) do update set present = excluded.present;
end $$;

create function public.close_meeting(p_meeting uuid, p_cash bigint, p_c1 uuid, p_c2 uuid, p_minutes text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mt meetings; me members; v_ledger bigint; v_diff bigint;
begin
  select * into mt from meetings where id = p_meeting for update;
  if mt.id is null or mt.status <> 'open' then raise exception 'This meeting is not open.'; end if;
  me := public.require_role(mt.org_id, array['org_admin','treasurer','secretary']);
  if p_c1 = p_c2 then raise exception 'Two different people must count the closing cash.'; end if;
  v_ledger := public.account_balance(mt.org_id,'1010');
  v_diff := p_cash - v_ledger;
  if v_diff <> 0 then
    -- Meeting stays open until the count matches.
    raise exception 'Cash does not match. Counted %, ledger says %. % of %. Recount or find the missing record.', p_cash, v_ledger,
      case when v_diff > 0 then 'Surplus' else 'Shortage' end, abs(v_diff);
  end if;
  update meetings set status = 'closed', closed_at = now(), closed_by = me.id, closing_cash = p_cash, closing_counter1 = p_c1, closing_counter2 = p_c2, minutes = nullif(trim(p_minutes),'') where id = p_meeting;
  perform public.add_audit(mt.org_id, 'CLOSE_MEETING', 'meeting', p_meeting::text, 'Meeting #' || mt.meeting_number || ' closed. Cash reconciled at ' || p_cash, me.full_name);
  return jsonb_build_object('ok', true, 'ledger_cash', v_ledger);
end $$;

create function public.list_meetings(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_member_or_platform(p_org);
  return (select coalesce(jsonb_agg(to_jsonb(mt) || jsonb_build_object(
      'attendance', (select coalesce(jsonb_agg(jsonb_build_object('member_id', a.member_id, 'present', a.present, 'name', m.full_name, 'role', m.role) order by m.member_no), '[]'::jsonb)
                     from attendance a join members m on m.id = a.member_id where a.meeting_id = mt.id)
    ) order by mt.meeting_number desc), '[]'::jsonb) from meetings mt where mt.org_id = p_org);
end $$;

-- ========== LOANS ==========
create function public.apply_loan(p_org uuid, p_member uuid, p_principal bigint, p_term int, p_type text, p_purpose text) returns uuid
language plpgsql security definer set search_path = public as $$
declare me members; o organizations; v_sav bigint; v_active bigint; v_cap bigint; v_id uuid; v_no int; v_int bigint;
begin
  me := public.my_member(p_org);
  if me.id is null then raise exception 'You are not an active member of this group.'; end if;
  if p_member <> me.id and me.role not in ('org_admin','loan_officer','treasurer','secretary') then raise exception 'You can only apply for your own loan.'; end if;
  if not exists(select 1 from members where id = p_member and org_id = p_org and is_active) then raise exception 'That member is not active in this group.'; end if;
  select * into o from organizations where id = p_org;
  v_sav := public.member_savings(p_member);
  if v_sav <= 0 then raise exception 'This member has no savings yet.'; end if;
  select coalesce(sum(public.loan_remaining(l.id)),0) into v_active from loans l where l.member_id = p_member and l.status = 'active';
  select v_active + coalesce(sum(l.principal),0) into v_active from loans l where l.member_id = p_member and l.status in ('pending_approval','approved');
  v_cap := v_sav * o.max_loan_multiplier - v_active;
  if p_principal > v_cap then raise exception 'Limit reached. Can borrow up to % (savings x %, less current loans).', greatest(v_cap,0), o.max_loan_multiplier; end if;
  perform pg_advisory_xact_lock(hashtext('loan' || p_org::text));
  select count(*)+1 into v_no from loans where org_id = p_org;
  select coalesce(sum(interest_due),0) into v_int from public.calc_schedule(p_principal, o.default_interest_rate_pct, p_term, p_type, current_date);
  insert into loans(org_id, member_id, loan_number, principal, interest_rate_pct, term_months, calculation_type, total_interest, purpose, requested_by)
  values (p_org, p_member, 'LN-' || to_char(now(),'YY') || '-' || lpad(v_no::text,4,'0'), p_principal, o.default_interest_rate_pct, p_term, p_type, v_int, nullif(trim(p_purpose),''), me.id)
  returning id into v_id;
  perform public.add_audit(p_org, 'APPLY_LOAN', 'loan', v_id::text, 'Principal ' || p_principal || ', ' || p_term || ' months', me.full_name);
  return v_id;
end $$;

create function public.approve_loan(p_loan uuid, p_resolution text, p_w1 uuid, p_w2 uuid) returns void
language plpgsql security definer set search_path = public as $$
declare l loans; me members;
begin
  select * into l from loans where id = p_loan for update;
  if l.id is null then raise exception 'Loan not found.'; end if;
  me := public.require_role(l.org_id, array['org_admin','loan_officer']);
  if l.status <> 'pending_approval' then raise exception 'This loan is not waiting for approval.'; end if;
  if me.id = l.member_id then raise exception 'A borrower cannot approve their own loan.'; end if;
  if p_w1 is null or p_w2 is null or p_w1 = p_w2 then raise exception 'Two different witnesses are required.'; end if;
  if l.member_id in (p_w1,p_w2) then raise exception 'A borrower cannot witness their own loan.'; end if;
  if (select count(*) from members where id in (p_w1,p_w2) and org_id = l.org_id and is_active) <> 2 then raise exception 'Witnesses must be active members.'; end if;
  if coalesce(trim(p_resolution),'') = '' then raise exception 'Enter the committee resolution reference.'; end if;
  update loans set status = 'approved', approver_id = me.id, approved_at = now(), resolution_ref = trim(p_resolution), witness1_id = p_w1, witness2_id = p_w2 where id = p_loan;
  perform public.add_audit(l.org_id, 'APPROVE_LOAN', 'loan', p_loan::text, l.loan_number || ' resolution ' || trim(p_resolution), me.full_name);
end $$;

create function public.reject_loan(p_loan uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare l loans; me members;
begin
  select * into l from loans where id = p_loan for update;
  if l.id is null then raise exception 'Loan not found.'; end if;
  me := public.require_role(l.org_id, array['org_admin','loan_officer']);
  if l.status not in ('pending_approval','approved') then raise exception 'This loan cannot be rejected now.'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'Say why.'; end if;
  update loans set status = 'rejected', rejected_reason = trim(p_reason) where id = p_loan;
  perform public.add_audit(l.org_id, 'REJECT_LOAN', 'loan', p_loan::text, l.loan_number || ': ' || trim(p_reason), me.full_name);
end $$;

create function public.disburse_loan(p_loan uuid, p_channel text, p_ref text) returns uuid
language plpgsql security definer set search_path = public as $$
declare l loans; me members; v_acc text := public.channel_account(p_channel); v_meet uuid; v_j uuid; v_free bigint; v_name text;
begin
  select * into l from loans where id = p_loan for update;
  if l.id is null then raise exception 'Loan not found.'; end if;
  me := public.require_role(l.org_id, array['org_admin','treasurer']);
  if l.status <> 'approved' then raise exception 'This loan is not approved yet.'; end if;
  if me.id = l.approver_id then raise exception 'The person who approved cannot also pay out. (Two people rule)'; end if;
  if me.id = l.member_id then raise exception 'A borrower cannot pay out their own loan.'; end if;
  if p_channel <> 'cash' and coalesce(trim(p_ref),'') = '' then raise exception 'Enter the transaction ID.'; end if;
  -- The emergency fund is never lent.
  v_free := public.account_balance(l.org_id,'1010') + public.account_balance(l.org_id,'1020') + public.account_balance(l.org_id,'2100');
  if l.principal > v_free then raise exception 'Not enough lending money. Available % (emergency fund is protected).', greatest(v_free,0); end if;
  if l.principal > public.account_balance(l.org_id, v_acc) then raise exception 'Not enough money recorded in this channel.'; end if;
  select id into v_meet from meetings where org_id = l.org_id and status = 'open';
  select full_name into v_name from members where id = l.member_id;
  v_j := public.post_journal(l.org_id, 'DISB-' || l.id::text, 'loan_disbursement', 'Loan ' || l.loan_number || ' paid out to ' || v_name,
    jsonb_build_array(public.line('1050',l.member_id,l.principal,0), public.line(v_acc,null,0,l.principal)), v_meet, null, nullif(upper(trim(p_ref)),''), p_channel);
  update loans set status = 'active', disburser_id = me.id, disbursed_at = now(), disbursement_journal_id = v_j where id = p_loan;
  return v_j;
end $$;

create function public.list_loans(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object(
      'borrower', m.full_name,
      'remaining', public.loan_remaining(l.id),
      'repaid', (public.loan_repaid(l.id)).total,
      'arrears_days', public.loan_arrears_days(l.id),
      'approver_name', (select full_name from members where id = l.approver_id),
      'witness1_name', (select full_name from members where id = l.witness1_id),
      'witness2_name', (select full_name from members where id = l.witness2_id)
    ) order by l.requested_at desc), '[]'::jsonb)
    from loans l join members m on m.id = l.member_id
    where l.org_id = p_org and (v_off or l.member_id = v_me));
end $$;

create function public.loan_schedule(p_loan uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare l loans;
begin
  select * into l from loans where id = p_loan;
  if l.id is null then raise exception 'Loan not found.'; end if;
  if not public.is_officer(l.org_id) and l.member_id is distinct from (public.my_member(l.org_id)).id then raise exception 'Not allowed.'; end if;
  return (select jsonb_agg(to_jsonb(s) order by s.installment)
    from public.calc_schedule(l.principal, l.interest_rate_pct, l.term_months, l.calculation_type, coalesce(l.disbursed_at::date, current_date)) s);
end $$;

-- ========== EMERGENCY FUND (separate pot, never lent) ==========
create function public.request_emergency(p_org uuid, p_member uuid, p_amount bigint, p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare me members; v_id uuid;
begin
  me := public.my_member(p_org);
  if me.id is null then raise exception 'You are not an active member of this group.'; end if;
  if p_member <> me.id and me.role not in ('org_admin','treasurer','secretary') then raise exception 'You can only claim for yourself.'; end if;
  insert into emergency_claims(org_id, member_id, amount, reason, requested_by) values (p_org, p_member, p_amount, trim(p_reason), me.id) returning id into v_id;
  perform public.add_audit(p_org, 'REQUEST_EMERGENCY', 'emergency_claim', v_id::text, p_amount || ': ' || trim(p_reason), me.full_name);
  return v_id;
end $$;

create function public.decide_emergency(p_claim uuid, p_approve boolean, p_channel text, p_ref text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare c emergency_claims; me members; v_j uuid; v_acc text; v_name text;
begin
  select * into c from emergency_claims where id = p_claim for update;
  if c.id is null then raise exception 'Claim not found.'; end if;
  me := public.require_role(c.org_id, array['org_admin','treasurer']);
  if c.status <> 'pending' then raise exception 'This claim was already decided.'; end if;
  if me.id = c.member_id then raise exception 'Someone else must decide your own claim. (Two people rule)'; end if;
  if p_approve then
    v_acc := public.channel_account(p_channel);
    if p_channel <> 'cash' and coalesce(trim(p_ref),'') = '' then raise exception 'Enter the transaction ID.'; end if;
    if c.amount > -public.account_balance(c.org_id,'2100') then raise exception 'The emergency fund does not have this much.'; end if;
    if c.amount > public.account_balance(c.org_id, v_acc) then raise exception 'Not enough money recorded in this channel.'; end if;
    select full_name into v_name from members where id = c.member_id;
    v_j := public.post_journal(c.org_id, 'EMG-' || c.id::text || '-' || extract(epoch from now())::bigint, 'emergency_payout', 'Emergency relief to ' || v_name || ': ' || c.reason,
      jsonb_build_array(public.line('2100',c.member_id,c.amount,0), public.line(v_acc,null,0,c.amount)), null, null, nullif(upper(trim(p_ref)),''), p_channel);
    update emergency_claims set status = 'paid', decided_by = me.id, decided_at = now(), decision_note = nullif(trim(p_note),''), channel = p_channel, external_ref = nullif(upper(trim(p_ref)),''), journal_id = v_j where id = p_claim;
  else
    if coalesce(trim(p_note),'') = '' then raise exception 'Say why you are rejecting this.'; end if;
    update emergency_claims set status = 'rejected', decided_by = me.id, decided_at = now(), decision_note = trim(p_note) where id = p_claim;
    perform public.add_audit(c.org_id, 'REJECT_EMERGENCY', 'emergency_claim', p_claim::text, trim(p_note), me.full_name);
  end if;
end $$;

create function public.list_emergency(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('member_name', m.full_name, 'decided_by_name', d.full_name) order by c.requested_at desc), '[]'::jsonb)
    from emergency_claims c join members m on m.id = c.member_id left join members d on d.id = c.decided_by
    where c.org_id = p_org and (v_off or c.member_id = v_me));
end $$;

-- ========== SHARE-OUT (largest remainder: pays out exactly the pool, nothing left over) ==========
create function public.shareout_calc(p_org uuid) returns table(member_id uuid, full_name text, savings bigint, base bigint, remainder numeric, bonus boolean, payout bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_pool bigint; v_total bigint; v_surplus bigint;
begin
  v_pool := public.account_balance(p_org,'1010') + public.account_balance(p_org,'1020') + public.account_balance(p_org,'2100');
  select coalesce(sum(public.member_savings(m.id)),0) into v_total from members m where m.org_id = p_org;
  if v_total <= 0 or v_pool <= 0 then return; end if;
  select v_pool - coalesce(sum(floor(v_pool::numeric * public.member_savings(m.id) / v_total)),0)::bigint into v_surplus from members m where m.org_id = p_org;
  return query
  with b as (
    select m.id, m.full_name, public.member_savings(m.id) as s from members m where m.org_id = p_org and public.member_savings(m.id) > 0
  ), c as (
    select b.*, floor(v_pool::numeric * b.s / v_total)::bigint as base, mod(v_pool::numeric * b.s, v_total) as rem from b
  ), r as (
    select c.*, row_number() over (order by c.rem desc, c.id::text) as rn from c
  )
  select r.id, r.full_name, r.s, r.base, r.rem, r.rn <= v_surplus, r.base + case when r.rn <= v_surplus then 1 else 0 end from r order by r.full_name;
end $$;

create function public.shareout_preview(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_pool bigint;
begin
  perform public.require_member_or_platform(p_org);
  v_pool := greatest(public.account_balance(p_org,'1010') + public.account_balance(p_org,'1020') + public.account_balance(p_org,'2100'),0);
  return jsonb_build_object(
    'pool', v_pool,
    'emergency', -public.account_balance(p_org,'2100'),
    'blockers', (select jsonb_agg(b) from (
        select 'Some loans are still active.' b where exists(select 1 from loans where org_id = p_org and status = 'active')
        union all select 'A meeting is still open.' where exists(select 1 from meetings where org_id = p_org and status = 'open')
        union all select 'Some payment records still wait for review.' where exists(select 1 from payment_records where org_id = p_org and status = 'pending')
      ) x),
    'payouts', (select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.shareout_calc(p_org) s));
end $$;

create function public.execute_shareout(p_org uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare me members; o organizations; r record; v_lines jsonb := '[]'::jsonb; v_pool bigint; v_sum bigint := 0; v_box bigint; v_momo bigint; v_from_box bigint; v_j uuid; v_rows jsonb := '[]'::jsonb;
begin
  me := public.require_role(p_org, array['org_admin','treasurer']);
  select * into o from organizations where id = p_org for update;
  if exists(select 1 from loans where org_id = p_org and status = 'active') then raise exception 'All loans must be repaid before share-out.'; end if;
  if exists(select 1 from meetings where org_id = p_org and status = 'open') then raise exception 'Close the open meeting first.'; end if;
  if exists(select 1 from payment_records where org_id = p_org and status = 'pending') then raise exception 'Review all pending payment records first.'; end if;
  v_box := public.account_balance(p_org,'1010'); v_momo := public.account_balance(p_org,'1020');
  v_pool := v_box + v_momo + public.account_balance(p_org,'2100');
  if v_pool <= 0 then raise exception 'There is nothing to share out.'; end if;
  for r in select * from public.shareout_calc(p_org) loop
    v_lines := v_lines || public.line('2010', r.member_id, r.savings, 0);
    v_sum := v_sum + r.payout;
    v_rows := v_rows || jsonb_build_object('m', r.member_id, 's', r.savings, 'p', r.payout);
  end loop;
  if v_sum <> v_pool then raise exception 'Share-out check failed: % vs %. Nothing was posted.', v_sum, v_pool; end if;
  -- Close income and expense for the cycle, take the pool out of cash, keep the emergency fund.
  v_lines := v_lines || public.line('4010',null,greatest(-public.account_balance(p_org,'4010'),0),0);
  v_lines := v_lines || public.line('4020',null,greatest(-public.account_balance(p_org,'4020'),0),0);
  v_lines := v_lines || public.line('5010',null,0,greatest(public.account_balance(p_org,'5010'),0));
  v_from_box := least(v_box, v_pool);
  v_lines := v_lines || public.line('1010',null,0,v_from_box);
  v_lines := v_lines || public.line('1020',null,0,v_pool - v_from_box);
  -- Anything left between retained earnings and profit/loss goes through 3010.
  declare d bigint; c bigint; begin
    select coalesce(sum((l->>'d')::bigint),0), coalesce(sum((l->>'c')::bigint),0) into d, c from jsonb_array_elements(v_lines) l;
    if d > c then v_lines := v_lines || public.line('3010',null,0,d-c);
    elsif c > d then v_lines := v_lines || public.line('3010',null,c-d,0); end if;
  end;
  v_j := public.post_journal(p_org, 'SHAREOUT-' || p_org::text || '-' || o.cycle_number, 'share_out', 'Cycle ' || o.cycle_number || ' share-out of ' || v_pool, v_lines);
  insert into shareout_payouts(org_id, cycle_number, member_id, savings, payout, journal_id)
  select p_org, o.cycle_number, (x->>'m')::uuid, (x->>'s')::bigint, (x->>'p')::bigint, v_j from jsonb_array_elements(v_rows) x;
  update organizations set cycle_number = cycle_number + 1 where id = p_org;
  perform public.add_audit(p_org, 'EXECUTE_SHAREOUT', 'organization', p_org::text, 'Cycle ' || o.cycle_number || ' closed. Pool ' || v_pool, me.full_name);
  return v_j;
end $$;

-- ========== REPORTS ==========
create function public.trial_balance(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_officer(p_org) then raise exception 'Only officers can see the trial balance.'; end if;
  return (select jsonb_build_object(
    'rows', coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'category', category, 'debit', d, 'credit', c, 'net', d - c) order by code), '[]'::jsonb),
    'total_debit', coalesce(sum(d),0), 'total_credit', coalesce(sum(c),0), 'balanced', coalesce(sum(d),0) = coalesce(sum(c),0))
  from (select a.code, a.name, a.category, coalesce(sum(l.debit),0)::bigint d, coalesce(sum(l.credit),0)::bigint c
        from accounts a left join journal_lines l on l.account_code = a.code and l.org_id = p_org group by a.code, a.name, a.category) t);
end $$;

create function public.list_journals(p_org uuid, p_limit int default 100, p_cycle int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select to_jsonb(j) || jsonb_build_object(
      'is_reversed', exists(select 1 from journals r where r.reversal_of = j.id),
      'total', (select sum(debit) from journal_lines where journal_id = j.id),
      'lines', (select jsonb_agg(jsonb_build_object('account_code', l.account_code, 'account_name', a.name, 'member_name', m.full_name, 'debit', l.debit, 'credit', l.credit) order by l.id)
                from journal_lines l join accounts a on a.code = l.account_code left join members m on m.id = l.member_id where l.journal_id = j.id)) as x
    from journals j
    where j.org_id = p_org and (p_cycle is null or j.cycle_number = p_cycle)
      and (v_off or exists(select 1 from journal_lines l where l.journal_id = j.id and l.member_id = v_me))
    order by j.journal_number desc limit p_limit) s);
end $$;

create function public.member_statement(p_org uuid, p_member uuid, p_cycle int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m members;
begin
  select * into m from members where id = p_member and org_id = p_org;
  if m.id is null then raise exception 'Member not found.'; end if;
  if not public.is_officer(p_org) and m.id is distinct from (public.my_member(p_org)).id then raise exception 'You can only see your own statement.'; end if;
  return jsonb_build_object(
    'member', jsonb_build_object('id', m.id, 'member_no', m.member_no, 'full_name', m.full_name, 'phone', m.phone),
    'savings', public.member_savings(m.id),
    'emergency', coalesce((select sum(credit-debit) from journal_lines where member_id = m.id and account_code = '2100'),0),
    'fines', coalesce((select sum(credit-debit) from journal_lines where member_id = m.id and account_code = '4020'),0),
    'loan_balance', coalesce((select sum(public.loan_remaining(l.id)) from loans l where l.member_id = m.id and l.status = 'active'),0),
    'payouts', (select coalesce(jsonb_agg(to_jsonb(s) order by s.cycle_number),'[]'::jsonb) from shareout_payouts s where s.member_id = m.id),
    'rows', (select coalesce(jsonb_agg(x order by (x->>'journal_number')::bigint, (x->>'line_id')::bigint), '[]'::jsonb) from (
      select jsonb_build_object('line_id', l.id, 'date', j.created_at, 'journal_number', j.journal_number, 'cycle_number', j.cycle_number, 'type', j.type, 'description', j.description,
        'recorded_by', j.actor_name, 'channel', j.channel, 'external_ref', j.external_ref,
        'account_code', l.account_code, 'account_name', a.name, 'debit', l.debit, 'credit', l.credit,
        'is_reversed', exists(select 1 from journals r where r.reversal_of = j.id),
        'savings_after', (select coalesce(sum(l2.credit - l2.debit),0) from journal_lines l2 join journals j2 on j2.id = l2.journal_id
                          where l2.member_id = m.id and l2.account_code = '2010' and (j2.journal_number, l2.id) <= (j.journal_number, l.id))) x
      from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
      where l.member_id = m.id and (p_cycle is null or j.cycle_number = p_cycle)) s));
end $$;

create function public.list_audit(p_org uuid, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_officer(p_org) then raise exception 'Only officers can read the audit trail.'; end if;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select to_jsonb(a) as x from audit_log a where a.org_id = p_org order by a.seq desc limit p_limit) s);
end $$;

create function public.dashboard(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_cash bigint; v_momo bigint; v_sav bigint; v_active bigint := 0; v_par30 bigint := 0; v_par90 bigint := 0; v_top bigint := 0; v_top_no text; v_cnt int := 0;
  r record; v_due bigint := 0; v_coll bigint; v_month_start date := date_trunc('month', current_date)::date; v_month_end date;
begin
  perform public.require_member_or_platform(p_org);
  v_month_end := (v_month_start + interval '1 month')::date;
  v_cash := public.account_balance(p_org,'1010'); v_momo := public.account_balance(p_org,'1020'); v_sav := -public.account_balance(p_org,'2010');
  for r in select l.*, public.loan_remaining(l.id) rem, public.loan_arrears_days(l.id) ar from loans l where l.org_id = p_org and l.status = 'active' loop
    v_cnt := v_cnt + 1; v_active := v_active + r.rem;
    if r.ar > 30 then v_par30 := v_par30 + r.rem; end if;
    if r.ar > 90 then v_par90 := v_par90 + r.rem; end if;
    if r.rem > v_top then v_top := r.rem; v_top_no := r.loan_number; end if;
    select v_due + coalesce(sum(total_due),0) into v_due from public.calc_schedule(r.principal, r.interest_rate_pct, r.term_months, r.calculation_type, r.disbursed_at::date)
      where due_date >= v_month_start and due_date < v_month_end;
  end loop;
  select coalesce(sum(x.amount),0) into v_coll from loan_repayments x where x.org_id = p_org and x.created_at >= v_month_start
    and not exists(select 1 from journals j where j.reversal_of = x.journal_id);
  return jsonb_build_object(
    'cash_box', v_cash, 'momo_bank', v_momo, 'member_savings', v_sav,
    'loan_portfolio', public.account_balance(p_org,'1050'), 'emergency_fund', -public.account_balance(p_org,'2100'),
    'interest_income', -public.account_balance(p_org,'4010'), 'fine_income', -public.account_balance(p_org,'4020'), 'expenses', public.account_balance(p_org,'5010'),
    'members_active', (select count(*) from members where org_id = p_org and is_active),
    'loans_total', (select count(*) from loans where org_id = p_org),
    'active_loans', v_cnt, 'active_portfolio', v_active, 'par30_amount', v_par30, 'par90_amount', v_par90,
    'top_loan_amount', v_top, 'top_loan_number', v_top_no, 'collected_month', v_coll, 'scheduled_month', v_due,
    'pending_payments', (select count(*) from payment_records where org_id = p_org and status = 'pending'),
    'pending_loans', (select count(*) from loans where org_id = p_org and status = 'pending_approval'),
    'pending_emergency', (select count(*) from emergency_claims where org_id = p_org and status = 'pending'),
    'open_meeting_id', (select id from meetings where org_id = p_org and status = 'open'));
end $$;

-- The search box: type anything, get matching people, transactions, loans, meetings, claims and audit rows.
create function public.global_search(p_org uuid, p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
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
    (select jsonb_build_object('kind','journal','id',j.id,'title','#' || j.journal_number || ' ' || j.description,'subtitle',j.type || ' - by ' || j.actor_name || coalesce(' - ref ' || j.external_ref,''),'at',j.created_at)
       from journals j where j.org_id = p_org and (j.description ilike q or j.external_ref ilike q or j.type ilike q or '#' || j.journal_number ilike q or j.actor_name ilike q)
         and (v_off or exists(select 1 from journal_lines l where l.journal_id = j.id and l.member_id = v_me)) order by j.journal_number desc limit 15)
    union all
    (select jsonb_build_object('kind','payment','id',p.id,'title',p.purpose || ' ' || p.amount || ' - ' || coalesce(m.full_name,'group'),'subtitle',p.channel || ' - ' || p.status || coalesce(' - ref ' || p.external_ref,''),'at',p.submitted_at)
       from payment_records p left join members m on m.id = p.member_id where p.org_id = p_org and (p.external_ref ilike q or p.purpose ilike q or p.note ilike q or p.status ilike q or p.channel ilike q or m.full_name ilike q)
         and (v_off or p.member_id = v_me or p.submitted_by = v_me) order by p.submitted_at desc limit 15)
    union all
    (select jsonb_build_object('kind','loan','id',l.id,'title',l.loan_number || ' - ' || m.full_name,'subtitle',l.status || ' - principal ' || l.principal,'at',l.requested_at)
       from loans l join members m on m.id = l.member_id where l.org_id = p_org and (l.loan_number ilike q or m.full_name ilike q or l.status ilike q or l.purpose ilike q or l.resolution_ref ilike q)
         and (v_off or l.member_id = v_me) limit 10)
    union all
    (select jsonb_build_object('kind','meeting','id',mt.id,'title','Meeting #' || mt.meeting_number,'subtitle',mt.status || ' - ' || mt.meeting_date || coalesce(' - ' || left(mt.minutes,60),''),'at',mt.opened_at)
       from meetings mt where mt.org_id = p_org and ('meeting #' || mt.meeting_number ilike q or mt.minutes ilike q or mt.meeting_date::text ilike q or mt.status ilike q) limit 10)
    union all
    (select jsonb_build_object('kind','emergency','id',c.id,'title','Emergency claim - ' || m.full_name,'subtitle',c.status || ' - ' || c.amount || ' - ' || c.reason,'at',c.requested_at)
       from emergency_claims c join members m on m.id = c.member_id where c.org_id = p_org and (c.reason ilike q or m.full_name ilike q or c.status ilike q)
         and (v_off or c.member_id = v_me) limit 10)
    union all
    (select jsonb_build_object('kind','audit','id',a.id,'title',a.action,'subtitle',a.actor_name || ' - ' || left(a.details,80),'at',a.created_at)
       from audit_log a where v_off and a.org_id = p_org and (a.action ilike q or a.actor_name ilike q or a.details ilike q) order by a.seq desc limit 10)
  ) s);
end $$;

create function public.platform_overview() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform admins only.'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'edition',o.edition,'currency_code',o.currency_code,'cycle_number',o.cycle_number,
      'licence_type',o.licence_type,'licence_number',o.licence_number,'licence_expiry',o.licence_expiry,'is_demo',o.is_demo,
      'members',(select count(*) from members where org_id=o.id and is_active),
      'journals',(select count(*) from journals where org_id=o.id),
      'pending',(select count(*) from payment_records where org_id=o.id and status='pending'),
      'created_at',o.created_at) order by o.created_at desc),'[]'::jsonb) from organizations o);
end $$;

-- ========== DEMO DATA (clearly named, for trying the app) ==========
create function public.seed_demo(p_my_name text) returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_me uuid; v_ben uuid; v_cy uuid; v_dan uuid; v_ev uuid; v_t uuid; v_loan uuid; v_j uuid;
  v_int bigint; r record; n int := 0;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  insert into organizations(name, edition, currency_code, is_demo, created_by) values ('Twekembe Savings Group (Demo)','tier_1_vsla','UGX',true,auth.uid()) returning id into v_org;
  insert into members(org_id,user_id,member_no,full_name,role,consent_at) values (v_org,auth.uid(),1,trim(p_my_name),'org_admin',now()) returning id into v_me;
  insert into members(org_id,member_no,full_name,phone,role) values (v_org,2,'Ann Namubiru (demo)','256700000002','treasurer') returning id into v_t;
  insert into members(org_id,member_no,full_name,phone,role) values (v_org,3,'Ben Okello (demo)','256700000003','secretary') returning id into v_ben;
  insert into members(org_id,member_no,full_name,phone,role) values (v_org,4,'Cy Mugisha (demo)','256700000004','loan_officer') returning id into v_cy;
  insert into members(org_id,member_no,full_name,phone) values (v_org,5,'Dan Kato (demo)','256700000005') returning id into v_dan;
  insert into members(org_id,member_no,full_name,phone) values (v_org,6,'Eva Nakato (demo)','256700000006') returning id into v_ev;
  for r in select * from (values (v_me,20000),(v_t,40000),(v_ben,20000),(v_cy,30000),(v_dan,25000),(v_ev,15000)) t(m,a) loop
    n := n + 1;
    perform public.post_journal(v_org,'DEMO-S'||n,'share_purchase','Shares bought (demo)',jsonb_build_array(public.line('1010',null,r.a::bigint,0),public.line('2010',r.m,0,r.a::bigint)));
    perform public.post_journal(v_org,'DEMO-E'||n,'emergency_contribution','Emergency contribution (demo)',jsonb_build_array(public.line('1010',null,1000,0),public.line('2100',r.m,0,1000)));
  end loop;
  perform public.post_journal(v_org,'DEMO-F','fine_collection','Fine for lateness (demo)',jsonb_build_array(public.line('1010',null,2000,0),public.line('4020',v_dan,0,2000)));
  select coalesce(sum(interest_due),0) into v_int from public.calc_schedule(30000,10,3,'flat',current_date - 40);
  v_j := public.post_journal(v_org,'DEMO-D','loan_disbursement','Loan LN-DEMO-0001 paid out (demo)',jsonb_build_array(public.line('1050',v_dan,30000,0),public.line('1010',null,0,30000)));
  insert into loans(org_id,member_id,loan_number,principal,interest_rate_pct,term_months,total_interest,purpose,status,requested_by,approver_id,approved_at,resolution_ref,witness1_id,witness2_id,disburser_id,disbursed_at,disbursement_journal_id)
  values (v_org,v_dan,'LN-DEMO-0001',30000,10,3,v_int,'School fees','active',v_dan,v_cy,now()-interval '41 days','MIN-DEMO-1',v_ben,v_ev,v_t,now()-interval '40 days',v_j);
  perform public.add_audit(v_org,'SEED_DEMO','organization',v_org::text,'Demo data created');
  return v_org;
end $$;

-- ========== ROW SECURITY: nobody writes tables directly; reads limited to your own group ==========
do $$
declare t text;
begin
  foreach t in array array['platform_admins','organizations','members','accounts','meetings','attendance','journals','journal_lines','payment_records','loans','loan_repayments','emergency_claims','shareout_payouts','audit_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

create policy read_own on public.platform_admins for select using (user_id = auth.uid());
create policy read_all on public.accounts for select to authenticated using (true);
create policy read_org on public.organizations for select using (public.org_role(id) is not null);
create policy read_self_or_officer on public.members for select using (user_id = auth.uid() or public.is_officer(org_id));
create policy read_org on public.meetings for select using (public.org_role(org_id) is not null);
create policy read_org on public.attendance for select using (exists(select 1 from public.meetings mt where mt.id = meeting_id and public.org_role(mt.org_id) is not null));
create policy read_officer on public.journals for select using (public.is_officer(org_id));
create policy read_officer_or_self on public.journal_lines for select using (public.is_officer(org_id) or member_id = (public.my_member(org_id)).id);
create policy read_officer_or_self on public.payment_records for select using (public.is_officer(org_id) or member_id = (public.my_member(org_id)).id or submitted_by = (public.my_member(org_id)).id);
create policy read_officer_or_self on public.loans for select using (public.is_officer(org_id) or member_id = (public.my_member(org_id)).id);
create policy read_officer on public.loan_repayments for select using (public.is_officer(org_id));
create policy read_officer_or_self on public.emergency_claims for select using (public.is_officer(org_id) or member_id = (public.my_member(org_id)).id);
create policy read_officer_or_self on public.shareout_payouts for select using (public.is_officer(org_id) or member_id = (public.my_member(org_id)).id);
create policy read_officer on public.audit_log for select using (public.is_officer(org_id));

-- ========== WHO MAY CALL WHAT ==========
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('my_memberships','create_organization','update_organization','add_member','update_member','new_member_code','claim_invite',
    'list_members','record_payment','review_payment','list_payments','reverse_journal','open_meeting','set_attendance','close_meeting','list_meetings',
    'apply_loan','approve_loan','reject_loan','disburse_loan','list_loans','loan_schedule','request_emergency','decide_emergency','list_emergency',
    'shareout_preview','execute_shareout','trial_balance','list_journals','member_statement','list_audit','verify_audit_chain','dashboard','global_search','platform_overview','seed_demo',
    'is_platform_admin','my_member','org_role','is_officer') loop
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  execute 'grant execute on function public.reset_password_with_code(text,text,text) to anon, authenticated';
end $$;
