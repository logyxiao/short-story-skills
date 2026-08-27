import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = join(dirname(fileURLToPath(import.meta.url)), "..");

async function read(relativePath) {
  return readFile(join(repositoryRoot, relativePath), "utf8");
}

test("short-write enforces lead, design, and body approval gates", async () => {
  const skill = await read("skills/story-short-write/SKILL.md");
  const workflow = await read(
    "skills/story-short-write/references/writing-workflow.md",
  );

  assert.match(skill, /### Phase 1：导语候选与选定/);
  assert.match(skill, /一次给 \*\*4 组真正不同的导语候选\*\*/);
  assert.match(skill, /每组依次给：暂定标题、类型标签、150-220 字导语、250-450 字故事梗概/);
  assert.match(skill, /故事梗概面向作者，可以揭示底牌与结局/);
  assert.match(skill, /未选定前不创建项目目录和任何正文文件/);
  assert.match(skill, /### Phase 2：设定与小节大纲/);
  assert.match(skill, /不要把两者合成一份，也不要创建 `正文\.md`/);
  assert.match(skill, /#### Phase 2 批准门/);
  assert.match(skill, /只有“满意”“这个设计可以”“开始正文”“按此写正文”/);
  assert.match(skill, /\*\*进入条件：用户已明确批准 `设定\.md` 与 `小节大纲\.md`/);

  assert.match(workflow, /\| Phase 1 导语选择 \|/);
  assert.match(workflow, /每组附完整故事梗概/);
  assert.match(workflow, /#### 故事梗概/);
  assert.match(workflow, /对应故事梗概迁入 `设定\.md`/);
  assert.match(workflow, /\| Phase 2 设计 \|/);
  assert.match(workflow, /\| Phase 3 正文 \|/);
  assert.match(workflow, /> 状态：待用户确认（未批准正文）/);
  assert.match(workflow, /> 状态：已批准，可进入正文/);
});

test("short-write routes ancient and modern prose to the requested references", async () => {
  const skill = await read("skills/story-short-write/SKILL.md");
  const style = await read(
    "skills/story-short-write/references/style-benchmarks.md",
  );

  assert.match(skill, /古言主参考《卿候海棠》，现言主参考《白沅》/);
  assert.match(
    style,
    /\/Users\/to\/Documents\/小说工作台\/例文\/古言\/浮月\/卿候海棠\.txt/,
  );
  assert.match(
    style,
    /\/Users\/to\/Documents\/小说工作台\/例文\/追妻追夫\/知乎\/白沅\.txt/,
  );
  assert.match(style, /完整读取对应主参考原文一次/);
  assert.match(style, /不复制原句、人名、专有设定或关键桥段/);
});

test("short-write applies the project story constraints at every approval stage", async () => {
  const skill = await read("skills/story-short-write/SKILL.md");
  const workflow = await read(
    "skills/story-short-write/references/writing-workflow.md",
  );
  const constraints = await read(
    "skills/story-short-write/references/story-constraints.md",
  );

  assert.match(skill, /每一阶段必须加载并执行 `references\/story-constraints\.md`/);
  assert.match(skill, /文件顶部逐字放入用户批准的原 `导语\.md`/);
  assert.match(skill, /第一章第一句必须回应导语末句台词、延续末尾动作、聚焦核心物件/);
  assert.match(skill, /总字数含导语为 9000～12000/);
  assert.match(skill, /全文对话比例 ≤35%/);
  assert.match(skill, /任意连续两节至少一个炸点或爽点/);
  assert.match(skill, /通篇延续导语的诙谐声线/);
  assert.match(skill, /主角主动动作\/造成变化/);
  assert.match(skill, /信息来源\/视角边界/);
  assert.match(skill, /关键答案前一拍/);
  assert.match(workflow, /开端、收费卡点、高潮和结局四个节点/);
  assert.match(workflow, /全文只有单一主角限知视角/);
  assert.match(workflow, /第一章保持导语现场，前三段有新信息，前 500 字完成冲突升级/);
  assert.match(constraints, /主要角色不得使用以下姓氏：苏、裴、周、温/);
  assert.match(constraints, /正文不得出现以下字词，包含在更长词语中也算命中/);
  assert.match(constraints, /正文不得使用排比句/);
  assert.match(constraints, /禁用剧情解法/);
  assert.match(constraints, /真人感通读/);
});

test("story constraint checker blocks forbidden prose and main-character names", async () => {
  const fixtureDir = await mkdtemp(join(tmpdir(), "story-constraints-"));
  const bodyPath = join(fixtureDir, "body.md");
  const designPath = join(fixtureDir, "design.md");
  const cleanBodyPath = join(fixtureDir, "clean-body.md");
  const cleanDesignPath = join(fixtureDir, "clean-design.md");
  const leadPath = join(fixtureDir, "导语.md");
  const dialogueHeavyPath = join(fixtureDir, "dialogue-heavy.md");
  const overlongPath = join(fixtureDir, "overlong.md");
  const prefacedLeadPath = join(fixtureDir, "prefaced-lead.md");
  const checker = join(
    repositoryRoot,
    "skills/story-short-write/scripts/check-story-constraints.js",
  );

  const leadText = "我当众拒绝了他的条件。";
  await writeFile(leadPath, `${leadText}\n`, "utf8");
  await writeFile(bodyPath, "1.\n他猛地抓住我的手指，说已经请了律师。\n", "utf8");
  await writeFile(
    designPath,
    "| 角色 | 姓名 | 故事目标 | 主动策略 |\n|---|---|---|---|\n| 主角 | 顾知微 | 离开 | 主动退婚 |\n",
    "utf8",
  );
  await writeFile(cleanBodyPath, `${leadText}\n1.\n${"我向前走。".repeat(1800)}`, "utf8");
  await writeFile(
    dialogueHeavyPath,
    `${leadText}\n1.\n${"「好。」".repeat(2400)}${"我点头。".repeat(200)}`,
    "utf8",
  );
  await writeFile(overlongPath, `${leadText}\n1.\n${"我向前走。".repeat(2500)}`, "utf8");
  await writeFile(prefacedLeadPath, `正文说明\n${leadText}\n1.\n${"我向前走。".repeat(1800)}`, "utf8");
  await writeFile(
    cleanDesignPath,
    "| 角色 | 姓名 | 故事目标 | 主动策略 |\n|---|---|---|---|\n| 主角 | 许安然 | 离开旧公司 | 主动辞职 |\n| 核心对手 | 梁颂 | 留住人才 | 当面谈判 |\n",
    "utf8",
  );

  const body = spawnSync(process.execPath, [checker, "--kind=body", `--lead=${leadPath}`, "--json", bodyPath], { encoding: "utf8" });
  const design = spawnSync(process.execPath, [checker, "--kind=design", "--json", designPath], { encoding: "utf8" });
  const cleanBody = spawnSync(process.execPath, [checker, "--kind=body", `--lead=${leadPath}`, "--json", cleanBodyPath], { encoding: "utf8" });
  const dialogueHeavy = spawnSync(process.execPath, [checker, "--kind=body", `--lead=${leadPath}`, "--json", dialogueHeavyPath], { encoding: "utf8" });
  const overlong = spawnSync(process.execPath, [checker, "--kind=body", `--lead=${leadPath}`, "--json", overlongPath], { encoding: "utf8" });
  const prefacedLead = spawnSync(process.execPath, [checker, "--kind=body", `--lead=${leadPath}`, "--json", prefacedLeadPath], { encoding: "utf8" });
  const cleanDesign = spawnSync(process.execPath, [checker, "--kind=design", "--json", cleanDesignPath], { encoding: "utf8" });

  assert.equal(body.status, 1);
  assert.equal(design.status, 1);
  const bodyTypes = JSON.parse(body.stdout).findings.map((finding) => finding.type);
  const designTypes = JSON.parse(design.stdout).findings.map((finding) => finding.type);
  assert.ok(bodyTypes.includes("forbidden-body-literal"));
  assert.ok(bodyTypes.includes("forbidden-plot-device"));
  assert.ok(bodyTypes.includes("body-length-out-of-range"));
  assert.ok(bodyTypes.includes("approved-lead-not-verbatim"));
  assert.ok(designTypes.includes("forbidden-character-name"));
  assert.equal(cleanBody.status, 0);
  assert.equal(cleanDesign.status, 0);
  assert.equal(dialogueHeavy.status, 1);
  assert.ok(
    JSON.parse(dialogueHeavy.stdout).findings.some(
      (finding) => finding.type === "dialogue-ratio-too-high",
    ),
  );
  assert.equal(overlong.status, 1);
  assert.ok(
    JSON.parse(overlong.stdout).findings.some(
      (finding) => finding.type === "body-length-out-of-range",
    ),
  );
  assert.equal(prefacedLead.status, 1);
  assert.ok(
    JSON.parse(prefacedLead.stdout).findings.some(
      (finding) => finding.type === "content-before-approved-lead",
    ),
  );
});
