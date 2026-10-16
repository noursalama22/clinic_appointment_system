# PLAN-002 — Initial Multi-tenant Database Migration

| | |
| --- | --- |
| Plan ID | PLAN-002 |
| Derived from | `docs/ai-sdlc/specs/SPEC-002-database-schema-revision.md` (APPROVED — human-approved 2026-10-10) |
| Intent source | `intent/clinic-appointment-system.md` (approved) |
| Status | APPROVED — human-approved 2026-10-10 |
| Date | 2026-10-10 |
| Author | architect |

> **Approval gate.** This plan authorizes the baseline schema migration described below. Later
> trigger, booking-constraint, and RLS migrations require explicit scope in this or a later
> approved plan.

## 1. Goal and scope

Replace the current, unapplied single-clinic initial schema baseline with the initial schema defined
by approved SPEC-002. The user confirmed the existing initial migration has not been applied and
requested that it be replaced only after approval.

### In scope

- Create the `user_role` and `appointment_status` enums with the exact values in SPEC-002.
- Create `public.clinics`, `public.profiles`, `public.doctors`, `public.working_hours`, and
  `public.appointments` with the columns, types, defaults, nullability, foreign keys, and delete
  actions in SPEC-002, including the user clarification that `working_hours.doctor_id`,
  `appointments.patient_id`, and `appointments.doctor_id` are NOT NULL.
- Add indexes for each foreign-key column to support joins and foreign-key checks.
- Use the requested logical filename `001_init.sql` and keep the existing project workflow in mind:
  the current `supabase/README.md` describes manual execution in Supabase SQL Editor, which does
  not register a file in Supabase CLI migration history.
- Replace the existing unapplied baseline and update its setup instructions only after plan
  approval; do not modify the current untracked migration during plan drafting.

### Out of scope

- Auth signup and appointment-status triggers.
- Appointment overlap exclusion/booking logic and status-transition enforcement.
- RLS policies or grants.
- Seed users or application/Flutter changes.
- Additional tables or columns from SPEC-001, including breaks, slot duration, availability
  exceptions, audit, and consultation data.
- Unresolved validation rules not explicitly required by SPEC-002, such as interval ordering,
  cross-clinic consistency, or whether completed appointments reserve a slot.

## 2. Implementation sequence

1. **Baseline replacement:** After plan approval, replace the unapplied prior schema baseline with
   `001_init.sql`. Preserve the existing copy until the new migration is reviewed and validated.
2. **Schema migration:** Implement the enums, five tables, specified key and cascade behavior, and
   foreign-key indexes. Use only constraints explicitly required by SPEC-002 and this plan.
3. **Setup documentation:** Update Supabase setup instructions to identify the selected execution
   method, warn that SQL Editor execution is not recorded by Supabase CLI, and prevent accidental
   reapplication. Do not claim that later triggers, booking constraints, or RLS are installed.
4. **Verification:** Apply the script to a clean Supabase-compatible database, inspect object
   definitions and indexes, and run targeted integrity checks before considering the phase done.

## 3. Migration behavior and safety

- The target is a clean database because the existing migration is confirmed not applied. Do not
  attempt an in-place conversion from the prior single-clinic schema in this phase.
- The migration must fail clearly if incompatible objects already exist; do not conceal schema
  drift with broad `IF NOT EXISTS` fallbacks.
- Use PostgreSQL/Supabase-supported UUID generation for `gen_random_uuid()`.
- Do not seed fabricated Auth users or profiles.
- This baseline does not by itself provide safe application access. No grants or RLS policy changes
  are part of this migration; do not connect client write paths to these tables until the planned
  security migrations are approved and installed.

## 4. Verification and acceptance

- The migration applies successfully once to an empty Supabase-compatible database.
- The two enums contain exactly the specified labels and order.
- All five tables exist with the specified columns, types, defaults, nullability, PKs, FKs, and
  `ON DELETE` behavior.
- The three explicitly required non-null foreign keys reject NULL.
- Every FK column has an index; primary-key indexes are present.
- A database catalog review confirms no unrequested columns, tables, triggers, policies, or status
  values were introduced.
- Re-running the migration fails rather than reporting a success-shaped partial application.
- Setup documentation accurately distinguishes manual SQL Editor execution from CLI migration
  history.

## 5. Risks and open decisions carried forward

- Approved SPEC-002 still leaves deletion/retention behavior for some relationships, exact
  appointment overlap participation, email synchronization, cross-clinic consistency, and
  role-specific CRUD details unresolved. This baseline must not invent answers to these questions.
- Database tables without RLS are not ready for client access. A separate approved plan or a scope
  expansion must cover the RLS migration before application features rely on the database.
- A plain `001_init.sql` filename is compatible with the documented manual SQL Editor workflow,
  but is not a timestamp-versioned Supabase CLI migration name. If CLI-managed migration history is
  required, approve a filename/workflow adjustment before implementation.
- The previous untracked initial migration was confirmed unapplied and replaced by
  `supabase/migrations/001_init.sql`; the Supabase README now documents the new manual-run baseline.

## 6. Rollback

The migration is for a clean, unapplied baseline only. Before application, rollback is to discard
the uncommitted replacement and retain the existing baseline. After application to a disposable
development database, rollback may drop only objects created by this migration after confirming no
data needs preservation. Do not run destructive rollback against a database containing user or
appointment data.

## 7. Definition of Done

- [x] Human approves PLAN-002 — 2026-10-10.
- [ ] The approved plan's precise filename/execution workflow is confirmed if Supabase CLI history
      is required.
- [x] Existing unapplied baseline and README reviewed before replacement.
- [ ] All §4 acceptance checks pass against a clean database.
- [ ] Later trigger, overlap, and RLS requirements remain explicitly unimplemented until separately
      authorized.
