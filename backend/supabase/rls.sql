-- ============================================================================
-- She Shield — Row Level Security (RLS) policies
--
-- Target: Supabase/PostgreSQL project. The application has no ORM/migration
-- pipeline, so these statements are the documented, safest-practice setup to
-- run from the Supabase SQL editor (or `supabase db push` if the CLI is wired
-- to the project). They are idempotent and safe to re-run.
--
-- Scope:
--   profiles        -> user-owned table (id references auth.users)
--   auth_audit_log  -> backend-only (service-role inserts); no client access
--
-- Design:
--   * The Flutter app NEVER talks to Postgres directly and only carries the
--     anon key. The backend performs user-scoped reads/writes with the
--     service-role key (which bypasses RLS by design).
--   * RLS is the LAST line of defense: policies keep a direct anon/authenticated
--     JWT client from reading or mutating another user's row.
--   * Identity comes from auth.uid() (the verified JWT), never from a request
--     body.
--   * Least privilege: users may SELECT/INSERT/UPDATE only their own row and
--     may NOT DELETE it.
--   * No service-role key appears anywhere in this file (keys are
--     environment-provided on the server).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- profiles
-- ----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_select_own'
  ) THEN
    CREATE POLICY profiles_select_own ON public.profiles
      FOR SELECT
      USING (auth.uid() = id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_insert_own'
  ) THEN
    CREATE POLICY profiles_insert_own ON public.profiles
      FOR INSERT
      WITH CHECK (auth.uid() = id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_update_own'
  ) THEN
    CREATE POLICY profiles_update_own ON public.profiles
      FOR UPDATE
      USING (auth.uid() = id)
      WITH CHECK (auth.uid() = id);
  END IF;

  -- Intentionally NO DELETE policy: users cannot delete their own profile
  -- through RLS, matching the backend behaviour.
END $$;

-- ----------------------------------------------------------------------------
-- auth_audit_log
-- ----------------------------------------------------------------------------
-- Backend-only table. No RLS policy grants anon or authenticated access, so
-- RLS denies all direct client reads/writes. It stays writable only by the
-- service-role backend (RLS bypass) which inserts from the audit service.

ALTER TABLE public.auth_audit_log ENABLE ROW LEVEL SECURITY;

-- Verification queries (should return exactly one row: your own profile):
--
--   SET ROLE authenticated;
--   SELECT * FROM public.profiles WHERE id = auth.uid();
--
-- Sanity check that cross-user access is blocked (should return no rows):
--
--   SELECT * FROM public.profiles WHERE id <> auth.uid();