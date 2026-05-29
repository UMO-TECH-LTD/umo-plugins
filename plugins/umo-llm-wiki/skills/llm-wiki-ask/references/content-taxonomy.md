# LLM-MIRROR Content Taxonomy

> **Source of truth for all Confluence page IDs.**
> Do not copy these IDs to other files — always reference this document.

## Atlassian coordinates

| Key | Value |
|-----|-------|
| Site | `https://umotech.atlassian.net` |
| cloudId | `b347643a-d5fa-4f1c-ba69-4901fdb8717d` |
| Space key | `PM1` |
| Space id | `106496007` |
| Space name | Process Library |

---

## LLM-MIRROR root

| Page | ID |
|------|----|
| `LLM-MIRROR` (root folder) | `789905426` |

---

## Meta pages

| Page | ID | Purpose |
|------|----|---------|
| README | `792723922` | Overview of the mirror structure and update schedule |
| index | `792953969` | Full catalog of all mirrored pages — start every query here |
| log | `792298725` | Mirror run history and last-updated timestamps |
| how-to-query | `792168097` | Query guidance for AI agents — ground once per session |

---

## Content type folders and page counts

| Type | Folder ID | Page count | URL pattern |
|------|-----------|------------|-------------|
| decisions | `791773211` | 102 | `/spaces/PM1/pages/791773211` |
| concepts | `791937031` | 23 | `/spaces/PM1/pages/791937031` |
| entities (parent) | `792887297` | — | `/spaces/PM1/pages/792887297` |
| entities › services | `791937034` | 15 | `/spaces/PM1/pages/791937034` |
| entities › teams | `792264718` | 6 | `/spaces/PM1/pages/792264718` |
| people | `791871495` | 39 | `/spaces/PM1/pages/791871495` |
| topics | `792756226` | 16 | `/spaces/PM1/pages/792756226` |

**Total mirrored pages: 201** (at last mirror run)

---

## Per-type question hints

Use these to route an incoming query to the right folder before running CQL.

### decisions (102 pages)
Questions this type answers:
- "What was decided about X?"
- "Is there an ADR for Y?"
- "Why did we choose Z over W?"
- "What architectural decisions exist for the payments domain?"
- "Has a decision been made on database technology?"

CQL anchor: `ancestor = 791773211`

### concepts (23 pages)
Questions this type answers:
- "What is X in UMO terms?"
- "How does the Y concept work?"
- "Explain the onboarding model."
- "What patterns does UMO use for event sourcing?"

CQL anchor: `ancestor = 791937031`

### entities › services (15 pages)
Questions this type answers:
- "Who owns the payments service?"
- "What does the X service do?"
- "Which services are in the billing domain?"
- "What are the dependencies of service Y?"

CQL anchor: `ancestor = 791937034`

### entities › teams (6 pages)
Questions this type answers:
- "Which team is responsible for X?"
- "What does the platform team own?"
- "Who do I contact about service Y?"

CQL anchor: `ancestor = 792264718`

### people (39 pages)
Questions this type answers:
- "Who is responsible for X?"
- "What is [person]'s role?"
- "Who made decision Y?"
- "Who is the tech lead for the Z domain?"

CQL anchor: `ancestor = 791871495`

### topics (16 pages)
Questions this type answers:
- "What are the known issues with X?"
- "Give me an overview of the Y initiative."
- "What background exists on the Z migration?"
- Cross-cutting themes that span multiple services or decisions.

CQL anchor: `ancestor = 792756226`

---

## Citation URL template

```
https://umotech.atlassian.net/wiki/spaces/PM1/pages/<pageId>
```

Always use this URL format when citing a page in an answer. Never fabricate
IDs — only cite pages returned by `getConfluencePage` or
`searchConfluenceUsingCql`.
