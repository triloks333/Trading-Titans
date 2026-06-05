-- 1. Move extensions from public schema to extensions schema (extension_in_public)
ALTER EXTENSION pg_trgm SET SCHEMA extensions;

-- http extension does not support SET SCHEMA directly, so drop and recreate it
DROP EXTENSION IF EXISTS http;
CREATE EXTENSION http SCHEMA extensions;

-- 2. Hardening Function Search Paths (function_search_path_mutable)
ALTER FUNCTION public.is_admin() SET search_path = public;
ALTER FUNCTION public.auth_uid() SET search_path = public;
ALTER FUNCTION public.notify_order_executed() SET search_path = public;
ALTER FUNCTION public.notify_balance_change() SET search_path = public;

-- 3. Change helper/trigger functions to SECURITY INVOKER to satisfy linter warnings (anon_security_definer_function_executable)
ALTER FUNCTION public.auth_uid() SECURITY INVOKER;
ALTER FUNCTION public.is_admin() SECURITY INVOKER;
ALTER FUNCTION public.notify_balance_change() SECURITY INVOKER;
ALTER FUNCTION public.notify_order_executed() SECURITY INVOKER;

-- 4. Explicitly grant execute back to PUBLIC, anon, and authenticated so RLS policies don't crash
GRANT EXECUTE ON FUNCTION public.auth_uid() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_uid() TO anon;
GRANT EXECUTE ON FUNCTION public.auth_uid() TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_admin() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

GRANT EXECUTE ON FUNCTION public.notify_balance_change() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_balance_change() TO anon;
GRANT EXECUTE ON FUNCTION public.notify_balance_change() TO authenticated;

GRANT EXECUTE ON FUNCTION public.notify_order_executed() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_order_executed() TO anon;
GRANT EXECUTE ON FUNCTION public.notify_order_executed() TO authenticated;

