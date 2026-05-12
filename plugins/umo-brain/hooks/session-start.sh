#!/usr/bin/env bash
# umo-brain SessionStart hook — nudges the agent to use the brain-harness skill
# before any tool call. This replaces Cursor's `alwaysApply: true` semantics.
#
# Output is injected into the agent's context as an additionalContext message.
# Keep it short — the full policy lives in skills/brain-harness/SKILL.md.

cat <<'EOF'
DAVID brain is available (david-brain MCP). Before substantive work in this session:

  1. Invoke the `brain-harness` skill to load the full memory workflow policy.
  2. Call `david_whoami` to see role and session mode.
  3. Call `david_recall` with a broad orientation query (limit: 5).
  4. Call `david_feedback` on every returned memory — mandatory.

Save durable learnings with `david_remember` before ending the session.
If BRAIN_MCP_API_KEY is unset, `david-brain` will be unavailable — report the error rather than skipping silently.
EOF
