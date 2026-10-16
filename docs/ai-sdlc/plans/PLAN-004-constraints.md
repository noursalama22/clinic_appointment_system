# PLAN-004 — Schedule Validation and Appointment Overlap Constraints

| | |
| --- | --- |
| Plan ID | PLAN-004 |
| Derived from | `docs/ai-sdlc/specs/SPEC-002-database-schema-revision.md` (APPROVED — human-approved 2026-10-10; amended 2026-10-10) |
| Depends on | `docs/ai-sdlc/plans/PLAN-002-database-schema.md` and `PLAN-003-triggers.md` (approved) |
| Status | APPROVED — human-approved 2026-10-10 |
| Date | 2026-10-10 |
| Author | architect |

> **Approval gate.** This plan authorizes the check constraints and database-level overlap
> prevention for `working_hours` and `appointments` described below.

## 1. Goal and scope

Create `supabase/migrations/003_constraints.sql` to enforce the following rules:

- Working-hour and appointment end times must be strictly later than their start times.
- `working_hours.day_of_week` must be between 0 (Sunday) and 6 (Saturday), inclusive.
- For the same doctor, no two time-overlapping appointments may exist when both appointment
  statuses are `pending` or `confirmed`.
- `cancelled` and `completed` appointments do not reserve time and are excluded from overlap
  conflicts. This resolves SPEC-002 §4: only `pending` and `confirmed` reserve slots.
- Use PostgreSQL exclusion-constraint semantics, backed by `btree_gist`, so concurrent transactions
  cannot both book overlapping time for the same doctor.

The appointment intervals use `appointment_date + start_time/end_time` as local `timestamp`
boundaries and a half-open range `[start, end)`: adjacent appointments where one ends exactly when
the next begins are allowed. Because end must be later than start on the same date, overnight
appointments are not supported by this schema.

## 2. Implementation requirements

- Add named check constraints for:
  - `working_hours.day_of_week BETWEEN 0 AND 6`
  - `working_hours.end_time > working_hours.start_time`
  - `appointments.end_time > appointments.start_time`
- Enable the `btree_gist` extension if it is not already installed; do not remove it during
  rollback because other database objects may depend on it.
- Add a GiST exclusion constraint combining equality on `doctor_id` and overlap on the generated
  appointment timestamp range.
- The exclusion predicate must include exactly `status IN ('pending', 'confirmed')`. It must not
  include `cancelled` or `completed`.
- Use a half-open range to permit directly adjacent appointments.
- Do not add tables, columns, triggers, RLS policies, grants, or status transitions.
- Do not silently delete, modify, or normalize existing records. Before applying, inspect existing
  rows for invalid time/day values and overlapping pending/confirmed appointments; report blockers
  for explicit resolution if any are found.
- Provide a rollback script that drops only constraints created by this migration. Preserve the
  extension.

## 3. Implementation sequence

1. Confirm `001_init.sql` and `002_triggers.sql` have been installed in the target project.
2. Preflight `working_hours` and `appointments` for records that violate the proposed checks or
   overlap rule; do not auto-correct existing data. Even if the intended baseline is empty, check
   the actual target database in case it has been manually populated.
3. Implement `003_constraints.sql` and `003_constraints_down.sql`.
4. Review that the predicate includes only pending/confirmed and that the range uses the same
   doctor, date, and time interval with `[)` semantics.
5. Apply to a disposable Supabase-compatible database, run the §4 checks, then update setup
   documentation with migration order and rollback notes.

## 4. Verification and acceptance

- Migration succeeds after `001_init.sql` and `002_triggers.sql` on a clean database.
- Day values 0 and 6 and valid start/end intervals are accepted.
- Day values below 0 or above 6, and intervals where `end_time <= start_time`, are rejected.
- A pending or confirmed appointment can be inserted when no conflicting active appointment exists.
- Any overlapping pending/confirmed interval for the same doctor is rejected, including overlaps
  with unequal start/end boundaries and concurrent insert attempts.
- Overlapping appointments for different doctors are allowed.
- An appointment whose interval begins exactly when another ends is allowed.
- A cancelled or completed appointment does not prevent a pending or confirmed appointment from
  using the same interval.
- Transitioning an appointment to cancelled or completed releases its interval for a subsequent
  active appointment; transitioning into pending/confirmed is checked against other active rows.
- A catalog review confirms the GiST exclusion constraint and its partial predicate are installed
  as specified.
- Rollback removes the three check constraints and the exclusion constraint, but leaves `btree_gist`
  installed.

## 5. Risks and boundaries

- Existing invalid rows or active overlaps cause constraint creation to fail. Resolve them through
  an explicitly authorized data-correction process before retrying; this migration must not hide or
  repair the condition automatically.
- A GiST exclusion constraint serializes conflicting concurrent bookings at the database level;
  callers should treat exclusion violations as booking conflicts, not generic success.
- This rule treats completed appointments as non-reserving regardless of appointment date, as
  explicitly requested. If historical completed records should block a future re-booking, that
  behavior requires a new approved spec change.
- The check and overlap rules do not verify that an appointment fits within working hours or matches
  a clinic assignment.
- This migration does not install RLS or grants. Do not expose the tables to client roles until
  separately approved and verified security migrations are complete.
- The filename follows the manual Supabase SQL Editor workflow and is not a timestamp-versioned
  Supabase CLI migration filename.

## 6. Rollback

Run the rollback only when intentionally removing schedule validation and overlap protection. Drop
only the named constraints created by this migration. Leave `btree_gist` installed. No appointment
or schedule data is modified or deleted by rollback.

## 7. Definition of Done

- [x] Human approves PLAN-004 — 2026-10-10.
- [ ] `001_init.sql` and `002_triggers.sql` are confirmed installed in the target database.
- [ ] Preflight finds no unresolved invalid rows or active overlaps.
- [ ] Migration and rollback pass §4 checks in a disposable Supabase-compatible database.
- [ ] The partial exclusion constraint permits only cancelled/completed re-booking and rejects
      active overlaps under concurrent transactions.
- [ ] README accurately documents migration order and remaining RLS/grant boundary.
