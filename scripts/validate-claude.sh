#!/usr/bin/env bash
# Validate the Claude Code marketplace and plugin manifests in this repo.
#
# Performs three checks:
#   1. JSON syntax for every .claude-plugin/*.json and hooks/hooks.json
#   2. YAML frontmatter parses on every SKILL.md and every command .md
#   3. If the `claude` CLI is available, runs `claude plugin validate .`
#
# Exit non-zero on the first failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

fail=0

check_json() {
  local file="$1"
  if ! python3 -c "import json,sys; json.load(open('$file'))" 2>/dev/null; then
    echo "FAIL: invalid JSON: $file"
    fail=1
  else
    echo "ok:   $file"
  fi
}

check_yaml_frontmatter() {
  local file="$1"
  python3 - "$file" <<'PY' || fail=1
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---\n', text, flags=re.S)
if not m:
    print(f"FAIL: missing YAML frontmatter: {path}")
    sys.exit(1)
try:
    import yaml
    data = yaml.safe_load(m.group(1))
    if not isinstance(data, dict):
        raise ValueError("frontmatter is not a mapping")
    if 'description' not in data:
        raise ValueError("frontmatter missing required key: description")
except Exception as e:
    print(f"FAIL: bad YAML frontmatter in {path}: {e}")
    sys.exit(1)
print(f"ok:   {path}")
PY
}

echo "== JSON manifests =="
check_json ".claude-plugin/marketplace.json"
for f in plugins/*/.claude-plugin/plugin.json; do
  check_json "$f"
done
for f in plugins/*/hooks/hooks.json; do
  [ -f "$f" ] && check_json "$f"
done

echo
echo "== Skill, command & agent frontmatter =="
for f in plugins/*/skills/*/SKILL.md; do
  [ -f "$f" ] && check_yaml_frontmatter "$f"
done
for f in plugins/*/commands/*.md; do
  [ -f "$f" ] && check_yaml_frontmatter "$f"
done
for f in plugins/*/agents/*.md; do
  [ -f "$f" ] && check_yaml_frontmatter "$f"
done

echo
echo "== claude plugin validate =="
if command -v claude >/dev/null 2>&1; then
  claude plugin validate .
else
  echo "skip: claude CLI not on PATH; run 'claude plugin validate .' yourself before publishing"
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "validation FAILED"
  exit 1
fi

echo
echo "validation passed"
