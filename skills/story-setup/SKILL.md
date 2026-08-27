---
name: story-setup
version: 1.2.8
description: "网文写作工具集基础设施部署。为 Codex 提供内置适配（hooks + AGENTS.md + 知识库）；默认不部署 custom agents，全部工作由默认 agent 直接执行。触发方式：/story-setup、$story-setup、「准备写书」「帮我搭一下环境」「配置写作项目」。"
metadata: {"openclaw":{"source":"https://github.com/worldwonderer/oh-story-claudecode"}}
---
# story-setup：环境部署

把本工具集部署到你的写作项目：Codex hooks（写正文流程守卫）、路由用的 `AGENTS.md`、共享知识库副本。**不部署 custom agents**——所有 skill 由默认 agent 直接执行（solo 模式）；如需多 agent 协作，可自行部署 `.codex/agents/*.toml` 后再用。

## Phase 1：检测项目状态

**先自检参考目录**：以正在执行的本 `SKILL.md` 所在目录为准，列出与它同级的 `references/` 下的子目录，核对下面 2 个名字是否都在**且都非空**——`agent-references`、`codex`；同级 `scripts/merge-codex-hooks.py` 必须存在（Codex hooks 合并算法依赖它）。有缺即 skill 包没装全，**立即停止，不写任何部署文件**，报告「story-setup 参考资料包不完整，缺 {目录名}」，修复指令：按你的安装方式重装 oh-story-claudecode（命令行装的重跑 `npx skills add worldwonderer/oh-story-claudecode -y -g`），再执行 `$story-setup`。

1. 检查当前目录是否已部署过（存在 `.story-deployed`）
   - `agents_version` 缺失、非整数或小于 `26` → 标记为待更新，继续执行当前部署
   - `agents_version: 26` → 使用 AskUserQuestion 确认是否重新部署；重新部署只用**当前本地 skill 包**刷新项目文件，要拿 skill 本身的新版本得先更新 oh-story-claudecode，再回来重跑
   - `agents_version` 大于 `26` → 当前 story-setup 比项目部署旧；停止以避免降级覆盖，提示先更新 oh-story-claudecode
2. 检查是否有书名目录（短篇信号：目录内含 `正文.md` 文件，或用户自定义结构）
   - 有 → 识别为短篇项目，显示当前项目信息
   - 无 → 识别为新项目
3. 检查 `.codex/`、`.codex/config.toml`、`.codex/hooks.json`、`AGENTS.md` 中的 Codex 段
   - 存在 → 识别为 Codex 项目，`target_cli = codex`
   - 不存在 → 跳过
4. 全新项目 → `target_cli = codex`（本工具集仅做 Codex 适配）。

## Phase 2：部署基础设施

使用 AskUserQuestion 确认部署位置后，依次执行。整个 Phase 2 幂等：目录复制、文件写入和合并算法重复执行结果一致。因环境原因中途失败时，直接从头重跑本 Phase，不需要先清理半成品。

### Step 1：部署清单（机械可检查）

| Source path | Target path | Owner class | Merge mode | Validation check |
|-------------|-------------|-------------|------------|------------------|
| `skills/story-setup/references/codex/AGENTS.md.tmpl` | `AGENTS.md` | user+managed | marker/section merge | contains Codex story skill routing sections |
| `skills/story-setup/references/codex/hooks/hooks.json` | `.codex/hooks.json` | user+managed | replace managed registrations by stable hook identity | hook JSON valid; all stale direct/launcher registrations removed, current 6 registrations present exactly once |
| `skills/story-setup/references/codex/hooks/{story_codex_hook.py,run-story-hook.sh,run-story-hook.cmd}` | `.codex/hooks/` 同名文件 | story-setup managed | replace | Python/shell/cmd launcher 文件齐全 |
| `skills/story-setup/scripts/merge-codex-hooks.py` | 部署时执行，不复制到项目 | story-setup helper | execute | 替换已知管理注册、保留用户 hooks 与未知顶层字段，结果幂等 |
| `skills/story-setup/references/agent-references/*.md` | `.codex/skills/story-setup/references/agent-references/*.md` | story-setup managed | replace | every `story-setup/references/agent-references/*.md` reference resolves |
| generated sentinel | `.story-deployed` | story-setup managed | replace | contains `agents_version`, `setup_skill_version`, `target_cli`, `resolver_strategy`, `references_dir` |

