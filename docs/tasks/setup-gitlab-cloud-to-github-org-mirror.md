# Task: Mirror a private GitLab.com project to a private GitHub organization repo

Use this when source of truth is **GitLab SaaS (gitlab.com)** and you need a **read/write mirror** on **GitHub** (for example Cursor **team marketplace**, which imports from GitHub only).

## Preconditions

- **GitLab:** Maintainer (or higher) on the GitLab **project** to mirror.
- **GitHub:** Permission to create repos under the target **organization** and to add credentials (PAT or deploy key).
- **Direction:** GitLab → GitHub (**push** mirror). GitHub is overwritten to match GitLab on each sync (do not treat GitHub as an independent edit surface unless you understand mirror semantics).

## Security choices (pick one)

| Method | Pros | Cons |
|--------|------|------|
| **HTTPS + GitHub PAT** | Quick | PAT rotation tied to user or bot account |
| **SSH + deploy key** | Scoped per repo | Key management per GitHub repo |

Prefer a **machine user** or **fine-grained PAT** scoped to only the mirror repos.

## Step 1 — Create empty private repo on GitHub

1. GitHub org → **New repository**.
2. Name it (example: `umo-plugins`).
3. **Private**, **no** README / .gitignore / license (avoid merge conflicts on first push).
4. Note the clone URL: `https://github.com/<ORG>/<REPO>.git` or `git@github.com:<ORG>/<REPO>.git`.

## Step 2 — GitHub credentials GitLab may use

### Option A — HTTPS (classic PAT)

1. GitHub → **Settings → Developer settings → Personal access tokens**.
2. Create a token that can **push** to the org repo:
   - **Classic:** `repo` scope for private repos.
   - **Fine-grained:** repository access = that repo only; **Contents: Read and write**; **Metadata: Read-only**.
3. Store the token in your secret manager; GitLab will ask for it when configuring the mirror (often as “password” with HTTPS URL).

### Option B — SSH deploy key

1. In GitLab, when configuring push mirror, note or generate the **SSH public key** GitLab shows for mirroring (or use project/group CI key policy per your standards).
2. GitHub repo → **Settings → Deploy keys → Add deploy key** → paste public key → enable **Allow write access**.
3. Mirror URL: `git@github.com:<ORG>/<REPO>.git`.

## Step 3 — Configure push mirror on GitLab

1. Open the GitLab project → **Settings → Repository**.
2. Expand **Mirroring repositories**.
3. **Git repository URL:** paste the GitHub URL (HTTPS or SSH).
4. **Mirror direction:** **Push**.
5. **Authentication:** match your choice (password + PAT for HTTPS, or SSH).
6. Save — **Mirror repository**.

Notes:

- Sync interval depends on GitLab edition/plan; check GitLab docs for **push mirroring** if you need guaranteed SLA.
- GitLab may cap how many push mirrors are enabled per project.

## Step 4 — First sync and verification

1. Use **Update now** / wait for the scheduled push (per GitLab UI).
2. On GitHub, confirm **branches and tags** appeared and latest commits match GitLab default branch.
3. Optional: protect GitHub default branch and restrict who can push directly — mirror pushes typically need the credential you configured.

## Step 5 — Cursor team marketplace (if applicable)

1. Ensure **Cursor GitHub App** is installed on the GitHub **organization** with access to this repo (**All** or **Selected** repositories).
2. Cursor Dashboard → **Team Marketplace** → import `https://github.com/<ORG>/<REPO>`.
3. Repo root should include **`.cursor-plugin/marketplace.json`** for multi-plugin marketplaces (see Cursor plugins reference).

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Authentication failed | PAT scopes (write), deploy key **write** enabled, SSH host keys |
| Partial branches | Mirror options / protected branches settings on GitLab |
| Empty GitHub repo | Wrong URL, wrong org, or mirror disabled |
| Duplicate history errors | GitHub repo was non-empty with unrelated history — use empty target or reset per runbook |

## References

- GitLab: [Push mirroring](https://docs.gitlab.com/user/project/repository/mirror/push/)
- GitHub: PAT and deploy keys documentation
- Cursor: [Plugins](https://cursor.com/docs/plugins) (team marketplace import)

## Maintenance

- Rotate PAT / deploy keys on a schedule.
- Document **source of truth** (GitLab); train contributors not to rely on GitHub for merges if mirror is one-way.
