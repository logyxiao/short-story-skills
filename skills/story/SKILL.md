---
name: story
description: "网络小说工具箱主入口。根据用户需求自动路由到对应 skill，并可启动本地 Dashboard 查看小说工作室中的拆书库、正文项目和编辑文本。触发方式：/story、$story、/story dashboard、$story dashboard、/网文、「我想写小说」「打开工作台」「检查更新」。"
metadata: {"openclaw":{"source":"https://github.com/worldwonderer/oh-story-claudecode"}}
---
# story：网文工具箱路由

你是网文工具箱的路由入口。用户的请求模糊时由你分发到具体 skill。

## 路由表

> Codex CLI 中优先使用 `$story-*` 或 `/skills` 触发；Claude Code 使用 `/story-*`。下表以 slash command 展示，Codex 可将 `/story-short-write` 等价替换为 `$story-short-write`。

| 用户意图 | 关键词示例 | 路由到 |
|---|---|---|
| 写短篇 | 短篇、盐言、一万字 | `/story-short-write` |
| 短篇拆文 | 拆短篇、分析这个故事 | `/story-short-analyze` |
| 短篇扫榜 | 短篇排行、知乎盐言排行 | `/story-short-scan` |
| 去 AI 味 | 去 AI 味、太 AI、去味 | `/story-deslop` |
| 审查稿件 | 审查、审稿、帮我审一下、一致性检查、看看有没有问题 | `/story-review` |
| 环境部署 | 准备写书、搭环境、初始化 | `/story-setup` |
| 工作台 | dashboard、工作台、看拆书库、浏览项目文件、打开项目面板 | 见下方「Dashboard 工作台」 |
| 检查/更新版本 | 检查更新、有新版本吗、升级、更新工具箱 | 见下方「版本更新检查」 |
| 切换/列出书目 | 切书、换书、列出我的书、我在写哪几本、切换项目 | 见下方「多书切换」 |
| 查故事资料 | 查角色、查伏笔、查进度、查设定、什么状态、写到哪了 | 主线程直接用 Read/Grep 从项目文件检索（见下方「查询降级」） |
| 查资料 | 查资料、帮我查资料、调研、搜索一下、搜一下 | spawn `story-researcher` agent；agent 不可用时见下方「查询降级」 |

## Dashboard 工作台

用户执行 `/story dashboard`（Codex 为 `$story dashboard`），或明确说“打开工作台 / 看项目
文件”时，直接启动随本 skill 分发的本地 Dashboard，不再转发到其他 skill：

1. 把**当前工作目录**作为默认工作区；用户明确给出目录时改用该目录。目录必须存在。
2. 从当前已加载的 `story` skill 目录定位 `scripts/dashboard-server.mjs`，不要硬编码仓库路径、
   全局 skill 路径或用户主目录。
3. 检查 `node` 可用后，以长运行进程执行：

   ```bash
   node "<story-skill-dir>/scripts/dashboard-server.mjs" --root "<workspace>" --open
   ```

4. 等待输出出现“本机地址”，把完整 URL 回给用户。工具支持后台进程/PTY 时让服务保持运行；
   无法自动拉起浏览器不算失败，仍返回可点击 URL。
5. Dashboard 默认只监听 `127.0.0.1`。不要主动增加 `--allow-network`，不要把工作区暴露到
   局域网或公网。

工作台只扫描统一工作室结构：拆书项目位于 `小说工作室/拆书/{书名}/`；写作项目位于 `小说工作室/正文/{书名}/`，目录内含普通文件 `正文.md`，并同时含 `小节大纲.md` 或 `设定.md`。

符号链接不作为项目标记，只有单个 `正文.md` 的普通资料目录也不会被误认。浏览器可编辑
`.md`、`.txt`、`.json`、`.yaml`、`.yml`、`.toml`，保存或确认删除前用修改时间防止
误操作外部更新。

停止服务时终止对应的 Node 长运行进程即可。若用户只问用法，不要替他启动；给出
`/story dashboard` / `$story dashboard` 两种平台对应入口。

## 路由流程

1. 分析用户请求，提取意图关键词
2. 匹配上表，找到对应的 skill
3. 如果能明确匹配，直接调用对应 skill（Claude 可用 `Skill("skill-name")` 或 slash command；Codex 用 `$skill-name` / `/skills`）
4. 如果无法匹配，询问用户想做什么（从上表中选择）
5. 如果用户说"我想写小说"，按短篇写作路由到 `/story-short-write`

## 查询降级

「查故事资料」「查资料」由默认 agent 在主会话直接用 Read/Grep 从项目文件检索（设定/进度/角色）。若在已手工部署 `.codex/agents/story-researcher.toml` 的 Codex 项目中且运行时暴露该 `agent_type`，可 spawn `story-researcher` 做资料研究；运行时返回 `unknown agent_type` / 未暴露 custom-agent registry 时降级为直接检索，回答前标注 `Fallback: agent unavailable -> direct lookup`。

## 项目状态感知

路由前先检查当前项目状态：

- **无项目目录**（`小说工作室/正文/` 下没有包含 `正文.md` 的书名目录）：
  - 如果用户要写作，下一步是先运行 `/story-setup` 初始化环境（Codex 中用 `$story-setup`）
  - 如果用户要扫榜/拆文，直接路由
- **已有项目**：检查 `.story-deployed` 标记，如未部署则先运行 `/story-setup`（Codex 中用 `$story-setup`）

## 多书切换

用户想切换或查看在写的书时（一个项目可同时有多本）：

1. 只在 `小说工作室/正文/` 下查找书目录：目录内包含普通文件 `正文.md`，并同时包含 `小节大纲.md` 或 `设定.md`。
2. 列出书名，并标出当前 `.active-book` 指向的那本。
3. 让用户选择，把所选书的相对路径写入项目根 `.active-book`（覆盖原内容）。
4. 只发现一本时直接确认为活跃书，无需询问。

## 版本更新检查

用户问"有没有新版本""检查更新""升级"时执行。**只通知，更不更新由用户定，不自动安装。**

1. **当前版本**：读本 skill 同目录的 `VERSION` 文件；缺失则视为未知。
2. **最新版本**：优先 `gh release view --json tagName,name,url -R worldwonderer/oh-story-claudecode` 取 `tagName`；无 gh 用 `curl -fsS --max-time 5 https://api.github.com/repos/worldwonderer/oh-story-claudecode/releases/latest` 取 `.tag_name`（jq 或 grep）。查不到 → 告知"暂时拉不到最新版本，可手动看 [Releases](https://github.com/worldwonderer/oh-story-claudecode/releases)"，不报错。
3. **比较**：去掉 `v` 前缀按语义版本比（major.minor.patch）。`gh release` 默认取 latest 稳定版，不含 pre-release。
4. **告知**：
   - 已最新 → 「已是最新版 vX.Y.Z」。
   - 有新版 → 列出 当前 vA → 最新 vB + [Releases](https://github.com/worldwonderer/oh-story-claudecode/releases)/[CHANGELOG](https://github.com/worldwonderer/oh-story-claudecode/blob/main/CHANGELOG.md)（能拿到 release notes 就附本次要点），再用 AskUserQuestion 问「现在更新吗？」：
     - 选更新 → 跑 `npx skills add worldwonderer/oh-story-claudecode -y -g`（`-g` 全局，去掉则只更当前目录）；完成后提示：已部署过的项目在项目根重跑 `/story-setup`（Codex 中用 `$story-setup`）同步 hooks/references。
     - 选先不 → 不动，告知随时可再来。
