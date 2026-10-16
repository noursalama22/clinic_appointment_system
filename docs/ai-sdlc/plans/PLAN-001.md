# PLAN-001 — Clinic Appointment Management System (MVP Implementation Plan)

| | |
| --- | --- |
| Plan ID | PLAN-001 |
| Derived from | `docs/ai-sdlc/specs/SPEC-001.md` (Status: APPROVED — human-approved 2026-10-05) |
| Intent source | `intent/clinic-appointment-system.md` (Status: approved) |
| Status | APPROVED — human-approved 2026-10-07 |
| Date | 2026-10-06 |
| Author | architect |

> **Approval gate (binding).** This plan is human-approved and authorizes implementation within its
> phased scope. Do not implement later-phase behavior early or invent requirements absent from this plan/spec.
> Smallest change satisfying SPEC-001. Reuse existing resources before adding packages.
> Supabase-only backend (Auth, PostgreSQL). Storage unused (D-43). No FCM/email provider/Maps/payments.
> Every phase below carries its own rollback note and test list mapped to acceptance criteria.
> **Global rollback note** is in §7.

## 0. Spec-fidelity notes (do not invent)

1. **D-register coverage.** SPEC-001 §4 defines **D-01…D-45** explicitly. The plan uses those exact
   meanings. SPEC-001 text *references* `D-46, D-47, D-48, D-49, D-50, D-51`
   (PAT-001, PAT-005, DOC-012, ADM-001, ADM-010, ADM-007, SYS-001) but §4 contains **no rows** for
   them and §9 counts "45" decisions. These are **undefined placeholders** — the plan does NOT invent
   definitions for them. Where a requirement cites one, the plan maps the requirement's *testable text*
   instead and flags the gap:
   - PAT-001/D-48 (pagination page size): SPEC-001 §4 Defaults state `page size 20` and
     `slot fetch window 30d` — plan uses those stated defaults.
   - ADM-007/D-48, ADM-010/D-46/D-47/D-48 (metrics shape, audit columns, pagination): plan uses the
     requirement text itself (ADM-001 metrics list; ADM-010 audit columns
     actor/role/action/entity/reason/timestamp; page-size default 20, reject > 200).
   - PAT-005/ADM-002/SYS-001/D-49, SYS-001/D-50 (fee display, out-of-scope integrations): plan uses §1
     out-of-scope list + requirement text (fee informational only; no payment/Maps/FCM/email).
   - DOC-012/D-51 (no Doctor-side creation): plan uses DOC-012 requirement text directly.
   - **Recommended spec amendment:** add D-46 (activity-metrics definition), D-47 (audit columns),
     D-48 (pagination defaults), D-49 (fee informational), D-50 (integration ban list),
     D-51 (doctor-insert ban) as explicit rows, or re-point the citations to existing D-nn.
     Implementation MUST NOT proceed on invented meanings; if human rejects this note, re-plan.
2. **Schema derivation discipline.** SPEC-001 names no tables/columns (schema derives from requirements
   per AGENTS.md). §2 below proposes the *minimal* tables/columns that satisfy the cited requirements.
   Anything not traceable to a SPEC-001 requirement is excluded. Column choices marked `[derived-minimal]`
   are the smallest set that makes the cited guards/RLS testable — subject to human approval, not new
   requirements.
3. **Defaults (SPEC-001 §4, stated once):** clinic timezone `UTC` placeholder (real zone before
   production per R-04/ADM-010); slot duration `30` min; lead `0`h; horizon `30`d; cancel window `2`h;
   reschedule window `2`h; max patient reschedules `2`; free-text cap `500`; page size `20`;
   slot fetch window `30`d.

---

## 1. Decisions applied (exact D-01…D-45 from SPEC-001 §4)

| ID | Decision (verbatim essence) | Plan application |
| --- | --- | --- |
| D-01 | Five statuses: `scheduled, in_progress, completed, no_show, cancelled`; `no_show` in scope | `appointment_status` enum; §6.1 transition table enforced in trigger |
| D-02 | Reschedule mutates same record (`start_at/end_at`); before/after audited | `UPDATE` path, never second row; audit before/after |
| D-03 | Only Admin MAY leave `completed/cancelled` (→ `scheduled/completed/cancelled`) w/ reason + audit | Trigger guard on terminal-exit; role check |
| D-04 | Single clinic; `departments` group `specialties` | `departments` + `specialties.department_id`; Admin calendar grouping |
| D-05 | Instants UTC; one clinic-wide timezone drives generation/display | `timestamptz` everywhere; `clinic_settings.timezone`; RPC converts |
| D-06 | One primary specialty per Doctor; specialty's department is source of truth | `doctor_profiles.specialty_id`; snapshot specialty/department on appointment |
| D-07 | Name search = case-insensitive substring on display name, `full_name ASC` | `ILIKE '%q%'` RPC, `ORDER BY full_name ASC`, page size 20 |
| D-08 | Only active + accepting-patients doctors discoverable | `is_active AND accepting_patients` predicate in Patient RPC/RLS projection |
| D-09 | Exactly 1 appointment per slot | Exclusion constraint (D-23) |
| D-10 | Email+password self-service; confirmation required; unconfirmed may sign in, MUST NOT transact | `auth.users.email_confirmed_at` check in booking/cancel/reschedule guards |
| D-11 | No Doctor self-registration; Admin provisions w/ temp password; forced change first | Provisioning flow + `must_change_password` flag gate |
| D-12 | No Admin self-registration; first Admin via service-role seed; further Admins by Admin | Seed script only path for first Admin; no in-app bootstrap |
| D-13 | `role` immutable for all incl. Admins | Trigger rejects any `role` change; RLS denies role column writes |
| D-14 | Password ≥ 8 chars; no complexity; no rotation | Client + Auth validation; recovery requires 8+ |
| D-15 | Supabase Auth JWT; SDK transparent refresh; sign-out revokes server-side; no extra timeout | `supabase_flutter` session handling; sign-out clears local state |
| D-16 | Deactivation = `deactivated` flag: no sign-in/transact, hidden from Patient views, appointments retained, NO auto-cancel, impact dialog w/ count, reversible | `profiles.is_deactivated`; guards; no cascade |
| D-17 | Deactivating only remaining active Admin fails | Guard function counts active admins |
| D-18 | `notes` R/W assigned Doctor only; denied Admins/Patients/other Doctors | Column-level denial: Patient/Admin/other-doctor reads strip `notes`; writes rejected |
| D-19 | Doctor context for own appointments: patient name/phone/reason + last 10 same-doctor appointments | Scoped RPC `get_own_appointment_detail` |
| D-20 | Availability = weekly working windows + weekly breaks + date-specific `blocked/extra` exceptions | `working_windows`, `breaks`, `availability_exceptions` tables |
| D-21 | Availability edits affect future generation only; never modify existing; out-of-window flagged, Admin resolves | No trigger touches existing rows on template edit; flag view for Admin |
| D-22 | Slots computed server-side only; client MUST NOT be source of truth | `get_available_slots(doctor_id, from_date, to_date)` RPC; client renders only |
| D-23 | Double-booking prevention = DB exclusion on overlapping active intervals per doctor | `EXCLUDE USING gist` on active statuses |
| D-24 | Rules in DB triggers/functions; client validation presentational only | All guards in PL/pgSQL; §7 RLS; client mirrors messages only |
| D-25 | Patient bookings: `start_at > now+lead` (0h) and `≤ now+horizon` (30d); per-doctor override within clinic maxima | Guard reads doctor overrides clamped to clinic settings |
| D-26 | Patient cancel own `scheduled` only when `start_at > now+2h` (configurable) | Cancel guard |
| D-27 | Patient reschedule only when `start_at > now+2h` AND `reschedule_count < 2` (configurable) | Reschedule guard |
| D-28 | No cross-doctor reschedule; same Doctor only (switch = cancel + rebook) | Guard `doctor_id` immutable on reschedule |
| D-29 | Doctor MAY cancel own `scheduled`+`in_progress` / reschedule own `scheduled` w/ reason; patient windows N/A | Doctor cancel/reschedule guard branch |
| D-30 | Admin MAY bypass lead/horizon/patient windows/reschedule count/grid; mandatory reason + audit | `is_admin_override` path w/ `bypassed_rules[]` recorded |
| D-31 | Admin MUST NOT bypass: double-booking exclusion, window containment, break/blocked avoidance | No bypass flag for these; exclusion + guards unconditional |
| D-32 | Patient bookings grid-aligned; Admin MAY create off-grid inside window (duration = slot duration) | Grid check skipped only for admin path |
| D-33 | Per-doctor slot duration default 30 min; every appointment duration MUST equal it, all actors | Duration-equality guard unconditional |
| D-34 | Doctors MUST NOT create appointments; walk-in/emergency Admin-only | RLS: no Doctor INSERT on appointments |
| D-35 | Cancellation reason mandatory, all actors; ≤ 500 chars; stored on record + audit | `cancel_reason` NOT NULL on cancelled; length guard |
| D-36 | Reason-for-visit optional all actors; ≤ 500; blank→null; visible to Doctor + Admins; not notes | `reason` nullable; normalization trigger |
| D-37 | `no_show` only once `start_at` passed | Guard `now() >= start_at` |
| D-38 | Optimistic `version` per appointment; stale writes fail; UI refetches | `version int DEFAULT 1`; guard + increment |
| D-39 | No clinical record; `notes` = free-text Doctor-only, NOT medical record | `notes` ≤ 500, no clinical schema |
| D-40 | Web in scope for Admin (responsive mandatory); Patient/Doctor mobile-first, web not deliverable but not blocked | Build matrix per SYS-002; responsive Admin |
| D-41 | `flutter_localizations` + `gen_l10n` ARB; device default; persisted per-device override; AR ⇒ RTL | `l10n/app_en.arb`, `app_ar.arb`; locale Cubit |
| D-42 | system/light/dark, default system, persisted per-device, not synced | Theme Cubit + local persistence |
| D-43 | Storage unused; no avatars/attachments/documents/uploads | No buckets; review gate |
| D-44 | No delivery channels (no FCM/email barred); dashboards always current, never stale-as-current | Pull-to-refresh + re-read on open; SYS-007 |
| D-45 | Activity metrics: counts by status today + next 7d; active doctor/patient counts; 50 most-recent privileged-action audit feed filterable role/action/entity | `get_clinic_activity()` RPC; audit feed query |

