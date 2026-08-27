#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const USAGE = `Usage: node check-story-constraints.js [--kind=lead|design|body] [--lead=<导语.md>] [--json] [--fail-on=blocking|all] <file...>

Check project-specific story constraints:
  - body-only forbidden literals
  - procedural revenge / investigation plot vocabulary
  - forbidden surnames and given-name fragments in the design's main-character table
  - common explicit parallel constructions
  - body length of 9000-12000 Unicode characters
  - dialogue at no more than 35% of visible story characters
  - the approved lead included verbatim before chapter 1

This checker is report-only. Point-of-view, protagonist agency, paywall strength,
and natural human voice still require the semantic review in story-constraints.md.`;

const FORBIDDEN_BODY_LITERALS = ['指尖', '手指', '铁青', '泛白', '猛', '僵'];
const FORBIDDEN_SURNAMES = new Set([
  '苏', '裴', '周', '温', '江', '傅', '顾', '陈', '林', '沈',
  '陆', '秦', '姜', '霍', '厉', '时', '萧', '晏', '谢',
]);
const FORBIDDEN_NAME_PARTS = [
  '砚', '舟', '晚', '婉', '珩', '明珠', '珠珠', '晴',
  '知微', '知义', '令仪', '知夏', '微',
];
const PROCEDURAL_PLOT_PATTERNS = [
  { re: /算账|查账|对账|账本|银行流水|资金流水/g, label: '算账/账目核对' },
  { re: /取证|搜集证据|收集证据|证据链|固定证据/g, label: '取证' },
  { re: /录音|偷拍视频|偷拍|监控录像|调取监控|保存通话/g, label: '录音/监控取证' },
  { re: /律师函|律师|起诉|诉讼|开庭|法庭|打官司/g, label: '律师/诉讼翻盘' },
  { re: /报警|报案|立案|警方介入|警察介入/g, label: '报警办案推进' },
];
const EXPLICIT_PARALLEL_PATTERNS = [
  /(?:有的[^，。！？!?]{1,24}[，,]){2}有的/g,
  /(?:一边[^，。！？!?]{1,24}[，,]){2}一边/g,
];
const CHARACTER_ROLE = '(?:主角|女主|男主|爱情线另一方(?:\\s*/\\s*核心对手)?|核心对手|关键角色(?:\\s*[一二三四五六七八九十0-9]+)?)';
const LIST_CHARACTER_RE = new RegExp(`^[-*]\\s*(${CHARACTER_ROLE})\\s*[：:]\\s*(.+)$`);
const TABLE_CHARACTER_RE = new RegExp(`^\\|\\s*(${CHARACTER_ROLE})\\s*\\|\\s*([^|]+)\\|`);
const BODY_MIN_CHARS = 9000;
const BODY_MAX_CHARS = 12000;
const DIALOGUE_MAX_RATIO = 0.35;

const options = { kind: 'body', leadPath: null, json: false, failOn: 'all', files: [] };

for (let index = 2; index < process.argv.length; index += 1) {
  const arg = process.argv[index];
  if (arg === '--json') {
    options.json = true;
  } else if (arg.startsWith('--kind=')) {
    const kind = arg.slice('--kind='.length);
    if (!['lead', 'design', 'body'].includes(kind)) die(`Unknown kind: ${kind}`);
    options.kind = kind;
  } else if (arg.startsWith('--lead=')) {
    options.leadPath = arg.slice('--lead='.length);
  } else if (arg.startsWith('--fail-on=')) {
    const failOn = arg.slice('--fail-on='.length);
    if (!['blocking', 'all'].includes(failOn)) die(`Unknown fail-on value: ${failOn}`);
    options.failOn = failOn;
  } else if (arg === '--check') {
    // Accepted for symmetry with the other report-only checkers.
  } else if (arg === '-h' || arg === '--help') {
    process.stdout.write(`${USAGE}\n`);
    process.exit(0);
  } else if (arg.startsWith('-')) {
    die(`Unknown option: ${arg}`);
  } else {
    options.files.push(arg);
  }
}

if (options.files.length === 0) die('No files provided');

let readFailed = false;
const findings = [];
const metrics = [];
let leadInput = null;

if (options.kind === 'body') {
  if (!options.leadPath) {
    findings.push({
      file: '(arguments)',
      ...makeFinding(1, 1, 'missing-lead-reference', '正文检查必须用 --lead=<导语.md> 提供已批准导语', ''),
    });
  } else {
    try {
      leadInput = fs.readFileSync(path.resolve(options.leadPath), 'utf8');
    } catch (error) {
      readFailed = true;
      if (!options.json) console.error(`${options.leadPath}: unable to read lead (${error.message})`);
    }
  }
}

for (const file of options.files) {
  let input;
  try {
    input = fs.readFileSync(path.resolve(file), 'utf8');
  } catch (error) {
    readFailed = true;
    if (!options.json) console.error(`${file}: unable to read (${error.message})`);
    continue;
  }

  const result = scanDocument(input, options.kind, leadInput);
  findings.push(...result.findings.map((finding) => ({ file, ...finding })));
  if (result.metrics) metrics.push({ file, ...result.metrics });
}

if (options.json) {
  process.stdout.write(`${JSON.stringify({ findings, metrics }, null, 2)}\n`);
} else {
  for (const finding of findings) {
    console.log(`${finding.file}:${finding.line}:${finding.column}: [${finding.severity}] ${finding.type}: ${finding.message} (${finding.excerpt})`);
  }
  for (const metric of metrics) {
    console.log(`${metric.file}: [metrics] characters=${metric.characterCount}, dialogue=${(metric.dialogueRatio * 100).toFixed(2)}%`);
  }
}

if (readFailed) process.exit(2);
const hasBlocking = findings.some((finding) => finding.severity === 'blocking');
if (options.failOn === 'blocking' ? hasBlocking : findings.length > 0) process.exit(1);

function scanDocument(input, kind, leadInput) {
  const findings = [];
  const lines = input.split(/\r?\n/);

  if (kind === 'body') {
    for (const literal of FORBIDDEN_BODY_LITERALS) {
      findings.push(...findLiteral(lines, literal, 'forbidden-body-literal', `正文禁用字词「${literal}」`));
    }
  }

  for (const { re, label } of PROCEDURAL_PLOT_PATTERNS) {
    findings.push(...findPattern(lines, re, 'forbidden-plot-device', `禁用程序化剧情：${label}`));
  }

  for (const re of EXPLICIT_PARALLEL_PATTERNS) {
    findings.push(...findPattern(lines, re, 'parallelism-pattern', '正文禁止排比句；改成有主次的自然叙述'));
  }

  if (kind === 'design') findings.push(...scanCharacterNames(lines));

  let metrics = null;
  if (kind === 'body') {
    metrics = measureBody(input);
    if (metrics.characterCount < BODY_MIN_CHARS || metrics.characterCount > BODY_MAX_CHARS) {
      findings.push(makeFinding(
        1,
        1,
        'body-length-out-of-range',
        `全文（含导语）必须为 ${BODY_MIN_CHARS}-${BODY_MAX_CHARS} 字；当前 ${metrics.characterCount} 字`,
        lines[0] || '',
      ));
    }
    if (metrics.dialogueRatio > DIALOGUE_MAX_RATIO) {
      findings.push(makeFinding(
        1,
        1,
        'dialogue-ratio-too-high',
        `全文对话比例不得超过 35%；当前 ${(metrics.dialogueRatio * 100).toFixed(2)}%`,
        lines[0] || '',
      ));
    }
    if (leadInput !== null) findings.push(...checkLeadPlacement(input, leadInput));
  }

  return {
    findings: findings.sort((a, b) => a.line - b.line || a.column - b.column),
    metrics,
  };
}

function measureBody(input) {
  const characterCount = Array.from(input.replace(/\r\n/g, '\n')).length;
  const visibleText = input
    .split(/\r?\n/)
    .filter((line) => !isStructuralLine(line.trim()))
    .join('')
    .replace(/\s/gu, '');
  const visibleCount = Array.from(visibleText).length;
  let dialogueCount = 0;
  const dialoguePattern = /「([^」]*)」|“([^”]*)”|"([^"]*)"/gu;
  let match;
  while ((match = dialoguePattern.exec(visibleText)) !== null) {
    dialogueCount += Array.from(match[1] ?? match[2] ?? match[3] ?? '').length;
  }
  return {
    characterCount,
    visibleCount,
    dialogueCount,
    dialogueRatio: visibleCount === 0 ? 0 : dialogueCount / visibleCount,
  };
}

function checkLeadPlacement(body, lead) {
  const result = [];
  const normalizedBody = normalizeNewlines(body).trim();
  const normalizedLead = normalizeNewlines(lead).trim();
  if (!normalizedLead) {
    return [makeFinding(1, 1, 'empty-lead-reference', '导语文件为空，无法验证正文接入', '')];
  }

  const leadIndex = normalizedBody.indexOf(normalizedLead);
  if (leadIndex === -1) {
    return [makeFinding(1, 1, 'approved-lead-not-verbatim', '正文顶部没有逐字收录已批准导语', normalizedBody.slice(0, 100))];
  }
  if (leadIndex !== 0) {
    result.push(makeFinding(1, 1, 'content-before-approved-lead', '正文必须以已批准导语开头，导语前不得插入标题、说明或梗概', normalizedBody.slice(0, Math.min(100, leadIndex))));
  }

  const chapterIndex = firstChapterMarkerIndex(normalizedBody);
  if (chapterIndex === -1 || leadIndex > chapterIndex) {
    result.push(makeFinding(1, 1, 'lead-after-chapter-one', '已批准导语必须出现在第一章标记之前', normalizedBody.slice(0, 100)));
  }
  if (normalizedBody.indexOf(normalizedLead, leadIndex + normalizedLead.length) !== -1) {
    result.push(makeFinding(1, 1, 'approved-lead-duplicated', '已批准导语在正文中出现超过一次', normalizedLead.slice(0, 100)));
  }
  return result;
}

function firstChapterMarkerIndex(text) {
  const match = /^(?:\d+\.|###\s*(?:\d+\.?|第[一二三四五六七八九十百千万两0-9]+章))\s*$/mu.exec(text);
  return match ? match.index : -1;
}

function isStructuralLine(line) {
  return /^【截断点】$/.test(line)
    || /^(?:\d+\.|###\s*(?:\d+\.?|第[一二三四五六七八九十百千万两0-9]+章))$/.test(line)
    || /^#{1,6}\s+/.test(line);
}

function normalizeNewlines(text) {
  return String(text).replace(/\r\n?/g, '\n');
}

function scanCharacterNames(lines) {
  const result = [];
  let foundMainCharacter = false;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const match = line.match(TABLE_CHARACTER_RE) || line.match(LIST_CHARACTER_RE);
    if (!match) continue;

    const role = match[1].replace(/\s+/g, '');
    const name = normalizeName(match[2]);
    if (!name) continue;
    foundMainCharacter = true;

    if (FORBIDDEN_SURNAMES.has(name[0])) {
      result.push(makeFinding(index + 1, line.indexOf(name) + 1, 'forbidden-character-name', `主要角色「${role}」使用禁用姓氏「${name[0]}」`, line));
    }

    for (const part of FORBIDDEN_NAME_PARTS) {
      const offset = name.indexOf(part);
      if (offset !== -1) {
        result.push(makeFinding(index + 1, line.indexOf(name) + offset + 1, 'forbidden-character-name', `主要角色「${role}」姓名含禁用字词「${part}」`, line));
      }
    }
  }

  if (!foundMainCharacter) {
    result.push(makeFinding(1, 1, 'missing-main-character-name-table', '设定中缺少可检查的主要角色姓名表', lines[0] || ''));
  }
  return result;
}

function normalizeName(raw) {
  return raw
    .replace(/[*_`]/g, '')
    .trim()
    .split(/[（(，,；;：:\s/]/, 1)[0]
    .replace(/[^\u3400-\u9fff·]/g, '');
}

