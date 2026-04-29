---
name: umo-agent-setup
description: Adapts a repository to use UMO Agentic Core. Use when setting up, onboarding, or migrating a repo to this plugin, or when the user asks to create repo bindings, AGENTS.md, local templates, adoption mode, or plugin-version reporting.
---

# UMO Agent Setup

Use this skill to adapt a repository after `umo-agentic-core` is installed. The
plugin provides Cursor-supported rules, skills, and commands. Repo-local setup
creates the files that Cursor plugins do not install as components, such as
`AGENTS.md` and project-specific templates.

## Boundaries

Do not copy core lifecycle rules into the repo. Repo setup may only bind:

- local paths, service names, and terminology;
- exact quality commands or aliases;
- memory namespace defaults;
- adoption mode;
- approved exceptions;
- local doc/template locations.

Core still owns lifecycle, planning, beads, memory workflow, docs lifecycle,
quality evidence, review, closeout, adoption modes, and composition.

## Setup Workflow

1. Inspect the repo root and existing guidance:
   - `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/`, `.cursor/skills/`;
   - package/build files and Makefiles;
   - docs module/index files if present.
2. Determine current adoption mode: `observe`, `assist`, `evidence`, or
   `enforced`. Default new repos to `observe`.
3. Create or update `AGENTS.md` as a thin binding file.
4. Create a repo-local binding rule only when paths or commands cannot be
   inferred from code.
5. Create repo-local templates only if the repo lacks suitable proposal, ADR,
   plan, review, or verification templates.
6. Run available markdown/lint checks and report what could not be verified.

## AGENTS.md Binding Template

Use this shape and keep it short:

```markdown
# AGENTS.md

This repo uses `umo-agentic-core`.

## Repo Bindings

- Adoption mode: `observe`
- Memory namespace: `<namespace>`
- Planning substrate: `beads` when `bd` is available
- Quality command: `<command or "see package/Makefile">`
- Docs root: `<docs path>`

## Local Guidance

Only include local paths, service names, command aliases, environment notes, and
approved exceptions. Do not duplicate core lifecycle, planning, memory, quality,
review, or closeout rules.
```

## Local Template Minimums

When creating templates, include:

- status;
- active plugin versions;
- related module or owner;
- acceptance criteria or evidence section;
- closeout/evidence section where relevant.

Example proposal header:

```markdown
# Proposal: <Title>

> Status: draft
> Active plugins: umo-agentic-core@<version>
> Related module: <module or repo area>

## Summary
```

## Verification

Before reporting completion:

- confirm unsupported plugin components were not added to the plugin package;
- run repo-available markdown or lint checks;
- list files created or updated;
- report adoption mode and active plugin version if known.
