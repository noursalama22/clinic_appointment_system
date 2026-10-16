# SPEC-002 — Clinic Appointment Database Schema Revision

**Status: APPROVED — human-approved 2026-10-10**

> This specification revises the database requirements in approved SPEC-001. It does not authorize
> SQL, migrations, RLS policies, or application code until an implementation plan is approved.

| | |
| --- | --- |
| Spec ID | SPEC-002 |
| Derived from | Approved `intent/clinic-appointment-system.md`; user-provided database requirements |
| Relationship | Revises SPEC-001's conflicting database requirements |
| Approval | Human-approved 2026-10-10 |

## 1. Purpose and scope

Specify an initial Supabase PostgreSQL data model for clinic identity, user profiles, doctors,
doctor working hours, and appointments. This document records required entities, fields, integrity
requirements, and access intent. It is a specification, not executable SQL.

## 2. Roles and status values

- `user_role`: `patient`, `doctor`, `admin`.
- `appointment_status`: `pending`, `confirmed`, `cancelled`, `completed`.
- Every new Auth signup receives the `patient` role. Doctor and admin roles are assigned only by a
  trusted admin or service process; clients must not be able to grant themselves elevated roles.

## 3. Required tables

Unless a column is explicitly marked `NOT NULL` below, its nullability remains unspecified and must
not be strengthened without approval. All `created_at` fields default to the database's current
timestamp.

### 3.1 `public.clinics`

| Column | Type | Requirement |
| --- | --- | --- |
| `id` | UUID | Primary key; default `gen_random_uuid()` |
| `name` | TEXT | NOT NULL |
| `address` | TEXT | Nullable |
| `created_at` | TIMESTAMPTZ | Default `now()` |

### 3.2 `public.profiles`

| Column | Type | Requirement |
| --- | --- | --- |
| `id` | UUID | Primary key; references `auth.users(id)` with `ON DELETE CASCADE` |
| `email` | TEXT | NOT NULL |
| `full_name` | TEXT | Nullable |
| `role` | `public.user_role` | NOT NULL; default `patient` |
| `clinic_id` | UUID | References `public.clinics(id)` |
| `created_at` | TIMESTAMPTZ | Default `now()` |

`profiles.id` is the identity key and has a one-to-one relationship to `auth.users.id`. An
`AFTER INSERT` trigger on `auth.users` creates a patient profile for each new Auth user.

### 3.3 `public.doctors`

| Column | Type | Requirement |
| --- | --- | --- |
| `doctor_id` | UUID | Primary key; references `public.profiles(id)` with `ON DELETE CASCADE` |
| `specialization` | TEXT | Nullable |
| `bio` | TEXT | Nullable |
| `clinic_id` | UUID | References `public.clinics(id)` |
| `created_at` | TIMESTAMPTZ | Default `now()` |

### 3.4 `public.working_hours`

| Column | Type | Requirement |
| --- | --- | --- |
| `id` | UUID | Primary key; default `gen_random_uuid()` |
| `doctor_id` | UUID | NOT NULL; references `public.doctors(doctor_id)` with `ON DELETE CASCADE` |
| `day_of_week` | INT | NOT NULL; intended values are 0 (Sunday) through 6 (Saturday) |
| `start_time` | TIME | NOT NULL |
| `end_time` | TIME | NOT NULL |
| `created_at` | TIMESTAMPTZ | Default `now()` |

### 3.5 `public.appointments`

| Column | Type | Requirement |
| --- | --- | --- |
| `id` | UUID | Primary key; default `gen_random_uuid()` |
| `patient_id` | UUID | NOT NULL; references `public.profiles(id)` with `ON DELETE CASCADE` |
| `doctor_id` | UUID | NOT NULL; references `public.doctors(doctor_id)` with `ON DELETE CASCADE` |
| `clinic_id` | UUID | References `public.clinics(id)` |
| `appointment_date` | DATE | NOT NULL |
| `start_time` | TIME | NOT NULL |
| `end_time` | TIME | NOT NULL |
| `status` | `public.appointment_status` | NOT NULL; default `pending` |
| `created_at` | TIMESTAMPTZ | Default `now()` |

## 4. Appointment lifecycle and booking conflicts

Allowed status transitions:

- `pending` → `confirmed` or `cancelled`
- `confirmed` → `cancelled` or `completed`
- `cancelled` and `completed` are terminal

Database logic must reject other status transitions. Only `pending` and `confirmed` appointments
reserve time and participate in overlap prevention. `cancelled` and `completed` appointments do not
reserve time. The database must prevent overlapping active intervals for the same doctor.

## 5. Triggers and constraints

- An `AFTER INSERT ON auth.users` trigger creates exactly one profile using the Auth user's ID and
  the default `patient` role.
- A trigger or equivalent database logic enforces the allowed appointment status transitions.
- Foreign keys and delete actions must match §3.
- `working_hours.day_of_week` is restricted to 0 through 6, inclusive.
- Working-hour and appointment intervals require `end_time > start_time`.
- The overlap constraint applies only to appointments with status `pending` or `confirmed`;
  `cancelled` and `completed` rows are excluded.
