#!/usr/bin/env bash
# test-codex-hooks.sh — synthetic Codex hook contract tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

HOOKS_SRC="$REPO_ROOT/skills/story-setup/references/codex/hooks"
HOOK_SRC="$HOOKS_SRC/story_codex_hook.py"
ROOT="$TMP_DIR/story-project"
HOOK="$ROOT/.codex/hooks/story_codex_hook.py"
mkdir -p "$ROOT/.codex/hooks"
cp "$HOOK_SRC" "$HOOK"
cp "$HOOKS_SRC/run-story-hook.sh" "$HOOKS_SRC/run-story-hook.cmd" "$ROOT/.codex/hooks/"
chmod +x "$HOOK"

git -C "$ROOT" init -q
git -C "$ROOT" config user.email codex-hook@example.invalid
git -C "$ROOT" config user.name codex-hook-test

run_hook() {
  local event="$1" payload="$2"
  (cd "$ROOT" && printf '%s' "$payload" | CODEX_PROJECT_DIR="$ROOT" python3 "$HOOK" "$event")
}

# Read the hook's stdout as UTF-8 bytes (not locale-decoded text): the hook emits
# UTF-8 Chinese deny reasons, and Windows Python defaults stdin to the ANSI code page,
# which would raise UnicodeDecodeError here even when the hook output is correct.
assert_json() {
  python3 -c 'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8"))' >/dev/null
}

assert_denied() {
  local out="$1" label="$2"
  printf '%s' "$out" | assert_json || fail "$label did not emit valid JSON: $out"
  printf '%s' "$out" | python3 -c 'import json,sys; o=json.loads(sys.stdin.buffer.read().decode("utf-8")); h=o.get("hookSpecificOutput",{}); assert h.get("hookEventName")=="PreToolUse" and h.get("permissionDecision")=="deny" and h.get("permissionDecisionReason")' || fail "$label was not denied: $out"
}

assert_additional_context() {
  local out="$1" label="$2"
  printf '%s' "$out" | assert_json || fail "$label did not emit valid JSON: $out"
  printf '%s' "$out" | python3 -c 'import json,sys; o=json.loads(sys.stdin.buffer.read().decode("utf-8")); h=o.get("hookSpecificOutput",{}); assert h.get("additionalContext")' || fail "$label missing additionalContext: $out"
}

assert_empty() {
  local out="$1" label="$2"
  [ -z "$out" ] || fail "$label expected empty allow output, got: $out"
}

echo "Codex hook synthetic tests"
echo "=========================="
echo "Fixture: $ROOT"

# ── 大纲守卫：短篇 正文.md 首建缺 小节大纲.md（有 设定.md 信号）→ 拦；补纲 → 放行 ──
mkdir -p "$ROOT/short"
: > "$ROOT/short/设定.md"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Write","tool_input":{"file_path":"short/正文.md","content":"正文"}}')"
assert_denied "$out" "short prose without section outline"
: > "$ROOT/short/小节大纲.md"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Write","tool_input":{"file_path":"short/正文.md","content":"正文"}}')"
assert_empty "$out" "short prose with outline"

# 无 设定.md 信号（docs/正文.md 之类）→ 放行（宁可漏拦不可误伤）
mkdir -p "$ROOT/bare" "$ROOT/cwd-book"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Write","tool_input":{"file_path":"bare/正文.md","content":"正文"}}')"
assert_empty "$out" "bare 正文.md without 设定.md signal is allowed"
: > "$ROOT/cwd-book/设定.md"
relative_payload="$(python3 - "$ROOT/cwd-book" <<'PY'
import json, sys
from pathlib import Path
payload = {"cwd": str(Path(sys.argv[1]).resolve()), "tool_name": "Write", "tool_input": {"file_path": "正文.md", "content": "正文"}}
sys.stdout.buffer.write(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
PY
)"
out="$(run_hook pre-tool-prose-guard "$relative_payload")"
assert_denied "$out" "relative prose target from hook cwd"
printf '%s' "$out" | grep -q 'cwd-book/正文.md' || fail "relative target was not resolved from hook cwd: $out"
: > "$ROOT/cwd-book/小节大纲.md"
out="$(run_hook pre-tool-prose-guard "$relative_payload")"
assert_empty "$out" "relative prose target with cwd-local outline"

