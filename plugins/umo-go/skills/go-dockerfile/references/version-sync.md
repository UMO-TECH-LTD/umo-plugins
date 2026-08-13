# Go Dockerfile Version Sync & Private Module Auth

When modifying a Go service's `go.mod` or `Dockerfile`, the Go version in the Dockerfile `FROM` line **must match** the version in `go.mod`.

## Why

Docker builds fail with `go.mod requires go >= X.Y.Z (running go A.B.C; GOTOOLCHAIN=local)` when the builder image uses an older Go than what `go.mod` declares. This is a hard failure at the `go mod download` step.

Image Scan also fails when the **compiled binary** embeds an outdated Go stdlib (Trivy `gobinary` — e.g. CVE-2026-39822 / CVE-2026-42505). Distroless migrations must bump to the latest patch on the service's minor **in the same MR** — see `distroless-dockerfile-design` skill → "Go patch bump — mandatory".

Common triggers:
- Running `go mod tidy` pulls in a dependency that bumps the `go` directive
- Manually updating `go.mod` to a newer Go version
- Adding a dependency built with a newer Go version (e.g., proto-api)
- Migrating a Go service to distroless (proactive stdlib CVE gate)

## Rule

### After any `go.mod` change

1. Read the `go` directive from `go.mod` (e.g., `go 1.25.5`)
2. Check **all** Dockerfiles in the service directory (including `deploy/`, `deployment/`, `deploy/local/`)
3. Verify every `FROM ... golang:X.Y.Z` line uses **the same version** as `go.mod`
4. If mismatched, update the Dockerfile

### After any Dockerfile change

1. Verify the `golang:` tag matches the `go` directive in the service's `go.mod`

### Version format

Use **exact patch versions**, not floating tags:

```dockerfile
# CORRECT - exact match with go.mod
FROM public.ecr.aws/docker/library/golang:1.25.5 AS builder

# WRONG - floating minor, may not satisfy go.mod's patch requirement
FROM public.ecr.aws/docker/library/golang:1.25 AS builder

# WRONG - alpine variant still needs exact version
FROM public.ecr.aws/docker/library/golang:1.25-alpine AS builder

# CORRECT - alpine with exact version
FROM public.ecr.aws/docker/library/golang:1.25.5-alpine AS builder
```

### Multi-Dockerfile services

Some services have multiple Dockerfiles (CI, local dev, deploy). **All must be updated:**

```
services/my-service/
├── Dockerfile              # Main build
├── deploy/Dockerfile       # Deploy variant
└── deploy/local/Dockerfile # Local dev
```

## GitLab Private Module Authentication

Go services that depend on private GitLab modules (`gitlab.com/*`) **must** configure authentication in the builder stage before `go mod download`. Without this, builds fail.

### Why two mechanisms are required

Go resolves private module locations using **two separate auth paths**:

| Mechanism | Authenticates | Used for |
|-----------|--------------|----------|
| `~/.netrc` | HTTPS requests (curl-style) | Go's HTTP `?go-get=1` VCS discovery — finds the repo root for a module path |
| `git config url.insteadOf` | Git protocol operations | `git clone`, `git ls-remote`, `git fetch` |

**Both are required** because Go first makes an HTTPS request to discover the VCS root (uses `.netrc`), then performs git operations to fetch the module (uses `git config`).

**What breaks without `.netrc`:** When a module uses a canonical path **without** the `.git` suffix (e.g. `gitlab.com/umo-tech-ltd-group/platform/devkit/common`), Go sends an unauthenticated `?go-get=1` request. The private GitLab repo returns 404, so Go falls back to guessing repo boundaries by walking up parent paths via `git ls-remote` — e.g. tries `platform.git`, which is a group not a repo, and fails with `fatal: repository not found`.

**`.git` suffix paths** (e.g. `devkit.git/common`) skip the HTTP discovery and jump straight to git — so `git config` alone works. But you cannot control transitive dependencies, which may use canonical paths. **Always include both mechanisms.**

