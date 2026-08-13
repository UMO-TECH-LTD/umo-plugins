---
name: go-dockerfile
description: Security and version rules for Go service Dockerfiles — non-root USER, pinned base image tags behind the ECR prefix, GitLab private-module auth for gitlab.com/umo-tech-ltd-group/platform/*, and keeping the builder Go version in step with go.mod. Use when creating or editing a Go service Dockerfile, bumping the Go version in go.mod, or fixing a Trivy misconfig/image finding that fails the pipeline.
---

# Go service Dockerfiles

Two things break Go images in this org, and both are caught by CI rather than by
review: a Dockerfile that fails the Trivy gates, and a builder image whose Go
version has drifted from `go.mod`.

## Read this first

- **`references/security-requirements.md`** — the requirements the Trivy
  `misconfig` and `image` scanners enforce: non-root `USER`, pinned base image
  tags, the ECR registry prefix, and how private module auth is wired without
  leaking the token into a layer. A violation fails the MR pipeline.
- **`references/version-sync.md`** — the `FROM golang:<version>` ↔ `go` directive
  in `go.mod` invariant, and the GitLab private-module auth setup that goes with
  it.

## Checklist

- [ ] Base images pinned to an explicit tag (never `latest`) and pulled through the ECR prefix.
- [ ] Final stage runs as a non-root `USER`.
- [ ] Builder Go version matches the `go` directive in `go.mod`.
- [ ] Private module auth (`ARG` + `~/.netrc` + `git … insteadOf` + `GOPRIVATE`) present in the **builder** stage for `gitlab.com/umo-tech-ltd-group/*`, and never carried into the runtime stage.
- [ ] Services that run migrations at boot: the `atlas-builder` stage has the same auth before its `git clone`.
- [ ] Trivy `misconfig` and `image` jobs green on the MR.
