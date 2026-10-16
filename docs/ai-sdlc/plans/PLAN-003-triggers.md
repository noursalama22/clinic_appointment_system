# PLAN-003 — Signup Profile and Appointment Lifecycle Triggers

| | |
| --- | --- |
| Plan ID | PLAN-003 |
| Derived from | `docs/ai-sdlc/specs/SPEC-002-database-schema-revision.md` (APPROVED — human-approved 2026-10-10) |
| Depends on | `docs/ai-sdlc/plans/PLAN-002-database-schema.md` (APPROVED — human-approved 2026-10-10) |
| Status | APPROVED — human-approved 2026-10-10 |
| Date | 2026-10-10 |
| Author | architect |

> **Approval gate.** This plan authorizes the profile-on-signup trigger and appointment status
> transition guard described below.
> It does not authorize booking-conflict constraints, RLS, grants, or other database behavior.

## 1. Goal and scope

Add the database trigger behavior required by approved SPEC-002 after `001_init.sql` has been
applied:

1. Create one `public.profiles` row after each `auth.users` insert, taking `id`, `email`, and
   `raw_user_meta_data ->> 'full_name'` from the inserted Auth row. Always set `role` explicitly to
   `patient`, regardless of metadata.
2. Reject appointment updates whose status changes do not follow the approved lifecycle:
   - `pending` → `confirmed` or `cancelled`
   - `confirmed` → `cancelled` or `completed`
   - `cancelled` and `completed` are terminal
   Updates that leave the status unchanged remain valid with respect to this guard.

Create `supabase/migrations/002_triggers.sql` for the documented manual Supabase SQL Editor workflow.

## 2. Implementation requirements

- The Auth trigger is `AFTER INSERT ON auth.users`, row-level, and invokes a `SECURITY DEFINER`
  function owned by a trusted database role. The function uses a fixed, empty or otherwise
  strictly controlled `search_path` and schema-qualifies referenced objects.
- The signup function inserts only `id`, `email`, `full_name`, and the fixed patient role. It must
  not accept or copy the requested role from user-controlled metadata. It must not silently swallow
  insert errors; a missing required email or other profile constraint failure must fail the Auth
  insert transaction rather than leave an Auth user without the required profile.
- The appointment transition guard is a `BEFORE UPDATE` trigger on `public.appointments`. It must
  compare `OLD.status` with `NEW.status`, allow unchanged status, allow only the transitions in §1,
  and raise an exception for all other status changes.
- Restrict direct function execution privileges where compatible with PostgreSQL trigger
  invocation. Do not grant client roles elevated access as part of this migration.
- Do not add tables, columns, enum values, policies, grants, or booking constraints.
- Do not use `IF NOT EXISTS` or exception-swallowing wrappers that mask partially applied state.
- Provide a rollback script that drops only the two triggers and their dedicated functions, after
  confirming trigger/function dependencies.

## 3. Implementation sequence

1. Confirm `001_init.sql` has been applied to the target empty Supabase project.
2. Review the target project’s available owner/execution role and Auth trigger conventions; keep
   `SECURITY DEFINER` ownership trusted and the function search path hardened.
3. Implement `002_triggers.sql` and its rollback script under the migration naming workflow already
   documented in `supabase/README.md`.
4. Review the full SQL for exact field mapping, fixed role assignment, hardened execution context,
   and transition completeness.
5. Apply to a disposable Supabase-compatible database and run the checks in §4.
6. Update setup documentation to describe the required migration order and rollback behavior.

## 4. Verification and acceptance

### Signup profile trigger

- An inserted Auth user with email and `full_name` metadata receives exactly one matching profile
  whose ID/email/name match the Auth row and whose role is `patient`.
- An inserted Auth user whose metadata requests `doctor` or `admin` still receives a `patient`
  profile; unrelated metadata is ignored.
- Null `full_name` metadata is stored as NULL.
- Duplicate invocation cannot create a second profile; unexpected insert failures are not swallowed.
- Auth insertion with a missing email fails visibly instead of creating an invalid profile.
- Untrusted `anon` and `authenticated` callers cannot invoke the security-definer function directly.

### Appointment status trigger

- `pending` → `confirmed` and `pending` → `cancelled` succeed.
- `confirmed` → `cancelled` and `confirmed` → `completed` succeed.
- Updates with unchanged `pending`, `confirmed`, `cancelled`, or `completed` status succeed as far
  as the transition guard is concerned.
- `pending` → `completed`, `confirmed` → `pending`, and every transition out of `cancelled` or
  `completed` raise an exception and leave the row unchanged.
- Other appointment-field updates do not bypass a simultaneously invalid status change.

### Migration checks

- Migration applies once after `001_init.sql` on a clean database.
- Reapplication fails clearly rather than masking partial installation.
- Rollback removes only the two triggers and their dedicated functions.
- No RLS, grants, extra schema objects, or appointment overlap behavior is introduced.

## 5. Risks and boundaries

- `public.profiles.email` is `NOT NULL`; if an Auth row has no email, profile creation must fail
  explicitly as required for a consistent Auth/profile identity. This migration does not add
  phone-only signup behavior.
- A trigger may fail an Auth signup transaction if profile creation fails. This is intentional:
  the one-to-one profile requirement must not be weakened by a success-shaped fallback.
- This migration does not by itself secure table access. Do not expose the tables to client roles
  until separately approved RLS and grants are implemented and verified.
- This migration does not prevent overlapping appointment bookings; that remains a separate
  constraint migration.
- The plain `002_triggers.sql` filename follows manual SQL Editor execution; it is not a
  timestamp-versioned Supabase CLI migration. Reconcile migration history before using `supabase
  db push`.

## 6. Rollback

Rollback only in an environment where the trigger behavior is being removed intentionally. Drop the
Auth and appointment triggers before dropping their functions. Do not change or delete profile or
appointment data during rollback. Revoke any explicit function privileges granted by the migration.

## 7. Definition of Done

- [x] Human approves PLAN-003 — 2026-10-10.
- [ ] `001_init.sql` is confirmed installed in the target database.
- [ ] Migration and rollback scripts pass §4 checks in a disposable Supabase-compatible database.
- [ ] Signup never permits metadata-based role escalation.
- [ ] All permitted and forbidden lifecycle transitions behave as specified.
- [ ] README accurately documents migration order and current RLS/booking-protection boundaries.
