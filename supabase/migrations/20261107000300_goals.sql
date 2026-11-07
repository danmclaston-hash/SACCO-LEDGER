-- Savings goals. All money stays in the one savings account (2010). A payment can carry a goal label,
-- and the app shows how the savings split: this much for each goal, the rest not for any goal.
-- Labels never change the ledger, so the books balance exactly as before.
-- Run after 20261107000200_owner.sql.

create table public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null check (length(trim(name)) between 2 and 60),
  target bigint not null check (target > 0),
  start_date date not null default current_date,
  end_date date,
  frequency text not null default 'weekly' check (frequency in ('daily','weekly','monthly')),
  per_person bigint check (per_person is null or per_person > 0),
  status text not null default 'active' check (status in ('active','closed')),
  created_by uuid references public.members(id),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check (end_date is null or end_date >= start_date)
);
create index savings_goals_org on public.savings_goals(org_id, status);

alter table public.payment_records add column goal_id uuid references public.savings_goals(id);
create index payments_goal on public.payment_records(goal_id) where goal_id is not null;

alter table public.savings_goals enable row level security;
revoke all on public.savings_goals from anon, public;
revoke insert, update, delete, truncate on public.savings_goals from authenticated;
grant select on public.savings_goals to authenticated;
create policy read_org on public.savings_goals for select using (public.org_role(org_id) is not null);

