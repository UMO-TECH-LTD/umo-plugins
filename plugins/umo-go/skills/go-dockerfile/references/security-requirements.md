# Go Dockerfile Security Requirements

Every Go service Dockerfile must satisfy these security requirements. Trivy CI gates (`misconfig` and `image` scanners) enforce them — violations fail the MR pipeline.

## 1. Non-root USER (Trivy DS-0002)

The runtime stage must run as a non-root user. Without an explicit `USER` directive, the container runs as root, which is flagged as a HIGH misconfiguration.

### Alpine-based runtime

```dockerfile
FROM public.ecr.aws/docker/library/alpine:3.22

WORKDIR /app

# ... copy binary, config, migrations ...

# Non-root user
RUN addgroup -S app && adduser -S app -G app
RUN chown -R app:app /app
USER app

ENTRYPOINT ["/app/myservice"]
CMD ["serve"]
```

### Distroless runtime

Distroless images have a built-in nonroot user — use the `:nonroot` tag and do NOT add a separate `USER` directive:

```dockerfile
FROM gcr.io/distroless/static:nonroot
# No USER directive needed — :nonroot runs as UID 65532
```

### Nginx-based containers

Use the `nginx-unprivileged` base or add `USER 101` (standard nginx UID):

```dockerfile
FROM public.ecr.aws/docker/library/nginx:alpine
USER 101
```

## 2. Pinned base image tags

Never use `latest` or floating minor tags. Always pin to a specific patch version:

```dockerfile
# CORRECT
FROM public.ecr.aws/docker/library/golang:1.25.5-alpine AS builder
FROM public.ecr.aws/docker/library/alpine:3.22

# WRONG — floating tags
FROM public.ecr.aws/docker/library/golang:1.25-alpine AS builder
FROM public.ecr.aws/docker/library/alpine:latest
FROM alpine
```

The `golang:` builder tag must match the `go` directive in `go.mod` exactly (see `references/version-sync.md`).

## 3. ECR prefix for base images

All standard Docker images must use the `public.ecr.aws/docker/library/` prefix to avoid Docker Hub rate limits (see `docker-ecr-images` rule):

```dockerfile
# CORRECT
FROM public.ecr.aws/docker/library/golang:1.25.5-alpine AS builder
FROM public.ecr.aws/docker/library/alpine:3.22

# WRONG — bare Docker Hub references
FROM golang:1.25.5-alpine AS builder
FROM alpine:3.22
```

## 4. GitLab private module authentication

Go services that depend on private `gitlab.com/*` modules must include a **two-mechanism auth block** before `go mod download`. Using only `git config url.insteadOf` is not sufficient — see `references/version-sync.md` for the full rationale.

**Both mechanisms are required:**
- `~/.netrc` — authenticates Go's HTTP `?go-get=1` VCS discovery for canonical module paths (without `.git` suffix). Without this, Go falls back to guessing VCS boundaries via `git ls-remote` and hits parent group paths that aren't repos.
- `git config url.insteadOf` — authenticates the actual `git clone` / `git ls-remote` operations.

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

Check `go.mod` for `gitlab.com` imports to determine if the auth block is needed:

```bash
grep 'gitlab.com' go.mod
```

See `references/version-sync.md` for the full explanation of why both mechanisms are needed, security notes on ARG/`.netrc` scope, and reference implementations.

## 5. Atlas CLI source (services with runtime migrations)

If the image ships `/usr/local/bin/atlas` (services with `migrate` / `migrate-db`):

- ✅ Clone **`gitlab.com/umo-tech-ltd-group/platform/atlas`** tag **`v1.2.0-umo.1`** (UMO fork)
- ✅ `atlas-builder` stage needs GitLab auth (`.netrc` + `git config`) before `git clone`
- ✅ Pin `golang.org/x/net@v0.55.0` and `golang.org/x/text@v0.39.0` after clone (the fork resolves `x/text` v0.37.0, blocked as HIGH by CVE-2026-56852); build with `CGO_ENABLED=0`
- ❌ Do **not** clone `github.com/ariga/atlas` — upstream transitive deps fail Image Scan
- ❌ Do **not** use `arigaio/atlas` prebuilt image or `atlasgo.sh` binaries

**Reference:** `services/kyc-compliance/Dockerfile`, `distroless-dockerfile-design` skill → "Atlas CLI source".

## Checklist

When creating or modifying a Go service Dockerfile:

- [ ] Runtime stage has explicit `USER` directive (non-root)
- [ ] All base images use `public.ecr.aws/docker/library/` prefix
- [ ] All base image tags are pinned to specific versions (no `latest`, no floating minor)
- [ ] `golang:` tag matches `go.mod` `go` directive exactly
- [ ] If `go.mod` has `gitlab.com/*` deps, full auth block is present (both `.netrc` AND `git config`)
- [ ] `chmod 600 ~/.netrc` is present
- [ ] Auth block is in the same `RUN` step as `go mod download`
- [ ] Multi-stage builds: all `FROM` lines checked (builder + runtime)
- [ ] If image includes `atlas` CLI: built from UMO fork `platform/atlas@v1.2.0-umo.1`, not `github.com/ariga/atlas`
- [ ] If image includes `atlas` CLI: `go get` pins both `golang.org/x/net` and `golang.org/x/text` before the build
- [ ] All Dockerfiles in the service directory tree are updated consistently
