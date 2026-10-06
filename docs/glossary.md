# Glossary — Clinic Appointment Management System

Agreed vocabulary for intents, specs, and plans. Do not add schema, statuses, or rules here — those belong in the approved spec.

- **Patient**: App user who searches doctors, views profiles and available slots, and books/views/cancels/reschedules their own appointments.
- **Doctor**: App user who views assigned appointments with patient and time details, manages own availability/schedule, and updates appointment status.
- **Clinic Administrator**: App user with broader access to manage doctors, patients, schedules, and appointments and oversee clinic operations.
- **Doctor profile**: Information shown to patients when choosing a doctor (exact fields defined by spec, not assumed).
- **Available slot**: A date/time a doctor is bookable (booking and availability rules defined by spec, not assumed).
- **Appointment**: A booked meeting between a patient and a doctor at an agreed date/time (lifecycle states defined by spec, not assumed).
- **Role-based access**: Each role sees and manages only the features and data relevant to its responsibilities, enforced via Supabase Auth (exact policies per approved spec).