**Undefined-but-cited (gap, NOT invented — see §0.1):** D-46 (cited ADM-001, ADM-010), D-47
(cited ADM-010), D-48 (cited PAT-001, ADM-007, ADM-010), D-49 (cited PAT-005, ADM-002, SYS-001),
D-50 (cited SYS-001), D-51 (cited DOC-012). Plan implements the citing requirement text + §0.1
defaults; spec amendment recommended.

---

## 2. Supabase database schema & RLS policies

### 2.1 Enums

```sql
-- role: fixed at insert, immutable after (D-13)
CREATE TYPE user_role AS ENUM ('patient', 'doctor', 'admin');
-- D-01 five statuses
CREATE TYPE appointment_status AS ENUM
  ('scheduled', 'in_progress', 'completed', 'no_show', 'cancelled');
-- D-20 exception kinds
CREATE TYPE exception_kind AS ENUM ('blocked', 'extra');
```

### 2.2 Tables (columns / types / constraints)

> `auth.users.id (uuid)` is the PK source. `profiles.id` FK → `auth.users.id`.
> All instants `timestamptz` (UTC storage, D-05). `[derived-minimal]` = smallest column set making the
> cited SPEC guard/RLS testable.

```sql
-- profiles: one row per auth user. Covers AUTH-001..009, D-10..D-17, §7 "Own profile".
CREATE TABLE profiles (
  id               uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role             user_role NOT NULL,                       -- server-set; immutable D-13
  full_name        text NOT NULL,                             -- [derived-minimal] display name (D-07 search)
  phone            text,                                      -- [derived-minimal] patient/doctor contact (D-19)
  is_deactivated   boolean NOT NULL DEFAULT false,            -- D-16
  must_change_password boolean NOT NULL DEFAULT false,       -- D-11/D-12 forced change (AUTH-005)
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX profiles_role_active_idx ON profiles (role)
  WHERE (NOT is_deactivated);                                -- discoverability + counts (D-08, D-45)

-- departments: D-04 grouping for ADM-003/ADM-007.
CREATE TABLE departments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,                           -- [derived-minimal] stable key
  name_en     text NOT NULL,                                 -- [derived-minimal] locale labels (SYS-005)
  name_ar     text NOT NULL,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- specialties: D-06; Patient filter (PAT-002); deactivation hides from filter (ADM-003).
CREATE TABLE specialties (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid NOT NULL REFERENCES departments(id),   -- D-06 source of truth
  code          text NOT NULL UNIQUE,                        -- ADM-003 duplicate-code guard
  name_en       text NOT NULL,
  name_ar       text NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,               -- ADM-003 deactivate vs delete
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX specialties_dept_idx ON specialties (department_id);

-- doctor_profiles: professional data; one-to-one with profiles (role=doctor).
-- Covers PAT-005 fields, DOC-009/D-25/D-33 tunables, DOC-010 toggle.
CREATE TABLE doctor_profiles (
  profile_id          uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  specialty_id        uuid REFERENCES specialties(id),       -- D-06 primary specialty (nullable until assigned)
  qualifications      text,                                  -- PAT-005 [derived-minimal]
  bio                 text,                                  -- ADM-002 manageable field
  experience_years    integer CHECK (experience_years IS NULL OR experience_years >= 0), -- [derived-minimal]
  consultation_fee    numeric(10,2) CHECK (consultation_fee IS NULL OR consultation_fee >= 0),
                                                             -- informational only, D-49-gap/§1 out-of-scope
  accepting_patients  boolean NOT NULL DEFAULT true,         -- D-08/DOC-010
  slot_duration_min   integer NOT NULL DEFAULT 30 CHECK (slot_duration_min > 0), -- D-33
  lead_time_hours     numeric NOT NULL DEFAULT 0 CHECK (lead_time_hours >= 0),   -- D-25 per-doctor
  horizon_days        integer NOT NULL DEFAULT 30 CHECK (horizon_days > 0),      -- D-25 per-doctor
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- working_windows: D-20 recurring weekly intervals. Doctor-owned (DOC-009).
CREATE TABLE working_windows (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id   uuid NOT NULL REFERENCES doctor_profiles(profile_id) ON DELETE CASCADE,
  weekday     smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6), -- 0=Sunday..6=Saturday [derived-minimal convention; document in migration]
  start_time  time NOT NULL,                                 -- clinic-local wall time; RPC interprets in clinic tz (D-05)
  end_time    time NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time < end_time)                               -- DOC-009 zero-length/overlap guard (overlap checked in function)
);
CREATE INDEX working_windows_doctor_day_idx ON working_windows (doctor_id, weekday);

-- breaks: D-20 recurring weekly breaks inside windows. Doctor-owned.
CREATE TABLE breaks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id   uuid NOT NULL REFERENCES doctor_profiles(profile_id) ON DELETE CASCADE,
  weekday     smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time  time NOT NULL,
  end_time    time NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time < end_time)
  -- NOTE: break outside every window saves harmlessly (DOC-009 negative case) — no containment CHECK.
);
CREATE INDEX breaks_doctor_day_idx ON breaks (doctor_id, weekday);

-- availability_exceptions: D-20 date-specific overrides. Doctor-owned (DOC-009).
CREATE TABLE availability_exceptions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id   uuid NOT NULL REFERENCES doctor_profiles(profile_id) ON DELETE CASCADE,
  ex_date     date NOT NULL,                                 -- clinic-local date
  kind        exception_kind NOT NULL,                       -- blocked | extra
  start_time  time,                                          -- NULL = whole day when kind=blocked [derived-minimal]
  end_time    time,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'blocked' AND start_time IS NULL) OR (start_time IS NOT NULL AND end_time IS NOT NULL AND start_time < end_time))
);
CREATE INDEX avail_ex_doctor_date_idx ON availability_exceptions (doctor_id, ex_date);

-- appointments: lifecycle core. D-01 statuses, D-02 same-record reschedule, D-38 version,
-- D-35/D-36 reasons, D-06 snapshot, §6.1 state machine.
CREATE TABLE appointments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id        uuid NOT NULL REFERENCES doctor_profiles(profile_id),
  patient_id       uuid NOT NULL REFERENCES profiles(id),
  start_at         timestamptz NOT NULL,                      -- UTC instant (D-05)
  end_at           timestamptz NOT NULL,
  status           appointment_status NOT NULL DEFAULT 'scheduled',
  version          integer NOT NULL DEFAULT 1,                -- D-38 optimistic concurrency
  reschedule_count integer NOT NULL DEFAULT 0,                -- D-27
  reason           text,                                      -- D-36 optional, blank→null, ≤500
  cancel_reason    text,                                      -- D-35 mandatory when cancelled, ≤500
  notes            text,                                      -- D-18/D-39 doctor-only, ≤500
  specialty_snapshot_id   uuid REFERENCES specialties(id),   -- ADM-002: specialty change must not recategorise
  department_snapshot_id  uuid REFERENCES departments(id),   -- ADM-007 grouping stability
  created_by       uuid REFERENCES profiles(id),             -- attribution incl. on-behalf-of (D-30)
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (end_at > start_at),
  CHECK (reason IS NULL OR char_length(reason) <= 500),
  CHECK (cancel_reason IS NULL OR char_length(cancel_reason) <= 500),
  CHECK (notes IS NULL OR char_length(notes) <= 500),
  CHECK (reschedule_count >= 0)
);
CREATE INDEX appts_doctor_start_idx ON appointments (doctor_id, start_at);
CREATE INDEX appts_patient_start_idx ON appointments (patient_id, start_at);
CREATE INDEX appts_status_start_idx ON appointments (status, start_at);

-- D-09/D-23 double-booking impossibility: exclusion on overlapping ACTIVE intervals per doctor.
-- Only scheduled/in_progress occupy a slot (Terms: Active appointment, D-01).
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE appointments ADD CONSTRAINT no_double_booking
  EXCLUDE USING gist (
    doctor_id WITH =,
    tstzrange(start_at, end_at) WITH &&,
    (CASE WHEN status IN ('scheduled','in_progress') THEN doctor_id ELSE NULL END) WITH =
    -- Practical form (Postgres): partial exclusion is not native; implement as:
    -- EXCLUDE with a predicate column. Final migration MUST use the standard pattern:
  );
-- Authoritative pattern to use in migration (replaces sketch above):
-- ALTER TABLE appointments ADD CONSTRAINT no_double_booking EXCLUDE USING gist
--   (doctor_id WITH =, tstzrange(start_at, end_at) WITH &&)
--   WHERE (status IN ('scheduled','in_progress'));  -- D-09/D-23/D-31 hard limit, incl. Admin
-- Adjacent non-overlapping intervals are accepted (PAT-004 AC-3): && is strict overlap.

-- audit_logs: append-only (ADM-010, NFR-008). privileged mutations write actor/role/action/entity/
-- before-after/reason/timestamp.
CREATE TABLE audit_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid REFERENCES profiles(id),                 -- NULL only for seed-script bootstrap entry
  actor_role  user_role,
  action      text NOT NULL,                                 -- e.g. book/cancel/reschedule/status_change/correct/provision/deactivate/settings [derived-minimal vocabulary; document]
  entity      text NOT NULL,                                 -- e.g. appointment/profile/availability/settings
  entity_id   uuid,
  reason      text,                                          -- mandatory for cancel/correct/override paths
  bypassed_rules text[],                                     -- D-30/D-31: which rules an Admin bypassed (ADM-006)
  before_data jsonb,
  after_data  jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_entity_idx ON audit_logs (entity, entity_id);
CREATE INDEX audit_created_idx ON audit_logs (created_at DESC); -- ADM-001 50-most-recent feed

-- clinic_settings: single-row table (D-05 timezone, D-25/D-26/D-27/D-33 defaults, pagination cap).
CREATE TABLE clinic_settings (
  id                    integer PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- singleton
  timezone              text NOT NULL DEFAULT 'UTC',          -- D-05; real zone before production (R-04)
  default_slot_min      integer NOT NULL DEFAULT 30 CHECK (default_slot_min > 0),   -- D-33
  default_lead_hours    numeric NOT NULL DEFAULT 0 CHECK (default_lead_hours >= 0), -- D-25
  default_horizon_days  integer NOT NULL DEFAULT 30 CHECK (default_horizon_days > 0),
  cancel_window_hours   numeric NOT NULL DEFAULT 2 CHECK (cancel_window_hours >= 0), -- D-26
  reschedule_window_hours numeric NOT NULL DEFAULT 2 CHECK (reschedule_window_hours >= 0), -- D-27
  max_reschedules       integer NOT NULL DEFAULT 2 CHECK (max_reschedules >= 0),     -- D-27
  page_size             integer NOT NULL DEFAULT 20 CHECK (page_size > 0 AND page_size <= 200), -- §4 defaults + ADM-010 cap
  updated_at            timestamptz NOT NULL DEFAULT now()
);
INSERT INTO clinic_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING; -- idempotent default row
```

