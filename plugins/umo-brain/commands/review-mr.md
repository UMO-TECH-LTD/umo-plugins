---
name: review-mr
description: Review a GitLab merge request with all 4 DAVID personas. Usage — /review-mr <project-path> <mr-iid>
---

Review GitLab merge request `$ARGUMENTS` using the `mr-reviewer` agent.

Parse the arguments to extract the project path and MR IID. Then follow the `/mr-review-orchestrator` skill workflow: fetch MR → brain recall → 4 persona analysis → deduplicate → post to GitLab → brain save.

Report the summary table and a link to the MR when done.
