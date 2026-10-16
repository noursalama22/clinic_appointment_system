# PLAN-005 — Tenant-scoped Row-level Security and Client Privileges

| | |
| --- | --- |
| Plan ID | PLAN-005 |
| Derived from | `docs/ai-sdlc/specs/SPEC-002-database-schema-revision.md` (APPROVED — human decisions recorded 2026-10-10) |
| Depends on | `PLAN-002-database-schema.md`, `PLAN-003-triggers.md`, and `PLAN-004-constraints.md` (approved) |
| Status | APPROVED — human-approved 2026-10-10 |
| Date | 2026-10-10 |
| Author | architect |

> **Approval gate.** This plan authorizes one security migration,
> `supabase/migrations/004_rls.sql`, and a corresponding rollback file only.

## 1. Goal

Enable RLS on `clinics`, `profiles`, `doctors`, `working_hours`, and `appointments`, and grant
authenticated clients only the operations and columns needed to perform the approved workflows.
Use database-enforced role, row, clinic, and field boundaries. Do not give `anon` table privileges.

## 2. Approved authorization decisions

These decisions were gathered one at a time from the human owner on 2026-10-10 and are reflected in
approved SPEC-002 §6.1:

- Anonymous clients receive no row access. All signed-in users may browse clinic, doctor, and
  working-hours rows across clinics.
- A patient assigned to a clinic may book only within that clinic. An unassigned patient may book
  at any clinic.
- `profiles.clinic_id` is nullable for patients and required for doctor/admin profiles. Each user
  has at most one clinic. A doctor's `doctors.clinic_id` must match its profile's clinic.
- An appointment requires a clinic matching its doctor's clinic and, where set, its patient's
  profile clinic.
- Only a trusted backend/service-role process may assign or change profile roles or clinic
  membership. No client, including an admin, may change those fields.
- A user may read their own profile and update only `full_name`. Profile email follows Auth and is
  visible only to its owner. Related doctors/admins may read permitted profile basics, not email.
- A doctor may read a patient profile only when the patient has an appointment assigned to that
  doctor. A clinic admin may read profiles in their clinic and patients with appointments at their
  clinic.
- Clinic admins may update their clinic's name/address and create/update doctor records only within
  their clinic. Doctor specialization/bio are editable only by an admin of that doctor’s clinic or
  a trusted service process. Clients cannot create/delete clinics or delete doctors.
- Doctors manage their own working hours; clinic admins manage working hours for doctors in their
  clinic.
- Patients create pending appointments for themselves and may reschedule/cancel only their own
  pending/confirmed appointments. They may not change patient, doctor, or clinic identity; terminal
  appointments are immutable to them.
- Doctors read assigned appointments and may update status only, subject to the specified lifecycle.
- Clinic admins read appointments in their clinic, create pending appointments there, and reschedule
  or cancel pending/confirmed appointments without changing patient, doctor, or clinic identity.
  Terminal appointments are immutable to admins.
- Clients cannot delete appointments; cancellation is the supported client operation.
- No anonymous table privileges are granted. SQL grants and RLS policies both enforce access.
- Auth email changes synchronize `profiles.email`; client roles cannot update role, clinic, or
  appointment identity fields.

## 3. Migration scope

Create `supabase/migrations/004_rls.sql` and `supabase/migrations/004_rls_down.sql`.

### 3.1 RLS and policy scope

- Enable RLS on all five core tables.
- Grant `USAGE` on `public` and enum `USAGE` as needed to `authenticated`. Explicitly revoke
  `anon` table privileges and do not grant it table access.
- Clear inherited/default `anon` and `authenticated` table privileges for the five tables, then
  grant only approved table/column operations to `authenticated`.
- Do not grant client `DELETE` on clinics, profiles, doctors, or appointments. Working-hours
  deletion is allowed only to the owning doctor or an admin of that doctor's clinic.
- Use policies with an explicit `TO authenticated` role. Never rely on RLS alone to limit which
  columns a client can read or update.
- Clinic and doctor discovery reads are available to all authenticated users. Working-hours reads
  are available to all authenticated users.
- Profile row reads are limited to self, clinic admin scope, or the approved doctor-patient
  appointment relationship. Do not grant `SELECT` on `profiles.email` to client roles; owners can
  use the owner-only email getter in this migration. This prevents related doctors/admins from
  reading email through the public table.
- Appointment reads are limited to the patient owner, assigned doctor, or admin whose current
  profile clinic matches the appointment clinic.
- Clinic update policies permit only an admin of that clinic. Doctor insert/update policies permit
  only an admin of the target doctor clinic. Doctor delete is service-only.
- Schedule policies permit a doctor to manage rows whose `doctor_id` is their own ID and clinic
  admins to manage schedules for doctors in their clinic.
