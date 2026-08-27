import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const libraryRoot = "skills/story-short-write/references/example-library/甜宠";

async function read(relativePath) {
  return readFile(join(repositoryRoot, relativePath), "utf8");
}

test("sweet-romance example library covers all 44 source stories", async () => {
  const expectedByPlatform = new Map([
    ["未分类.md", 1],
    ["知乎.md", 5],
    ["番茄.md", 8],
    ["盐言.md", 30],
  ]);
  let total = 0;

  for (const [fileName, expected] of expectedByPlatform) {
    const contents = await read(`${libraryRoot}/${fileName}`);
    const cards = contents.split(/^## 《/m).slice(1);
    assert.equal(cards.length, expected, `${fileName} card count`);
    total += cards.length;

    for (const card of cards) {
      for (const field of [
        "平台",
        "原型定位",
        "导语摘要",
        "导语结构",
        "故事梗概",
        "可复用机制",
        "使用边界",
      ]) {
        assert.match(card, new RegExp(`^- ${field}：\\S`, "m"));
      }
    }
  }

  assert.equal(total, 44);
});

test("sweet-romance index exposes every card and retrieval safeguards", async () => {
  const index = await read(`${libraryRoot}/索引.md`);
  const rows = index
    .split("\n")
    .filter((line) => /^\|\s*\d+\s*\|/.test(line));

  assert.equal(rows.length, 44);
  assert.match(index, /A：与当前甜宠目标接近/);
  assert.match(index, /C：隔离素材或反例/);
  assert.match(index, /每组新导语最多选两张资料卡/);
  assert.match(index, /重合下列五项中的三项，直接废弃重做/);
});

test("short-write routes sweet-romance leads through the indexed library", async () => {
  const skill = await read("skills/story-short-write/SKILL.md");
  const workflow = await read(
    "skills/story-short-write/references/writing-workflow.md",
  );

  assert.match(skill, /references\/example-library\/甜宠\/README\.md/);
  assert.match(skill, /`索引\.md`/);
  assert.match(skill, /只从 A\/B 级中选 4～8 张候选卡/);
  assert.match(skill, /C 级卡只作风险提醒，禁止成为情节来源/);
  assert.match(skill, /四案至少覆盖三种关系发动机/);
  assert.match(skill, /五项中重合三项，直接废弃重做/);
  assert.match(workflow, /甜宠例文库召回/);
  assert.match(workflow, /不要一开始加载 44 篇卡片全文/);
  assert.match(workflow, /资料卡是结构证据，不是素材拼贴池/);
});
