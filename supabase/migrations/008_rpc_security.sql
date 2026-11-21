-- The default Supabase function privileges can grant EXECUTE to anon explicitly.
-- Revoke them and ensure only authenticated callers can reach the account RPC.
revoke all privileges on function public.change_application_status(uuid, public.application_status)
  from public, anon;
grant execute on function public.change_application_status(uuid, public.application_status)
  to authenticated;

-- Future functions should be private by default; individually grant authenticated RPC use.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
