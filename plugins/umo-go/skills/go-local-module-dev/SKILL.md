---
name: go-local-module-dev
description: Build a Go service against an unreleased local platform module (proto-api/gen/go, devkit/common) through go.work, never through a replace directive in go.mod. Covers the workspace recipe on host and in Docker Compose, the go mod tidy / go.sum trap, pinning a real tag once upstream releases, and the MR ordering when a change spans a platform module and a consuming service. Use when editing go.mod, wiring a local sibling checkout, waiting on an unmerged proto-api or devkit MR, or debugging "missing go.sum entry" and "ambiguous import" build failures.
---

# Local platform modules: `go.work`, not `go.mod replace`

A service needs an **unreleased** change from a sibling platform repo
(`proto-api/gen/go`, `devkit/common`) reasonably often — the proto MR is open,
the tag is not cut yet, and the code has to compile now. Resolve that with a
workspace file, never by editing the module graph.

## Rule

**Never add a `replace` directive for a platform module to a service's `go.mod`.**
`go.mod` is a shipped artifact: it is committed, reviewed, consumed by CI, and
baked into the production image. A host-relative path like
`../../../proto-api/gen/go` exists only on the machine that wrote it — in the
build container and in CI that directory is absent, so the build fails or, worse,
silently resolves to something else.

**Use `go.work` instead.** Repos that follow this workflow gitignore `**/go.work`
repo-wide, so the override is local by construction and cannot leak into an MR.
Check the repo's `.gitignore` first; if the pattern is missing, add it before
creating the workspace.

## Recipe — host

From the service directory:

```bash
cd services/<service>
go work init .
go work use ../../../proto-api/gen/go        # path to the local sibling checkout
```

Resolve the sibling path from the repo's own convention (in `products/saas`:
`REPOS_ROOT` in `services/.secret.env`) — do not hardcode an absolute path, and
do not guess the layout.

**Do not run `go mod tidy` while the workspace is active.** With `go.work` in
place the platform module resolves from the local checkout, so `tidy` sees no
need for its checksums and strips them from `go.sum`. Everything still builds on
your machine; CI, which has no workspace, fails the Docker build with
`missing go.sum entry for module providing package …/proto-api/gen/go/…`. If it
already happened, `GOWORK=off go mod tidy` puts the entries back.

While a `go.work` is in play, **drop `GOWORK=off`** from your build/test/lint
commands — that flag exists to reproduce CI (released versions only) and will
deliberately ignore the workspace. Run the `GOWORK=off` variant before opening
the MR: it is the honest check that `go.mod` stands on its own.

## Recipe — Docker Compose

The container gets the same treatment: the sibling repo is bind-mounted and the
entrypoint writes a `go.work` at boot (see `local-entrypoint.sh` in a service
that already does this). Mounts belong in the Compose file under the repo's
sibling-root variable; `go.work` references the **in-container** path, never a
host path. Mount each module at the path the entrypoint expects, e.g.

```yaml
volumes:
  - ${REPOS_ROOT}/go-devkit:/gowork/platform/devkit:ro
  - ${REPOS_ROOT}/proto-api:/gowork/platform/proto-api:ro
```

Prefer a plain `use (...)` block. A blanket `replace` inside `go.work` is only
needed to override a `replace` already present in `go.mod` — which this skill
removes, so the need disappears with it.

### `ambiguous import` after enabling the workspace

Adding unpinned local modules to a workspace **disables module-graph pruning**.
A transitive dependency that MVS would normally prune can then win selection —
the classic case is an old pre-split `google.golang.org/genproto` pulled in by
`github.com/cockroachdb/errors`, which still physically contains packages that
now live in `google.golang.org/genproto/googleapis/{rpc,api}`:

```
ambiguous import: found package google.golang.org/genproto/googleapis/rpc/status in multiple modules
```

Diagnose with `go mod graph | grep <offending-module>` **inside the build
environment with the workspace active** to find who still requires the old
module. The fix is a `replace` in the service's `go.mod` pinning that module
forward to a release that no longer ships the moved packages — for the genproto
case, `replace google.golang.org/genproto => google.golang.org/genproto
v0.0.0-20260414002931-afd174a4e478` (this is a *third-party* module pinned to a
published version; the prohibition above is on local-path replaces of platform
modules). Adding the module to the workspace `use` block does **not** resolve
the ambiguity on its own. Re-tidy with `GOWORK=off` afterwards — tidying with a
workspace active drags in unrelated checksums from the other workspace modules'
tool dependencies.

It is a workspace-only failure: the same build passes with `GOWORK=off`, which
is why it surfaces in `make up` and never in CI. Worked example:
`services/accounting-ledger` in `products/saas` (`dragonboat`/`pebble` pull
`github.com/cockroachdb/errors`, the only requirer of the pre-split module).

## Ordering the two MRs

A `go.work` unblocks the *code*, not the *merge*. The two MRs stay in a fixed
order, and the consuming one carries the blocker:

1. **Platform MR first.** Open the `proto-api` / `devkit` MR as soon as the
   contract stops moving — review plus `semantic-release` is the long pole, and
   nothing downstream can pin a version that does not exist yet.
2. **Consuming MR opens whenever it is ready, as a Draft.** Mark it `Draft:` and
   record the dependency in GitLab: **Merge request dependencies → blocked by**
   the platform MR, plus a link in the description. The Draft flag is what
   actually prevents a merge; the dependency is what tells a reviewer *why* it is
   parked. Do not wait for the platform MR to merge before opening it —
   reviewers need the consumer side to judge the contract.
3. **Un-draft only after the tag exists.** Platform MR merged →
   `semantic-release` cut a tag → pin it and drop the workspace (below) → both
   `GOWORK=off` gates green → push → remove `Draft:`.

## Getting back to released versions

A `go.work` is a dev loop, not a destination. As soon as the upstream MR merges
and `semantic-release` cuts a tag:

```bash
cd services/<service>
go get gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go@v<NEW_TAG>
go mod tidy
rm go.work go.work.sum
GOWORK=off go build ./... && GOWORK=off go test ./...
```

Never pin a **pseudo-version** (`v1.215.1-0.20260717143543-c185d73b6a23`) as the
"temporary" answer either. Pseudo-versions are derived from a commit SHA and
resolve only while that commit is reachable through the module proxy, which
caches tagged releases — so it works on your machine and fails in CI and in the
cluster.

## Checklist

- [ ] No `replace` for `gitlab.com/umo-tech-ltd-group/platform/*` in any committed `go.mod`.
- [ ] Local override lives in `go.work`, gitignored, sibling path derived from the repo's convention — not hardcoded.
- [ ] `go.sum` still carries the platform module's checksums — `go mod tidy` under a workspace removes them.
- [ ] `GOWORK=off go build ./... && GOWORK=off go test ./...` passes before the MR.
- [ ] Platform MR opened first; consuming MR is `Draft:` and marked *blocked by* it until the tag is cut.
- [ ] Version bumped to a real tag (not a pseudo-version) once upstream releases; `go.work` deleted.
