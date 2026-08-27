#!/usr/bin/env bash
# check-codex-adapter.sh — deterministic checks for the Codex adapter surface.
#
# Codex support here is repo skill discovery (.agents/skills symlink) plus
# `$story-setup` project deployment (.codex/hooks. hooks + AGENTS.md + knowledge base).
# 本包默认不部署 custom agents；各 skill 由默认 agent 直接执行。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "required file missing: $1"; }
assert_path() { [ -e "$1" ] || fail "required path missing: $1"; }
assert_grep() { grep -Eq "$1" "$2" || fail "$3 ($2)"; }

cd "$REPO_ROOT"

echo "Codex adapter check"
echo "==================="
echo "Repo: $REPO_ROOT"

CODEX_DIR="skills/story-setup/references/codex"
assert_path ".agents/skills"
assert_file "$CODEX_DIR/AGENTS.md.tmpl"
assert_file "$CODEX_DIR/hooks/hooks.json"
assert_file "$CODEX_DIR/hooks/story_codex_hook.py"
assert_file "$CODEX_DIR/hooks/run-story-hook.sh"
assert_file "$CODEX_DIR/hooks/run-story-hook.cmd"
assert_file "scripts/generate-codex-hooks.py"
assert_file "scripts/test-codex-hook-merge.py"
assert_file "skills/story-setup/scripts/merge-codex-hooks.py"

python3 -m json.tool "$CODEX_DIR/hooks/hooks.json" >/dev/null
python3 - <<'PY'
from pathlib import Path
for name in (
    'scripts/generate-codex-hooks.py',
    'skills/story-setup/references/codex/hooks/story_codex_hook.py',
):
    compile(Path(name).read_text(encoding='utf-8'), name, 'exec')
PY
python3 scripts/generate-codex-hooks.py --check
python3 scripts/test-codex-hook-merge.py

echo "  OK JSON/Python syntax"

# Windows encoding safety (issue #164 class): the hook carries Chinese 正文/细纲 over
# stdin/stdout, so it must use UTF-8 bytes, not Windows' ANSI code page text streams.
HOOK_PY="$CODEX_DIR/hooks/story_codex_hook.py"
# Walk the AST instead of grepping lines. A line-based read_text(/encoding= pair fails both ways:
# it reports a regression against a correct call wrapped over two lines (or against a comment that
# merely mentions .read_text()), and it accepts `p.read_text() + p.read_text(encoding="utf-8")[:0]`
# because the encoding token is somewhere on the line. The AST sees calls, never comments.
python3 - "$HOOK_PY" <<'PY'
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
tree = ast.parse(path.read_text(encoding="utf-8"), str(path))


