-- Loan rules: how interest works, when it starts, how the loan is paid back, and what lateness costs.
-- Run after 20261107000500_countries_prefs.sql.
--
-- Old loans keep their old maths (schedule_version 1). New loans use these rules (schedule_version 2).
-- Every number is worked out from the rules and the payment dates, so anyone can check it again later.

-- ========== 1. THE RULES ==========
-- interest_mode   none | once (one fee on the whole loan) | monthly | yearly
-- calculation     flat (on the full loan) | reducing_balance (on what is still owed)   [monthly/yearly only]
-- free_months     the first months with no interest (monthly/yearly only)
-- repayment_plan  monthly (pay a part every month) | end (pay everything on the last day)
-- late_fee_type   none | fixed (an amount) | percent (of the missed payment)
-- late_fee_every  once | day | week | month    (how often the fee is added while still late)
-- late_fee_grace_days  days after the due date before any fee
-- late_fee_cap_pct     late fees never pass this % of the loan (empty = no limit)

alter table public.organizations
  add column loan_interest_mode text not null default 'yearly' check (loan_interest_mode in ('none','once','monthly','yearly')),
  add column loan_interest_rate numeric(6,2) not null default 10 check (loan_interest_rate between 0 and 100),
  add column loan_calculation text not null default 'flat' check (loan_calculation in ('flat','reducing_balance')),
  add column loan_free_months int not null default 0 check (loan_free_months between 0 and 59),
  add column loan_repayment_plan text not null default 'monthly' check (loan_repayment_plan in ('monthly','end')),
  add column late_fee_type text not null default 'none' check (late_fee_type in ('none','fixed','percent')),
  add column late_fee_amount bigint not null default 0 check (late_fee_amount >= 0),
  add column late_fee_pct numeric(6,2) not null default 0 check (late_fee_pct between 0 and 100),
  add column late_fee_every text not null default 'once' check (late_fee_every in ('once','day','week','month')),
  add column late_fee_grace_days int not null default 0 check (late_fee_grace_days between 0 and 90),
  add column late_fee_cap_pct numeric(6,2) check (late_fee_cap_pct is null or late_fee_cap_pct between 0 and 1000);
-- Existing groups keep what they had: their yearly rate.
update public.organizations set loan_interest_rate = default_interest_rate_pct;

alter table public.loans
  add column schedule_version int not null default 1 check (schedule_version in (1,2)),
  add column interest_mode text not null default 'yearly' check (interest_mode in ('none','once','monthly','yearly')),
  add column interest_rate numeric(6,2) check (interest_rate between 0 and 100),
  add column free_months int not null default 0 check (free_months >= 0),
  add column repayment_plan text not null default 'monthly' check (repayment_plan in ('monthly','end')),
  add column late_fee_type text not null default 'none' check (late_fee_type in ('none','fixed','percent')),
  add column late_fee_amount bigint not null default 0 check (late_fee_amount >= 0),
  add column late_fee_pct numeric(6,2) not null default 0 check (late_fee_pct between 0 and 100),
  add column late_fee_every text not null default 'once' check (late_fee_every in ('once','day','week','month')),
  add column late_fee_grace_days int not null default 0 check (late_fee_grace_days between 0 and 90),
  add column late_fee_cap_pct numeric(6,2) check (late_fee_cap_pct is null or late_fee_cap_pct between 0 and 1000);
update public.loans set interest_rate = interest_rate_pct;

-- Part of each repayment that paid late fees.
alter table public.loan_repayments add column fee_portion bigint not null default 0 check (fee_portion >= 0);

-- Late fees the group forgave. Permanent and in the audit trail.
create table public.loan_fee_waivers (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.loans(id),
  org_id uuid not null references public.organizations(id),
  amount bigint not null check (amount > 0),
  reason text not null check (length(trim(reason)) >= 3),
  waived_by uuid not null references public.members(id),
  created_at timestamptz not null default now()
);
create trigger loan_fee_waivers_no_change before update or delete on public.loan_fee_waivers for each row execute function public.block_change();
alter table public.loan_fee_waivers enable row level security;
revoke all on public.loan_fee_waivers from anon, public, authenticated;