### 2.3 Server-side functions / triggers (D-22/D-24 — DB is the single rule source)

All functions `SECURITY DEFINER`, minimal surface, called from RLS-guarded RPCs or row triggers.
Client validation is presentational only (SYS-004).

| Function / trigger | Enforces (SPEC) | Behaviour |
| --- | --- | --- |
| `trg_profiles_immutable_role` (BEFORE UPDATE on `profiles`) | D-13, AUTH-007 | Reject any `role` change (`OLD.role <> NEW.role` → exception). Smuggled role inside profile update rejects whole write |
| `trg_appointments_normalize` (BEFORE INSERT/UPDATE) | D-36 | Blank/whitespace `reason` → NULL; length already CHECKed |
| `check_booking_allowed(p_patient, p_doctor, p_start, p_end, p_is_admin, OUT bypassed text[])` | D-25, D-31, D-32, D-33, D-08, D-16, D-10 | (1) doctor active + accepting (non-admin path hidden earlier; hard check here); (2) patient + doctor not deactivated; (3) patient email confirmed (`auth.users.email_confirmed_at NOT NULL`) unless admin path (AUTH-002 server-side); (4) `end-start` = doctor `slot_duration_min` (all actors, D-33); (5) inside a working window, not in break/`blocked`, `extra` adds range (D-20/D-31); (6) non-admin: `start > now+lead`, `start ≤ now+horizon` (per-doctor clamped to clinic maxima), grid-aligned to slot duration; admin: may bypass lead/horizon/grid → record names in `bypassed` (D-30), never bypass window/break/blocked (D-31); (7) past starts rejected (admin historical-entry choice is the only exception — explicit flag, audited) |
| `trg_appointments_insert_guard` (BEFORE INSERT) | PAT-004, DOC-012, D-34 | Doctor-role INSERT rejected (permission error, nothing written). Patient INSERT only own row (`patient_id = auth.uid()`). Admin INSERT any patient w/ mandatory reason (`cancel_reason` repurposed? NO — separate `reason` mandatory; record `created_by = auth.uid()`) |
| `trg_appointments_transition_guard` (BEFORE UPDATE of `status/start_at/end_at`) | §6.1 table, DOC-004..008, PAT-007/008, ADM-005/008, D-02/D-03/D-26..D-29/D-35/D-37/D-38 | Version check first (`NEW.version = OLD.version+1` else conflict error, D-38). Then per-transition: `scheduled→in_progress` (doctor own only); `→completed` (doctor own from scheduled/in_progress; admin correction w/ reason); `→cancelled` (patient own + outside window + reason; doctor own + reason; admin any non-terminal + reason; ADM-005 terminal-as-cancel rejected → use ADM-008); `scheduled→no_show` only `now() ≥ start_at` (D-37); terminal exits (`completed/cancelled/no_show → …`) admin-only + reason + slot-free recheck (D-03/ADM-008). Reschedule = same row, same `doctor_id` (D-28), patient windows/count (D-27) unless doctor (reason) / admin (reason + bypass log, D-29/D-30). `cancel_reason` mandatory non-empty whenever new status = cancelled (D-35). Rejected transition: no write, no version bump, no audit row (DOC-007) |
| `trg_appointments_notes_guard` (BEFORE INSERT/UPDATE when `notes` changes) | D-18/DOC-011/ADM-011 | Only assigned doctor (`doctor_id = auth.uid()`) may write `notes`; all other roles rejected |
| `trg_audit_append_only` (BEFORE UPDATE/DELETE on `audit_logs`) | ADM-010 | Reject all UPDATE/DELETE from any role |
| `trg_last_admin_guard` (BEFORE UPDATE of `is_deactivated=true` on admin profile) | D-17/ADM-009 | If no other active admin remains → domain error, nothing changes |
| `get_available_slots(p_doctor uuid, p_from date, p_to date)` RPC (STABLE) | D-22/PAT-003, D-20/D-25/D-05 | Reads clinic tz + doctor windows/breaks/exceptions + active appointments; emits grid starts (slot duration) minus breaks/blocked/occupied/lead/horizon/past; caps range to slot-fetch-window 30d; returns zone-labelled rows. Past/lead/beyond-horizon/break/blocked/occupied absent; cancelled/completed history does not suppress (PAT-003 neg) |
| `get_clinic_activity()` RPC (admin-only) | D-45/ADM-001 | Counts by status today + next 7d (clinic tz), active doctor/patient counts, 50 most-recent privileged audit rows |
| `get_own_appointment_detail(p_id)` RPC | D-19/DOC-003 | Doctor-own: appointment + patient name/phone/reason + last-10 same-doctor appointments. Denies other-doctor ids |
| `doctor_public_list(q text, spec_id uuid, page int)` RPC | D-07/D-08/PAT-001/002 | Active + accepting only, ILIKE substring, `ORDER BY full_name ASC`, page size from settings (default 20); returns published fields only (no contact/notes) |
| Settings guard trigger | ADM-010 | Reject negative lead, zero horizon, page_size > 200 |
| Deactivation effects | AUTH-008/D-16/ADM-009 | Sign-in refusal enforced at app/Auth-hook layer reading `is_deactivated`; transacting refusal in guards above; mid-session deactivation → next request rejected, session cleared client-side |

**Out-of-window flag (D-21):** view `flagged_out_of_window_appointments` (appointment outside current
template) for Admin resolution; never auto-modifies bookings.

**DST (NFR-011):** generation iterates clinic-local days via tz-aware arithmetic; DST-boundary fixtures in
unit tests prove no duplicate/dropped slots. Stored instants unchanged on tz change (ADM-010 AC-2).

### 2.4 RLS policies (§7 matrix — DB-enforced, D-24; client hiding never the control)

RLS enabled on all tables. Helper: `current_role()` = `profiles.role` for `auth.uid()`;
`is_admin()`, `is_own_doctor(doctor_id)`, `is_owner(patient_id)` built on it.
Every denial below MUST have a dedicated integration test (§6 test map, §11).