# 已存在正文 -> 放行（续写/改稿/去AI味）
: > "$ROOT/short/正文.md"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Write","tool_input":{"file_path":"short/正文.md","content":"改稿"}}')"
assert_empty "$out" "existing prose rewrite"

mkdir -p "$ROOT/patchbook"
: > "$ROOT/patchbook/设定.md"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: patchbook/正文.md\n+正文\n*** End Patch\n"}}')"
assert_denied "$out" "apply_patch short prose without outline"
: > "$ROOT/patchbook/小节大纲.md"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: patchbook/正文.md\n+正文\n*** End Patch\n"}}')"
assert_empty "$out" "apply_patch short prose with outline"

# story-import 迁移：已有 拆文库/{书名}/ 分析源时，正文先于小节大纲迁移是正常流程，放行
mkdir -p "$ROOT/impbook" "$ROOT/拆文库/impbook"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Write","tool_input":{"file_path":"impbook/正文.md","content":"正文"}}')"
assert_empty "$out" "story-import short migration (拆文库 source present)"

echo "  OK outline-before-prose guard"

# The shared parser's full syntax matrix lives in test-prose-net-parity.sh. Here we only verify
# that the Codex adapter forwards one write and one read-only mention correctly.
mkdir -p "$ROOT/bashbook"
: > "$ROOT/bashbook/设定.md"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Bash","tool_input":{"command":"grep -n bashbook/正文.md notes.md"}}')"
assert_empty "$out" "command merely mentioning prose path is not denied"
out="$(run_hook pre-tool-prose-guard '{"tool_name":"Bash","tool_input":{"command":"cat draft.md > bashbook/正文.md"}}')"
assert_denied "$out" "write to prose without outline is denied"

echo "  OK prose command-scan precision"

cat > "$ROOT/short/正文.md" <<'TXT'
身高: 180
TXT
git -C "$ROOT" add short/正文.md
out="$(run_hook pre-tool-commit-advisory '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}')"
assert_additional_context "$out" "commit advisory"
echo "$out" | grep -q '正文硬编码角色属性' || fail "commit advisory did not inspect staged markdown"
echo "$out" | grep -q 'short/正文.md' || fail "commit advisory missed short prose"
out="$(run_hook pre-tool-commit-advisory '{"tool_name":"Bash","tool_input":{"command":"echo git commit docs"}}')"
assert_empty "$out" "non-commit bash command"

echo "  OK commit advisory"

cat > "$ROOT/.story-deployed" <<'TXT'
deployed_at: 2026-06-25T00:00:00Z
agents_version: 26
setup_skill_version: 1.2.7
target_cli: codex
resolver_strategy: project-local-skill-reference
references_dir: .codex/skills/story-setup/references/agent-references
TXT
printf 'book\n' > "$ROOT/.active-book"
mkdir -p "$ROOT/book"
out="$(run_hook session-start '{"hook_event_name":"SessionStart"}')"
assert_additional_context "$out" "session-start context"
echo "$out" | grep -q 'Active story project' || fail "session-start did not mention active book"
out="$(run_hook pre-compact '{"hook_event_name":"PreCompact"}')"
printf '%s' "$out" | assert_json || fail "pre-compact invalid JSON: $out"
echo "$out" | grep -q 'Story Compact Summary' || fail "pre-compact missing summary"
out="$(run_hook post-compact '{"hook_event_name":"PostCompact"}')"
printf '%s' "$out" | assert_json || fail "post-compact invalid JSON: $out"
out="$(run_hook stop '{"hook_event_name":"Stop"}')"
printf '%s' "$out" | assert_json || fail "stop invalid JSON: $out"