-- ========== 2. THE MATHS ==========
-- Whole money units only (rounded down). Due dates are calendar months after the start.
create function public.calc_schedule2(p_principal bigint, p_rate numeric, p_mode text, p_calc text, p_term int,
  p_free int, p_plan text, p_start date)
returns table(installment int, due_date date, principal_due bigint, interest_due bigint, total_due bigint, ending_balance bigint)
language plpgsql immutable set search_path = public as $$
declare
  -- Multiply first, divide last, so 10% a year on 12000 for 1 month is exactly 100 (not 99.99...).
  d numeric := case p_mode when 'monthly' then 100 when 'yearly' then 1200 else 1 end;
  v_free int := case when p_mode in ('monthly','yearly') then least(greatest(coalesce(p_free,0),0), p_term - 1) else 0 end;
  v_total bigint; v_n int; v_base bigint; v_rest bigint; v_mp bigint; v_pr bigint; v_rem bigint := p_principal; i int;
begin
  if p_term < 1 then raise exception 'Term must be at least 1 month.'; end if;
  -- Pay everything on the last day.
  if p_plan = 'end' then
    installment := 1; due_date := (p_start + make_interval(months => p_term))::date; principal_due := p_principal;
    interest_due := case p_mode
      when 'none' then 0
      when 'once' then floor(p_principal * p_rate / 100)::bigint
      else floor(p_principal * p_rate * (p_term - v_free) / d)::bigint end;  -- nothing paid back early, so flat = reducing
    total_due := principal_due + interest_due; ending_balance := 0;
    return next; return;
  end if;
  -- Pay a part every month.
  v_mp := p_principal / p_term; v_pr := p_principal % p_term;
  if p_mode = 'once' then v_total := floor(p_principal * p_rate / 100)::bigint; v_n := p_term;
  elsif p_mode in ('monthly','yearly') and p_calc = 'flat' then v_total := floor(p_principal * p_rate * (p_term - v_free) / d)::bigint; v_n := p_term - v_free;
  else v_total := 0; v_n := 1; end if;
  v_base := v_total / v_n; v_rest := v_total % v_n;
  for i in 1..p_term loop
    installment := i; due_date := (p_start + make_interval(months => i))::date;
    principal_due := v_mp + case when i = p_term then v_pr else 0 end;
    if p_mode = 'once' then
      interest_due := v_base + case when i = p_term then v_rest else 0 end;
    elsif p_mode in ('monthly','yearly') and p_calc = 'flat' then
      interest_due := case when i <= v_free then 0 else v_base + case when i = p_term then v_rest else 0 end end;
    elsif p_mode in ('monthly','yearly') then
      interest_due := case when i <= v_free then 0 else floor(v_rem * p_rate / d)::bigint end;
    else
      interest_due := 0;
    end if;
    v_rem := v_rem - principal_due;
    total_due := principal_due + interest_due; ending_balance := greatest(v_rem, 0);
    return next;
  end loop;
end $$;

-- One door for both kinds of loan.
create function public.loan_sched(p_loan uuid)
returns table(installment int, due_date date, principal_due bigint, interest_due bigint, total_due bigint, ending_balance bigint)
language plpgsql stable security definer set search_path = public as $$
declare l loans;
begin
  select * into l from loans where id = p_loan;
  if l.schedule_version = 2 then
    return query select * from public.calc_schedule2(l.principal, l.interest_rate, l.interest_mode, l.calculation_type, l.term_months,
      l.free_months, l.repayment_plan, coalesce(l.disbursed_at::date, current_date));
  else
    return query select * from public.calc_schedule(l.principal, l.interest_rate_pct, l.term_months, l.calculation_type, coalesce(l.disbursed_at::date, current_date));
  end if;
end $$;

