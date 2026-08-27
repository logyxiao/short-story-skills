#!/usr/bin/env python3
"""Validate the repository's current-only skill and artifact contracts.

The JSON manifest is the single structured inventory for version numbers,
primary benchmark artifacts, and outline sections.  This module deliberately
keeps the older path/legacy guards too, but implements them with scoped file
walks and actionable findings rather than a chain of shell grep calls.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, List, Optional, Sequence, Tuple


SUPPORTED_MANIFEST_VERSION = 1
EXPECTED_MANIFEST_KEYS = {
    "manifest_version",
    "setup_skill_version",
    "agents_version",
}
SEMVER_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
ARTIFACT_PATH_RE = re.compile(r"(?:[^/\s]+/)+[^/\s]+\.md")


@dataclass(frozen=True)
class ContractManifest:
    manifest_version: int
    setup_skill_version: str
    agents_version: int


@dataclass(frozen=True)
class Finding:
    code: str
    message: str
    path: Optional[Path] = None
    line: Optional[int] = None
    excerpt: Optional[str] = None

    def detail(self, repo_root: Path) -> str:
        location = ""
        if self.path is not None:
            try:
                shown = self.path.resolve().relative_to(repo_root.resolve())
            except ValueError:
                shown = self.path
            location = str(shown)
            if self.line is not None:
                location += ":{}".format(self.line)
            location += ": "
        suffix = ""
        if self.excerpt:
            suffix = " [{}]".format(self.excerpt.strip())
        return "{}{}{}".format(location, self.message, suffix)


@dataclass(frozen=True)
class AbsentRule:
    code: str
    label: str
    pattern: str
    relative_roots: Tuple[str, ...]
    # 「静默才禁」豁免：命中行的本地上下文若带显式容忍标记（不阻塞 / [待补充] / 回退 /
    # 只核对 / 记录…），说明是有据可查的旧格式容忍而非静默降级，放行。仅用于旧格式大纲容忍
    # （keep C）；benchmark 回退（drop A/B）的规则不设豁免，静默与显式一律禁。
    exempt_when: Optional[str] = None


LEGACY_RULES = (
    AbsentRule(
        "legacy-progress-branch",
        "no legacy deconstruction/progress branches",
        r"legacy_deconstruction|contract_version[^\n]*legacy|pre-v12|schema v1|lazy migration|schema_migration",
        ("skills",),
    ),
    AbsentRule(
        "old-artifact-prose",
        "no silent old artifact-format downgrade",
        r"旧拆文库|旧版细纲|旧式薄细纲|旧版内部降级标记|早期拆文库格式|兼容旧结构",
        ("skills",),
        # keep C：旧格式大纲/细纲容忍是显式、有据可查的（不阻塞日更、回退读取旧字段、未知写
        # [待补充]、记录到追踪），不是静默降级——带这些标记就放行，只拦无标记的静默兼容措辞。
        exempt_when=r"不阻塞|\[待补充\]|回退|只核对|记录|保留或映射|仍可续写|仍可用|仍要保留",
    ),
    AbsentRule(
        "removed-hook-alias",
        "removed hook alias stays removed",
        r"discover_book_dir\s*\(",
        ("skills/story-setup/references/templates/hooks",),
    ),
    AbsentRule(
        "obsolete-novel-workspace-path",
        "active story skills use only 小说工作室/正文 and 小说工作室/拆书",
        r"拆文库(?:/|-)|短篇/\{标题\}",
        (
            "skills/story",
            "skills/story-short-analyze",
            "skills/story-short-write",
            "skills/story-setup/references/codex",
        ),
    ),
    AbsentRule(
        "dotted-demo-workflow-label",
        "shipped demos do not preserve dotted workflow labels",
        r"(?:Step|Phase|Stage)\s*[0-9]+\.[0-9]+",
        ("demo",),
    ),
    AbsentRule(
        "duplicate-adapter-reference-fallback",
        "story-setup deploys one canonical reference path per adapter",
        r"同步复制到\s*`skills/[^`]+`\s*作为 fallback",
        ("skills/story-setup/SKILL.md",),
    ),
    AbsentRule(
        "codex-old-reference-prefix",
        "Codex agents use the deployed .codex/skills reference path only",
        r"\{项目根\}/skills/story-setup/references/agent-references/",
        ("skills/story-setup/references/codex/hooks",),
    ),
)


PRIMARY_GAP_TERMS = (
    "module_missing",
    "rhythm_missing",
    "missing_primary_contract",
    "主产物",
    "权威文件",
    "主文件",
)
def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def load_manifest(path: Path) -> Tuple[Optional[ContractManifest], List[Finding]]:
    findings: List[Finding] = []
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, [Finding("manifest-missing", "current contract manifest is missing", path)]
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return None, [Finding("manifest-invalid-json", "cannot parse manifest: {}".format(exc), path)]

    if not isinstance(raw, dict):
        return None, [Finding("manifest-type", "manifest root must be a JSON object", path)]

    keys = set(raw)
    for missing in sorted(EXPECTED_MANIFEST_KEYS - keys):
        findings.append(Finding("manifest-key-missing", "missing manifest key: {}".format(missing), path))
    for unknown in sorted(keys - EXPECTED_MANIFEST_KEYS):
        findings.append(Finding("manifest-key-unknown", "unknown manifest key: {}".format(unknown), path))

    if "manifest_version" in raw:
        if not _is_int(raw["manifest_version"]):
            findings.append(Finding("manifest-value-type", "manifest_version has the wrong type", path))
        elif raw["manifest_version"] != SUPPORTED_MANIFEST_VERSION:
            findings.append(
                Finding(
                    "manifest-version-unsupported",
                    "manifest_version must be {}, got {}".format(
                        SUPPORTED_MANIFEST_VERSION, raw["manifest_version"]
                    ),
                    path,
                )
            )

    setup_version = raw.get("setup_skill_version")
    if not isinstance(setup_version, str):
        if "setup_skill_version" in raw:
            findings.append(Finding("manifest-value-type", "setup_skill_version has the wrong type", path))
    elif not SEMVER_RE.fullmatch(setup_version):
        findings.append(Finding("manifest-value-format", "setup_skill_version must be x.y.z", path))

    for key in (
        "agents_version",
    ):
        if key not in raw:
            continue
        if not _is_int(raw[key]):
            findings.append(Finding("manifest-value-type", "{} has the wrong type".format(key), path))
        elif raw[key] < 1:
            findings.append(Finding("manifest-value-range", "{} must be a positive integer".format(key), path))

    if findings:
        return None, findings

    manifest = ContractManifest(
        manifest_version=raw["manifest_version"],
        setup_skill_version=raw["setup_skill_version"],
        agents_version=raw["agents_version"],
    )
    return manifest, []


def iter_files(root: Path) -> Iterator[Path]:
    if root.is_file():
        if root.name not in {"UPGRADING.md", "CHANGELOG.md"}:
            yield root
        return
    if not root.exists():
        return
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.name in {"UPGRADING.md", "CHANGELOG.md"}:
            continue
        if any(part in {".git", ".omx"} for part in path.parts):
            continue
        yield path


def read_text(path: Path) -> Optional[str]:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return None


# 二进制资产读不出文本是正常的（demo 封面图、__pycache__ 字节码），静默跳过即可；其余文件
# 一律按 UTF-8 文本对待。GBK/cp936 的 Markdown 会让所有内容规则一起失效——regex_hits 拿到
# None 就当「没命中」，检查照样打 [PASS]——所以文本文件解码失败必须是命名失败，不是跳过。
BINARY_SUFFIXES = frozenset(
    {
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".ico",
        ".pdf",
        ".zip",
        ".gz",
        ".woff",
        ".woff2",
        ".ttf",
        ".otf",
        ".mp3",
        ".mp4",
        ".pyc",
        ".pyo",
        ".so",
        ".dylib",
    }
)

TEXT_SUFFIXES = frozenset(
    {
        ".cmd",
        ".css",
        ".csv",
        ".html",
        ".ini",
        ".js",
        ".json",
        ".md",
        ".mjs",
        ".patch",
        ".py",
        ".sh",
        ".svg",
        ".tmpl",
        ".toml",
        ".ts",
        ".txt",
        ".xml",
        ".yaml",
        ".yml",
    }
)


def is_binary_asset(path: Path) -> bool:
    """二进制资产（封面图、字节码、.DS_Store 之类）读不出文本是正常的。

    后缀白名单之外再看有没有 NUL 字节：这样 `.DS_Store`、无后缀的二进制不会误报，而
    GBK/cp936 的 Markdown（没有 NUL）仍会被判成必须修的文本文件。读不到字节就按文本算，
    宁可报错也不静默放行。
    """
    if path.suffix.lower() in BINARY_SUFFIXES:
        return True
    # UTF-16 文本同样含大量 NUL；已知文本后缀必须先按契约文本处理，让 UTF-8 解码失败成为
    # 命名错误。NUL sniff 只服务于 .DS_Store / 未知扩展二进制，不能覆盖文件类型事实。
    if path.suffix.lower() in TEXT_SUFFIXES:
        return False
    try:
        return b"\x00" in path.read_bytes()[:8192]
    except OSError:
        return False


def undecodable_source_findings(roots: Sequence[Path]) -> List[Finding]:
    """内容规则扫过的文本文件必须能按 UTF-8 读出来，否则整条规则静默放行。"""
    findings: List[Finding] = []
    seen: set[str] = set()
    for root in roots:
        for path in iter_files(root):
            key = str(path.resolve())
            if key in seen:
                continue
            seen.add(key)
            if read_text(path) is not None:
                continue
            if is_binary_asset(path):
                continue
            findings.append(
                Finding(
                    "unreadable-source-file",
                    "contract guards need UTF-8 text; this file cannot be read as UTF-8",
                    path,
                )
            )
    return findings


def regex_hits(path: Path, pattern: re.Pattern[str]) -> Iterator[Finding]:
    text = read_text(path)
    if text is None:
        return
    for match in pattern.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        excerpt = text.splitlines()[line - 1] if text.splitlines() else ""
        yield Finding("", "", path, line, excerpt)


def check_absent_rule(repo_root: Path, rule: AbsentRule) -> List[Finding]:
    compiled = re.compile(rule.pattern)
    exempt = re.compile(rule.exempt_when) if rule.exempt_when else None
    findings: List[Finding] = []
    for relative_root in rule.relative_roots:
        root = repo_root / relative_root
        for path in iter_files(root):
            for hit in regex_hits(path, compiled):
                if exempt is not None:
                    # 只看命中行本身：显式容忍标记须与旧格式措辞同处一行才算「有据可查」，
                    # 避免相邻的静默降级借上一行的标记蒙混过关
                    if exempt.search(hit.excerpt):
                        continue
                findings.append(
                    Finding(rule.code, rule.label, hit.path, hit.line, hit.excerpt)
                )
    return findings


# 列表项与表格行都是「一条独立记录」：条件与动作要在同一条记录（或它的上级）里才算一件事。
def require_pattern(path: Path, pattern: str, code: str, message: str) -> List[Finding]:
    text = read_text(path)
    if text is None:
        return [Finding(code, "cannot read required file", path)]
    if re.search(pattern, text, re.MULTILINE):
        return []
    return [Finding(code, message, path)]



def rubric_dimension_names(repo_root: Path) -> Tuple[List[str], List[str]]:
    """取 quality-rubric.md「核心维度」表与 SKILL.md 内置 fallback 的维度名。"""

    table: List[str] = []
    rubric_text = read_text(repo_root / "skills/story-review/references/quality-rubric.md") or ""
    in_table = False
    for line in rubric_text.splitlines():
        if line.startswith("| 维度 |"):
            in_table = True
            continue
        if not in_table:
            continue
        if not line.startswith("|"):
            break
        cell = line.split("|")[1].strip()
        if cell and not set(cell) <= {"-", ":"}:
            table.append(cell)

    embedded: List[str] = []
    skill_text = read_text(repo_root / "skills/story-review/SKILL.md") or ""
    if "通用网文内容 rubric：" in skill_text:
        block = skill_text.split("通用网文内容 rubric：", 1)[1]
        for line in block.splitlines():
            if not line.startswith("- "):
                if embedded:
                    break
                continue
            embedded.append(line[2:].split("：", 1)[0].strip())
    return table, embedded


def rubric_parity_findings(repo_root: Path) -> List[Finding]:
    """内置 fallback rubric 与 quality-rubric.md 必须是同一套维度。

    两者是同一套标准的两个副本：文件可读时用文件，不可读时用内置。漂移过一次
    （文件版独有「任务卡点」，内置版独有「标点节奏」「具体字数表达校验」），
    结果是审查口径取决于路径可读性。手工对齐只管一次，这条断言管以后。
    """

    table, embedded = rubric_dimension_names(repo_root)
    path = repo_root / "skills/story-review/SKILL.md"
    if not table or not embedded:
        return [
            Finding(
                "rubric-parity-unreadable",
                "cannot read both generic rubrics to compare dimensions",
                path,
            )
        ]
    findings = []
    for missing, where in (
        (sorted(set(table) - set(embedded)), "内置 fallback rubric"),
        (sorted(set(embedded) - set(table)), "quality-rubric.md"),
    ):
        if missing:
            findings.append(
                Finding(
                    "rubric-dimension-drift",
                    "generic rubric dimensions drifted: {} missing from {}".format(
                        "、".join(missing), where
                    ),
                    path,
                )
            )
    return findings


def parse_frontmatter_version(path: Path) -> Optional[str]:
    text = read_text(path)
    if text is None:
        return None
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        match = re.fullmatch(r"version:\s*([^\s]+)\s*", line)
        if match:
            return match.group(1)
    return None


def extract_current_version_fields(text: str) -> dict[str, str]:
    """Parse version bullets from the `## 当前版本` section only."""
    lines = text.splitlines()
    start: Optional[int] = None
    for index, line in enumerate(lines):
        if re.fullmatch(r"##\s+当前版本\s*", line):
            start = index + 1
            break
    if start is None:
        return {}

    end = len(lines)
    for index in range(start, len(lines)):
        if re.match(r"^#{1,2}\s+", lines[index]):
            end = index
            break

    fields: dict[str, str] = {}
    for line in lines[start:end]:
        match = re.fullmatch(
            r"\s*-\s+`(setup_skill_version|agents_version):\s*([^`]+)`\s*",
            line,
        )
        if match:
            fields[match.group(1)] = match.group(2).strip()
    return fields


def upgrading_version_findings(
    text: str, manifest: ContractManifest, path: Path
) -> List[Finding]:
    fields = extract_current_version_fields(text)
    expected = {
        "setup_skill_version": manifest.setup_skill_version,
        "agents_version": str(manifest.agents_version),
    }
    findings: List[Finding] = []
    for key, value in expected.items():
        actual = fields.get(key)
        if actual != value:
            findings.append(
                Finding(
                    "upgrading-current-version",
                    "UPGRADING current-version bullet {} must be {!r}, got {!r}".format(
                        key, value, actual
                    ),
                    path,
                )
            )
    # 「升级步骤」里让用户核对的版本号是操作指令，bump 时最容易漏（它不在当前版本 bullet
    # 里，也不被部署检查的 TS10 锚点覆盖）。任何写成 `agents_version: N` 的行都必须是当前值。
    for raw in text.splitlines():
        match = re.search(r"`agents_version:\s*(\d+)`", raw)
        if match and match.group(1) != str(manifest.agents_version):
            findings.append(
                Finding(
                    "upgrading-step-version",
                    "UPGRADING step line pins agents_version {!r}, must be {!r}: {}".format(
                        match.group(1), str(manifest.agents_version), raw.strip()
                    ),
                    path,
                )
            )
    return findings


def extract_sentinel_fields(text: str) -> Optional[dict[str, str]]:
    """Parse the generated `.story-deployed` YAML example from its Step section.

    This intentionally ignores version strings in surrounding explanatory
    prose.  The deployment contract is the fenced block following the
    "写入以下字段" instruction inside "创建部署标记".
    """
    lines = text.splitlines()
    section_start: Optional[int] = None
    heading_level = 0
    for index, line in enumerate(lines):
        match = re.match(r"^(#{2,6})\s+Step\s+[A-Za-z0-9]+[：:]\s*创建部署标记\s*$", line)
        if match:
            section_start = index + 1
            heading_level = len(match.group(1))
            break
    if section_start is None:
        return None

    section_end = len(lines)
    for index in range(section_start, len(lines)):
        match = re.match(r"^(#{1,6})\s+", lines[index])
        if match and len(match.group(1)) <= heading_level:
            section_end = index
            break

    marker_index: Optional[int] = None
    for index in range(section_start, section_end):
        if "写入以下字段" in lines[index]:
            marker_index = index + 1
            break
    if marker_index is None:
        return None

    fence_start: Optional[int] = None
    for index in range(marker_index, section_end):
        if re.match(r"^\s*```(?:ya?ml)?\s*$", lines[index], re.IGNORECASE):
            fence_start = index + 1
            break
    if fence_start is None:
        return None

    fence_end: Optional[int] = None
    for index in range(fence_start, section_end):
        if re.match(r"^\s*```\s*$", lines[index]):
            fence_end = index
            break
    if fence_end is None:
        return None

    fields: dict[str, str] = {}
    for line in lines[fence_start:fence_end]:
        match = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", line)
        if match:
            fields[match.group(1)] = match.group(2)
    return fields


def sentinel_contract_findings(
    text: str, manifest: ContractManifest, path: Path
) -> List[Finding]:
    fields = extract_sentinel_fields(text)
    if fields is None:
        return [
            Finding(
                "setup-sentinel-block",
                "cannot find the structured generated-sentinel fenced block",
                path,
            )
        ]

    required = {
        "deployed_at",
        "agents_version",
        "setup_skill_version",
        "target_cli",
        "resolver_strategy",
        "references_dir",
    }
    findings: List[Finding] = []
    missing = sorted(required - set(fields))
    if missing:
        findings.append(
            Finding(
                "setup-sentinel-fields",
                "generated sentinel is missing fields: {}".format(", ".join(missing)),
                path,
            )
        )

    expected = {
        "agents_version": str(manifest.agents_version),
        "setup_skill_version": manifest.setup_skill_version,
    }
    for key, value in expected.items():
        actual = fields.get(key)
        if actual != value:
            findings.append(
                Finding(
                    "setup-sentinel-field",
                    "generated sentinel {} must be {!r}, got {!r}".format(key, value, actual),
                    path,
                )
            )
    return findings


def _clean_markdown_label(label: str) -> str:
    return label.strip().strip("`*_ ")


def _normalize_rule_field(label: str) -> str:
    label = _clean_markdown_label(label)
    if label.startswith("本章"):
        label = label[2:]
    label = re.sub(r"[（(].*$", "", label).strip()
    return label


def validate_repository(repo_root: Path, manifest: ContractManifest) -> List[Finding]:
    findings: List[Finding] = []

    scan_roots = [repo_root / "skills", repo_root / "demo"]
    scan_roots.extend(
        repo_root / relative_root
        for rule in LEGACY_RULES
        for relative_root in rule.relative_roots
    )
    findings.extend(undecodable_source_findings(scan_roots))

    for rule in LEGACY_RULES:
        findings.extend(check_absent_rule(repo_root, rule))

    setup_skill = repo_root / "skills/story-setup/SKILL.md"
    actual_setup_version = parse_frontmatter_version(setup_skill)
    if actual_setup_version != manifest.setup_skill_version:
        findings.append(
            Finding(
                "setup-frontmatter-version",
                "story-setup frontmatter version must be {}, got {!r}".format(
                    manifest.setup_skill_version, actual_setup_version
                ),
                setup_skill,
            )
        )
    setup_text = read_text(setup_skill) or ""
    findings.extend(sentinel_contract_findings(setup_text, manifest, setup_skill))



    upgrading = repo_root / "skills/story-setup/UPGRADING.md"
    upgrading_text = read_text(upgrading) or ""
    findings.extend(upgrading_version_findings(upgrading_text, manifest, upgrading))

    findings.extend(rubric_parity_findings(repo_root))

    return findings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root (default: parent of scripts/)",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(__file__).resolve().with_name("current-contract.json"),
        help="current contract manifest",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    repo_root = args.repo_root.resolve()
    manifest, manifest_findings = load_manifest(args.manifest.resolve())

    print("Current Skill Contract Check")
    print("============================")
    if manifest_findings:
        for finding in manifest_findings:
            print("  [FAIL] {}: {}".format(finding.code, finding.detail(repo_root)))
        print("\nResult: {} failure(s)".format(len(manifest_findings)))
        return 1

    assert manifest is not None
    print("  [PASS] manifest schema and declared release values")
    findings = validate_repository(repo_root, manifest)
    if findings:
        for finding in findings:
            print("  [FAIL] {}: {}".format(finding.code, finding.detail(repo_root)))
        print("\nResult: {} failure(s)".format(len(findings)))
        return 1

    print("  [PASS] legacy/path guards")
    print("  [PASS] version contracts")
    print("\nResult: all current-contract checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