| Collection | Patient | Doctor | Admin | Denials tested |
| --- | --- | --- | --- | --- |
| Own profile (`profiles` self row) | SELECT own; UPDATE `full_name/phone` only (role/is_deactivated/must_change_password unwritable; role change → whole-write reject, AUTH-007 neg) | SELECT own; UPDATE own allowed fields (non-role) | SELECT all; UPDATE all except `role` | Patient cross-profile SELECT denied; any `role` write denied |
| Other profiles | No access; doctors visible only via `doctor_public_list` projection | SELECT patients on own appointments only, D-19 fields via RPC (no direct table SELECT) | SELECT all; no `role` writes | Patient direct SELECT on another profile denied; doctor bulk-profiles SELECT denied |
| Doctor professional data | SELECT published fields of discoverable only (RPC projection; no contact/notes) | SELECT/UPDATE own row only | SELECT/UPDATE all rows (notes never returned) | Patient read of deactivated/non-accepting doctor denied; doctor cross-row UPDATE denied |
| Specialties/departments | SELECT `is_active` only | SELECT all | SELECT/INSERT/UPDATE all; DELETE specialty only when zero doctors reference it (blocked w/ reassignment message, ADM-003) | Patient read of inactive specialty denied; non-admin INSERT/UPDATE/DELETE denied; duplicate code rejected |
| Own availability (windows/breaks/exceptions) | No access (no SELECT/INSERT/UPDATE/DELETE) | SELECT/INSERT/UPDATE/DELETE own `doctor_id` rows only | SELECT all; no per-doctor row writes (clinic-wide via settings only) | Patient any-access denied; doctor cross-doctor write denied; admin per-doctor row write denied |
| Appointments | SELECT own; INSERT own per PAT-004 guard; UPDATE own per PAT-007/008 guard only | SELECT own (doctor_id = self); UPDATE status/notes/reschedule per DOC-004–008/011 guards; NO INSERT (DOC-012) | SELECT all **minus `notes`** (view `appointments_admin` excludes column; ADM-011); INSERT/UPDATE per ADM-004–006/008 guards | Patient cross-read denied (no data renders, PAT-009); doctor cross-doctor read denied; doctor INSERT denied; patient `in_progress`/terminal cancel denied; reschedule other-doctor denied |
| `notes` value | Never returned (excluded from all patient payloads/views) | Assigned doctor only (read + write); other doctors denied | Never returned in any query/view/export; writes rejected (ADM-011) | Admin notes read (absent field, not placeholder) + write denied; patient notes read denied; other-doctor read/write denied; over-length blocked |
| Audit trail | No access | No access | SELECT only; UPDATE/DELETE rejected for ALL roles incl. admin (append-only) | Patient/doctor SELECT denied; any UPDATE/DELETE denied |
| Clinic settings | SELECT (limits/timezone read) | SELECT | SELECT/UPDATE (validated ranges) | Non-admin UPDATE denied |

**Notes-stripping implementation:** role-aware views/RPCs — `appointments_patient` (own, no notes),
`appointments_doctor` (own, with notes only when requester = assigned doctor),
`appointments_admin` (all, no notes column at all). Direct table SELECT denied for patient/doctor;
all reads go through views/RPCs. Reason-for-visit stays visible to Admins (ADM-011 neg).

### 2.5 Seed script — first Admin, idempotent (AUTH-006)

- Location (proposed, created at implementation): `supabase/seed_first_admin.sql` executed with the
  **service-role key only**, never from the app. No in-app Admin creation exists when zero Admins
  (operator-setup notice shown, AUTH-006 AC-2).
- Behaviour: inserts `auth.users` (email + temp password, `email_confirmed_at = now()`) + `profiles`
  (`role='admin'`, `must_change_password=true`) **only if** no active admin exists; second run creates
  nothing (idempotent, AUTH-006 AC-3). Writes a bootstrap audit row with `actor_id NULL`.
- Inputs via environment (`FIRST_ADMIN_EMAIL`), never hardcoded. Rollback: delete is manual and
  requires confirming ≥1 other active admin remains (D-17).

### 2.6 Storage

Unused in MVP (D-43, SYS-001). No buckets created. Any future file need requires an approved spec
amendment before any bucket/policy exists.

---

## 3. Flutter project architecture & scaffolding

### 3.1 Single codebase layout (proposed — created at implementation, not in planning)

```text
lib/
  main.dart                    # composition root: DI, Supabase init, locale/theme load, role router
  core/
    config/                    # supabase client, env, constants (page size fallback 20, fetch window 30d)
    di/                        # service locator (get_it or hand-rolled; Bloc/Cubit only, SYS-003)
    error/                     # failure types → localized-message mapper (SYS-008: no raw SQL text)
    network/                   # connectivity guard (offline-distinct errors, NFR-007)
    l10n/                      # gen_l10n wiring; locale Cubit (persisted per-device, D-41)
    theme/                     # light/dark/system ThemeData + theme Cubit (per-device, D-42)
    widgets/                   # shared loading/empty/error-with-retry, responsive scaffolds
    utils/                     # clinic-tz formatters (UTC instant → clinic zone display, D-05)
  features/
    auth/                      # data (datasource via Supabase Auth + profiles repo), domain, presentation (Cubits: session, sign-in/up, recovery, force-change)
    patient/                   # discovery (search/filter), slots, booking, my-appointments, detail/cancel/reschedule
    doctor/                    # schedule day/week, filters, detail+context, status transitions, availability editor, toggle, notes
    admin/                     # dashboard, user provisioning/lists, catalogue, on-behalf-of, calendar, corrections, audit, settings
  l10n/arb/app_en.arb  l10n/arb/app_ar.arb   # 100% user-visible strings (NFR-005)
```

Clean Architecture per feature: `data/` (datasources,DTOs,repository impls) → `domain/`
(entities,use-cases,repository interfaces) → `presentation/` (Bloc/Cubit + pages/widgets).
Repository Pattern + DI throughout; business logic in testable units separable from widgets (SYS-003).
`setState`-as-state-management, Riverpod, Provider, GetX-for-state MUST NOT be used; review gate.

### 3.2 Cross-cutting wiring

- **State:** Bloc/Cubit only (SYS-003). One Cubit per flow (session, locale, theme, discovery, slots,
  booking, schedule, availability, admin lists, audit, settings). No global non-Bloc state.
- **Backend:** `supabase_flutter` only (SYS-001). Auth + PostgreSQL (RPC/views). No FCM, no email
  provider, no Maps, no payments, no Storage client use. Architecture review fails on any other backend import.
- **Localization (D-41/SYS-005):** `flutter_localizations` + `gen_l10n` ARB; device locale default;
  in-app override persisted locally per device (not synced). Arabic ⇒ full RTL mirroring; numerics per
  locale (PAT-005 AC-3). Zero raw keys (NFR-005 catalogue-completeness test).
- **Theming (D-42/SYS-006):** system default; light/dark/system switch persisted locally; WCAG AA contrast
  both themes (NFR-004).
- **Responsive (SYS-006/ADM-012/D-40):** 360→1440px+ breakpoints; shared responsive scaffold; Admin tables
  collapse to non-truncating card representations; no page-level horizontal scroll; verified 360/768/1024/1440
  × AR/EN widget tests.
- **Role-gated nav (AUTH-009):** post-auth router → Patient appointments / Doctor schedule / Admin dashboard;
  cross-role deep links denied with localized error and redirect home (no data leak); unauthenticated deep
  link → entry screen → return after sign-in.
- **Freshness (SYS-007/D-44):** re-read on open/refresh everywhere; failed refresh ⇒ localized error +
  retry (offline distinguished), never stale-as-current. No badges/toasts implying unconfirmed state.
- **Error hygiene (SYS-008):** localized user-readable errors naming the failed action; no crash, no raw DB
  text, on-screen data unchanged; unexpected errors ⇒ generic message + locally logged correlation id.

### 3.3 Proposed packages (NOT installed in planning — install only after plan approval, smallest set)

| Package | Purpose | Justifies (SPEC) |
| --- | --- | --- |
| `supabase_flutter` | Auth + PostgreSQL only | SYS-001 backend |
| `flutter_bloc` (+ `equatable`) | Bloc/Cubit state | SYS-003 (Bloc/Cubit only) |
| `get_it` | DI/service locator | SYS-003 repository+DI |
| `flutter_localizations` (SDK) + `intl` | AR/EN + RTL + tz-aware formatting | SYS-005/D-41/D-05 |
| `timezone` | Clinic-zone conversion/DST-correct display | D-05/NFR-011 |
| `shared_preferences` | Per-device locale/theme persistence | D-41/D-42 |
| `connectivity_plus` | Distinct offline errors | NFR-007/PAT-010 |
| `mocktail`, `bloc_test` (dev) | Unit/widget tests | §11 |

`flutter_lints` retained; `flutter analyze` clean is a per-phase gate. Anything beyond this table
(icons already present) needs a plan-amendment justification.

---

## 4. Five-week phased roadmap

> Each week maps SPEC IDs + D-decisions, lists entry/exit criteria, and names its rollback.
> Week boundaries are incremental-integration order, not waterfall sign-off: every week ends with
> `flutter analyze` + its test tier green on the merged tree.

### W1 — Foundation: setup, schema/RLS shell, Auth, l10n/theme shell

**SPEC:** AUTH-001…009 (scaffolding paths), SYS-001…008 (shell), D-05/D-10…D-17/D-40…D-44, §7 matrix shell.
**Build:**

1. Project scaffolding per §3.1 (no feature logic beyond auth shell); proposed packages installed
   (post-approval); `gen_l10n` wired with minimal AR/EN catalogues; theme + locale Cubits persisted.
