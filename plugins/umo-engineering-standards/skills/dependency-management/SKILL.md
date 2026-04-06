---
name: dependency-management
description: Change dependencies safely with exact versions, scoped upgrades, and verification gates.
---

# Dependency Management

Load when adding, upgrading, or removing dependencies. The objective is deterministic
changes with clear blast radius and explicit verification.

## Version policy

- Use exact versions in dependency manifests.
- Do not introduce semver ranges unless the repository already has a strong reason for them.
- Upgrade only the requested package or scope unless a broader update is explicitly asked for.

## Upgrade workflow

```text
1. Identify the exact package and target scope
2. Update manifest entries
3. Refresh the lockfile
4. Refactor code for API or type changes
5. Verify the affected package or repository
```

## Verification gates

Run the project-standard checks after dependency changes. In a TypeScript repository,
that usually means:

```bash
bunx @biomejs/biome check --write .
tsc --noEmit
bun test
```

Add build or integration checks when the dependency affects bundling, code generation,
runtime services, or native modules.

## Safety rules

- Do not silently downgrade packages.
- Do not do broad dependency churn when the request is scoped.
- Note any required code refactors caused by the upgrade.
- If package tooling fails, report the failure mode and recover with the safest available path.
