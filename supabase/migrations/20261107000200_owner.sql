-- The platform owner becomes Platform Admin the moment they sign up (email or Google).
-- Change the email if the owner changes.
create or replace function public.make_owner_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) = 'danmclaston@gmail.com' then
    insert into public.platform_admins(user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;
revoke all on function public.make_owner_admin() from public, anon, authenticated;
create trigger owner_auto_admin after insert on auth.users for each row execute function public.make_owner_admin();