-- Checks a goal label. Only savings money (shares, savings) can be for a goal.
create function public.check_goal(p_org uuid, p_goal uuid, p_purpose text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_goal is null then return; end if;
  if p_purpose not in ('shares','savings') then raise exception 'Only shares or savings can be for a goal.'; end if;
  if not exists(select 1 from savings_goals where id = p_goal and org_id = p_org and status = 'active') then
    raise exception 'That goal is not open in this group.';
  end if;
end $$;

-- Same as record_payment, plus an optional goal label.
create function public.record_payment(p_org uuid, p_member uuid, p_purpose text, p_amount bigint, p_channel text,
  p_ref text, p_payer_phone text, p_loan uuid, p_note text, p_idem text, p_goal uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform public.check_goal(p_org, p_goal, p_purpose);
  r := public.record_payment(p_org, p_member, p_purpose, p_amount, p_channel, p_ref, p_payer_phone, p_loan, p_note, p_idem);
  if p_goal is not null and (r->>'goal_id') is null then
    update payment_records set goal_id = p_goal where id = (r->>'id')::uuid returning to_jsonb(payment_records.*) into r;
  end if;
  return r;
end $$;

-- Fix a forgotten or wrong label later. Officers only, reason required, kept in the audit trail.
create function public.set_payment_goal(p_payment uuid, p_goal uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare pm payment_records; me members; v_old text; v_new text;
begin
  select * into pm from payment_records where id = p_payment for update;
  if pm.id is null then raise exception 'Payment record not found.'; end if;
  me := public.require_role(pm.org_id, array['org_admin','treasurer','secretary']);
  if coalesce(trim(p_reason),'') = '' then raise exception 'Say why the label is changing.'; end if;
  perform public.check_goal(pm.org_id, p_goal, pm.purpose);
  select name into v_old from savings_goals where id = pm.goal_id;
  select name into v_new from savings_goals where id = p_goal;
  update payment_records set goal_id = p_goal where id = pm.id;
  perform public.add_audit(pm.org_id, 'CHANGE_GOAL_LABEL', 'payment', pm.id::text,
    'From ' || coalesce(v_old, 'no goal') || ' to ' || coalesce(v_new, 'no goal') || ': ' || trim(p_reason), me.full_name);
end $$;

create function public.create_goal(p_org uuid, p_name text, p_target bigint, p_start date, p_end date, p_frequency text, p_per_person bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare me members; v_id uuid;
begin
  me := public.require_role(p_org, array['org_admin','treasurer','secretary']);
  insert into savings_goals(org_id, name, target, start_date, end_date, frequency, per_person, created_by)
  values (p_org, trim(p_name), p_target, coalesce(p_start, current_date), p_end, coalesce(p_frequency,'weekly'), p_per_person, me.id)
  returning id into v_id;
  perform public.add_audit(p_org, 'CREATE_GOAL', 'goal', v_id::text, trim(p_name) || ': target ' || p_target, me.full_name);
  return v_id;
end $$;

create function public.close_goal(p_goal uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g savings_goals; me members;
begin
  select * into g from savings_goals where id = p_goal for update;
  if g.id is null or g.status <> 'active' then raise exception 'This goal is not open.'; end if;
  me := public.require_role(g.org_id, array['org_admin','treasurer','secretary']);
  update savings_goals set status = 'closed', closed_at = now() where id = g.id;
  perform public.add_audit(g.org_id, 'CLOSE_GOAL', 'goal', g.id::text, g.name, me.full_name);
end $$;

-- Every goal with its progress. Only confirmed (checked) records count.
-- Officers see each member's share; a member sees only their own line.
create function public.list_goals(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid; v_people int;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  select count(*) into v_people from members where org_id = p_org and is_active;
  return (select coalesce(jsonb_agg(to_jsonb(g) || jsonb_build_object(
      'people', v_people,
      'collected', (select coalesce(sum(p.amount),0) from payment_records p where p.goal_id = g.id and p.status = 'confirmed'),
      'records', (select count(*) from payment_records p where p.goal_id = g.id and p.status = 'confirmed'),
      'pending', (select coalesce(sum(p.amount),0) from payment_records p where p.goal_id = g.id and p.status = 'pending'),
      'mine', (select coalesce(sum(p.amount),0) from payment_records p where p.goal_id = g.id and p.status = 'confirmed' and p.member_id = v_me),
      'by_member', case when v_off then (select coalesce(jsonb_agg(jsonb_build_object('member_id', m.id, 'name', m.full_name,
          'amount', (select coalesce(sum(p.amount),0) from payment_records p where p.goal_id = g.id and p.status = 'confirmed' and p.member_id = m.id)) order by m.member_no), '[]'::jsonb)
          from members m where m.org_id = p_org and m.is_active) end,
      -- Running total by day, for the "planned vs real" chart.
      'points', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'total', t) order by d), '[]'::jsonb) from (
          select d, sum(s) over (order by d) t from (
            select coalesce(p.reviewed_at, p.submitted_at)::date d, sum(p.amount) s
            from payment_records p where p.goal_id = g.id and p.status = 'confirmed' group by 1) x) y)
    ) order by g.status, g.created_at desc), '[]'::jsonb)
    from savings_goals g where g.org_id = p_org);
end $$;

-- How today's savings split between goals and money not for any goal (this cycle only).
create function public.savings_allocation(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_total bigint; v_cycle int; v_goals jsonb; v_goal_sum bigint;
begin
  perform public.require_member_or_platform(p_org);
  v_total := -public.account_balance(p_org, '2010');
  select cycle_number into v_cycle from organizations where id = p_org;
  select coalesce(jsonb_agg(jsonb_build_object('goal_id', g.id, 'name', g.name, 'status', g.status, 'amount', a) order by a desc), '[]'::jsonb),
         coalesce(sum(a),0)
    into v_goals, v_goal_sum
  from (select g.*, (select coalesce(sum(p.amount),0) from payment_records p join journals j on j.id = p.journal_id
                     where p.goal_id = g.id and p.status = 'confirmed' and j.cycle_number = v_cycle) a
        from savings_goals g where g.org_id = p_org) g
  where a > 0;
  return jsonb_build_object(
    'total', v_total,
    'goals', v_goals,
    'for_goals', v_goal_sum,
    'not_for_goal', greatest(v_total - v_goal_sum, 0),
    -- Withdrawals come out of the shared pot. If they ate into goal money, say how much.
    'goal_money_used', greatest(v_goal_sum - v_total, 0));
end $$;

-- Chart data: money in and out per month, and savings at each month end. Last 12 months.
-- Reversed records and their reversals are left out, so mistakes never show as money.
create function public.monthly_flows(p_org uuid, p_months int default 12) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_off boolean; v_me uuid; v_from date;
begin
  perform public.require_member_or_platform(p_org);
  v_off := public.is_officer(p_org); v_me := (public.my_member(p_org)).id;
  v_from := (date_trunc('month', current_date) - make_interval(months => greatest(least(p_months,24),1) - 1))::date;
  return (select coalesce(jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'paid_in', i, 'paid_out', o, 'savings', s) order by m), '[]'::jsonb) from (
    select m,
      (select coalesce(sum(l.debit),0) from journal_lines l join journals j on j.id = l.journal_id
        where j.org_id = p_org and l.account_code in ('1010','1020') and j.type <> 'reversal'
          and not exists(select 1 from journals r where r.reversal_of = j.id)
          and date_trunc('month', j.created_at) = m
          and (v_off or exists(select 1 from journal_lines x where x.journal_id = j.id and x.member_id = v_me))) i,
      (select coalesce(sum(l.credit),0) from journal_lines l join journals j on j.id = l.journal_id
        where j.org_id = p_org and l.account_code in ('1010','1020') and j.type <> 'reversal'
          and not exists(select 1 from journals r where r.reversal_of = j.id)
          and date_trunc('month', j.created_at) = m
          and (v_off or exists(select 1 from journal_lines x where x.journal_id = j.id and x.member_id = v_me))) o,
      (select coalesce(sum(l.credit - l.debit),0) from journal_lines l join journals j on j.id = l.journal_id
        where j.org_id = p_org and l.account_code = '2010' and j.created_at < m + interval '1 month'
          and (v_off or l.member_id = v_me)) s
    from generate_series(v_from, date_trunc('month', current_date)::date, interval '1 month') m) x);
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
   ('check_goal','record_payment','set_payment_goal','create_goal','close_goal','list_goals','savings_allocation','monthly_flows') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    if f.proname <> 'check_goal' then
      execute format('grant execute on function %s to authenticated', f.sig);
    else
      execute format('revoke all on function %s from authenticated', f.sig);
    end if;
  end loop;
end $$;