function findLiteral(lines, literal, type, message) {
  const result = [];
  for (let index = 0; index < lines.length; index += 1) {
    let offset = lines[index].indexOf(literal);
    while (offset !== -1) {
      result.push(makeFinding(index + 1, offset + 1, type, message, lines[index]));
      offset = lines[index].indexOf(literal, offset + literal.length);
    }
  }
  return result;
}

function findPattern(lines, pattern, type, message) {
  const result = [];
  for (let index = 0; index < lines.length; index += 1) {
    pattern.lastIndex = 0;
    let match;
    while ((match = pattern.exec(lines[index])) !== null) {
      result.push(makeFinding(index + 1, match.index + 1, type, message, lines[index]));
      if (match[0].length === 0) pattern.lastIndex += 1;
    }
  }
  return result;
}

function makeFinding(line, column, type, message, excerpt) {
  return {
    line,
    column: Math.max(1, column),
    type,
    severity: 'blocking',
    message,
    excerpt: compact(excerpt),
  };
}

function compact(text) {
  const normalized = String(text).replace(/\s+/g, ' ').trim();
  return normalized.length > 100 ? `${normalized.slice(0, 97)}...` : normalized;
}

function die(message) {
  console.error(message);
  console.error(USAGE);
  process.exit(2);
}