-- Late fee for one payment that is [p_days] days past its due date.
create function public.late_fee_for(p_installment bigint, p_days int, p_type text, p_amount bigint, p_pct numeric, p_every text, p_grace int)
returns bigint language sql immutable set search_path = public as $$
  select case when p_type = 'none' or p_days - p_grace <= 0 then 0::bigint else
    (case p_type when 'fixed' then p_amount else floor(p_installment * p_pct / 100)::bigint end) *
    (case p_every when 'once' then 1 when 'day' then p_days - p_grace
                  when 'week' then ceil((p_days - p_grace) / 7.0)::int else ceil((p_days - p_grace) / 30.0)::int end)
  end;
$$;

-- Every late payment, how late it was, and its fee. A payment stops getting fees the day it is fully paid.
create function public.loan_late_fees(p_loan uuid, p_asof date default current_date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l loans; s record; r record; v_due_cum bigint := 0; v_paid_cum bigint := 0; v_covered date;
  v_days int; v_fee bigint; v_total bigint := 0; v_rows jsonb := '[]'::jsonb; v_cap bigint; v_pays jsonb;
begin
  select * into l from loans where id = p_loan;
  if l.id is null or l.late_fee_type = 'none' or l.status not in ('active','paid') then
    return jsonb_build_object('total', 0, 'rows', '[]'::jsonb);
  end if;
  -- Money that went to the loan itself (not to fees), oldest first, without reversed payments.
  select coalesce(jsonb_agg(jsonb_build_object('d', r2.created_at::date, 'a', r2.interest_portion + r2.principal_portion) order by r2.created_at), '[]'::jsonb)
    into v_pays from loan_repayments r2
   where r2.loan_id = p_loan and not exists (select 1 from journals j where j.reversal_of = r2.journal_id);
  for s in select * from public.loan_sched(p_loan) order by installment loop
    v_due_cum := v_due_cum + s.total_due;
    -- The day this payment was covered in full (or still open).
    v_covered := null; v_paid_cum := 0;
    for r in select (e->>'d')::date as d, (e->>'a')::bigint as a from jsonb_array_elements(v_pays) e loop
      v_paid_cum := v_paid_cum + r.a;
      if v_paid_cum >= v_due_cum then v_covered := r.d; exit; end if;
    end loop;
    v_days := coalesce(v_covered, p_asof) - s.due_date;
    if v_days > 0 then
      v_fee := public.late_fee_for(s.total_due, v_days, l.late_fee_type, l.late_fee_amount, l.late_fee_pct, l.late_fee_every, l.late_fee_grace_days);
      if v_fee > 0 then
        v_total := v_total + v_fee;
        v_rows := v_rows || jsonb_build_object('installment', s.installment, 'due_date', s.due_date, 'amount_due', s.total_due,
          'paid_on', v_covered, 'days_late', v_days, 'fee', v_fee);
      end if;
    end if;
  end loop;
  if l.late_fee_cap_pct is not null then
    v_cap := floor(l.principal * l.late_fee_cap_pct / 100)::bigint;
    if v_total > v_cap then v_total := v_cap; end if;
  end if;
  return jsonb_build_object('total', v_total, 'rows', v_rows, 'capped', l.late_fee_cap_pct is not null and v_total = v_cap);
end $$;

create function public.loan_fees_paid(p_loan uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(r.fee_portion),0)::bigint from loan_repayments r
   where r.loan_id = p_loan and not exists (select 1 from journals j where j.reversal_of = r.journal_id);
$$;
create function public.loan_fees_waived(p_loan uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount),0)::bigint from loan_fee_waivers where loan_id = p_loan;
$$;
-- Late fees still owed now.
create function public.loan_fees_due(p_loan uuid) returns bigint language sql stable security definer set search_path = public as $$
  select greatest((public.loan_late_fees(p_loan)->>'total')::bigint - public.loan_fees_waived(p_loan) - public.loan_fees_paid(p_loan), 0);
$$;

-- What is left = loan + interest + late fees - forgiven - paid.
create or replace function public.loan_remaining(p_loan uuid) returns bigint language sql stable security definer set search_path = public as $$
  select case when l.status in ('active','paid') then
      l.principal + l.total_interest + (public.loan_late_fees(l.id)->>'total')::bigint - public.loan_fees_waived(l.id) - (public.loan_repaid(l.id)).total
    else 0 end
  from loans l where l.id = p_loan;
