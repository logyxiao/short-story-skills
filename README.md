# oh-story-claudecode

短篇网络小说写作 skill 包：**扫榜 → 拆文 → 写作 → 去AI味 → 审查** 全流程。运行在 **Codex CLI** 上，默认由 Codex 的默认 agent 直接执行（solo），无需部署 custom agents，零配置即可用。

## 执行模型

- **默认 agent（solo）**：架构、角色、文笔、一致性等专业分工由同一个 agent 按 skill 内的角色指引在同一会话内依次完成。
- **可选多 Agent**：需要多视角并行时（如 `story-review` 的 full/lean），可自行部署 5 个 custom agents（`story-architect` / `character-designer` / `narrative-writer` / `consistency-checker` / `story-researcher`）到 `.codex/agents/*.toml`，新开 Codex 会话后生效；未部署时所有 skill 自动以默认 agent 执行并报告 `Fallback: ... -> solo`。
- **Codex hooks**：`$story-setup` 部署 6 组事件守卫（写正文前大纲校验、压缩前后上下文快照、Stop 兜底扫描），保护写作流程。

## 核心思路

> **套路 = 确定性的情绪满足**

1. **扫榜**：分析热门榜单，洞察题材、人设、切入点。
2. **拆文**：拆解大纲节奏与剧情素材，建立个人模块库。
3. **商业化写作**：学习并运用钩子、爽感、期待感等核心技巧。

围绕四条线展开：爆款逆向 · 剧情模块化重组 · 上下文状态分层管理 · 人机协同。

**适用平台**：知乎盐言故事 · 番茄短篇 · 七猫短篇

## 流程总览

```mermaid
flowchart LR
    entry{{"短篇作者"}} --> setup["$story-setup 环境部署"]
    setup --> scan["$story-short-scan 扫榜选材"]
    scan --> analyze["$story-short-analyze 拆文学习"]
    analyze --> write["$story-short-write 落笔创作"]
    write --> deslop["$story-deslop 去AI味"]
    deslop --> review["$story-review 多视角审查"]
```

## 安装

```bash
npx skills add worldwonderer/oh-story-claudecode -y -g
```

`-g` 全局安装，所有目录可用；去掉 `-g` 只装到当前目录。更新时重新执行同一条命令。

**Codex 使用**：Codex 扫描 `$REPO_ROOT/.agents/skills`（指向 `skills/` 的 symlink）发现 7 个 skill；用 `$story-*`、`/skills` 或自然语言调用。Windows 上 git 需开 `core.symlinks=true`，否则 symlink 失效。

**部署到写作项目**：在写作项目根运行 `$story-setup`，部署 `.codex/hooks.json`、`.codex/hooks/`、`AGENTS.md` 路由与 `.codex/skills/story-setup/references/agent-references/` 知识库副本；信任项目 `.codex/` 配置层并在 `/hooks` review/trust hooks。升级后建议重跑 `$story-setup` 同步 hooks / references。

## Skills

| Skill | 触发 | 说明 |
|:------|:-----|:-----|
| `story-setup` | `$story-setup` `/准备写书` | 环境部署 · Codex hooks + AGENTS 路由 + 知识库 |
| `story` | `$story` `$story dashboard` | 工具箱路由 · 模糊意图分发 + 本地拆文/项目 Dashboard |
| `story-short-write` | `$story-short-write` | 短篇写作 · 情绪设计、反转构思、精修出稿 |
| `story-short-analyze` | `$story-short-analyze` | 短篇拆文 · 故事核、结构、情感线、反转设计、写作手法、共鸣 |
| `story-short-scan` | `$story-short-scan` | 短篇扫榜 · 知乎盐言/番茄短篇风口数据（CDP 采集） |
| `story-deslop` | `$story-deslop` `/去AI味` | 去AI味 · 检测并清除 AI 写作痕迹 |
| `story-review` | `$story-review` `/审查` | 多视角审查 · 架构/角色/文笔/一致性 4 视角 + 番茄/起点/知乎评分标准 |

> `story-deslop` 的本地检查是写作 lint：blocking 只限确定性句式/标点问题，其他提示按读感判断；朱雀等外部检测只作自测参考，不替代人工读感。

自然语言同样触发：「这篇太 AI 了」→ deslop，「打开工作台」→ `$story dashboard`（本机浏览小说工作室中的拆书与正文项目，可轻量编辑）。

## 自动化 Hooks（Codex）

`$story-setup` 部署的 hooks（`.codex/hooks.json` + Python 实现）：

| Hook 事件 | 功能 |
|:----------|:-----|
| SessionStart | 显示书目与拆文状态快照 |
| PreToolUse（Write/Edit/Bash） | 写正文前大纲守卫：缺 `小节大纲.md` 时阻断首次创建正文；命令目标提取与 commit 侦测 |
| PreCompact / PostCompact | 压缩前保存进度快照路径、压缩后提示恢复 |
| Stop | 正文兜底扫描（截断、工程词、毒句式） |

## 项目文件结构

短篇虽短，设定、结构、情绪曲线同样要落到文件里，别靠对话记忆硬撑。

**短篇：**

```
小说工作室/
├── 拆书/{书名}/        # 拆书源数据（analyze 产出）
└── 正文/{标题}/
    ├── 设定.md         # 题材定位、角色设定、反转铺垫、贯穿道具、对标摘要
    ├── 小节大纲.md     # 每节 1 行轻量蓝图 + 情绪曲线
    ├── 正文.md         # 完成稿（单文件，不切章）
    └── 对标/{书名}/    # 如有参考小说（analyze 输出）
        ├── 拆文报告.md
        ├── 情节节点.md
        └── 写作手法.md
```

`story-setup` 会创建 `小说工作室/正文/`、`小说工作室/拆书/`，并把这两个生成内容目录加入项目根 `.gitignore`，避免测试小说混入代码变更。

`.active-book`：项目根目录的文本文件，内容为当前活跃书目的相对路径（如 `小说工作室/正文/我的小说`），hook 与写作 skill 据此定位当前项目。

## 知识体系

各 skill 自带 `references/` 知识库，按需加载，不占上下文。覆盖：大纲排布、开头设计、人物设计、钩子技法、情绪设计、题材框架、对话技法、反转工具箱、去AI味、质量检查、写作公式、女频写作、拆文方法、短篇方法论、市场数据、多视角审稿等。

## 真实输出样例

`demo/` 下有完整示例：拆文《曾将爱意私藏》（约 8500 字短篇的 拆文报告 / 情节节点 / 写作手法 全量输出）与 Dashboard 截图。

---

交流与反馈：GitHub Discussions（<https://github.com/worldwonderer/oh-story-claudecode/discussions>）。
