# Supabase setup

## Run the initial migration in Supabase

1. Create a Supabase project and open its **SQL Editor**.
2. Apply the files under `supabase/migrations/` in numeric order: `001_init.sql`, `002_triggers.sql`, `003_constraints.sql`, then `004_rls.sql`. Copy each whole file into a separate SQL Editor query.
3. Run `001_init.sql` once against an empty project, then run `002_triggers.sql`, `003_constraints.sql`, and `004_rls.sql` once each. The first migration creates the initial enums, tables, and foreign-key indexes. The second adds automatic patient-profile creation and appointment status transition enforcement. The third validates time intervals and prevents overlapping pending/confirmed appointments for the same doctor; cancelled and completed appointments do not reserve time. The fourth enables RLS and narrowly grants authenticated access for the approved workflows. Do not connect app clients until all four have been installed and verified. Do not rerun a migration; it intentionally fails if its objects already exist.
4. In **Table Editor**, confirm the tables exist. RLS is intentionally not enabled by this initial migration. To inspect the current RLS state:

   ```sql
   SELECT tablename, rowsecurity
   FROM pg_tables
   WHERE schemaname = 'public'
   ORDER BY tablename;
   ```

5. In **Project Settings → API**, copy the Project URL and the publishable/anon key for later client setup. Never put the `service_role` key in the app or source control. Do not enable app access to these tables until all four migrations have been installed and the RLS policies and grants have been verified.

The Dashboard SQL Editor does not record these files in the Supabase CLI migration history. The filenames `001_init.sql`, `002_triggers.sql`, `003_constraints.sql`, and `004_rls.sql` are for the documented manual workflow and are not timestamp-versioned Supabase CLI migration names. Do not later run them with `supabase db push` unless their versions have first been reconciled with the remote migration history.

## Run Flutter

Install the Flutter SDK and dependencies, then pass the project values at launch. In PowerShell:

```powershell
flutter pub get
flutter run --dart-define='SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co' --dart-define='SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY'
```

Use the same `--dart-define` values with `flutter test` or release builds that initialize the app. These values are public client configuration, not secrets. Client access is safe only after RLS policies have been installed and verified.

## Initial schema boundary

These migrations create the baseline schema, signup/status triggers, schedule checks, appointment overlap protection, and approved RLS/grants. Configure Supabase API **Exposed schemas** so `private` is not exposed; it contains authorization helper functions. The private helpers require database-level schema/function access for policy evaluation, but must not be available as client RPC endpoints. The owner-only profile email is retrieved with the no-argument `get_own_profile_email` RPC; direct `SELECT` of `profiles.email` is intentionally denied. To remove RLS, policies, and tenant guards, run `supabase/migrations/004_rls_down.sql` only in a controlled rollback; it revokes client table privileges before disabling RLS. To remove the constraints, run `supabase/migrations/003_constraints_down.sql`; it leaves `btree_gist` installed. To remove the triggers, run `supabase/migrations/002_triggers_down.sql`. Never expose a service-role key in Flutter or other client code.