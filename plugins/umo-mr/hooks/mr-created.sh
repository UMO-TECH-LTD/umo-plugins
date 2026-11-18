#!/usr/bin/env bash
# umo-mr postToolUse hook: when a tool call has just created a GitLab MR
# (`glab mr create`, or a GitLab MCP create/save merge request tool), tell the
# agent to run the /mr Phase 8 review loop on it. Covers MRs opened outside /mr.
# Usage: mr-created.sh cursor|claude   (stdin: the host's postToolUse JSON)
# Fail-open: any parse problem prints the host's empty answer and exits 0.
set -uo pipefail

host="${1:-cursor}"
none() {
  echo '{}'
  exit 0
}

command -v jq >/dev/null 2>&1 || none
input="$(cat)"

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)"
case "$host" in
  claude) output="$(jq -c '.tool_response // empty' <<<"$input" 2>/dev/null)" ;;
  *) output="$(jq -r '.tool_output // empty' <<<"$input" 2>/dev/null)" ;;
esac

created=""
case "$tool" in
  Shell | Bash)
    [[ "$cmd" =~ (^|[;&|[:space:]])glab[[:space:]]+mr[[:space:]]+create([[:space:]]|$) ]] && created=1
    ;;
  *create_merge_request* | *save_merge_request*) created=1 ;;
esac
[[ -n "$created" ]] || none

url="$(grep -oE 'https://[^[:space:]"\\]+/-/merge_requests/[0-9]+' <<<"$output" | head -n 1)"
[[ -n "$url" ]] || none

root="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"
loop="$root"
for part in skills gitlab-mr references review-loop.md; do loop="$loop/$part"; done

context="An MR was just created: $url. Opening it does not finish the work. Run /mr Phase 8 now, unless the developer asked not to wait: read $loop and follow it — wait for the pipeline on the pushed head SHA and for the review agent's note on that SHA, fix valid findings, reply with evidence to the rest, then report. Do not tell the developer the work is done before that report."

case "$host" in
  claude)
    jq -n --arg c "$context" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
    ;;
  *)
    jq -n --arg c "$context" '{additional_context: $c}'
    ;;
esac
exit 0
