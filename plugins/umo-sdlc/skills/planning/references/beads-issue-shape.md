<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-05

# Beads Issue Shape

Beads are the executable issue graph for UMO Planning. Keep durable research,
proposals, ADRs, specs, and postmortems in docs. Use Beads to track work,
dependencies, provenance, current state, and evidence.

## Epic

Use an epic for a coherent deliverable from a proposal, spec, incident
follow-up, or product intent.

Include:

- source links to proposal/spec/incident/research;
- outcome statement;
- scope and non-goals;
- child task list;
- acceptance criteria for epic completion;
- dependency summary;
- risk and human decision points;
- suggested execution order and parallelizable groups.

## Task

Use a task for one focused implementation, docs, test, or cleanup unit.

Include:

- specific outcome;
- starting context and relevant files or docs;
- acceptance criteria;
- verification plan;
- dependencies;
- expected docs updates;
- what not to change.

## Spike

Use a spike when the next action is learning, not implementation.

Include:

- research question;
- timebox or stop condition;
- evidence to collect;
- expected output;
- decision the spike unlocks.

## Decision

Use a `decision` bead when human judgment is required before implementation can
safely proceed. UMO uses the latest Beads version, where `--type=decision` is
available.

Include:

- decision needed;
- options;
- recommendation;
- risks;
- owner or approving role;
- work unblocked by the decision.

## Discovered Work

File discovered work instead of hiding it in summaries.

```bash
bd create --title="<found work>" --description="<what was found, evidence, recommended action>" --type=task --priority=2 --deps discovered-from:<source-id> --json
```

Use:

- `bug` for broken behavior;
- `chore` for maintenance and technical debt;
- `decision` for human approval before implementation can proceed;
- `task` for implementation, docs, tests, and process work;
- `validates` dependencies for tests or monitors proving another bead;
- `caused-by` dependencies for root-cause follow-ups.

## Comments

Descriptions are stable context. Comments are timeline events.

Add a comment when:

- the user makes a decision that changes scope or priority;
- implementation discovers a blocker or follow-up;
- a spike concludes with evidence and recommendation;
- a dependency or owner changes;
- verification evidence is collected.

Prefer short structured comments:

```text
Decision: <what changed>
Evidence: <link, command, or observed fact>
Next: <what this unlocks or blocks>
```

Do not paste full chat transcripts into comments.

## Close Reasons

Close with evidence, not generic "done".

Examples:

- `Completed: acceptance criteria met; tests and docs updated.`
- `Superseded: replaced by <id> after scope split.`
- `Rejected: not doing after proposal review; see <proposal>.`
- `Deferred: moved to backlog because <reason>.`

## Command Reference

Prefer JSON for agent-readable workflows:

```bash
bd ready --json
bd show <id> --json
bd create --title="..." --description="..." --type=task --priority=2 --json
bd update <id> --claim --json
bd close <id> --reason="Completed: ..." --json
```

Check graph quality:

```bash
bd dep tree <epic-id>
bd ready --json
bd blocked --json
```

