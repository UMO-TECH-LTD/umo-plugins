---
name: docs-lifecycle
description: Use when creating, updating, promoting, or checking docs.
---

# Docs Lifecycle

Docs are deliverables when behavior changes.

## Flow

1. Check the doc status and trust level.
2. Prefer foundation, product, system, implementation, then module docs over proposals.
3. Update affected docs with the code or workflow change.
4. Promote stable decisions into the correct tier.
5. Archive or supersede stale proposals instead of leaving duplicate sources of truth.
6. Run a staleness or cross-reference check when the repo provides one.

If a functional plugin generates a report, the report must include active plugin
versions and any source docs it relied on.
