-- Stand-in for Supabase's auth system so the database can be tested on plain Postgres.
do $$ declare r text; begin
  foreach r in array array['anon','authenticated','service_role','supabase_auth_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then execute format('create role %I nologin', r); end if;
  end loop;
end $$;
create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(), email text unique, encrypted_password text,
  created_at timestamptz not null default clock_timestamp(), last_sign_in_at timestamptz,
  raw_app_meta_data jsonb default '{"provider":"email"}', email_confirmed_at timestamptz, confirmation_sent_at timestamptz,
  banned_until timestamptz); -- same columns Supabase has
create table auth.sessions(id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true),'')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
