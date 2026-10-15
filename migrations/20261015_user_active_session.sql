-- Single active device session per user (columns on public.users — no new table).
-- App stores a local session id; force-login overwrites these fields and signs out other JWTs.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS active_session_id text,
  ADD COLUMN IF NOT EXISTS session_claimed_at timestamptz,
  ADD COLUMN IF NOT EXISTS active_device_label text,
  ADD COLUMN IF NOT EXISTS active_device_platform text;

COMMENT ON COLUMN public.users.active_session_id IS
  'Client-generated id of the device currently allowed to use this account.';
COMMENT ON COLUMN public.users.session_claimed_at IS
  'When active_session_id was last claimed (login or force login).';
COMMENT ON COLUMN public.users.active_device_label IS
  'Human-readable device label for support (not shown on force-login popup).';
COMMENT ON COLUMN public.users.active_device_platform IS
  'Platform key: android, ios, web, windows, macos, linux, other.';

-- Ensure Realtime can push active_session_id changes to connected clients.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'users'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
  END IF;
END $$;