### Step 2：部署 AGENTS.md

- 读取 `skills/story-setup/references/codex/AGENTS.md.tmpl`
- 替换占位符（见「模板占位符」段）
- 写入项目根目录 `AGENTS.md`（如已存在，按「AGENTS.md 合并策略」处理）

### Step 3：部署 Codex Hooks

- 将 `references/codex/hooks/hooks.json` 通过 `merge-codex-hooks.py` 合并进项目 `.codex/hooks.json`（见「Codex hooks.json 合并算法」）。
- 复制 `references/codex/hooks/story_codex_hook.py`、`run-story-hook.sh`、`run-story-hook.cmd` 到项目 `.codex/hooks/`。
- 提示用户：项目 `.codex/` 配置层需要被 Codex trust；非 managed command hooks 还需在 `/hooks` review/trust 后运行。

### Step 4：部署 Agent References 知识库

- 将 `skills/story-setup/references/agent-references/` 下所有 `.md` 复制到项目内 `.codex/skills/story-setup/references/agent-references/`
- 校验：凡 skill 或 reference 中出现 `story-setup/references/agent-references/<file>.md`，源包与目标包都必须存在 `<file>.md`

> 各 skill 引用的参考资料一律走这份部署到 `.codex/skills/story-setup/references/agent-references/` 的副本路径；不要跨 skill 引用其他 skill 的 references，也不要手工复制 `references/` 到别处——手工副本不受 story-setup 管理，升级后会静默变旧。

### Step 5：创建部署标记

- 创建 `.story-deployed` 文件（sentinel file），写入以下字段（YAML `key: value` 格式）：
  ```
  deployed_at: <date -u +"%Y-%m-%dT%H:%M:%SZ">
  agents_version: 26
  setup_skill_version: 1.2.8
  target_cli: codex
  resolver_strategy: project-local-skill-reference
  references_dir: .codex/skills/story-setup/references/agent-references
  ```
- 此文件供 session-start.sh 与写作 skill 检测部署状态，避免重复提示
- 若 `.story-deployed` 已存在但 `agents_version` 缺失、非整数或小于 `26`，按本次流程更新 hooks/reference bundle；大于 `26` 时已在 Phase 1 停止，不得降级覆盖

### Codex hooks.json 合并算法

Codex 项目 hooks 部署到 `.codex/hooks.json`；运行脚本部署到 `.codex/hooks/story_codex_hook.py`、`run-story-hook.sh`、`run-story-hook.cmd`。JSON 只负责定位项目根与传递 event，解释器探测与事件处理由复制到 `.codex/hooks/` 的 launcher 统一完成。

1. 定位当前 story-setup skill 目录，读取 `references/codex/hooks/hooks.json` 作为唯一当前模板；读取项目 `.codex/hooks.json`（不存在时视为空对象）。
2. 按现有跨平台规则探测可用 Python：`for PYBIN in python3 python py; do "$PYBIN" -c "" 2>/dev/null && break; done`；无可用解释器时停止，不手写或简化 JSON 合并。
3. 调用 `"$PYBIN" "{story-setup skill目录}/scripts/merge-codex-hooks.py" --existing "{项目}/.codex/hooks.json" --template "{story-setup skill目录}/references/codex/hooks/hooks.json" --output "{项目}/.codex/hooks.json"`。该 helper 会识别旧直调 `story_codex_hook.py`、当前 `run-story-hook.sh` 和 `run-story-hook.cmd` 三类管理身份，先移除所有已知管理注册，再追加当前模板。
4. 保留用户已有的非 story-setup hooks、matcher 块与未知顶层字段。重复执行必须幂等；禁止再按原始 `command` 字符串追加去重。
5. 写入后解析 JSON 验证：旧直调 `story_codex_hook.py` 命令数为 0，当前模板 6 个注册各存在且仅存在一次，用户 hook 与未知顶层字段仍在。Windows 下走 `commandWindows`，launcher 从当前目录向上定位项目 `.codex/hooks/`，与 POSIX 路径的嵌套目录行为一致。

## Phase 3：验证安装

