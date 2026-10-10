-- Auto-pause sync when subscription expiry has passed.
-- Call via: SELECT public.pause_expired_sync_machines();
-- Optional: schedule with pg_cron if available.

CREATE OR REPLACE FUNCTION public.pause_expired_sync_machines()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  paused_count integer;
BEGIN
  UPDATE public.script_control
  SET
    sync_should_run = false,
    updated_at = now()
  WHERE sync_should_run = true
    AND expires_at IS NOT NULL
    AND expires_at < now();

  GET DIAGNOSTICS paused_count = ROW_COUNT;
  RETURN paused_count;
END;
$$;

COMMENT ON FUNCTION public.pause_expired_sync_machines() IS
  'Sets sync_should_run=false for machines whose expires_at is in the past. Returns rows updated.';

GRANT EXECUTE ON FUNCTION public.pause_expired_sync_machines() TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_expired_sync_machines() TO service_role;