2. Supabase project + migration with §2.1–§2.2 DDL + exclusion constraint + `clinic_settings` row;
   seed script `seed_first_admin.sql` (service-role only, idempotent).
3. RLS policies §2.4 + guard triggers §2.3 (profiles immutability, audit append-only, last-admin).
4. Auth flows: Patient sign-up (role server-set `patient`, smuggled-role-ignored), sign-in/out + refresh,
   recovery, forced-change gate for provisioned accounts, deactivation refusal, role-gated router.
5. Role-gated nav shell + error-hygiene + offline-distinct error plumbing.

**Exit:** sign-up/in/out/recovery/force-change/deactivation-denied journeys pass against real backend;
`flutter analyze` clean; AR/EN shell renders RTL without raw keys.
**Tests (§6 map rows AUTH-001…009, SYS-005/006/008):** unit (password/email validators, locale/theme
persistence); widget (entry, sign-up, sign-in, recovery, force-change gate, role routing, AR RTL smoke,
theme triple); integration (smuggled-role ignored; unconfirmed transacting refused server-side;
generic auth errors identical; revoked token never re-authenticates; deactivated sign-in refused;
cross-role deep-link denied without data leak).
**Rollback:** drop migration (`supabase migration down` to pre-W1); revoke seed-created admin via SQL
confirming replacement admin exists; revert package installs (`git revert`, `flutter pub get`).
No patient data exists yet — data loss surface is nil.

### W2 — Patient: discovery → slots → booking → manage (PAT-001…PAT-010)

**SPEC:** PAT-001…010; D-02/D-05/D-07…D-10/D-20/D-22…D-28/D-32/D-33/D-35/D-36; §6.1 book/cancel/reschedule rows.
**Build:**

1. `doctor_public_list` RPC + discovery UI (D-07 substring ASC, D-08 discoverable-only, specialty filter
   conjunction + independent clear, PAT-001/002 pagination page-size 20 + totals).
2. `get_available_slots` RPC (D-22 server-side; D-20 windows/breaks/exceptions; D-25 lead/horizon;
   D-05 clinic-tz labelled) + slot calendar UI (14-day minimum, free/fully-booked/no-hours/blocked states,
   refresh recomputes, PAT-003).
3. Booking (PAT-004): grid-aligned, duration = doctor duration, single `scheduled` row; exclusion constraint
   is the control; loser UX = conflict error + return-to-availability. Profile view (PAT-005, no contact/notes).
4. My appointments upcoming/past (PAT-006), detail w/ permitted-actions-only (PAT-009, cross-patient denial
   renders nothing), cancel w/ window + mandatory reason (PAT-007), same-doctor reschedule w/ window + count
   + same-record mutation + audit before/after (PAT-008). Freshness/error states everywhere (PAT-010/SYS-007).

**Exit:** end-to-end patient journey (search → profile → slots → book → upcoming → reschedule → cancel →
past) green in both locales; concurrency probe shows exactly-one-winner.
**Tests (§6 rows PAT-001…010, NFR-002/005/007/010/011-part):** unit (lead/horizon/window guards, grid math,
reason normalization blank→null); widget (search/filter incl. empty states, slot calendar states,
booking confirmation, upcoming/past lists, cancel/reschedule dialogs, offline/error states, debounce with
fake clock); integration (concurrent same-slot ⇒ exactly one success; adjacent accepted; past/off-grid/
break/out-of-window/non-discoverable rejected; unconfirmed booking refused; cross-patient read denied;
cancel-inside-window rejected; reschedule-limit refused with Admin-escalation message; cross-doctor
reschedule rejected).
**Rollback:** feature-flag off patient booking UI; DB guards remain (safe — they only reject invalid
writes); revert client commits to W1 tag; no data migration to undo (no new tables this week beyond RPCs —
drop RPCs if needed).

### W3 — Doctor: schedule, transitions, availability, notes (DOC-001…DOC-013)

**SPEC:** DOC-001…013; D-01…D-03/D-08/D-18…D-21/D-23/D-29/D-33…D-39; §6.1 doctor rows; §7 doctor column.
**Build:**

1. Day/ISO-week dashboards (clinic-local, ASC, per-day counts, month/year/leap navigation, DOC-001) +
   status filter w/ visible clearable chip (DOC-002) + `get_own_appointment_detail` (D-19 context, DOC-003).
2. Transitions via guarded UPDATE: start (DOC-004) + stale-version conflict UX (D-38); complete (DOC-005);
   no-show past-start-only (DOC-006/037); illegal-transition rejection w/o audit (DOC-007); doctor
   cancel/reschedule own w/ mandatory reason (DOC-008/D-29).
3. Availability editor: windows/breaks/duration/lead/horizon within clinic maxima/exceptions (DOC-009;
   validation blocks overlap/zero-length/invalid; future-generation-only D-21; out-of-window flag view);
   accepting-patients toggle (DOC-010); notes editor ≤500, owner-only (DOC-011); no creation UI + insert
   rejection (DOC-012); loading/empty(+hours)/error-retry states w/ input retention (DOC-013).

**Exit:** doctor journey (schedule → detail → start → complete / no-show / cancel / reschedule →
availability edit → toggle) green; availability edit provably touches zero existing appointments.
**Tests (§6 rows DOC-001…013, NFR-011):** unit (slot-grid arithmetic incl. break overlap, non-multiple
remainder ⇒ no trailing slot; window/break/exception interaction; DST fixtures; transition-guard table);
widget (day/week dashboards, filter chips, detail, availability editor validation, toggle, notes field,
input-retention on failed save); integration (cross-doctor read denied; doctor INSERT denied; terminal
reversal by doctor denied; future no-show denied; stale-version conflict; notes hidden from admin/patient/
other-doctor payloads; availability narrowing retains all appointments).
**Rollback:** revert doctor client commits to W2 tag; keep DB guards (they only constrain); availability
edits are data — snapshot `working_windows/breaks/availability_exceptions/doctor_profiles` per doctor
before W3 UAT and restore on abort.

### W4 — Admin + Web responsive (ADM-001…ADM-012)

**SPEC:** ADM-001…012; D-03/D-04/D-06/D-11/D-12/D-16/D-17/D-30/D-31/D-40; §6.1 admin rows; §7 admin column.
**Build:**

1. Activity dashboard (D-45 metrics: today + 7d by status, active counts, 50-recent privileged feed;
   no financials, ADM-001) + provisioning (doctors w/ temp password + forced flag; further admins;
   specialty-change keeps snapshots, ADM-002) + catalogue (specialties/departments CRUD, in-use delete
   blocked, deactivation hides from filter, ADM-003).
2. On-behalf-of create (ADM-004: any patient/doctor, off-grid-in-window allowed, mandatory reason,
   duration = slot duration, hard limits unconditional) + move/cancel any non-terminal (ADM-005, same-record,
   bypass audit) + override boundaries incl. `bypassed_rules` recording (ADM-006/D-30/D-31).
3. Clinic-wide calendar (grouped department → start ASC, doctor/department/multi-status/range filters as
   chips, paginated, no notes, ADM-007) + terminal corrections w/ reason + overlap rejection (ADM-008/D-03).
4. Deactivate/reactivate w/ impact dialog (count + earliest date, explicit confirm, last-admin guard,
   ADM-009/D-16/D-17) + audit viewer (filters, newest-first, paginated, immutable, ADM-010) + settings
   (timezone/lead/horizon/windows/count/duration/page-size ≤200, ADM-010) + notes-absence guarantee (ADM-011).
5. Responsive Admin Web + mobile: 390–1440px+ full operability, tables→cards, RTL mirroring, theme contrast
   (ADM-012/D-40; builds per SYS-002: admin ships Web + Android/iOS).

**Exit:** admin journeys (provision → calendar → on-behalf-of → correction → deactivate → audit → settings)
green on Web (1440/1024/390) + mobile, AR + EN, all themes.
**Tests (§6 rows ADM-001…012, NFR-003/004/006):** unit (override-boundary matrix: bypassable vs hard-limit;
settings validators); widget (dashboard panels + failing-panel retry isolation; calendar groupings/filters;
user lists; audit filters; responsive 4-widths × 2-locales overflow-free; semantics + contrast);
integration (§7 admin denials: notes absent from every payload + writes rejected; audit UPDATE/DELETE
rejected all roles; settings write by non-admin rejected; last-admin deactivation fails; terminal correction
overlap rejected; reasonless correction blocked; off-window booking rejected even for admin).
**Rollback:** disable admin override endpoints (RLS `is_admin()` write paths) leaving read-only admin;
revert client to W3 tag; settings change during UAT snapshot-restored; Web deployment rolled back to prior
hosting revision independently of mobile.

### W5 — Hardening, testing, release (NFRs, concurrency, DST, offline, builds)

**SPEC:** NFR-001…011, SYS-001/002/004/007/008, Q-01…Q-05 confirmations, R-01…R-06 mitigations.
**Build:**

1. Perf: 30-day slot render < 3 s mid-range/4G (NFR-001 timed test; paginate/lazy day expansion if red);
   search debounce + empty-query-no-request (NFR-002).
