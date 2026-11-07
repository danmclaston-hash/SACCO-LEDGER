-- Pins the search path on helper functions (Supabase security check "function_search_path_mutable").
-- Run after 20261107000000_accounts.sql.
alter function public.block_change() set search_path = public;
alter function public.check_journal_balanced() set search_path = public;
alter function public.normalize_phone(text) set search_path = public;
alter function public.channel_account(text) set search_path = public;
alter function public.line(text, uuid, bigint, bigint) set search_path = public;
alter function public.calc_schedule(bigint, integer, integer, text, date) set search_path = public;