def dotted(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


required = {"sys.stdin.buffer.read", "sys.stdout.buffer.write"}
seen = set()
problems = []
for node in ast.walk(tree):
    if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
        continue
    name = dotted(node.func)
    if name in required:
        seen.add(name)
    if name in ("sys.stdin.read", "sys.stdout.write"):
        problems.append(f"line {node.lineno}: text-mode {name}() (Windows ANSI hazard)")
    if node.func.attr == "read_text" and not any(kw.arg == "encoding" for kw in node.keywords):
        problems.append(f"line {node.lineno}: read_text() without encoding='utf-8' (Windows ANSI hazard)")
for name in sorted(required - seen):
    problems.append(f"missing UTF-8 byte stdio call: {name}()")
if problems:
    raise SystemExit("FAIL: Codex hook Windows encoding safety (issue #164):\n  " + "\n  ".join(problems))
PY

echo "  OK Windows encoding safety (UTF-8 stdio + file reads)"

# Prose backstop parity surface: Codex has no PostToolUse, so the light prose net runs at Stop
# (sweeping git-changed 正文). These must stay present.
assert_grep 'def prose_net_findings' "$HOOK_PY" "Codex hook must carry the light prose net"
assert_grep 'def find_changed_prose_files' "$HOOK_PY" "Codex Stop sweep must discover git-changed prose"

echo "  OK prose backstop parity surface (Stop net)"

# .agents/skills is a relative symlink to skills/ (the agentskills.io path Codex scans), so
# there is no second skill copy. Must be a valid relative symlink: an invalid/absolute one
# (openai/codex#11314) or a Windows no-symlinks text stub silently breaks discovery.
[ -L ".agents/skills" ] || fail ".agents/skills must be a symlink (got a regular file/dir; on Windows enable git core.symlinks)"
target="$(readlink .agents/skills)"
[ "$target" = "../skills" ] || fail ".agents/skills symlink target must be relative '../skills', got '$target'"
skill_count="$(find skills -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
[ "$skill_count" = "7" ] || fail "expected 7 skills, found $skill_count"
for skill in skills/*/SKILL.md; do
  name="$(basename "$(dirname "$skill")")"
  assert_file ".agents/skills/$name/SKILL.md"
done

echo "  OK .agents/skills discovery symlink ($skill_count skills)"


# The generated registration owns only root lookup + event routing. Interpreter probing and
# hook dispatch live in one launcher per platform instead of being copied into six JSON commands.
assert_grep 'for candidate in python3 python py' "$CODEX_DIR/hooks/run-story-hook.sh" "POSIX launcher must probe Python interpreters"
assert_grep 'for %%P in \(python3 python py\) do' "$CODEX_DIR/hooks/run-story-hook.cmd" "Windows launcher must probe the current interpreter list"
assert_grep 'set "PYBIN=%%P"' "$CODEX_DIR/hooks/run-story-hook.cmd" "Windows launcher must retain the first working interpreter"
if grep -q 'git rev-parse' "$CODEX_DIR/hooks/hooks.json" "$CODEX_DIR/hooks/run-story-hook.sh" "$CODEX_DIR/hooks/run-story-hook.cmd"; then
  fail "deployment hooks must not require git to launch story_codex_hook.py"
fi

# Every launcher must (a) propagate the resolved root to Python (CODEX_PROJECT_DIR=$PROJECT_ROOT)
# and (b) no-op when the hook file is absent instead of running "//.codex/..." (root="/"). And
# the Python hook must self-locate from __file__ so a Git Bash MSYS root still resolves on Windows.
#
# 每份注册的 event token 还必须与三个消费方的白名单逐一对齐：run-story-hook.sh 的 case、
# run-story-hook.cmd 的 if /I 链、story_codex_hook.py main() 的分派。少一处就是一个永久哑火的
# hook（launcher case 落到 *) exit 2，stdout/stderr 全空），而 command↔commandWindows 的一致性
# 断言只证明两边抄的是同一个错字。白名单从三个消费方解析出来比较，不在这里再抄第五份。
python3 - "$CODEX_DIR/hooks/hooks.json" "$CODEX_DIR/hooks/story_codex_hook.py" \
  "$CODEX_DIR/hooks/run-story-hook.sh" "$CODEX_DIR/hooks/run-story-hook.cmd" <<'PY'
import json, re, sys
from pathlib import Path
hooks = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hooks"]
all_hooks = [h for arr in hooks.values() for blk in arr for h in blk["hooks"]]
assert all_hooks, "no launcher commands found"
registered = []
for h in all_hooks:
    c = h["command"]
    assert '.codex/hooks/run-story-hook.sh' in c, f"POSIX command must route through the shared launcher: {c}"
    assert 'python3 python py' not in c and 'story_codex_hook.py' not in c, f"registration duplicated launcher logic: {c}"
    w = h.get("commandWindows")
    assert w, f"hook missing commandWindows (Windows = cmd.exe /C): {c[:60]}"
    assert "run-story-hook.cmd" in w and "powershell -NoProfile" in w, f"Windows command must locate the shared launcher: {w}"
    assert "story_codex_hook.py" not in w and "python3" not in w, f"Windows registration duplicated launcher logic: {w}"
    posix_event = c.rsplit(" ", 1)[-1]
    assert f"'{posix_event}'" in w, f"command/commandWindows event mismatch: {posix_event} vs {w}"
    registered.append(posix_event)

# 同一个 handler 被注册两次 = 复制粘贴整块后忘了改 event token，另一个事件因此没有注册。
dupes = sorted({e for e in registered if registered.count(e) > 1})
assert not dupes, f"hooks.json registers the same event token more than once: {dupes}"

launcher_sh = Path(sys.argv[3]).read_text(encoding="utf-8")
launcher_cmd = Path(sys.argv[4]).read_text(encoding="utf-8")
hook_py = Path(sys.argv[2]).read_text(encoding="utf-8")

# 只在 case "$EVENT" in ... esac 这一段里收 arm，且把每个 arm 的 a|b|c 全部展开：
# 别的 case 块（比如探测 PYBIN）不会污染白名单，名单被改写成一行一个 arm 也照样解析。
case_block = re.search(r'case[ \t]+"\$EVENT"[ \t]+in(.*?)esac', launcher_sh, re.S)
assert case_block, 'run-story-hook.sh must gate "$EVENT" with a case allowlist'
sh_tokens = set()
for arm in re.findall(r'^[ \t]*([a-z0-9|-]+)\)', case_block.group(1), re.M):
    sh_tokens.update(arm.split("|"))
allowed = {
    "run-story-hook.sh": sh_tokens,
    "run-story-hook.cmd": set(re.findall(r'"%EVENT%"=="([a-z0-9-]+)"', launcher_cmd)),
    "story_codex_hook.py": set(re.findall(r'event == "([a-z0-9-]+)"', hook_py)),
}
for name, tokens in allowed.items():
    assert tokens, f"{name}: no event allowlist found (the parser or the file shape changed)"
    assert tokens == set(registered), (
        f"event token drift between hooks.json and {name}: "
        f"registered-only={sorted(set(registered) - tokens)}, {name}-only={sorted(tokens - set(registered))}"
    )

assert "Path(__file__)" in hook_py and "_deployed_root_from_file" in hook_py, \
    "story_codex_hook.py must self-locate the project root from __file__ (Windows MSYS-path safety)"
PY

echo "  OK generated launcher routing + Python self-location + cmd.exe commandWindows"

# Reference-path contract: generated Codex agents use only the bundle story-setup deploys.
python3 - "$CODEX_DIR/agents" <<'PY'
import sys
from pathlib import Path
for path in sorted(Path(sys.argv[1]).glob("*.toml")):
    text = path.read_text(encoding="utf-8")
    if "1. `{项目根}/" not in text:
        continue  # this agent has no numbered reference list
    assert text.count("1. `{项目根}/.codex/skills/story-setup/references/agent-references/") == 1, \
        f"{path.name}: numbered reference list must contain the canonical Codex path once"
    for stale in ("{项目根}/skills/story-setup/references/agent-references/"):
        assert stale not in text, f"{path.name}: stale cross-CLI reference fallback {stale}"
PY

echo "  OK Codex agent canonical reference path"

assert_grep '\$story-setup|\$story-short-write|/skills' "$CODEX_DIR/AGENTS.md.tmpl" "Codex AGENTS template must mention skill invocation"
assert_grep '\.codex/hooks\.json' "$CODEX_DIR/AGENTS.md.tmpl" "Codex AGENTS template must mention hooks location"
assert_grep 'references/codex' skills/story-setup/SKILL.md "story-setup must document Codex references"
assert_grep 'target_cli:.*codex|codex.*target_cli' skills/story-setup/SKILL.md "story-setup must document codex target_cli"

echo "  OK Codex docs/instruction anchors"
echo ""
echo "OK: Codex adapter checks passed"
