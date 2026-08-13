# Go services: format before commit

When changing Go code in **`services/<service>/`** and **before staging or creating git commits** (including Cursor `/commit` or any “commit these changes” flow):

1. **Format the touched code** so it matches `gofmt` output — this is required by the Google / project Go style and avoids CI noise.

## How to format

**Preferred (from the service module root, e.g. `services/accounting/`):**

```bash
cd services/<service>
go fmt ./...
```

**Specific files only:**

```bash
gofmt -w path/to/file1.go path/to/file2.go
```

**Multiple packages from repo root** (only if you know the module boundary):

```bash
cd services/<service>
go fmt ./...
```

Do **not** commit unformatted Go files; run `go fmt` or `gofmt -w` first, then `git add` / commit.

## Agent checklist

- [ ] After editing `.go` files in a service, run `go fmt ./...` in that service directory (or `gofmt -w` on edited files).
- [ ] Confirm diff shows only intentional logical changes, not formatting drift.
- [ ] If the service’s `Makefile` documents a `fmt` target, you may use `make fmt` when it wraps `go fmt` / `gofmt`.

## Note on `goimports`

If the service or `golangci-lint` config expects **import grouping** beyond `gofmt`, use the project’s documented formatter (often `goimports` or the `make fmt` / lint-fix target). When unsure, **`go fmt ./...` is always required**; add `goimports` only when the service already standardizes on it.