1. 验证 hooks 注册：检查 `.codex/hooks.json` 存在且 JSON 有效，Unix `command` 仅通过 `run-story-hook.sh` 启动，Windows `commandWindows` 仅通过 `run-story-hook.cmd` 启动；不存在直调 `story_codex_hook.py` 的注册。
2. 验证 launcher：`.codex/hooks/story_codex_hook.py`、`run-story-hook.sh`、`run-story-hook.cmd` 存在，Python 语法有效，POSIX/Windows launcher 能从嵌套 cwd 定位项目根。
3. 验证 agent reference bundle：`.codex/skills/story-setup/references/agent-references/` 下 reference 文件完整且数量与源目录一致。
4. 验证部署标记：`.story-deployed` 存在且含时间戳、`agents_version: 26`、`setup_skill_version: 1.2.8`、`target_cli`、`resolver_strategy`、`references_dir`。
5. 输出安装报告：
   - 列出所有已部署的文件与注意事项（如已有配置已合并）
   - **Codex 注意项（必须醒目输出）**：项目 `.codex/` 配置层需要被 Codex trust，非 managed command hooks 还需在 `/hooks` review/trust；本工具集默认不部署 custom agents，各 skill 由默认 agent 直接执行（solo）。若你自行部署了 `.codex/agents/*.toml`，新开 Codex 会话让 custom agents 生效；当前运行时返回 `unknown agent_type` 时按各 skill 的 fallback 规则降级默认 agent。
   - 重启后即可使用 `/story-short-write`（Codex：`$story-short-write`）

---

## 模板占位符

| 占位符 | 替换规则 | 示例 |
|--------|----------|------|
| `{项目名}` | 用户项目名称或目录名 | 《剑来》、《暗卫》 |
| `{书名}` | 书名目录名（与目录一致） | 与 `{项目名}` 相同，或用户自定义 |
| `{目标平台}` | 目标发布平台 | 起点、番茄、晋江、知乎盐言 |
| `{作者名}` | 用户笔名或昵称 | 未指定时用「作者」 |

替换时去掉花括号。如果用户未指定项目名，用当前目录名。未指定的占位符保留原样不替换。

## AGENTS.md 合并策略（Codex）

用户已有 AGENTS.md 时，按 marker/section 合并：
1. 优先识别 story-setup 管理块标记（如果旧项目已有标记，只替换标记内内容）
2. 无标记时，读取用户现有 AGENTS.md，按 `##` 标题切分为 section map
3. 读取模板 `skills/story-setup/references/codex/AGENTS.md.tmpl`，同样切分
4. 模板中的标准 section（Skill 路由表、文件结构、协作规则、Compact 后恢复上下文）覆盖用户同名 section；用户独有 section 保留
5. 未知冲突用 AskUserQuestion 让用户选择保留哪个版本

## 重新部署

- `.story-deployed` 不存在 → 全新安装，Phase 2 全部执行
- `.story-deployed` 存在且 `agents_version: 26` → 提示已部署，AskUserQuestion 确认是否重新部署；重新部署只用当前本地 skill 包刷新项目文件
- `.story-deployed` 存在但 `agents_version` 缺失、非整数或小于 `26` → 提示需要更新，重新执行 Phase 2 覆盖 hooks/reference bundle，AGENTS.md / .codex/hooks.json 走合并策略
- `.story-deployed` 存在且 `agents_version` 大于 `26` → 当前 skill 版本过旧，停止并提示先更新 oh-story-claudecode；不覆盖项目中的更新部署

---

## 参考资料

| 文件 | 用途 |
|------|------|
| references/codex/AGENTS.md.tmpl | Codex 版项目 AGENTS 路由模板 |
| references/codex/hooks/ | hooks.json（事件注册）+ story_codex_hook.py（正文网/大纲守卫/commit 侦测）+ run-story-hook 启动器 |
| references/agent-references/ | 各 skill 引用的共享知识库（写作方法论、审查 rubric），部署到项目 `.codex/skills/story-setup/references/agent-references/` |

---

## 流程衔接

**流水线：** 部署
**位置：** 初始化（最前置）

| 时机 | 跳转到 | 命令 |
|---|---|---|
| 部署完成，开始写作 | story-short-write | `/story-short-write` |