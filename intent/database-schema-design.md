# Intent: Define the clinic appointment database schema

## Problem and Opportunity
The Clinic Appointment Management System needs a clearly defined Supabase database design before database migrations or Flutter features are written. Defining the schema and access boundaries first should provide a reliable foundation for authentication, clinic operations, doctor schedules, and appointment booking.

## Users and Stakeholders
- Patients need profiles and access to their own appointments.
- Doctors need doctor profiles, schedule management, and access to appointments assigned to them.
- Clinic administrators need clinic-scoped access to manage clinic operations.
- The system needs to create a profile for each Supabase Auth user.

## Core Value Proposition
Agree on the database entities, appointment lifecycle, booking-conflict behavior, and role-based access before implementing the Supabase database.

## Functional Scope
- Use Supabase Auth as the authentication source and maintain a one-to-one relationship between an Auth user and a public profile.
- Support patient, doctor, and admin roles. New signups receive the patient role; a trusted admin or service process assigns doctor and admin roles.
- Define clinic data for clinic scoping.
- Define doctor data, including specialization, clinic association, and bio, along with doctor working-hours data.
- Define appointments with patient, doctor, clinic, date, time range, status, and timestamps.
- Use the statuses pending, confirmed, cancelled, and completed. Allow pending to transition to confirmed or cancelled, and confirmed to transition to cancelled or completed. Cancelled and completed are final.
- Prevent overlapping appointments for the same doctor. Cancelled appointments no longer reserve their time slot.
- Define row-level access so patients manage their own profiles and appointments, doctors access and update assigned appointments and manage their schedules, and admins operate within their clinic scope.
- Organize the eventual database implementation into sequential migrations for initialization, triggers, booking-conflict constraints, and RLS.

## Role-Based Access Notes
Supabase Auth is the identity source. Profiles are linked one-to-one to Auth users. Patients are limited to their own data, doctors to their assigned appointments and schedules, and administrators to their clinic scope. The exact permitted fields and operations for each role must be defined in the database spec.

## Platform and Technical Notes
Use Supabase Auth and PostgreSQL through the existing project constraints. This intent defines requirements only; schema details and migrations belong to the approved database spec and plan.

## Open Questions
- Which profile fields are required, and which profile fields may each role update?
- What are the exact working-hours fields and rules, including recurring days, date-specific exceptions, time zones, and effective dates?
- Which appointment fields may patients, doctors, and admins create or update?
- Should administrators be allowed to manage all records within their clinic, or only specific operations?
- How should doctor profiles and working hours be created and maintained by trusted administrators?
- What additional validation is required to ensure an appointment matches a doctor's working hours?
- What should happen when an Auth user is deleted or deactivated?
- Is a clinic record already provisioned before these migrations, or should its creation be part of the database setup?

## Intent Summary
Define a Supabase database specification for profiles, clinics, doctors, working hours, and appointments with role-based access and overlap prevention. The agreed requirements include patient-default signup roles, clinic-scoped admin access, and explicit appointment status transitions; exact fields and remaining operational rules are to be resolved in the spec.

Status: draft