echo "  OK session/compact/stop JSON"

# ── Stop content sweep: Codex 无 PostToolUse，回合结束对 git 改动正文复扫硬信号（轻量网）──
# 新写一篇带截断、留作 git 改动（untracked）→ stop 必须点名并报截断；非改动文件不复扫。
PAD6='江晨握紧拳头慢慢走向门口盘算着每一步。'  # bash 重复填充，避开 Windows python 文本 stdout 的 cp1252 崩溃
: > "$ROOT/book/设定.md"
printf '# 开头\n\n%s\n他冲过去一拳砸在' "$PAD6$PAD6$PAD6$PAD6$PAD6$PAD6" > "$ROOT/book/正文.md"
out="$(run_hook stop '{"hook_event_name":"Stop"}')"
printf '%s' "$out" | assert_json || fail "stop content-sweep invalid JSON: $out"
echo "$out" | grep -q '截断' || fail "stop did not flag truncated git-changed prose: $out"
echo "$out" | grep -q '正文.md' || fail "stop did not name the changed prose file: $out"
# 已提交（无 git 改动）的正文不应被复扫——只兜本回合改动集。
git -C "$ROOT" add -A && git -C "$ROOT" commit -qm wip >/dev/null 2>&1
out="$(run_hook stop '{"hook_event_name":"Stop"}')"
printf '%s' "$out" | python3 -c 'import json,sys; o=json.loads(sys.stdin.buffer.read().decode("utf-8")); assert "截断" not in o.get("systemMessage","")' || fail "stop re-flagged already-committed prose: $out"
echo "  OK stop content sweep (git-changed only)"

# 目录发现只看推荐结构深度，且不进入 node_modules/隐藏目录。Bash/Python/共享 JS 核应一致。
DISCOVERY_ROOT="$TMP_DIR/discovery-root"
mkdir -p "$DISCOVERY_ROOT/shallow" \
  "$DISCOVERY_ROOT/node_modules/fake" \
  "$DISCOVERY_ROOT/.hidden/fake" \
  "$DISCOVERY_ROOT/a/b/c/d/e/deep"
: > "$DISCOVERY_ROOT/shallow/正文.md"
: > "$DISCOVERY_ROOT/node_modules/fake/正文.md"
: > "$DISCOVERY_ROOT/.hidden/fake/正文.md"
: > "$DISCOVERY_ROOT/a/b/c/d/e/deep/正文.md"
python_discovered="$(python3 - "$HOOK_SRC" "$DISCOVERY_ROOT" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("story_codex_hook", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(sys.argv[2])
active = module.read_active_book(root)
all_books = "|".join(sorted(p.relative_to(root).as_posix() for p in module._discover_all_books(root)))
print(f"{active.relative_to(root).as_posix() if active else ''};{all_books}")
PY
)"
[ "$python_discovered" = "shallow;shallow" ] || fail "Codex discovery crossed depth/ignored dirs: $python_discovered"

# `.active-book` 不能通过目录 symlink 逃到项目根外；无效声明统一回落自动发现。
OUTSIDE_BOOK="$TMP_DIR/outside-book"
mkdir -p "$OUTSIDE_BOOK"
: > "$OUTSIDE_BOOK/正文.md"
# Windows/MSYS 没有创建符号链接的权限时 ln -s 会静默退化成「复制目录」：逃逸场景根本没复现，
# 复制出来的 escape/正文.md 还会被后面的深度断言当成一本书。必须确认真的拿到 symlink 才跑这段。
if ln -s "$OUTSIDE_BOOK" "$DISCOVERY_ROOT/escape" 2>/dev/null && [ -L "$DISCOVERY_ROOT/escape" ]; then
  printf '%s\n' 'escape' > "$DISCOVERY_ROOT/.active-book"
  python_active="$(python3 - "$HOOK_SRC" "$DISCOVERY_ROOT" <<'PY'
