# 升级指南

## 当前版本

- `setup_skill_version: 1.2.8`
- `agents_version: 26`

`.story-deployed` 缺失任一字段，或 `agents_version` 缺失 / 非整数 / 小于 `26`，都视为待更新部署。直接重新运行 `/story-setup`（Codex 用 `$story-setup`）；不在运行时逐级兼容历史模板。如项目 `agents_version` 大于 `26`，说明本地 story-setup 比项目旧：先更新 oh-story-claudecode，不得用 v26 降级覆盖。历史版本改动见仓库根目录 `CHANGELOG.md`。

## 升级策略

| 策略 | 适用场景 | 行为 |
|------|----------|------|
| 覆盖部署 | 全新项目 | 写入当前 agents/hooks/rules/reference bundle |
| 合并部署 | 已有项目 | 替换 story-setup 管理文件，合并用户维护文件 |
| 手动更新 | 只更新特定文件 | 仅建议熟悉部署契约的维护者使用 |

推荐始终重新运行 story-setup，让部署器按 owner class 处理文件。

## 文件所有权

### story-setup 管理，可替换

这些文件由 story-setup 管理，不含用户自定义内容：
- `.claude/hooks/` — 所有 hook 脚本与 `lib/` 辅助库
- `.claude/agents/` — 所有 agent 定义
- `.claude/rules/` — 所有 path-scoped 规则
- `.claude/skills/story-setup/references/agent-references/` — Agent 参考资料副本
- `.zcode/skills/{10 known skills}/`、`.zcode/commands/{10 known commands}.md` — 仅覆盖 oh-story 已知名称
- `.zcode/hooks/story_zcode_hook.js` — ZCode 专用 Hook runner

### 用户与 story-setup 共同维护，只合并管理块

这些文件可能含用户自定义内容：
- `CLAUDE.md` — 按 marker/section 合并，用户独有 section 保留
- `.claude/settings.local.json` — 按 command 识别 story hooks；已存在的受管 command 会迁移到当前模板的 event/matcher/timeout/if，其他用户 hook 与配置保留
- `AGENTS.md` — ZCode/OpenCode/Codex/OpenClaw/generic 按 marker/section 合并
- `.zcode/config.json` — 仅按事件、matcher 和 process args 去重合并 oh-story Hooks，其他字段保留

### 用户状态，不覆盖

- `{书名}/正文.md`、`{书名}/设定.md`、`{书名}/小节大纲.md`
- `{书名}/对标/`
- `.active-book`

## v26 当前契约（短篇-only）

- 本工具集已改为**纯短篇网文写作**：3 个长篇 skill（`story-long-scan` / `story-long-analyze` / `story-long-write`）与长篇追踪模型（`tracking_commit.py`、`追踪/` 目录、`validate-story-commit.sh`、`session-end.sh`）已整体移除；项目识别、hooks 守卫、agents、部署模板、Commands 全部按短篇工程（`正文.md` / `设定.md` / `小节大纲.md` / `对标/`）口径。
- 写正文前置守卫 `guard-outline-before-prose.sh` 只拦短篇首建 `正文.md` 缺 `小节大纲.md`；已存在的 `正文.md`（续写/改稿）放行。Bash 命令面复用共享 JS 核识别重定向 / `tee` / `touch` / `cp` / `mv` / `install` 写入正文；该面是**静态 best-effort 识别，不是 shell 沙箱**，且依赖 node，node/共享核异常时显式告警后 fail-open。
- 部署 agent 为 5 个：`story-architect`、`narrative-writer`、`character-designer`、`consistency-checker`、`story-researcher`（`chapter-extractor`、`story-explorer` 已随长篇移除）。
- 部署 hook 为 8 个：`session-start.sh`、`detect-story-gaps.sh`、`guard-outline-before-prose.sh`、`check-prose-after-write.sh`、`pre-compact.sh`、`post-compact.sh`、`story_hook_cli.js`、`story_hook_core.js`（+ `lib/`）；SessionEnd / commit 校验不再注册。
- 已部署的 v25 及更早项目重新部署时，旧的长篇 hooks（`validate-story-commit.sh`、`session-end.sh`）注册会被 merge 脚本按已知管理身份剥离，不残留指向已删文件的坏 hook。

重新部署后需**新开会话**，custom agent 与 hooks 才会重新注册。

## 升级步骤

1. 在项目根目录重新运行 story-setup。
2. 确认 `.story-deployed` 写入 `agents_version: 26` 与 `setup_skill_version: 1.2.8`。
3. 确认目标 CLI 的 agents、hooks/rules 和 reference bundle 都通过安装验证。
4. 新开会话，使 custom agents 与 hooks 按当前文件重新注册。
5. 若旧项目里残留长篇结构（`追踪/`、`正文/第N章_*.md`、`大纲/细纲_*`），不会被删除也不会参与短篇流程；短篇写作按 `正文.md` / `设定.md` / `小节大纲.md` 识别，可自行决定是否清理。

## 版本变更（历史）

### v25

- Claude Code 的正文前置守卫注册到 Bash；Codex Python 与共享 JS 的书目录发现统一限制为项目下 4 层；narrative-writer 增加 Gate B 引号口径。

### v24

- `.claude/rules/story-narrative.md` 删掉「禁止 AI 腔」红线块；`story-format.md` 对话标签规则改为「避免机械化」；`narrative-writer.md` 精简约 19%；`guard-outline-before-prose.sh` 补上长篇追踪检查点门（v26 已随长篇移除）。

### v23

- `story-import` 只重建写作工程、不再自动登记对标；agent 版本提示改为不阻断 spawn；拆文主产物缺失 fail-fast；细纲只接受完整章节蓝图（v26 已随长篇移除细纲契约，短篇用 小节大纲 轻量蓝图）。

### v22 及更早

- 长篇追踪单一权威事务模型、故事架构 Agent 演进、ZCode/OpenClaw/Reasonix/generic 适配等历史变更，见仓库根目录 `CHANGELOG.md`。v26 起上述长篇相关机制均已移除。
