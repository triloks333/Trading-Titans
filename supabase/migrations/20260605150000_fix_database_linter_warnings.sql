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

-- 3. Restrict Security Definer Function execution (anon_security_definer_function_executable / authenticated_security_definer_function_executable)
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.auth_uid() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.auth_uid() FROM anon;
REVOKE EXECUTE ON FUNCTION public.auth_uid() FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.notify_order_executed() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_order_executed() FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_order_executed() FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.notify_balance_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_balance_change() FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_balance_change() FROM authenticated;