### Required auth block

Insert this **after** `FROM ... AS builder` and **before** `COPY go.mod go.sum` / `RUN go mod download`. The ARG name (`GITLAB_TOKEN` or `GITLAB_PAT`) must match what your CI job passes as a build arg.

```dockerfile
# ARG name must match what CI passes — GITLAB_TOKEN or GITLAB_PAT depending on the service
ARG GITLAB_USER=gitlab-ci-token
ARG GITLAB_TOKEN

# Both mechanisms required for full private module coverage:
# 1. .netrc — authenticates Go's HTTP ?go-get=1 VCS discovery (canonical paths without .git suffix)
# 2. git config url.insteadOf — authenticates git clone/ls-remote operations
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    ENCODED_USER=$(echo "${GITLAB_USER}" | sed 's/@/%40/g') && \
    echo "machine gitlab.com login ${GITLAB_USER} password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc && \
    git config --global url."https://${ENCODED_USER}:${GITLAB_TOKEN}@gitlab.com/umo-tech-ltd-group/".insteadOf "https://gitlab.com/umo-tech-ltd-group/"; \
    fi

ENV GOPRIVATE=gitlab.com/* GONOSUMDB=gitlab.com/*
```

> **Note on `GITLAB_PAT` vs `GITLAB_TOKEN`:** Some services use `GITLAB_PAT` as the ARG/build-arg name instead of `GITLAB_TOKEN`. The pattern is identical — only the ARG name differs. Use whatever name your CI job passes. See `services/kyc-compliance/Dockerfile` (uses `GITLAB_PAT`) and `services/core/Dockerfile` (uses `GITLAB_TOKEN`).

> **Note on `.netrc` security:** Both ARG and `.netrc` are in the same `RUN` layer as `go mod download`. ARG values are not persisted in the final image. The `.netrc` is only in the builder stage and is not copied to the runtime image in multi-stage builds.

### When to check

- **Creating a new Go service Dockerfile** — always include the full auth block
- **Adding a private `gitlab.com/*` dependency** to `go.mod` — verify all Dockerfiles have the auth block
- **Reviewing an existing Dockerfile** that only has `git config url.insteadOf` — add `.netrc` to handle canonical module paths from transitive deps

### How to detect private deps

Check `go.mod` for any `gitlab.com/*` imports (e.g. `proto-api`, `devkit`):

```bash
grep 'gitlab.com' go.mod
```

If any match, the **full auth block** (`.netrc` + `git config`) is **required** in all Dockerfiles.

### Reference implementations

- `services/kyc-compliance/Dockerfile` — **canonical pattern**: both `.netrc` + `git config`, uses `GITLAB_PAT`
- `services/core/Dockerfile` — same pattern, uses `GITLAB_TOKEN`
- `services/payment-core/Dockerfile` — same pattern, uses `GITLAB_TOKEN`
- `services/accounting/Dockerfile` — alternative: BuildKit secrets + `.netrc` (no `git config`)

## Checklist

Before committing changes to `go.mod` or `Dockerfile`:

- [ ] `go.mod` `go` directive version matches Dockerfile `golang:` tag
- [ ] All Dockerfiles in the service directory tree are checked
- [ ] Using exact patch version (not floating `1.25` or `1.25-alpine`)
- [ ] Using ECR prefix (`public.ecr.aws/docker/library/golang:`)
- [ ] Runtime base image (e.g. `alpine`) is also pinned and uses ECR prefix
- [ ] If `go.mod` has `gitlab.com/*` deps, Dockerfile has full GitLab auth block
- [ ] Auth block includes **both** `~/.netrc` creation AND `git config url.insteadOf`
- [ ] `chmod 600 ~/.netrc` is present
- [ ] Auth block is in the same `RUN` step as `go mod download` (ARG values don't persist across layers)
- [ ] Runtime stage has explicit non-root `USER` directive (see `go-dockerfile-security` rule)
