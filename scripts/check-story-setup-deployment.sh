#!/bin/bash
# check-story-setup-deployment.sh — story-setup 部署完整性（Codex-only 适配）
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "Error: not in a git repository" >&2; exit 1; }

SKILL_DIR="$REPO_ROOT/skills/story-setup"
SKILL_FILE="$SKILL_DIR/SKILL.md"
AGENT_REFS_DIR="$SKILL_DIR/references/agent-references"
CODEX_DIR="$SKILL_DIR/references/codex"
CODX_HOOKS="$CODEX_DIR/hooks"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "required file missing: $1"; }
assert_grep() { grep -Eq "$1" "$2" || fail "$3 ($2)"; }

echo "Story setup deployment check"
echo "============================"
echo "Repo: $REPO_ROOT"

# R0 — 参考资料目录布局（Phase 1 自检同名）
ref_dir_count=0
for d in "$SKILL_DIR/references"/*/; do [ -d "$d" ] && ref_dir_count=$((ref_dir_count + 1)); done
[ "$ref_dir_count" -eq 2 ] || fail "story-setup references/ now has $ref_dir_count subdirs (expected 2); update the Phase 1 self-check list and this assertion"

# R1 — Codex 资源完整性
assert_file "$CODEX_DIR/AGENTS.md.tmpl"
assert_file "$CODX_HOOKS/hooks.json"
assert_file "$CODX_HOOKS/story_codex_hook.py"
assert_file "$CODX_HOOKS/run-story-hook.sh"
assert_file "$CODX_HOOKS/run-story-hook.cmd"
assert_file "$SKILL_DIR/scripts/merge-codex-hooks.py"
assert_grep 'references/codex' "$SKILL_FILE" "story-setup must document Codex references"

echo "  OK Codex resource completeness"

# R2 — 部署清单 / sentinel 契约
assert_grep 'hooks.json' "$SKILL_FILE" "story-setup must document hooks.json merge"
assert_grep '\.story-deployed' "$SKILL_FILE" "story-setup must document the deployment sentinel"
assert_grep 'agents_version' "$SKILL_FILE" "story-setup must pin agents_version"
assert_grep 'target_cli' "$SKILL_FILE" "story-setup must document target_cli"
assert_grep 'references_dir' "$SKILL_FILE" "story-setup must document references_dir"
assert_grep '默认不部署 custom agents|不部署 custom agents' "$SKILL_FILE" "story-setup must state the no-custom-agents default"
assert_grep 'unknown agent_type' "$SKILL_FILE" "story-setup must document the Codex agent_type fallback"

echo "  OK deployment manifest"

# R3 — Agent reference bundle 完整性
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  assert_file "$AGENT_REFS_DIR/$ref"
done < <(grep -RhoE 'story-setup/references/agent-references/[A-Za-z0-9_-]+\.md' \
  "$SKILL_DIR/references" "$REPO_ROOT/skills/story" "$REPO_ROOT/skills/story-short-write" "$REPO_ROOT/skills/story-short-analyze" "$REPO_ROOT/skills/story-short-scan" "$REPO_ROOT/skills/story-deslop" "$REPO_ROOT/skills/story-review" 2>/dev/null | sed 's|.*agent-references/||' | sort -u)

echo "  OK agent reference bundle ($(ls "$AGENT_REFS_DIR" | wc -l | tr -d ' ') files, $(grep -RhoE 'story-setup/references/agent-references/[A-Za-z0-9_-]+\.md' "$SKILL_DIR/references" 2>/dev/null | wc -l | tr -d ' ') cited)"

# R4 — Codex hooks.json 契约：只有 launcher，无直调、无旧 Agent 路径
grep -q 'story_codex_hook\.py' "$CODX_HOOKS/hooks.json" && fail "hooks.json must not direct-call story_codex_hook.py"
grep -q 'run-story-hook\.sh' "$CODX_HOOKS/hooks.json" || fail "hooks.json must route through run-story-hook.sh"
python3 -m json.tool "$CODX_HOOKS/hooks.json" > /dev/null || fail "hooks.json is not valid JSON"

echo "  OK hooks.json contract"

echo ""
echo "OK: story-setup deployment checks passed"