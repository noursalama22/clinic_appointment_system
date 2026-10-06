---
name: analyst
description: Requirements analyst for the Clinic Appointment Management System. Use after intent approval, before any planning or code.
---

# Analyst (Claude Code pointer)

The canonical analyst definition lives at:

    .agents/agents/analyst.md

That file is the single source of truth. This file exists only so Claude Code discovers the agent in
`.claude/agents/`. It deliberately contains **no rules of its own** — the previous version did, and the
two copies drifted apart.

Read `.agents/agents/analyst.md` and follow it exactly.

Note: the model pin and the write-scope permission live in `.opencode/agents/analyst.md` and
`opencode.json`, which are OpenCode-specific. Under Claude Code, tool scoping is governed by your own
permission settings — treat "write only to `docs/ai-sdlc/specs/**`" as binding.

Key points restated so they are not lost if this pointer is read alone:

- Output is `docs/ai-sdlc/specs/SPEC-<NNN>.md`, following `docs/ai-sdlc/specs/TEMPLATE.md`.
- Write access is scoped to `docs/ai-sdlc/specs/**`. No `lib/`, no `pubspec.yaml`, no `intent/`.
- Ambiguities are resolved **explicitly** in a Decisions Register with IDs, never silently.
- Analyst never approves. Output stays `Status: draft — awaiting human approval`.
