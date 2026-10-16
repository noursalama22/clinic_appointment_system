# AGENTS.md — Clinic Appointment Management System

## Project
- Flutter (Dart) clinic appointment app for Patients, Doctors, and Clinic Administrators.
- Current status: **Phase 1 complete; Phase 2 — Auth & Profiles active.**
- Follow the approved implementation plan in `docs/ai-sdlc/plans/PLAN-001.md` strictly. Do not invent, guess, or renumber plan IDs (for example, do not refer to a made-up “PLAN 5”). Refer only to plan files and IDs that actually exist.
- Do not add requirements, fields, tables, roles, workflows, or behavior not authorized by PLAN-001 and the approved specifications it references. If they conflict or leave a decision open, stop and ask the user before implementing.

## Mandatory implementation workflow
1. Break each requested task into small, atomic sub-tasks. Each sub-task must have a clear, independently verifiable outcome.
2. Implement and validate only the current sub-task. Keep changes limited to its scope.
3. Stop after each sub-task and require the user to create a Git commit for it. Do not create commits yourself.
4. Do not start the next sub-task until the user confirms that the current sub-task has been committed.
5. Follow PLAN-001's phase order, acceptance criteria, architecture, and rollback guidance. Do not implement later-phase work early.
6. Run the smallest relevant tests and checks for each sub-task before asking the user to commit. Report any unavailable validation clearly.

## Architecture and project constraints
- State management: Bloc/Cubit only. Follow the Clean Architecture and Repository Pattern structure specified in PLAN-001; keep business logic testable and use the approved dependency-injection approach.
- Backend: Supabase Flutter SDK and the approved Supabase services only. Database schema, migrations, RLS, and seed data must match the approved plan/specification; never infer or invent database requirements.
- Enforce role and tenant boundaries in the backend, including Supabase RLS. Never trust client-side role or authorization checks as the security boundary.
- Follow PLAN-001 for supported platforms, localization, theming, responsive behavior, and feature scope. Do not add dependencies or integrations outside its approved scope without user approval and a plan amendment.

## Validation
- Run the repository's relevant commands from the project root, such as `flutter analyze` and targeted `flutter test` tests, when the Flutter SDK is available.
- If a required tool or environment is unavailable, state that limitation and do not claim the check passed.
