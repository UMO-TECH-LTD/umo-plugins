# LLM-MIRROR Query Recipes

Copy-paste CQL snippets for common query patterns. All queries are scoped to
`space = PM1` and anchored under the `LLM-MIRROR` root (`ancestor = 789905426`)
unless a type-specific folder anchor is more precise.

Replace `<keyword>` with the relevant term from the user's question.
Replace `<name>` with a person or team name.

---

## Broad search across all LLM-MIRROR pages

Find any page mentioning a keyword anywhere in the space:

```
space = PM1 AND ancestor = 789905426 AND text ~ "<keyword>" ORDER BY lastModified DESC
```

Find pages whose title contains a keyword:

```
space = PM1 AND ancestor = 789905426 AND title ~ "<keyword>"
```

---

## Decisions (ADRs)

Find all decisions (returns up to 50 by default):

```
space = PM1 AND ancestor = 791773211 ORDER BY lastModified DESC
```

Find a decision about a specific topic:

```
space = PM1 AND ancestor = 791773211 AND title ~ "<keyword>"
```

Full-text search within decisions:

```
space = PM1 AND ancestor = 791773211 AND text ~ "<keyword>"
```

---

## Concepts

Find a concept by name:

```
space = PM1 AND ancestor = 791937031 AND title ~ "<keyword>"
```

Full-text search within concepts:

```
space = PM1 AND ancestor = 791937031 AND text ~ "<keyword>"
```

---

## Services

Find a service page by name:

```
space = PM1 AND ancestor = 791937034 AND title ~ "<keyword>"
```

Find which service owns a specific capability:

```
space = PM1 AND ancestor = 791937034 AND text ~ "<keyword>"
```

---

## Teams

Find a team page:

```
space = PM1 AND ancestor = 792264718 AND title ~ "<name>"
```

Find which team is responsible for a domain:

```
space = PM1 AND ancestor = 792264718 AND text ~ "<keyword>"
```

---

## People

Find a person's page:

```
space = PM1 AND ancestor = 791871495 AND title ~ "<name>"
```

Find who is associated with a topic or service:

```
space = PM1 AND ancestor = 791871495 AND text ~ "<keyword>"
```

---

## Topics

Find a topic overview:

```
space = PM1 AND ancestor = 792756226 AND title ~ "<keyword>"
```

Full-text search within topics:

```
space = PM1 AND ancestor = 792756226 AND text ~ "<keyword>"
```

---

## Cross-type search (when content type is unknown)

When you don't know which folder a concept lives in, search all of LLM-MIRROR:

```
space = PM1 AND ancestor = 789905426 AND (title ~ "<keyword>" OR text ~ "<keyword>") ORDER BY lastModified DESC
```

---

## Recently updated pages (any type)

Pages updated in the last 30 days:

```
space = PM1 AND ancestor = 789905426 AND lastModified >= now("-30d") ORDER BY lastModified DESC
```

---

## Usage notes

- Always read the index page (`792953969`) before running CQL — the index may
  surface the page without a search round-trip.
- Prefer `title ~` before `text ~` for precision; fall back to `text ~` when
  title search yields no results.
- The `ancestor` filter restricts results to the LLM-MIRROR subtree only,
  avoiding unrelated PM1 pages.
- Maximum useful result set: fetch the top 5 pages from search, then call
  `getConfluencePage` on each to get the full body.