import importlib.util, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location("h",sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
r=Path(sys.argv[2]); p=m.read_active_book(r); print(p.relative_to(r).as_posix() if p else "")
PY
)"
  [ "$python_active" = "shallow" ] || fail "Python accepted out-of-root .active-book symlink: $python_active"
  DISCOVERY_REAL="$(cd "$DISCOVERY_ROOT" && pwd -P)"
  rm -f "$DISCOVERY_ROOT/.active-book"
  rm -f "$DISCOVERY_ROOT/escape"
else
  # ln -s 失败或退化成复制：清掉残留，避免污染下面的 maxdepth 4 发现断言。
  rm -rf "$DISCOVERY_ROOT/escape"
fi

# `find -maxdepth 4` 的边界：正文.md marker 本身在深度 4 可见，深度 5 不可见；三端不能 off-by-one。
mkdir -p "$DISCOVERY_ROOT/a/b/book" "$DISCOVERY_ROOT/a/b/c/book"
: > "$DISCOVERY_ROOT/a/b/book/正文.md"
: > "$DISCOVERY_ROOT/a/b/c/book/正文.md"
python_books="$(python3 - "$HOOK_SRC" "$DISCOVERY_ROOT" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("story_codex_hook", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
root = Path(sys.argv[2])
print("|".join(sorted(p.relative_to(root).as_posix() for p in module._discover_all_books(root))))
PY
)"
[ "$python_books" = "a/b/book|shallow" ] || fail "Python depth-4 discovery mismatch: $python_books"
echo "  OK bounded directory discovery (depth 4, hidden/node_modules pruned, Bash/JS/Python parity)"

nested="$ROOT/nested/a/b"
# cwd 相对解析：file_path 相对 cwd 解析，书位于 cwd 之下；有 设定.md 信号、缺 小节大纲 → 拦。
mkdir -p "$nested/bashbook"
: > "$nested/bashbook/设定.md"
out="$(cd "$TMP_DIR" && printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"bashbook/正文.md","content":"正文"}}' "$nested" | python3 "$HOOK" pre-tool-prose-guard)"
assert_denied "$out" "cwd-based root resolution"

echo "  OK cwd-based root resolution"

# __file__ self-location (the Windows-critical resolver) on ALL platforms: with a bogus
# CODEX_PROJECT_DIR (env skipped) and an unrelated cwd, the hook must resolve root from its own
# .codex/hooks/ location. Discriminating: 小节大纲.md exists at the true root, so a wrong root
# (bare bashbook, only 设定.md signal) → deny; only __file__-derived root → allow. (The valid-env
# tests above let env win and never hit this.)
: > "$ROOT/bashbook/小节大纲.md"
# 错误 root 侧的判别 fixture：真 root 之外同名的 bashbook 只有 设定.md、缺 小节大纲.md，
# 若 hook 把 root 解错到 cwd 就会在这里 deny，从而暴露 root 解析失败。
mkdir -p "$TMP_DIR/bashbook"
: > "$TMP_DIR/bashbook/设定.md"
out="$(cd "$TMP_DIR" && CODEX_PROJECT_DIR="$TMP_DIR/does-not-exist" python3 "$HOOK" pre-tool-prose-guard <<'JSON'
{"tool_name":"Write","tool_input":{"file_path":"bashbook/正文.md","content":"x"}}
JSON
)"
assert_empty "$out" "__file__ self-location resolves root when env is bogus and cwd unrelated"
rm -f "$ROOT/bashbook/小节大纲.md"
rm -rf "$TMP_DIR/bashbook"

echo "  OK __file__ self-location (all platforms)"

NON_GIT="$TMP_DIR/non-git-story-project"
NON_GIT_HOOK="$NON_GIT/.codex/hooks/story_codex_hook.py"
mkdir -p "$NON_GIT/.codex/hooks" "$NON_GIT/book" "$NON_GIT/nested/a/b"
cp "$HOOK_SRC" "$NON_GIT_HOOK"
cp "$HOOKS_SRC/run-story-hook.sh" "$HOOKS_SRC/run-story-hook.cmd" "$NON_GIT/.codex/hooks/"
cp "$REPO_ROOT/skills/story-setup/references/codex/hooks/hooks.json" "$NON_GIT/.codex/hooks.json"
: > "$NON_GIT/book/设定.md"
launcher_cmd="$(
  NON_GIT="$NON_GIT" python3 - <<'PY'
