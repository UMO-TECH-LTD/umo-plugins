---
description: Run the quality loop for the current package or repository. Fix errors before moving on.
---

Find the nearest relevant project root from the files most recently edited or discussed.
Prefer the closest directory containing `package.json`, `tsconfig.json`, or the repo root.

Run the quality loop from that directory:

```bash
bunx @biomejs/biome check --write .
tsc --noEmit
bun test
```

If the repo does not use Bun, use the equivalent package manager or test runner already
configured in the project. The principle matters more than the exact tool.

Fix every reported error before moving on. Re-run until all applicable checks pass clean.

Report:

- which directory was used
- which checks were run
- pass/fail per check
- notable fixes required to get back to green
