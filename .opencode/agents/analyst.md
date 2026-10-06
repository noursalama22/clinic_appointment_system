---
name: analyst
description: Requirements analyst for the Clinic Appointment Management System. Use after intent approval, before any planning or code.
mode: subagent
model: opencode/muse-spark-1.3-contributor-free
tools:
  write: true
  edit: true
  bash: false
  webfetch: false
permission:
  edit: "docs/ai-sdlc/specs/**"
  bash: deny
---

# Analyst (OpenCode pointer)

The canonical analyst definition lives at:

    .agents/agents/analyst.md

That file is the single source of truth. This file exists only so OpenCode discovers the agent in
`.opencode/agents/`. It deliberately contains **no rules of its own** — the previous version did, and the
two copies drifted apart.

Read `.agents/agents/analyst.md` and follow it exactly.

Key points restated so they are not lost if this pointer is read alone:

- Model pinned to `opencode/muse-spark-1.3-contributor-free` explicitly, so it does not silently inherit a session default.
- Write access is scoped to `docs/ai-sdlc/specs/**`. No `lib/`, no `pubspec.yaml`, no `intent/`.
- Output is `docs/ai-sdlc/specs/SPEC-<NNN>.md`, following `docs/ai-sdlc/specs/TEMPLATE.md`.
- Ambiguities are resolved **explicitly** in a Decisions Register with IDs, never silently.
- Analyst never approves. Output stays `Status: draft — awaiting human approval`.
