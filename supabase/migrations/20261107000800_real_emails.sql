-- Real emails only. Run after 20261107000700_owners_shared_demo.sql.
-- The only way to know an email is real is to send it a link and see it clicked ("Confirm email" in Supabase).
-- This file adds the checks the database can do on its own:
--   1. A gatekeeper Supabase calls before any new account is made (turn it on: Authentication -> Hooks -> Before User Created).
--   2. The people list shows who has proved their email (Google, or clicked the link) and who has not.
--   3. Owners can block an account that is fake, and unblock it.

-- ========== 1. GATEKEEPER BEFORE A NEW ACCOUNT ==========
-- Throwaway inbox sites. Owners can add more here; checked on every sign-up.
create table public.blocked_email_domains (
  domain text primary key check (domain = lower(domain) and domain like '%.%'),
  reason text not null default 'Throwaway inbox',
  created_at timestamptz not null default now()
);
alter table public.blocked_email_domains enable row level security;
revoke all on public.blocked_email_domains from anon, public, authenticated;
insert into public.blocked_email_domains(domain) values
  ('mailinator.com'),('guerrillamail.com'),('guerrillamail.net'),('sharklasers.com'),('grr.la'),('10minutemail.com'),
  ('10minutemail.net'),('tempmail.com'),('temp-mail.org'),('temp-mail.io'),('tempmailo.com'),('throwawaymail.com'),
  ('yopmail.com'),('yopmail.net'),('getnada.com'),('nada.email'),('dispostable.com'),('maildrop.cc'),('mailnesia.com'),
  ('trashmail.com'),('trashmail.de'),('fakeinbox.com'),('mintemail.com'),('mohmal.com'),('emailondeck.com'),
  ('mail.tm'),('moakt.com'),('tempail.com'),('spamgourmet.com'),('mailcatch.com'),('burnermail.io'),('discard.email'),
  ('example.com'),('example.org'),('example.net'),('test.com');

create function public.hook_before_user_created(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_email text := lower(coalesce(event->'user'->>'email', ''));
  v_provider text := coalesce(event->'user'->'app_metadata'->>'provider', 'email');
  v_domain text := split_part(lower(coalesce(event->'user'->>'email', '')), '@', 2);
begin
  -- Google (and any other sign-in company) has already proved the email.
  if v_provider <> 'email' then return '{}'::jsonb; end if;
  -- Phone numbers ride on a made-up address that cannot get mail, so they cannot be checked yet.
  -- New phone accounts wait for WhatsApp/SMS codes. Phone accounts already made keep working.
  if v_domain = 'phone.saccoledger.app' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400,
      'message', 'New accounts with a phone number are paused until we can text you a code. Use your email or Google for now.'));
  end if;
  if v_email !~ '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400, 'message', 'That does not look like a real email address.'));
  end if;
  if exists(select 1 from blocked_email_domains b where v_domain = b.domain or v_domain like '%.' || b.domain) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400,
      'message', 'Throwaway email addresses cannot open an account. Use the email you really read.'));
  end if;
  return '{}'::jsonb;
end $$;

revoke all on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
grant select on public.blocked_email_domains to supabase_auth_admin;

-- ========== 2. WHO HAS PROVED THEIR EMAIL ==========
-- checked = signed in with Google (or similar), or clicked the link we emailed.
-- Accounts made by email while "Confirm email" was off never got a link, so they show as not checked.
create function public.email_checked(u auth.users) returns boolean language sql stable set search_path = public as $$
  select coalesce(u.raw_app_meta_data->>'provider', 'email') <> 'email'
      or (u.email_confirmed_at is not null and u.confirmation_sent_at is not null);
$$;
revoke all on function public.email_checked(auth.users) from public, anon, authenticated;

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
          'role', a.role,
          'via', case when u.email like '%@phone.saccoledger.app' then 'phone' else coalesce(u.raw_app_meta_data->>'provider', 'email') end,
          'checked', public.email_checked(u),
          'blocked', u.banned_until is not null and u.banned_until > now()) as x
        from auth.users u left join profiles p on p.user_id = u.id left join platform_admins a on a.user_id = u.id
        order by u.created_at desc limit 200) s),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('who', h.actor_email, 'action', h.action, 'details', h.details, 'at', h.created_at)
        order by h.seq desc), '[]'::jsonb) from (select * from platform_audit order by seq desc limit 30) h));
end $$;

-- ========== 3. BLOCK A FAKE ACCOUNT ==========
-- Blocking stops sign-in at once and can be undone. Nothing is deleted: the group records they touched stay whole.
create function public.set_account_blocked(p_user uuid, p_blocked boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  perform public.require_platform_owner();
  select email into v_email from auth.users where id = p_user;
  if v_email is null then raise exception 'Account not found.'; end if;
  if p_user = auth.uid() then raise exception 'You cannot block yourself.'; end if;
  if public.is_founder(p_user) then raise exception 'The founder cannot be blocked.'; end if;
  if p_blocked and exists(select 1 from platform_admins where user_id = p_user) then
    raise exception 'Remove this person from the platform team first.';
  end if;
  update auth.users set banned_until = case when p_blocked then 'infinity'::timestamptz else null end where id = p_user;
  if p_blocked then
    delete from auth.sessions where user_id = p_user; -- signs them out everywhere
  end if;
  perform public.add_platform_audit(case when p_blocked then 'BLOCK_ACCOUNT' else 'UNBLOCK_ACCOUNT' end, v_email);
end $$;

revoke all on function public.set_account_blocked(uuid, boolean) from public, anon;
grant execute on function public.set_account_blocked(uuid, boolean) to authenticated;