- `profiles.clinic_id` may be NULL for patients but is required for doctor and admin roles.
- `doctors.clinic_id` is required and must match the linked doctor's profile clinic.
- `appointments.clinic_id` is required and must match the doctor's clinic; when the patient has a
  clinic assignment, it must also match the patient's clinic.
- Additional booking validation constraints are not specified and must not be inferred during
  implementation.

## 6. Row-level access intent

RLS must be enabled on `public.profiles`, `public.doctors`, `public.working_hours`, and
`public.appointments`.

- Patients can manage their own profile and view/manage only their own appointments.
- Doctors can view and update appointments assigned to them and manage their own working hours.
- Admin access is scoped to the administrator's clinic.
- Signup clients cannot choose or elevate their role.

### 6.1 Approved security decision amendment — 2026-10-10

- Anonymous clients receive no row access. Authenticated users may read clinic, doctor, and working
  hours rows across clinics for discovery. A patient assigned to a clinic may book only there; an
  unassigned patient may book at any clinic.
- One profile belongs to at most one clinic. Doctor and admin profiles require a clinic assignment;
  doctor record and profile clinic IDs must match.
- `role` and `clinic_id` are assigned or changed only by a trusted backend/service-role process.
  Client users, including clinic admins, cannot change either field or change roles.
- Users may read their own profile and update only `full_name`. `profiles.email` follows
  `auth.users.email` and is visible only to its owner; related doctors/admins may read permitted
  profile basics but not email.
- Doctors may read patient profiles only for patients with appointments assigned to them. Clinic
  admins may read profiles associated with their clinic and patients who have an appointment at
  their clinic.
- Authenticated users may browse all clinic, doctor, and working-hours rows. Clinic admins may
  update their clinic's name/address and create/update doctor records only within their clinic.
  Doctor specialization and bio are editable only by a clinic admin or trusted service process.
  Clients cannot create/delete clinics or delete doctor records.
- Doctors may manage their own working hours; clinic admins may manage working hours for doctors
  in their clinic.
- Patients may create pending appointments for themselves, and may reschedule or cancel their own
  pending/confirmed appointments. A patient's update cannot change the patient, doctor, or clinic
  identity; cancelled/completed appointments are immutable to patients.
- Doctors may read appointments assigned to them and update only appointment status, subject to the
  specified lifecycle. Clinic admins may read appointments in their clinic, create pending
  appointments there, and reschedule or cancel pending/confirmed appointments without changing
  patient, doctor, or clinic identity. Cancelled/completed appointments are immutable to admins.
- Clients cannot delete appointments; cancellation is the supported client operation.
- An appointment must have a clinic matching its doctor's clinic. If a patient's profile is assigned
  to a clinic, the appointment must also match that clinic. Patients with no clinic assignment may
  book across clinics.
- RLS and SQL grants are both required. No `anon` table privileges are granted. Authenticated table
  grants are limited by table/column and paired with role- and tenant-aware RLS policies. Trusted
  service operations are kept out of client privileges.
- An Auth email change synchronizes `profiles.email`. Role, clinic, and record-identity fields are
  protected from client changes. Field-level update limits must be enforced with column privileges
  and database guards, not assumed from row policies alone.

## 7. Indexing

Indexes must support the application's actual read and write patterns. Index columns, ordering,
partial-index predicates, uniqueness behavior, and expected query patterns remain to be decided
before implementation; indexes must not be treated as a substitute for overlap prevention.

## 8. Conflict with approved SPEC-001

This proposal intentionally conflicts with existing approved decisions and requirements:

- It replaces the `scheduled`, `in_progress`, `no_show`, `completed`, `cancelled` lifecycle with
  `pending`, `confirmed`, `cancelled`, `completed`.
- It proposes clinic IDs and clinic-scoped administration, whereas SPEC-001 defines a single-clinic
  MVP and excludes multi-clinic tenancy.
- Its `working_hours` table contains only a weekday and time interval; SPEC-001 also requires
  breaks, slot duration, and date-specific availability exceptions.
- The field list omits items specified elsewhere in SPEC-001, including audit data, appointment
  consultation data, and additional schedule/availability behavior.
- Its requested `ON DELETE CASCADE` behavior for patient and doctor appointment references may
  remove appointment records when an account is deleted; the retention behavior needs approval.

These conflicts were explicitly accepted when this revision was approved. SPEC-001 remains
unchanged as a historical product specification; this document is authoritative for the database
entities and lifecycle defined here. Product requirements not addressed here remain governed by
SPEC-001 and must not be implemented through this migration scope without a further approved spec
revision.

## 9. Open questions

1. What should happen to clinic, profile, doctor, schedule, and appointment rows when their
   referenced records are deleted? In particular, should appointment history survive user deletion?
2. Which query patterns beyond foreign-key lookups should the indexes optimize?
3. Should SPEC-001 requirements for breaks, slot duration, availability exceptions, audit history,
   and consultation data be retained in additional database entities or explicitly removed?

## 10. Approval gate

This specification is human-approved. It does not independently authorize implementation. An
implementation plan must also be approved before SQL migrations, RLS policies, or application code
are written.