2. Full §11 suite green: unit + widget (4 widths × 2 locales × 3 themes) + integration incl. all denial tests,
   concurrency (exactly-one-winner, stale-version), DST fixtures, offline-cut freshness tests, audit-completeness
   per mutation (NFR-008), auth-enumeration negatives (NFR-009).
3. Release: Android + iOS (patient/doctor/admin), Web admin (SYS-002/D-40); no desktop artifacts; real clinic
   timezone set (ADM-010/R-04); Supabase tier quota check (R-05); security review of notes handling (Q-04/R-06).
4. Human approval gates: Q-01 (web effort), Q-02 (2h/2× defaults), Q-03 (no notifications), Q-04 (notes),
   Q-05 (5-week/budget) — all confirmed 2026-10-05 per SPEC-001 §12; re-confirm if W1–W4 findings challenge them.

**Exit (release criteria):** `flutter analyze` clean; full test suite green with negative/denial coverage
(happy-paths-only fails review); release artifacts for required platforms only; DoD checklist signed.
**Tests:** the complete §6 matrix executed; timed perf; network-cut offline tests; DST boundary fixtures.
**Rollback:** tag release; mobile rollback via staged rollout halt + prior build; Web rollback to prior
revision; DB: no destructive migration in W5 — any hotfix migration ships with its own down-script and
snapshot restore procedure (§7 global note).

---

## 5. Package & dependency plan (proposed only — DO NOT INSTALL in planning)

Per §3.3 table. Install order at implementation (post-approval): `supabase_flutter` →
`flutter_bloc`/`equatable` → `get_it` → `intl`/`timezone` → `shared_preferences` →
`connectivity_plus` → dev (`mocktail`, `bloc_test`). `flutter pub get` after each; `flutter analyze`
gate. Smallest-change rule: no additional package without a SPEC-traceable justification recorded here.

---

## 6. Test mapping — every AUTH/PAT/DOC/ADM/SYS/NFR acceptance criterion → test tier

Tier key: **U**nit (pure logic, no widgets/backend) · **W**idget (key UI, both locales AR/EN, 3 themes
unless noted) · **I**ntegration (real backend: RLS/constraints/concurrency/denials). Per §11: negative and
denial tests are mandatory; happy-paths-only fails review.

### AUTH

| Req | Acceptance criterion | U | W | I |
| --- | --- | --- | --- | --- |
| AUTH-001.1 | Valid unused email + 8+ pw ⇒ patient account + verification notice | validator-U | sign-up flow-W | created-role-is-patient-I |
| AUTH-001.2 | Registered email ⇒ generic error, no registration-status leak | — | generic-error message-W | identical-response probe-I |
| AUTH-001.3 | Short pw / bad email blocked client-side, no request | validator-U | blocked-submit-W | no-request assertion (empty-query analogue)-W |
| AUTH-001.neg | Smuggled doctor/admin role ignored, persisted patient | — | — | smuggled-role-ignored-I |
| AUTH-002.1 | Unconfirmed may browse doctors/slots normally | — | browse-renders-W | read-allowed-I |
| AUTH-002.2 | Unconfirmed book/cancel/reschedule refused, verify-email error, no write | — | refused-UX-W | server-side-refusal + no-write-I |
| AUTH-002.3 | Post-verification retry proceeds | — | — | retry-after-confirm-I |
| AUTH-002.neg | Confirmation evaluated server-side; client flag insufficient | — | — | forged-flag-denied-I |
| AUTH-003.1 | Valid credentials ⇒ role home | — | routing-W | sign-in-I |
| AUTH-003.2 | Wrong pw / unknown email ⇒ identical generic error | — | identical-message-W | enumeration-probe-I (NFR-009) |
| AUTH-003.3 | Expired access + valid refresh ⇒ transparent success | — | — | refresh-flow-I |
| AUTH-003.4 | Sign-out (even offline) ⇒ cleared state, entry screen, revoked token dead | session-U | signed-out-UI-W | revoked-token-rejected-I |
| AUTH-003.neg | Error text from catalogues, no distinction | catalogue-U | — | — |
| AUTH-004.1 | Reset request ⇒ generic success regardless of registration | — | generic-success-W | enumeration-probe-I |
| AUTH-004.2 | Valid link + 8+ pw ⇒ updated + signed in | validator-U | reset-flow-W | recovery-I |
| AUTH-004.3 | Expired/reused/tampered token ⇒ no change + error | — | error-W | token-reuse-denied-I |
| AUTH-004.neg | New pw identical to current refused | — | validation-W | refused-I |
| AUTH-005.1 | Temp-password sign-in ⇒ only change-password reachable | — | gate-W | flag-gate-I |
| AUTH-005.2 | Navigate-away ⇒ no role screen reachable | — | back-nav-blocked-W | deep-link-denied-I |
| AUTH-005.3 | After change ⇒ temp dead, activated | — | — | old-credential-rejected-I |
| AUTH-005.neg | Back-nav/deep-link never bypasses while flag set | — | bypass-attempts-W | bypass-denied-I |
| AUTH-006.1 | Admin provisions admin w/ temp ⇒ created + listed | — | provision-UI-W | provision-I |
| AUTH-006.2 | Zero-admin deployment ⇒ operator notice, no in-app creation | — | notice-W | creation-path-absent-I |
| AUTH-006.3 | Seed twice ⇒ idempotent, no duplicate | — | — | double-seed-I |
| AUTH-006.neg | Duplicate email ⇒ domain error, nothing created | — | error-W | duplicate-rejected-I |
| AUTH-007.1 | Any role-change attempt ⇒ rejected, unchanged | — | — | role-write-rejected-I (all roles incl. admin) |
| AUTH-007.2 | User screens: no role control, read-only display | — | absent-control-W | — |
| AUTH-007.neg | Smuggled role inside profile update rejects whole write | — | — | smuggled-role-update-rejected-I |
| AUTH-008.1 | Deactivated sign-in ⇒ deactivated message | — | message-W | sign-in-refused-I |
| AUTH-008.2 | Mid-session deactivation ⇒ next request rejected + cleared + message | — | signed-out-W | mid-session-rejected-I |
| AUTH-008.3 | Deactivated doctor absent from search/slots | — | absent-W | hidden-from-RPC-I |
| AUTH-008.neg | Deactivated appointments still retrievable by admins | — | — | admin-retained-I |
| AUTH-009.1 | Each role lands on correct home | — | three-roles-routing-W | — |
| AUTH-009.2 | Cross-role deep link ⇒ denied + home, localized | — | denial-W | no-data-leak-I |
| AUTH-009.3 | Unauthenticated deep link ⇒ entry → return post-sign-in | — | return-after-auth-W | — |
| AUTH-009.neg | Denial leaks no target data | — | — | leak-probe-I |

### PAT

| Req | Acceptance criterion | U | W | I |
| --- | --- | --- | --- | --- |
| PAT-001.1 | "ha" ⇒ active+accepting substring matches ASC | — | discovery-W | RPC-ordering-I |
| PAT-001.2 | No match ⇒ empty state, no error | — | empty-W | — |
| PAT-001.3 | >1 page ⇒ one page + total, no dup/omission | paging-U | pager-W | page-sizes-I (20 default) |
| PAT-001.neg | Deactivated/non-accepting never appear even exact match | — | — | hidden-I |
| PAT-002.1 | Specialty filter ⇒ only that primary specialty | — | filter-W | RPC-filter-I |
| PAT-002.2 | Search+filter conjunction | — | combined-W | conjunction-I |
| PAT-002.3 | Clear one ⇒ other retained + refresh | — | independent-clear-W | — |
| PAT-002.neg | Empty specialty listed, yields empty state not error | — | empty-W | — |
| PAT-003.1 | ≥14 days show available/fully-booked | — | calendar-W | RPC-range-I |
| PAT-003.2 | Free day ⇒ times in clinic tz, zone labelled | tz-format-U | times-W | — |
| PAT-003.3 | Fully-booked / no-hours / blocked ⇒ correct unavailable, no times | grid-U | states-W | blocked-suppresses-I |
| PAT-003.4 | Refresh ⇒ recomputed; stale never current | — | refresh-W | recompute-I + stale-flag test (SYS-007) |
| PAT-003.neg | Break/lead/horizon-blocked absent; cancelled/completed history doesn't suppress | guard-U | — | suppression-matrix-I |
| PAT-004.1 | Valid confirm ⇒ one scheduled, in upcoming, slot gone | — | booking-W | insert + slot-taken-I |
| PAT-004.2 | Concurrent same-slot ⇒ exactly one wins; loser conflict + return action | — | conflict-UX-W | concurrency-I (NFR-010) |
| PAT-004.3 | Adjacent non-overlap ⇒ both accepted | range-U | — | adjacency-I |
| PAT-004.4 | Past/horizon/off-grid/break/out-of-window/non-discoverable ⇒ rejected, no record | guard-U | error-W | rejection-matrix-I |
| PAT-004.neg | Duration ≠ slot duration rejected every actor | — | — | duration-matrix-I (patient/doctor/admin) |
| PAT-005.1 | Profile fields + slot path in active locale | — | profile-W (AR+EN) | published-fields-I |
| PAT-005.2 | Deactivated-after-open ⇒ unavailable, no booking control | — | unavailable-W | — |
| PAT-005.3 | Arabic ⇒ locale numerics + RTL | — | RTL-numerics-W | — |
| PAT-005.neg | No contact/notes/other-doctor data | — | absent-fields-W | payload-scan-I |
| PAT-006.1 | Upcoming: future scheduled/in_progress ASC | sort-U | upcoming-W | own-only-I |
| PAT-006.2 | Past: elapsed/terminal DESC w/ localized labels incl. no_show | sort-U | past-W | — |
| PAT-006.3 | Empty ⇒ localized empty + next action | — | empty-W | — |
| PAT-006.neg | Another patient's rows never appear | — | — | cross-read-denied-I |
| PAT-007.1 | Eligible cancel + reason ⇒ cancelled + actor/ts/reason, past list, slot freed | window-U | cancel-W | transition + slot-freed + audit-I |
| PAT-007.2 | Inside-window / non-scheduled ⇒ unoffered + direct attempt rejected | window-U | unoffered-W | policy-reject-I |
| PAT-007.3 | Empty/over-length reason blocked | validator-U | validation-W | — |
| PAT-007.neg | in_progress/terminal/other-patient cancel rejected | — | — | denial-matrix-I |
| PAT-008.1 | Eligible move ⇒ same id updated, count+1, old freed/new taken | — | reschedule-W | same-record + audit-before-after-I |
| PAT-008.2 | In-window/at-limit/non-scheduled ⇒ refused (+ Admin path named at limit) | guard-U | refused-W | policy-matrix-I |
| PAT-008.3 | Concurrently-taken target ⇒ conflict, original retained | — | conflict-W | race-I |
| PAT-008.neg | Different-doctor target rejected | — | — | doctor-immutable-I |
| PAT-009.1 | Own detail renders all fields + only permitted actions | — | detail-W | — |
| PAT-009.2 | Other-patient id ⇒ denied, nothing renders, no notes | — | denial-W | cross-read-denied-I |
| PAT-009.neg | Detail never exposes notes | — | — | notes-absent-I |
| PAT-010.1 | Loading ⇒ indicator, no partial-as-final | — | loading-W | — |
| PAT-010.2 | Failed refresh ⇒ error + retry (offline distinct), not stale-as-current | — | error-offline-W | network-cut-I (NFR-007) |
| PAT-010.3 | Slot-taken-at-confirm ⇒ PAT-004 conflict path, no success shown | — | conflict-W | race-I |
| PAT-010.neg | No silent success-with-no-effect | — | — | effect-assertion-I |