- Appointment insert policies permit only patients creating their own `pending` appointment or
  clinic admins creating a `pending` appointment in their clinic. A doctor cannot create an
  appointment.
- Appointment update policies permit only the row owner patient, assigned doctor, or clinic admin,
  with the additional actor/field restrictions in §3.3.
- Do not create policies that authorize `anon` or expose profile/appointment rows to all
  authenticated users.

### 3.2 Tenant integrity prerequisites

The current baseline leaves clinic IDs nullable and does not enforce cross-table clinic matches.
Apply these narrow integrity changes in `004_rls.sql` because the approved policy model depends on
them:

- Add a profile check requiring a non-NULL `clinic_id` when role is `doctor` or `admin`; patient
  clinic membership remains optional.
- Make `doctors.clinic_id` and `appointments.clinic_id` NOT NULL.
- Add trusted database validation for:
  - doctor rows referencing a doctor-role profile with the same clinic ID;
  - doctor/admin role profiles having a clinic ID;
  - appointments referencing a doctor at the appointment clinic and, when assigned, a patient at
    that same clinic.
- Apply identity/tenant validation to trusted service-role writes as well as authenticated client
  writes; do not rely only on RLS policies for cross-table integrity.
- Run preflight checks before adding constraints. Do not silently change existing rows; fail the
  migration if any data violates the approved clinic rules.

### 3.3 Field-level controls and auth email synchronization

- Revoke broad authenticated table update privileges before granting only these writable columns:
  - `profiles.full_name`
  - `clinics.name`, `clinics.address`
  - `doctors.specialization`, `doctors.bio`
  - working-hours schedule fields, not row `id` or owner `doctor_id`
  - appointments `status`, `appointment_date`, `start_time`, `end_time`, not
    `patient_id`/`doctor_id`/`clinic_id`
- Appointment update field guard:
  - patient: may change date/time on pending/confirmed own appointments and may change status only
    to `cancelled`;
  - doctor: may change status only, and only on assigned appointments;
  - clinic admin: may change date/time on pending/confirmed appointments in their clinic and may
    change status only to `cancelled`;
  - all other clients/fields are rejected. The existing transition trigger continues to validate
    permitted lifecycle transitions.
- Validate patient and admin inserts as pending, patient-owned or clinic-scoped respectively.
- Prevent authenticated users from changing profile role, clinic assignment, email, or ID. These
  fields are provisioned only through trusted backend/service-role operations.
- Add an `AFTER UPDATE OF email ON auth.users` trigger to synchronize the matching profile email.
  Use a tightly owned `SECURITY DEFINER` function with an empty/fixed `search_path`, qualified
  object references, and no direct client execution.
- Do not grant direct `SELECT` on `profiles.email`. Provide an owner-only, no-argument
  `SECURITY DEFINER` getter for the authenticated user's profile email, deriving the user only from
  `auth.uid()`. Revoke execution from `PUBLIC` and `anon`; grant only to `authenticated`.
- For policy checks that would otherwise recurse through `profiles` RLS, use narrowly scoped
  `SECURITY DEFINER` helper functions in a non-API-exposed `private` schema, owned by a trusted
  database role. Grant authenticated the schema usage/function execution needed for policy
  evaluation, but keep the `private` schema out of Supabase's exposed API schemas. Fix the search
  path, qualify every object, revoke execution from `PUBLIC` and `anon`, and grant only the
  execution needed by authenticated policy evaluation. Helpers must derive the caller from
  `auth.uid()`; they must not accept an arbitrary caller ID as an authorization principal.
- Deferred tenant-consistency checks must skip unrelated profile, doctor, or appointment updates;
  inspect related appointments only when a role/clinic/identity field actually changes.
- Preserve trusted `service_role` provisioning rights for role/clinic assignments and doctor
  account setup; never expose its key to a client.
- Do not include broad dynamic-SQL helpers, user-selectable roles, or client-callable role
  assignment functions.

## 4. RLS policy matrix

| Table | Read | Insert | Update | Delete |
| --- | --- | --- | --- | --- |
| `clinics` | All authenticated users | Trusted service only | Admin of same clinic: `name`, `address` | Trusted service only |
| `profiles` | Self; same-clinic admin; doctor for assigned patient; admin for patient with appointment at clinic | Signup trigger/trusted service only | Owner: `full_name` only | Trusted service only |
| `doctors` | All authenticated users | Admin of target clinic for pre-provisioned matching doctor profile | Same-clinic admin: specialization/bio | Trusted service only |
| `working_hours` | All authenticated users | Own doctor or same-clinic admin | Own doctor or same-clinic admin; schedule fields only | Own doctor or same-clinic admin |
| `appointments` | Patient owner; assigned doctor; same-clinic admin | Patient: own pending booking; same-clinic admin: pending on behalf | Patient: reschedule/cancel active own; doctor: status only; admin: reschedule/cancel active clinic rows | No client delete |

