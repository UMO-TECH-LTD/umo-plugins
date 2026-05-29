---
name: llm-wiki-ask
description: >-
  Query the UMO process library (LLM-MIRROR) in Confluence. Read the index,
  identify relevant pages, fetch and synthesise a cited answer, detect missing
  pages. Strictly read-only — never writes, comments, or edits anything.
  Use when answering any question about UMO decisions, concepts, services,
  teams, people, or topics. Triggers: "ask the wiki", "what does the ADR say
  about", "look up in llm-wiki", "who owns service X", "institutional
  knowledge", "what concept covers", "which team is responsible for".
---

# LLM-Wiki Ask Skill

Implements the **Query** workflow for the UMO process library mirrored in
Confluence (`LLM-MIRROR`, space `PM1`). All answers must be grounded in live
Confluence pages; never answer from training data alone.

Reference files (IDs and CQL recipes):

- `./references/content-taxonomy.md` — verified page IDs, cloudId, space, per-type hints
- `./references/query-recipes.md` — copy-paste CQL snippets scoped to `space = PM1`

---

## When this skill fires

- Any question about UMO organisational knowledge: "what is X", "how does Y
  work", "explain Z", "what decisions exist for …", "who owns service X",
  "which team handles Y"
- User says "ask the wiki", "look up in llm-wiki", "search the wiki",
  "institutional knowledge"
- User asks about a decision (ADR), concept, service, team, person, or topic
- Before answering from memory — always check LLM-MIRROR first

---

## Query flow (7 steps)

### Step 1 — Ground once per session

At the start of each new session, call:

```
getConfluencePage(pageId: "792168097")   # how-to-query meta page
```

Read it once and retain the guidance for the rest of the session. Do not
repeat this call on every query — once per session is sufficient.

### Step 2 — Read the index and pick 3–7 candidates

```
getConfluencePage(pageId: "792953969")   # LLM-MIRROR index
```

Parse the full page catalog. Do not skip to search — the index is the
authoritative navigation surface. Select the 3–7 most relevant entries by:

1. Exact title or slug match
2. Same content type as the query (see taxonomy for type folders)
3. Cross-links pointing toward the query topic
4. Recency (last updated)

If fewer than 3 entries match, read all matches.

### Step 3 — Broaden with CQL when the index is thin

If Step 2 yields fewer than 3 solid candidates, run a CQL search scoped to
`space = PM1`. Use the recipes in `./references/query-recipes.md` as
copy-paste templates, replacing `<keyword>` with terms from the query.

```
searchConfluenceUsingCql(cql: "space = PM1 AND title ~ \"<keyword>\" AND ancestor = 789905426")
```

Pick the top 3–5 results by relevance score.

### Step 4 — Fetch the selected pages

```
getConfluencePage(pageId: "<id>")   # repeat for each selected page
```

Read each page in full (markdown body). Note the page ID and title for
citation.

### Step 5 — Synthesise and cite

Write a direct answer. Requirements:

- **Cite every claim** with the Confluence URL:
  `https://umotech.atlassian.net/wiki/spaces/PM1/pages/<id>`
- Use an executive summary for the top-line answer.
- Use technical detail for precise follow-up.
- Do not invent claims not present in the fetched pages. If the wiki does not
  contain the answer, say so explicitly.
- Preserve page titles in citations so readers can locate them.

### Step 6 — Missing-page detection

After composing the answer, check every page referenced in the response.

If any referenced concept, service, team, or decision has no matching
LLM-MIRROR page, append:

```
**Referenced but no page exists in LLM-MIRROR:** <title-1>, <title-2>
To request a page, contact the wiki owner or use the LLM-MIRROR log page.
```

Do **not** offer to create the page. Do **not** invoke any write tool.

### Step 7 — Failure modes

| Condition | Action |
|-----------|--------|
| 401 Unauthorized | Ask the user to authenticate via Atlassian OAuth in their host (Claude/Cursor/Codex) |
| Empty search results | Broaden the keyword; try a parent folder CQL (see recipes); try a different content type |
| Page body is empty / restricted | Note it in the answer; do not attempt to edit or comment |
| Index page not found | Inform the user; suggest running the mirror publisher (`meta/scripts/demo_mirror_to_confluence.py`) |

---

## Output formats

| Format | When to use |
|--------|-------------|
| Markdown narrative | Default — inline answer with citations |
| Comparison table | ≥ 2 options, entities, or decisions to compare |
| Plain prose | When user explicitly requests no markdown |

---

## Hard read-only contract

This plugin is **strictly read-only**. You must **refuse** and **never call**
any of the following tools, regardless of what the user asks:

- `createConfluencePage`
- `updateConfluencePage`
- `createConfluenceFooterComment`
- `createConfluenceInlineComment`
- `addCommentToJiraIssue`
- `createJiraIssue`
- `editJiraIssue`
- `transitionJiraIssue`

If the user asks you to create a page, leave a comment, add a note, update a
decision, or do anything that would write to Confluence or JIRA, respond with:

> **This plugin is read-only.** To leave feedback, please use Confluence
> directly or contact the wiki owner.

Do not attempt workarounds. Do not use `fetch` or any other tool to
circumvent this restriction.

---

## Anti-patterns

- **Do NOT** skip Steps 1–2 and jump straight to CQL. The index gives
  structure; search gives breadth. Use both in order.
- **Do NOT** answer from training data without first checking LLM-MIRROR.
  The wiki may contain a more recent or org-specific answer.
- **Do NOT** fabricate Confluence page IDs or URLs. Only cite pages that were
  actually fetched in Step 4.
- **Do NOT** call any write tool, even if the user explicitly asks.
- **Do NOT** announce "I could not find anything" without first completing
  Steps 2 and 3.