### DOC

| Req | Acceptance criterion | U | W | I |
| --- | --- | --- | --- | --- |
| DOC-001.1 | Day dashboard: exactly those rows ASC w/ all fields, clinic tz | sort-U | daily-W | own-only-I |
| DOC-001.2 | Week: 7 clinic-local days + per-day counts, empties present | week-group-U | weekly-W | — |
| DOC-001.3 | Day/week/month-year/leap navigation loads correct dates, server re-read | date-U | navigation-W | re-read-I |
| DOC-001.neg | Other doctors' rows never appear | — | — | cross-doctor-denied-I |
| DOC-002.1 | Status filter ⇒ only that status | — | filter-W | — |
| DOC-002.2 | Empty filter ⇒ empty state + indicated + clearable | — | empty-W | — |
| DOC-002.neg | Filter never reveals others' rows | — | — | denied-I |
| DOC-003.1 | Own detail: name/phone/reason + ≤10 same-doctor recents | cap-U | detail-W | RPC-scope-I |
| DOC-003.2 | Other-doctor id ⇒ denied, nothing renders | — | denial-W | denied-I |
| DOC-003.neg | No clinical history/vitals/Rx/docs | — | absent-W | payload-scan-I |
| DOC-004.1 | Own scheduled ⇒ in_progress + audit | transition-U | start-W | transition + audit-I |
| DOC-004.2 | Stale version ⇒ conflict + refresh prompt, no change | version-U | conflict-W | race-I (NFR-010) |
| DOC-004.neg | Other-doctor start rejected | — | — | denied-I |
| DOC-005.1 | Own scheduled/in_progress ⇒ completed + audit | transition-U | complete-W | transition-I |
| DOC-005.2 | Completed ⇒ no control; direct attempt rejected, unchanged | transition-U | unoffered-W | terminal-denied-I |
| DOC-005.neg | Any other status ⇒ rejected | transition-U | — | matrix-I |
| DOC-006.1 | Past-start own scheduled ⇒ no_show + audit | timing-U | mark-W | transition-I |
| DOC-006.2 | Future-start ⇒ unoffered + direct rejected | timing-U | unoffered-W | policy-denied-I |
| DOC-006.3 | no_show ⇒ doctor change rejected | transition-U | — | terminal-denied-I |
| DOC-006.neg | Non-scheduled ⇒ rejected | transition-U | — | matrix-I |
| DOC-007.1 | Terminal + doctor attempt ⇒ rejected, no write/version change | transition-U | error-W | no-write-no-audit-I |
| DOC-007.2 | UI names action, no raw DB text | — | message-W | no-leak-I (SYS-008) |
| DOC-007.neg | Rejection writes no audit row | — | — | audit-absent-I |
| DOC-008.1 | Eligible cancel + reason ⇒ cancelled + freed | — | cancel-W | transition + audit-I |
| DOC-008.2 | Own scheduled → free own slot + reason ⇒ same record, count+1, audited; patient sees new time | — | move-W | same-record + visibility-I |
| DOC-008.3 | Overlap target / in_progress reschedule ⇒ rejected, original kept | guard-U | error-W | conflict/policy-denied-I |
| DOC-008.neg | Empty reason blocked; terminal uncancellable | validator-U | validation-W | denial-matrix-I |
| DOC-009.1 | 09–17 − 13–14 @30m ⇒ on-grid, no break overlap, no trailing remainder | grid-U | slots-preview-W | RPC-grid-I |
| DOC-009.2 | Overlap/zero-length/invalid ⇒ blocked, data unchanged | validator-U | editor-validation-W | unchanged-I |
| DOC-009.3 | Blocked day ⇒ none; extra on closed day ⇒ only that range | exception-U | preview-W | RPC-exceptions-I |
| DOC-009.4 | Narrow/delete/duration-change ⇒ all appointments retained (flagged) | — | flagged-W | retention-I (D-21) |
| DOC-009.neg | Break outside windows saves harmlessly | — | — | no-effect-I |
| DOC-010.1 | Off ⇒ vanishes from search/profile/slots, new bookings rejected, existing stay | — | vanished-W | hidden + retained-I |
| DOC-010.2 | On ⇒ discoverability/bookability resume next read | — | resumed-W | resumed-I |
| DOC-010.neg | Toggle never cancels/moves/hides own-schedule rows | — | — | retention-I |
| DOC-011.1 | Own notes save + render on reopen | — | notes-W | round-trip-I |
| DOC-011.2 | Admin/patient/other-doctor payloads: notes absent (no placeholder/length) | — | — | absence-scan-I |
| DOC-011.3 | Non-owner notes write rejected | — | — | write-denied-I |
| DOC-011.neg | Over-length blocked | validator-U | validation-W | length-reject-I |
| DOC-012.1 | No create/walk-in control on any doctor screen | — | absent-control-W | — |
| DOC-012.2 | Doctor insert ⇒ permission error, no record | — | — | insert-denied-I |
| DOC-013.1 | Loading ⇒ indicator | — | loading-W | — |
| DOC-013.2 | Empty day ⇒ empty state + working hours | — | empty+hours-W | — |
| DOC-013.3 | Failed load/save ⇒ error + retry, input retained, interactive | — | error-retain-W | — |
| DOC-013.neg | Failed save never clears form / partially persists | — | retained-W | no-partial-I |

### ADM