The grant layer must match this matrix. Row policies alone do not authorize an operation if the
corresponding SQL privilege is absent.

## 5. Migration sequence and safety

1. Confirm `001_init.sql`, `002_triggers.sql`, and `003_constraints.sql` are installed in order.
2. Preflight profiles/doctors/appointments for missing or mismatched clinic assignments. Stop and
   report blockers; do not auto-assign tenant IDs.
3. Implement the `004_rls.sql` migration as one transaction so a policy/constraint failure does not
   leave a partially enabled security boundary.
4. Review all table/column grants, RLS policies, SECURITY DEFINER helper/trigger ownership,
   search paths, and client execution privileges.
5. Apply to a disposable Supabase-compatible database and execute the positive/negative matrix in
   §6 before production.
6. Update `supabase/README.md` with all four migrations and the current security boundary.

The rollback must revoke the client grants created by this migration, remove only its policies and
helper/guard/email-sync objects, remove its tenant constraints after dropping dependent triggers,
then disable RLS on the five tables. It must not drop data or extensions. Since disabling RLS is
unsafe when client table privileges remain, rollback must revoke those privileges before RLS is
disabled.

## 6. Verification and acceptance

- Migration applies atomically after migrations 001–003 on a clean database.
- All five tables report `relrowsecurity = true`.
- `anon` has no table privileges and cannot read any of the five tables.
- Authenticated users can read clinic, doctor, and working-hours rows across clinics as approved.
- Patient cannot read or update another patient's profile or appointments; cannot read profile email
  through `public.profiles`; can update only their own `full_name`.
- Doctor cannot read unrelated patient profiles or appointments; can read an assigned patient's
  profile basics and update only status on assigned appointments.
- Admin cannot read or update another clinic's appointments, profiles, doctors, schedules, or clinic
  settings; may read an out-of-clinic patient profile only when that patient has an appointment at
  the admin's clinic.
- Patient with clinic assignment cannot create appointments outside that clinic; unassigned patient
  may book any clinic only when appointment clinic matches the doctor.
- Doctor/admin profile without clinic, doctor/profile clinic mismatch, appointment/doctor clinic
  mismatch, and patient clinic mismatch are rejected for both client and trusted writes.
- Client cannot change profile `role`, `clinic_id`, `email`, or `id`; metadata-based role escalation
  remains impossible.
- Clinic admin can edit only clinic name/address and manage doctor/schedule records in their clinic.
- Patient cannot create non-pending appointments, change appointment identity, complete/confirm an
  appointment, alter a terminal appointment, or delete an appointment.
- Doctor can update only status on assigned appointments; the state-machine trigger rejects invalid
  transitions.
- Clinic admin can create pending appointments and reschedule/cancel only pending/confirmed
  appointments in their clinic; identity fields and terminal rows remain unchanged.
- Email change in Auth updates `profiles.email`; only the account owner can read their email through
  an approved path.
- Direct execution of SECURITY DEFINER helpers/trigger functions by `anon` and unauthorized client
  roles is denied.
- SQL privilege checks verify column-level update grants and absence of client delete grants.
- Rollback revokes client table privileges before disabling RLS, removes its objects, and preserves
  all table data and the `btree_gist` extension.

## 7. Risks and boundaries

- The access model intentionally allows all authenticated users to browse clinic, doctor, and
  working-hours rows across tenants. This is an approved discovery behavior; patient booking remains
  clinic-scoped when their profile has a clinic assignment.
- This schema has no deactivation flag or soft-delete mechanism. Client deletes are withheld for
  profiles, clinics, doctors, and appointments; trusted lifecycle/deactivation behavior remains
  unresolved and must not be invented here.
- Clinic assignment or existing data that violates the new required tenant matches blocks
  migration. Explicitly repair or remove affected data only under separate authorization.
- SECURITY DEFINER functions are privileged. Their owner, grants, fixed search path, schema
  qualification, and lack of arbitrary identity parameters are release-blocking review points.
- This migration secures these five tables only. It does not implement Auth UI, storage, scheduling
  rules beyond constraints already in migration 003, or any other tables.
- SQL Editor execution is not recorded in Supabase CLI migration history; numbered filenames follow
  the manual workflow documented in `supabase/README.md`.

## 8. Definition of Done

- [x] Human approves PLAN-005 — 2026-10-10.
- [ ] Tenant preflight returns no blockers or blockers receive separately approved resolution.
- [ ] All §6 positive, negative, field-level, tenant-boundary, and privilege tests pass on a
      disposable Supabase-compatible database.
- [ ] Security review confirms no anonymous grants, recursive-policy bypass, unsafe
      SECURITY DEFINER execution, or cross-tenant leaks.
- [ ] README documents migrations 001–004 and warns not to enable client access before this
      migration is installed and verified.
