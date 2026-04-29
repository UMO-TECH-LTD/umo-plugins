---
name: implementation-routing
description: Use when moving from plan to implementation or deciding whether to hand off to a specialist plugin.
---

# Implementation Routing

Use the smallest capable workflow.

## Route

- Core lifecycle, planning, memory, docs, quality, review, closeout: use `umo-agentic-core`.
- Language-specific evidence and commands: use the active language plugin.
- Platform-specific evidence: use the active platform plugin.
- Domain or regulatory policy: use the active domain plugin.
- Functional workflow, such as service audit: use the functional plugin after core is active.
- Repo paths, names, aliases, exceptions: use the repo binding plugin.

If two plugins appear to own the same surface, stop and resolve ownership before
continuing.