| Req | Acceptance criterion | U | W | I |
| --- | --- | --- | --- | --- |
| ADM-001.1 | Dashboard: today + 7d by-status, active counts, 50-recent privileged feed | metrics-U | dashboard-W | RPC-values-I |
| ADM-001.2 | Failing panel ⇒ isolated error + retry, rest usable | — | isolated-error-W | — |
| ADM-001.neg | Zero financials shown | — | absent-W | — |
| ADM-002.1 | Valid provision ⇒ active doctor + forced flag, listed | — | provision-W | provision-I |
| ADM-002.2 | Specialty change ⇒ snapshots kept, nothing cancelled | — | — | snapshot-retained-I |
| ADM-002.3 | Duplicate/invalid/short-temp ⇒ error, nothing changed | validator-U | error-W | rejected-I |
| ADM-002.neg | Duplicate email never double-creates | — | — | idempotent-reject-I |
| ADM-003.1 | New specialty (unique code + locale names) ⇒ selectable + in filter | — | catalogue-W | filter-appears-I |
| ADM-003.2 | In-use delete ⇒ blocked + reassignment direction | — | blocked-W | delete-blocked-I |
| ADM-003.3 | Deactivation ⇒ leaves filter, doctors retained + admin-visible | — | hidden-W | retained-I |
| ADM-003.neg | Duplicate codes rejected | — | — | unique-violation-I |
| ADM-004.1 | Valid on-behalf create + reason ⇒ scheduled, duration = slot, bypass audited | — | create-W | insert + audit-bypass-I |
| ADM-004.2 | Off-grid in-window ⇒ succeeds | grid-U | — | accepted-I |
| ADM-004.3 | Out-of-window/break/blocked/overlap/past ⇒ rejected, no write | guard-U | error-W | hard-limit-matrix-I |
| ADM-004.4 | Empty reason blocked | validator-U | validation-W | — |
| ADM-004.neg | Double-booking bypass impossible even for admin | — | — | exclusion-holds-I |
| ADM-005.1 | Admin cancel any non-terminal + reason ⇒ cancelled + freed + audited | — | cancel-W | transition-I |
| ADM-005.2 | Admin move + reason ⇒ same record, count+1, before/after + bypass audited; both see new time | — | move-W | same-record + visibility-I |
| ADM-005.3 | Terminal-as-cancel/move ⇒ rejected (ADM-008 path instead) | transition-U | rejected-W | denied-I |
| ADM-005.4 | Overlap target ⇒ conflict, rejected | — | conflict-W | exclusion-I |
| ADM-005.neg | Stale version fails (D-38) | version-U | conflict-W | race-I |
| ADM-006.1 | 45d-out in-window + reason ⇒ succeeds, horizon bypass flagged | — | — | bypass-audit-I |
| ADM-006.2 | Overlap ⇒ rejected, no write | — | conflict-W | exclusion-I |
| ADM-006.3 | No-window date ⇒ rejected w/ window-must-exist message | — | message-W | rejected-I |
| ADM-006.neg | Override audit lists bypassed; reasonless entries never exist | — | — | audit-scan-I |
| ADM-007.1 | Day calendar grouped department → start ASC | sort-U | calendar-W | grouping-I |
| ADM-007.2 | Doctor/dept/multi-status/range conjunction + chips + paginated totals | paging-U | filters-W | conjunction-I |
| ADM-007.neg | Notes never in clinic-wide views | — | — | absence-scan-I |
| ADM-008.1 | completed → scheduled + reason ⇒ succeeds + audit | transition-U | correct-W | transition-I |
| ADM-008.2 | cancelled → scheduled when taken ⇒ conflict rejected | — | conflict-W | exclusion-I |
| ADM-008.3 | no_show → completed/cancelled + reason ⇒ succeeds + audit | transition-U | — | transition-I |
| ADM-008.neg | Reasonless blocked; patient/doctor path absent | — | unoffered-W | denied-I |
| ADM-009.1 | Dialog shows count=5 + earliest date before change | — | dialog-W | count-query-I |
| ADM-009.2 | Confirm ⇒ sign-in/bookings refused, views exclude, retained for admins; reactivate reverses w/o touching appointments | — | — | deactivate/reactivate-cycle-I |
| ADM-009.3 | Last-admin deactivation ⇒ domain error, unchanged | — | error-W | guard-I |
| ADM-009.neg | Dismiss ⇒ no change | — | dismissed-W | unchanged-I |
| ADM-010.1 | Audit view: actor/role/action/entity/reason/ts DESC + filters + pagination; no edit control; direct mutation rejected | — | audit-W | mutation-rejected-I |
| ADM-010.2 | Tz change ⇒ next-query generation/display new zone, instants unchanged | tz-U | — | instants-stable-I |
| ADM-010.3 | Invalid settings (neg lead, zero horizon, page > 200) blocked | validator-U | validation-W | guard-I |
| ADM-010.4 | Duration-default change ⇒ only duration-less doctors affected | — | — | scoped-effect-I |
| ADM-010.neg | Any audit UPDATE/DELETE rejected, all roles | — | — | append-only-I |
| ADM-011.1 | Every admin payload/view/export: no notes field/placeholder/count | — | absent-W | payload-scan-I |
| ADM-011.2 | Admin notes write ⇒ rejected, unchanged | — | — | write-denied-I |
| ADM-011.neg | Reason-for-visit stays visible (not notes) | — | visible-W | field-present-I |
| ADM-012.1 | 1440×900 / 1024×768 / 390×844 × AR/EN: reachable, no overflow, RTL mirrored | — | responsive-W (viewports × locales) | — |
| ADM-012.2 | Light/dark/system legible, contrast | — | themed-W | — |
| ADM-012.neg | No admin action viewport-exclusive | — | coverage-W | — |

### SYS + NFR

| Req | Acceptance criterion | U | W | I |
| --- | --- | --- | --- | --- |
| SYS-001.1 | One Flutter project, all roles, no non-Supabase backend client | — | — | import-scan + review gate |
| SYS-001.2 | No FCM/email/map/payment call in any flow | — | — | call-scan-I |
| SYS-001.neg | Unapproved integration fails review | — | — | review gate |
| SYS-002.1 | Required platforms present, excluded absent | — | — | artifact-check |
| SYS-002.2 | Future patient/doctor web not structurally blocked | arch-review | — | — |
| SYS-003.1 | All shared state via Bloc/Cubit; repos behind interfaces + DI | arch-review | — | — |
| SYS-003.2 | Logic in testable units separable from widgets | arch-review | — | — |
| SYS-003.neg | Non-Bloc global state fails review | review gate | — | — |
| SYS-004.1 | Identical allow/deny via mobile/web/CLI/SQL-under-role | — | — | parity-matrix-I |
| SYS-004.2 | No client-side availability truth | code-scan | — | — |
| SYS-004.neg | Client-only rule fails review | review gate | — | — |
| SYS-005.1 | AR: full catalogue + RTL, no fallback | catalogue-U | RTL-W | — |
| SYS-005.2 | EN LTR | — | LTR-W | — |
| SYS-005.3 | Device default; persists per-device only | prefs-U | — | — |
| SYS-005.neg | No raw keys / mixed-direction clipping | catalogue-U | clipping-W | — |
| SYS-006.1 | 3 themes legible + persisted | — | themed-W | — |
| SYS-006.2 | 360/768/1024/1440 × locales: no overflow | — | responsive-W | — |
| SYS-006.neg | Theme never on account / sign-in-gated | — | — | account-scan-I |
| SYS-007.1 | Open/refresh re-reads server | — | re-read-W | query-count-I |
| SYS-007.2 | Failure ⇒ error + retry, never stale-as-current | — | error-W | network-cut-I |
| SYS-008.1 | Denied op ⇒ localized action-named error, no trace/SQL, data unchanged | — | denial-W | message-scan-I |
| SYS-008.2 | Unexpected ⇒ generic + correlation id, locally logged | — | generic-W | — |
| SYS-008.neg | No silent success-with-no-effect | — | — | effect-assertion-I |
| NFR-001 | 30-day slot render < 3 s mid-range/4G | — | — | timed-I |
| NFR-002 | Debounced keystrokes; empty ⇒ no request | debounce-U (fake clock) | search-W | — |
| NFR-003 | 360–1440px+ no overflow both locales | — | 4-widths × 2-locales-W | — |
| NFR-004 | Semantics labels active-locale; WCAG AA both themes | — | semantics + contrast-W | — |
| NFR-005 | 100% strings from ARB; zero raw keys | catalogue-completeness-U | RTL-W | — |
| NFR-006 | All screens legible system/light/dark | — | themed-W | — |
| NFR-007 | Offline distinct + retry; no stale-as-current | — | offline-W | network-cut-I |
| NFR-008 | Every privileged mutation ⇒ append-only audit row | — | — | per-mutation-I |
| NFR-009 | No account enumeration; DB-enforced authz + denials | — | — | negative-I battery |
| NFR-010 | Concurrent same-slot ⇒ one success; stale-version fails | — | — | concurrency-I |
| NFR-011 | UTC instants; clinic-zone gen/display; DST no-dup/no-drop | DST-fixtures-U | — | — |

---

## 7. Global rollback note

- **Code:** every phase ends on a tagged commit (`plan-001/w1…w5`). Rollback = `git revert`/reset to last
  green tag + `flutter pub get` + `flutter analyze`. Client rollbacks never touch user data.
- **Database:** migrations are additive-only during W1–W5 (new tables/constraints/triggers/RPCs; no column
  drops). Each migration ships with a tested `down` script. RLS/guard changes default-deny: rolling back a
  loosening restores a stricter rule (safe direction). Availability-template edits made during UAT are
  snapshotted per doctor and restorable; appointments are never auto-modified (D-21).
- **Releases:** mobile via staged rollout (halt + prior build); Web admin via hosting revision rollback,
  independent of mobile. No destructive data migration ships in the MVP window.
- **Worst case:** full return to pre-PLAN-001 = revert client to `main`, run all migration `down` scripts to
  baseline, confirm zero Admin seed rows remain only if no production users exist; otherwise keep schema and
  disable write paths via RLS (read-only mode) while replanning. Data (appointments/audit) is never deleted
  by any rollback.

## 8. Definition of Done for PLAN-001 (plan acceptance)

- [ ] Human approves this plan (Status → approved with date); D-46…D-51 gap dispositioned (amend spec or accept §0.1 handling)
- [ ] §2 schema/RLS + §3 architecture + §4 roadmap + §6 test map + §7 rollback all present
- [ ] Every SPEC requirement ID appears in §6 with at least one test tier incl. negatives/denials
- [ ] No Flutter code, dependency, schema, or migration executed under this plan file itself
