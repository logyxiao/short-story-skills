# oh-story-claudecode

A short-form web novel writing skill pack: **scan → deconstruct → write → de-AI-ify → review**, end to end. Built for the **Codex CLI** and runs on Codex's default agent (solo) — no custom agents to deploy, zero configuration.

## Execution model

- **Default agent (solo)**: architecture, character, prose, and consistency work is carried out sequentially in one session by the default agent, following the per-skill role guidance.
- **Optional multi-agent**: for parallel multi-perspective review (e.g. `story-review` full/lean), manually deploy the 5 custom agents (`story-architect` / `character-designer` / `narrative-writer` / `consistency-checker` / `story-researcher`) to `.codex/agents/*.toml` and open a fresh Codex session; without them every skill runs on the default agent and reports `Fallback: ... -> solo`.
- **Codex hooks**: `$story-setup` deploys 6 event guards (outline-before-prose on write, pre/post-compact context snapshots, Stop backstop scan).

## Core idea

> **Formula = deterministic emotional payoff**

1. **Scan**: analyze popular rankings to spot genres, characters, and entry points.
2. **Deconstruct**: break down outline rhythm and plot material into a personal module library.
3. **Commercial writing**: apply hooks, satisfaction, and anticipation mechanics.

Four threads: bestseller reverse-engineering · plot modular recomposition · layered context-state management · human-in-the-loop writing.

**Target platforms**: Zhihu Yanyan · Fanqie short-form · Qimao short-form

## Pipeline

```mermaid
flowchart LR
    entry{{"短篇作者"}} --> setup["$story-setup 环境部署"]
    setup --> scan["$story-short-scan 扫榜选材"]
    scan --> analyze["$story-short-analyze 拆文学习"]
    analyze --> write["$story-short-write 落笔创作"]
    write --> deslop["$story-deslop 去AI味"]
    deslop --> review["$story-review 多视角审查"]
```

## Install

```bash
npx skills add worldwonderer/oh-story-claudecode -y -g
```

`-g` installs globally (usable everywhere); drop it to install only into the current directory. Re-run the same command to update.

**Codex usage**: Codex scans `$REPO_ROOT/.agents/skills` (a symlink to `skills/`) and discovers the 7 skills; invoke via `$story-*`, `/skills`, or natural language. On Windows, enable git `core.symlinks=true` or the symlink breaks.

**Deploy into a writing project**: run `$story-setup` in the project root to deploy `.codex/hooks.json`, `.codex/hooks/`, the `AGENTS.md` routing table, and the knowledge-base copy at `.codex/skills/story-setup/references/agent-references/`; trust the project `.codex/` layer and review/trust hooks in `/hooks`. Re-run `$story-setup` after upgrading to sync hooks / references.

## Skills

| Skill | Trigger | Description |
|:------|:--------|:------------|
| `story-setup` | `$story-setup` | Environment setup · Codex hooks + AGENTS routing + knowledge base |
| `story` | `$story` `$story dashboard` | Toolbox router · fuzzy-intent dispatch + local deconstruction/writing Dashboard |
| `story-short-write` | `$story-short-write` | Short-form writing — emotion design, twist crafting, polish & delivery |
| `story-short-analyze` | `$story-short-analyze` | Short-form deconstruction — story core, structure, emotional arc, reversal design, writing techniques, resonance |
| `story-short-scan` | `$story-short-scan` | Short-form trend scan — Zhihu Yanyan/Fanqie trending data (CDP scraping) |
| `story-deslop` | `$story-deslop` | De-AI-ify — detect and remove AI writing traces |
| `story-review` | `$story-review` | Multi-perspective review — architecture/character/prose/consistency + Fanqie/Qidian/Zhihu rubrics |

> `story-deslop` uses local prose linting: blocking applies only to deterministic style/punctuation issues; other findings require read-through judgment. External detectors such as Zhuque are self-check references, not replacements for human review.

Natural language also triggers: 「这篇太 AI 了」→ deslop, 「打开工作台」→ `$story dashboard` (browse the deconstruction library and writing projects locally, with light editing).

## Automation Hooks (Codex)

Deployed by `$story-setup` (`.codex/hooks.json` + Python implementation):

| Hook event | Function |
|:-----------|:---------|
| SessionStart | Shows the active book and deconstruction status snapshot |
| PreToolUse (Write/Edit/Bash) | Outline-before-prose guard: blocks first-time `正文.md` creation without `小节大纲.md`; command-target extraction and git-commit detection |
| PreCompact / PostCompact | Saves progress-snapshot paths before compaction; prompts to restore after |
| Stop | Prose backstop scan (truncation, engineering words, toxic phrasing) |

## Project file structure

Keep setting, structure, and emotional arc in files, not conversation memory.

**Short-form:**

```
小说工作室/
├── 拆书/{书名}/        # deconstruction source data (analyze output)
└── 正文/{标题}/
    ├── 设定.md         # genre positioning, characters, reversal setup, props, benchmark summary
    ├── 小节大纲.md     # one-line-per-section lightweight blueprint + emotional arc
    ├── 正文.md         # finished prose (single file, no chapter split)
    └── 对标/{书名}/    # reference analysis if any (analyze output)
        ├── 拆文报告.md
        ├── 情节节点.md
        └── 写作手法.md
```

`story-setup` creates `小说工作室/正文/` and `小说工作室/拆书/`, then adds both generated-content directories to the project-root `.gitignore` so test manuscripts do not appear in code changes.

`.active-book`: a text file in the project root holding the relative path of the active book (e.g. `小说工作室/正文/我的小说`); hooks and writing skills locate the current project from it.

## Knowledge base

Each skill ships a `references/` library loaded on demand, never preloaded into context: outline layout, opening design, character design, hook techniques, emotion design, genre frameworks, dialogue craft, reversal toolkit, de-AI-ify, quality checks, writing formulas, women's-fiction writing, deconstruction methods, short-form methodology, market data, multi-perspective review, etc.

## Sample outputs

`demo/` contains full examples: the deconstruction of 《曾将爱意私藏》(an ~8500-word short story: deconstruction report / plot beats / writing techniques) and a Dashboard screenshot.

---

Feedback: GitHub Discussions (<https://github.com/worldwonderer/oh-story-claudecode/discussions>).