$$;

create or replace function public.loan_arrears_days(p_loan uuid) returns int language plpgsql stable security definer set search_path = public as $$
declare l loans; v_paid bigint; v_cum bigint := 0; s record;
begin
  select * into l from loans where id = p_loan;
  if l.status <> 'active' then return 0; end if;
  v_paid := (public.loan_repaid(l.id)).total - public.loan_fees_paid(l.id);
  for s in select * from public.loan_sched(p_loan) order by installment loop
    v_cum := v_cum + s.total_due;
    if v_cum > v_paid then return greatest(current_date - s.due_date, 0); end if;
  end loop;
  return 0;
end $$;

create or replace function public.loan_schedule(p_loan uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare l loans;
begin
  select * into l from loans where id = p_loan;
  if l.id is null then raise exception 'Loan not found.'; end if;
  if not public.is_officer(l.org_id) and l.member_id is distinct from (public.my_member(l.org_id)).id then raise exception 'Not allowed.'; end if;
  return (select jsonb_agg(to_jsonb(s) order by s.installment) from public.loan_sched(p_loan) s);
end $$;

-- ========== 3. SETTING THE RULES ==========
-- Checks a set of rules and fills gaps from the group's own rules.
create function public.loan_terms(p_org uuid, p jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o organizations; t jsonb;
begin
  select * into o from organizations where id = p_org;
  p := coalesce(p, '{}'::jsonb);
  t := jsonb_build_object(
    'interest_mode', coalesce(p->>'interest_mode', o.loan_interest_mode),
    'interest_rate', coalesce((p->>'interest_rate')::numeric, o.loan_interest_rate),
    'calculation', coalesce(p->>'calculation', o.loan_calculation),
    'free_months', coalesce((p->>'free_months')::int, o.loan_free_months),
    'repayment_plan', coalesce(p->>'repayment_plan', o.loan_repayment_plan),
    'late_fee_type', coalesce(p->>'late_fee_type', o.late_fee_type),
    'late_fee_amount', coalesce((p->>'late_fee_amount')::bigint, o.late_fee_amount),
    'late_fee_pct', coalesce((p->>'late_fee_pct')::numeric, o.late_fee_pct),
    'late_fee_every', coalesce(p->>'late_fee_every', o.late_fee_every),
    'late_fee_grace_days', coalesce((p->>'late_fee_grace_days')::int, o.late_fee_grace_days),
    'late_fee_cap_pct', case when p ? 'late_fee_cap_pct' then p->'late_fee_cap_pct' else to_jsonb(o.late_fee_cap_pct) end);
  if t->>'interest_mode' not in ('none','once','monthly','yearly') then raise exception 'Choose how interest works.'; end if;
  if (t->>'interest_rate')::numeric not between 0 and 100 then raise exception 'Interest must be between 0 and 100%%.'; end if;
  if t->>'calculation' not in ('flat','reducing_balance') then raise exception 'Choose flat or reducing.'; end if;
  if (t->>'free_months')::int not between 0 and 59 then raise exception 'Interest-free months must be 0 to 59.'; end if;
  if t->>'repayment_plan' not in ('monthly','end') then raise exception 'Choose monthly or pay at the end.'; end if;
  if t->>'late_fee_type' not in ('none','fixed','percent') then raise exception 'Choose a late fee type.'; end if;
  if (t->>'late_fee_amount')::bigint < 0 or (t->>'late_fee_pct')::numeric not between 0 and 100 then raise exception 'Late fee must not be negative or above 100%%.'; end if;
  if t->>'late_fee_every' not in ('once','day','week','month') then raise exception 'Choose how often the late fee is added.'; end if;
  if (t->>'late_fee_grace_days')::int not between 0 and 90 then raise exception 'Grace days must be 0 to 90.'; end if;
  if nullif(t->>'late_fee_cap_pct','') is not null and (t->>'late_fee_cap_pct')::numeric not between 0 and 1000 then
    raise exception 'Late fee limit must be 0 to 1000%%.';
  end if;
  return t;
end $$;

create function public.set_loan_rules(p_org uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me members; t jsonb;
begin
  me := public.require_role(p_org, array['org_admin']);
  t := public.loan_terms(p_org, p);
  update organizations set
    loan_interest_mode = t->>'interest_mode', loan_interest_rate = (t->>'interest_rate')::numeric,
    default_interest_rate_pct = least(100, round((t->>'interest_rate')::numeric))::int,
    loan_calculation = t->>'calculation', loan_free_months = (t->>'free_months')::int, loan_repayment_plan = t->>'repayment_plan',
    late_fee_type = t->>'late_fee_type', late_fee_amount = (t->>'late_fee_amount')::bigint, late_fee_pct = (t->>'late_fee_pct')::numeric,
    late_fee_every = t->>'late_fee_every', late_fee_grace_days = (t->>'late_fee_grace_days')::int,
    late_fee_cap_pct = nullif(t->>'late_fee_cap_pct','')::numeric
  where id = p_org;
  perform public.add_audit(p_org, 'SET_LOAN_RULES', 'organization', p_org::text, t::text, me.full_name);
end $$;

-- What a loan would cost, before anyone applies. Same maths as the real loan.
create function public.preview_loan(p_org uuid, p_principal bigint, p_term int, p jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t jsonb;
begin
  perform public.require_member_or_platform(p_org);
  if p_principal is null or p_principal <= 0 then raise exception 'Enter a valid amount.'; end if;
  if p_term not between 1 and 60 then raise exception 'Term must be 1 to 60 months.'; end if;
  t := public.loan_terms(p_org, p);
  return jsonb_build_object('terms', t, 'schedule', (select jsonb_agg(to_jsonb(s) order by s.installment)
    from public.calc_schedule2(p_principal, (t->>'interest_rate')::numeric, t->>'interest_mode', t->>'calculation', p_term,
      (t->>'free_months')::int, t->>'repayment_plan', current_date) s));
end $$;

-- ========== 4. APPLYING WITH RULES ==========
-- p_terms: only officers may change the group's rules for one loan. Members get the group's rules.
create function public.apply_loan2(p_org uuid, p_member uuid, p_principal bigint, p_term int, p_terms jsonb, p_purpose text) returns uuid
language plpgsql security definer set search_path = public as $$
declare me members; o organizations; v_sav bigint; v_active bigint; v_cap bigint; v_id uuid; v_no int; v_int bigint; t jsonb;
begin
  me := public.my_member(p_org);
  if me.id is null then raise exception 'You are not an active member of this group.'; end if;
  if p_member <> me.id and me.role not in ('org_admin','loan_officer','treasurer','secretary') then raise exception 'You can only apply for your own loan.'; end if;
  if not exists(select 1 from members where id = p_member and org_id = p_org and is_active) then raise exception 'That member is not active in this group.'; end if;
  if p_principal is null or p_principal <= 0 then raise exception 'Enter a valid amount.'; end if;
  if p_term not between 1 and 60 then raise exception 'Term must be 1 to 60 months.'; end if;
  -- Anyone may pick flat or reducing (as before). Other changes need the admin or loan officer.
  if p_terms is not null and (p_terms - 'calculation') <> '{}'::jsonb and me.role not in ('org_admin','loan_officer') then
    raise exception 'Only the group admin or loan officer can change the rules for one loan.';
  end if;
  t := public.loan_terms(p_org, p_terms);
  select * into o from organizations where id = p_org;
  v_sav := public.member_savings(p_member);
  if v_sav <= 0 then raise exception 'This member has no savings yet.'; end if;
  select coalesce(sum(public.loan_remaining(l.id)),0) into v_active from loans l where l.member_id = p_member and l.status = 'active';
  select v_active + coalesce(sum(l.principal),0) into v_active from loans l where l.member_id = p_member and l.status in ('pending_approval','approved');
  v_cap := v_sav * o.max_loan_multiplier - v_active;
  if p_principal > v_cap then raise exception 'Limit reached. Can borrow up to % (savings x %, less current loans).', greatest(v_cap,0), o.max_loan_multiplier; end if;
  perform pg_advisory_xact_lock(hashtext('loan' || p_org::text));
  select count(*)+1 into v_no from loans where org_id = p_org;
  select coalesce(sum(interest_due),0) into v_int from public.calc_schedule2(p_principal, (t->>'interest_rate')::numeric, t->>'interest_mode',
    t->>'calculation', p_term, (t->>'free_months')::int, t->>'repayment_plan', current_date);
  insert into loans(org_id, member_id, loan_number, principal, interest_rate_pct, term_months, calculation_type, total_interest, purpose, requested_by,
    schedule_version, interest_mode, interest_rate, free_months, repayment_plan, late_fee_type, late_fee_amount, late_fee_pct, late_fee_every,
    late_fee_grace_days, late_fee_cap_pct)
  values (p_org, p_member, 'LN-' || to_char(now(),'YY') || '-' || lpad(v_no::text,4,'0'), p_principal,
    least(100, round((t->>'interest_rate')::numeric))::int, p_term, t->>'calculation', v_int, nullif(trim(p_purpose),''), me.id,
    2, t->>'interest_mode', (t->>'interest_rate')::numeric,
    case when t->>'interest_mode' in ('monthly','yearly') then least((t->>'free_months')::int, p_term - 1) else 0 end,
    t->>'repayment_plan', t->>'late_fee_type', (t->>'late_fee_amount')::bigint, (t->>'late_fee_pct')::numeric, t->>'late_fee_every',
    (t->>'late_fee_grace_days')::int, nullif(t->>'late_fee_cap_pct','')::numeric)
  returning id into v_id;
  perform public.add_audit(p_org, 'APPLY_LOAN', 'loan', v_id::text,
    'Principal ' || p_principal || ', ' || p_term || ' months, interest ' || (t->>'interest_mode') || ' ' || (t->>'interest_rate') || '%, total interest ' || v_int ||
    ', ' || (t->>'repayment_plan') || ', late fee ' || (t->>'late_fee_type'), me.full_name);
  return v_id;
end $$;

-- Old app versions still call apply_loan. They now get the group's rules too.
create or replace function public.apply_loan(p_org uuid, p_member uuid, p_principal bigint, p_term int, p_type text, p_purpose text) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  return public.apply_loan2(p_org, p_member, p_principal, p_term,
    case when p_type is null then null else jsonb_build_object('calculation', p_type) end, p_purpose);
end $$;

-- The group forgives some late fees. Not the borrower themself.
create function public.waive_late_fees(p_loan uuid, p_amount bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare l loans; me members; v_due bigint;
begin
  select * into l from loans where id = p_loan for update;
  if l.id is null then raise exception 'Loan not found.'; end if;
  me := public.require_role(l.org_id, array['org_admin','treasurer']);
  if me.id = l.member_id then raise exception 'Someone else must forgive your own late fees. (Two people rule)'; end if;
  if coalesce(trim(p_reason),'') = '' or length(trim(p_reason)) < 3 then raise exception 'Say why.'; end if;
  v_due := public.loan_fees_due(p_loan);
  if p_amount is null or p_amount <= 0 or p_amount > v_due then raise exception 'You can forgive up to % now.', v_due; end if;
  insert into loan_fee_waivers(loan_id, org_id, amount, reason, waived_by) values (p_loan, l.org_id, p_amount, trim(p_reason), me.id);
  perform public.add_audit(l.org_id, 'WAIVE_LATE_FEES', 'loan', p_loan::text, l.loan_number || ': ' || p_amount || ' forgiven. ' || trim(p_reason), me.full_name);
  if public.loan_remaining(p_loan) = 0 then update loans set status = 'paid' where id = p_loan; end if;
end $$;

-- Late fees on one loan, for the screen.
create function public.loan_late_fee_report(p_loan uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l loans;
begin
  select * into l from loans where id = p_loan;
  if l.id is null then raise exception 'Loan not found.'; end if;
  if not public.is_officer(l.org_id) and l.member_id is distinct from (public.my_member(l.org_id)).id then raise exception 'Not allowed.'; end if;
  return public.loan_late_fees(p_loan) || jsonb_build_object('paid', public.loan_fees_paid(p_loan), 'waived', public.loan_fees_waived(p_loan),
    'due', public.loan_fees_due(p_loan),
    'waivers', (select coalesce(jsonb_agg(jsonb_build_object('amount', w.amount, 'reason', w.reason, 'by', m.full_name, 'at', w.created_at) order by w.created_at), '[]'::jsonb)
      from loan_fee_waivers w join members m on m.id = w.waived_by where w.loan_id = p_loan));
end $$;

-- ========== 5. PAYMENTS: LATE FEES FIRST, THEN INTEREST, THEN THE LOAN ==========
create or replace function public.apply_payment(p payment_records, p_reviewer text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_acc text := public.channel_account(p.channel); v_meet uuid; v_j uuid; v_key text := 'PAY-' || p.id::text;
  v_name text; v_loan loans; v_rem bigint; v_int bigint; v_prin bigint; v_fee bigint; v_paid record; v_cap bigint; v_lines jsonb;
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
    v_rem := public.loan_remaining(v_loan.id);
    if p.amount > v_rem then raise exception 'Payment is bigger than what is left on this loan (%).', v_rem; end if;
    v_fee := least(p.amount, public.loan_fees_due(v_loan.id));                       -- late fees first
    v_int := least(p.amount - v_fee, v_loan.total_interest - v_paid.interest);       -- then interest
    v_prin := p.amount - v_fee - v_int;                                              -- then the loan itself
    v_lines := jsonb_build_array(public.line(v_acc,null,p.amount,0), public.line('1050',p.member_id,0,v_prin), public.line('4010',p.member_id,0,v_int));
    if v_fee > 0 then v_lines := v_lines || jsonb_build_array(public.line('4020',p.member_id,0,v_fee)); end if;
    v_j := public.post_journal(p.org_id, v_key, 'loan_repayment',
      'Repayment for ' || v_loan.loan_number || ' by ' || v_name || case when v_fee > 0 then ' (late fees ' || v_fee || ')' else '' end,
      v_lines, v_meet, null, p.external_ref, p.channel);
    insert into loan_repayments(loan_id, org_id, journal_id, amount, interest_portion, principal_portion, fee_portion)
    values (v_loan.id, p.org_id, v_j, p.amount, v_int, v_prin, v_fee);
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

-- Loans list now also shows late fees.
create or replace function public.list_loans(p_org uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  return (select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object(
      'borrower', m.full_name,
      'remaining', public.loan_remaining(l.id),
      'repaid', (public.loan_repaid(l.id)).total,
      'arrears_days', public.loan_arrears_days(l.id),
      'late_fees_due', public.loan_fees_due(l.id),
      'next_due', (select jsonb_build_object('date', s.due_date, 'amount', s.total_due) from public.loan_sched(l.id) s
                   where l.status = 'active' and (select coalesce(sum(s2.total_due),0) from public.loan_sched(l.id) s2 where s2.installment <= s.installment)
                         > (public.loan_repaid(l.id)).total - public.loan_fees_paid(l.id)
                   order by s.installment limit 1),
      'approver_name', (select full_name from members where id = l.approver_id),
      'witness1_name', (select full_name from members where id = l.witness1_id),
      'witness2_name', (select full_name from members where id = l.witness2_id)
    ) order by l.requested_at desc), '[]'::jsonb)
    from loans l join members m on m.id = l.member_id
    where l.org_id = p_org and (v_off or l.member_id = v_me));
end $$;

-- ========== WHO MAY CALL WHAT ==========
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('calc_schedule2','loan_sched','late_fee_for','loan_late_fees','loan_fees_paid','loan_fees_waived','loan_fees_due','loan_terms',
    'set_loan_rules','preview_loan','apply_loan2','waive_late_fees','loan_late_fee_report') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('set_loan_rules','preview_loan','apply_loan2','waive_late_fees','loan_late_fee_report','calc_schedule2','late_fee_for') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
