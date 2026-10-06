# Intent: Clinic Appointment Management System

## Problem and Opportunity
Inefficiency, manual overhead, and scheduling conflicts from traditional clinic booking methods (such as phone calls or walk-ins).

## Users and Stakeholders
1. Patients: need an effortless, digital way to discover doctors, view real-time available time slots, and schedule or manage appointments anytime.
2. Doctors: need a structured dashboard to manage availability, view daily schedules, and track appointment statuses efficiently.
3. Clinic Administrators: require full oversight to manage users (doctors and patients), control clinic schedules, and handle adjustments or operational conflicts centrally.

## Core Value Proposition
Replace phone/walk-in booking with digital discovery, real-time slots, and centralized schedule oversight for patients, doctors, and admins.

## Functional Scope
### Patient Workflow (as described)
- Open app and sign up / log in (author proposed Email/Password — pending spec; auth methods remain open per approved intent).
- Home: search doctors by name or filter by specialty.
- Open doctor profile (qualifications + calendar of available slots) and select date/time.
- Optionally enter brief reason for visit and confirm booking.
- System reserves slot and creates appointment (author proposed status 'Scheduled' — pending spec; statuses remain open).
- From profile/dashboard: view upcoming/past appointments, view details, request cancel/reschedule (author noted "if within allowed timeframe" — rules pending spec).

### Doctor Workflow (as described)
- Sign in with credentials provisioned by Clinic Administrator (author proposed — auth method pending spec).
- View daily/weekly schedule dashboard of booked appointments.
- Define/adjust working hours, break times, slot durations (e.g. 30 mins) to reflect open slots (proposed — rules pending spec).
- Open appointment to see relevant patient context for consultation (exact fields pending spec).
- Update appointment progress (author proposed In-Progress, Completed, No-Show, Cancelled — statuses pending spec).

### Clinic Administrator Workflow (as described)
- Log in with elevated admin credentials (proposed — auth pending spec).
- Provision/manage doctor accounts (profiles, specialties) and view/deactivate patient accounts if necessary (proposed — policies pending spec).
- Full visibility over clinic schedules, working hours, and calendars across departments.
- Manually create/reschedule/cancel on behalf of patients/doctors for walk-ins, emergencies, or conflicts (override rules pending spec).
- Track clinic activity, appointment statuses, and historical logs (exact metrics pending spec).

### MVP Scope (as described, pending spec/plan approval)
- Secure role-based auth (Patient, Doctor, Admin via Supabase Auth).
- Doctor search & specialty filtering.
- Real-time slot viewing, booking, and schedule management.
- Lifecycle status tracking (author proposed Scheduled, In-Progress, Completed, Cancelled; plus No-Show earlier — to resolve in spec).
- Admin provisioning & schedule override control.
- Multi-language Localization in scope (Arabic/English per AGENTS.md).
- Timeline target: 5 weeks for MVP delivery + testing; Budget: controlled, Supabase tier + Flutter OSS (feasibility pending plan).

### Future Phases (out-of-scope for MVP, as described)
- Online in-app payment gateways (MVP uses pay-at-clinic cash/in-person).
- Video / telemedicine consultations.
- Advanced financial & operational analytics.

## Role-Based Access Notes
Patient owns own data only; Doctor owns availability/appointments + relevant patient info; Admin has broader clinic management. Proposed provisioning/override/deactivation flows deferred to spec for RLS policies.

## Platform and Technical Notes
Only constraints already approved in AGENTS.md; nothing new added here.
Author proposes for spec consideration (pending approval):
- Single Flutter codebase for all clients.
- MVP: Mobile (Android & iOS) primary for Patients/Doctors; Web (Flutter Web) primary for Admins, optionally Patients/Doctors — note: web for admin differs from approved intent where web was undecided.
- Backend: Supabase (Auth, PostgreSQL, Storage) — Storage only if spec confirms file needs.
- Architecture: Clean Architecture + Bloc/Cubit + Repository Pattern (aligns with AGENTS.md).

## Open Questions
- Former intent/clinic-appointment-management.md superseded and deleted 2026-10-04; clinic-appointment-system.md is primary source of truth.
- Auth methods (Email/Password, provisioned credentials, elevated admin), session JWT/refresh/logout remain pending spec.
- Appointment statuses and lifecycle (author proposed Scheduled, In-Progress, Completed, Cancelled in MVP, plus No-Show earlier — inconsistency to resolve in spec).
- Cancellation/rescheduling/timeframe rules, override rules, and double-booking prevention remain pending spec.
- Web-for-Admin decision pending spec (approved intent left web undecided).
- Storage need, FCM push, Maps, email provider, and future Stripe gateway are beyond Supabase-only constraint — need spec approval.
- Timeline 5 weeks and controlled Supabase-tier budget are author targets — feasibility pending plan.
- Resolved per author 2026-10-04: Multi-language Localization is in scope for MVP (aligns with AGENTS.md Arabic/English).
- Notifications policy, security policies beyond role-level, and analytics/telemedicine scope pending spec.

## Intent Summary
Digital booking to replace phone/walk-in inefficiency for Patients, Doctors, and Admins with search, real-time slots, and central oversight. MVP targets 5-week delivery covering auth, booking lifecycle, admin control, and Arabic/English localization; payments online, video, and advanced analytics deferred. All statuses, rules, and integrations remain proposals pending spec/plan approval.

Status: approved — human-approved 2026-10-05