import json, os
from pathlib import Path
hooks = json.loads((Path(os.environ["NON_GIT"]) / ".codex/hooks.json").read_text(encoding="utf-8"))
print(hooks["hooks"]["PreToolUse"][0]["hooks"][0]["command"])
PY
)"
out="$(
  cd "$NON_GIT/nested/a/b"
  printf '{"tool_name":"Write","tool_input":{"file_path":"book/正文.md","content":"正文"}}' | eval "$launcher_cmd"
)"
assert_denied "$out" "non-git deployment launcher root search"

echo "  OK non-git deployment launcher root search"

# Root propagation: non-git project, 小节大纲.md PRESENT at the true root, triggered from a nested
# cwd → must ALLOW. The launcher resolves the root in shell; it must reach the Python hook
# (via CODEX_PROJECT_DIR and/or the hook self-locating from __file__) instead of Python falling
# back to the nested cwd and wrongly denying. This case also exercises Windows (Git Bash MSYS
# path passed to native Python), which is exactly where naive env/cwd propagation breaks.
: > "$NON_GIT/book/小节大纲.md"
out="$(cd "$NON_GIT/nested/a/b"; unset CODEX_PROJECT_DIR CLAUDE_PROJECT_DIR; printf '{"tool_name":"Write","tool_input":{"file_path":"book/正文.md","content":"正文"}}' | eval "$launcher_cmd")"
assert_empty "$out" "non-git nested cwd + outline present allows (root reaches Python hook)"
rm -f "$NON_GIT/book/小节大纲.md"

echo "  OK non-git nested root propagation"

case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*)
    NON_GIT="$NON_GIT" python3 - <<'PY'
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["NON_GIT"])
hooks = json.loads((root / ".codex/hooks.json").read_text(encoding="utf-8"))["hooks"]
command = hooks["PreToolUse"][0]["hooks"][0]["commandWindows"]
# bytes literals must be ASCII (b'中文' is a SyntaxError); build the str, then encode to UTF-8.
payload = '{"tool_name":"Write","tool_input":{"file_path":"book/正文.md","content":"正文"}}'.encode("utf-8")
completed = subprocess.run(
    command,
    cwd=root / "nested/a/b",
    input=payload,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    shell=True,
    timeout=20,
)
assert completed.returncode == 0, completed.stderr.decode("utf-8", "replace")
output = completed.stdout.decode("utf-8")
data = json.loads(output)
specific = data.get("hookSpecificOutput", {})
assert specific.get("permissionDecision") == "deny", output
PY
    echo "  OK commandWindows nested root + interpreter launcher"
    ;;
esac

# Missing deployment: a cwd whose ancestors have no .codex/hooks/story_codex_hook.py → the
# launcher must no-op (exit 0) silently, NOT run "//.codex/hooks/story_codex_hook.py" (which
# happens if it treats "/" as the project root after an exhausted upward search).
NO_DEPLOY="$TMP_DIR/no-deploy/x/y"
mkdir -p "$NO_DEPLOY"
out="$(cd "$NO_DEPLOY"; unset CODEX_PROJECT_DIR CLAUDE_PROJECT_DIR; printf '{"tool_name":"Write","tool_input":{"file_path":"book/正文.md","content":"正文"}}' | eval "$launcher_cmd" 2>&1)"
assert_empty "$out" "missing deployment launcher no-ops silently"
case "$out" in *//.codex*) fail "launcher executed //.codex/... on missing deployment: $out";; esac

echo "  OK missing-deployment launcher no-op"
echo ""
echo "OK: Codex hook synthetic tests passed"
