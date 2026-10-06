# AGENTS.md — Clinic Appointment Management System

## What this is
Flutter (Dart) clinic appointment app for 3 roles: Patient, Doctor, Clinic Administrator.
Source of truth for scope: `intent/clinic-appointment-system.md` (Status: approved).

## SDLC gate (binding)
Workflow: Intent → Spec → Plan → Implementation → Testing/Review.
- Intent is approved. No `spec/` or `plan/` exists yet → **do not write Flutter feature code, do not add dependencies, do not create DB schema/migrations.**
- Never invent requirements, tables, fields, relationships, auth methods, appointment statuses, or cancellation/rescheduling rules. Open questions are listed in the intent file — clarify, don't assume.
- Intent interview: ask one question at a time, keep new intents `Status: draft`, never mark approved. Skill: `.agents/skills/intent-interview/SKILL.md`.

## Current repo state (verified 2026-10-04)
- Vanilla `flutter create` counter template: `lib/main.dart` is the demo counter, `test/widget_test.dart` tests it.
- `pubspec.yaml` has only `cupertino_icons` + `flutter_test`/`flutter_lints`. `flutter_bloc`, `supabase_flutter`, localization, theming deps are **not yet added** — adding them is implementation, blocked until spec+plan approval.
- `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`. Verify with `flutter analyze`.
- Targets: single codebase, Android + iOS (`android/`, `ios/` present). Web exists as scaffold only; per approved intent Web is primary for Admins (optionally Patients/Doctors) — pending spec.
- Flutter is **not on PATH** in this environment — locate the SDK before running any command.

## Commands (run in `clinic_appointment_system/`)
- `flutter pub get` — install deps (after SDK available)
- `flutter analyze` — lint/typecheck (flutter_lints)
- `flutter test` — unit/widget tests (keep: unit = business logic, widget = key UI, integration where approved)
- `flutter run` — dev run; `flutter build apk` / `flutter build ipa` — release builds

## Constraints for future work (from approved intent)
- State: Bloc/Cubit only. Architecture: Clean Architecture + Repository Pattern + DI, SOLID, testable business logic.
- Backend only via Supabase Flutter SDK (Auth, PostgreSQL, Storage only if approved requirements need files). Schema derives strictly from approved spec.
- Roles: Patient (own data only), Doctor (own availability/appointments + relevant patient info), Admin (broader clinic management). Enforce via Supabase Auth + RLS per approved spec.
- UI (post-spec): Arabic/English localization, light/dark themes, responsive layout.
