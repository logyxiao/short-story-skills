#!/bin/bash
# test-prose-net-parity.sh — Codex 正文兜底「轻量确定性网」守卫
# 网在 Codex story_codex_hook.py 单处实现。本测试三层保证：
#   A. 功能断言（codex python 网）：毒句式/工程词/AI 自指/截断 fixtures 上的命中与静默断言。
#   B. 命令函数断言（codex python）：正文目标抽取、apply-patch 目标、git commit 侦测的
#      防转断言（含包装器/命令替换/多 heredoc/转义引号、apply_patch 搬家与 ReDoS 预算）。
#   C. staged warnings 与大纲阻断判定断言（codex python）：硬编码属性中文文案 + 短篇
#      大纲阻断 5 组判定（缺小节大纲/有纲/无信号/导入窗口/已存在），锚死期望方向。
# （原多端 parity 对照已完成历史使命：Claude/OpenCode/ZCode 实现均已随多端收敛移除。）
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && { echo "Error: not in a git repository" >&2; exit 1; }

CODEX="$ROOT/skills/story-setup/references/codex/hooks/story_codex_hook.py"
[ -f "$CODEX" ] || { echo "FAIL: missing impl: $CODEX" >&2; exit 1; }

fails=0

# ── B. 功能断言（codex python 网）──
run_functional() {
  command -v node >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  cat > "$tmp/fixtures.json" <<'EOF'
{
  "clean": "江晨睁开眼天还没亮。\n他要快要狠要赢这是唯一的活路。\n「作为AI管家，我劝你别白费力气。」\n他握紧拳头走向门口。",
  "truncate": "江晨握紧拳头慢慢走向门口。\n江晨冲过去一拳砸在",
  "refuse": "夜色压下来。\n作为AI我无法继续创作这部分内容。",
  "ai_selfref_model": "夜色压下来。\n作为一个AI语言模型，我需要提醒您接下来的情节包含暴力描写。",
  "ai_selfref_assistant": "他推门进来。\n作为一个AI助手，这段内容涉及敏感话题。",
  "ai_selfref_era_ok": "作为一个人工智能时代的产物，他对孤独习以为常。\n他把灯关了。",
  "terminal_banner_ok": "他抬起手按在光屏上。\n【叮！任务完成，奖励已发放】",
  "terminal_ascii_quote_ok": "他站起来推开门。\n他说：\"我回来了。\"",
  "toxic_quote_codename_ok": "他把烟头按进烟灰缸。\n这一战注定是「血屠」的开端，没人料到后来会那样。",
  "engword": "街灯一盏盏亮起。\n按照本章小节大纲的情节点他该出场了。",
  "repeat": "他握紧拳头一步步走过去缓缓逼近。\n他握紧拳头一步步走过去缓缓逼近。\n他终于停下了。",
  "placeholder": "他打开门。\n（此处省略三百字打斗描写）他赢了。",
  "english_ai": "他说。\nI cannot continue writing this scene for you.",
  "parallel": "要么生，要么死。\n要么战，要么逃。\n要么赢，要么输。\n他做出了选择。",
  "danmaku": "前方高能！\n前方高能！预警。\n这一段我哭了。\n作者加更！",
  "toxic_voice": "他开口了。\n声音不高，第一句却稳稳压住了整个大厅。",
  "toxic_negation": "没有伴奏，没有和声，没有提词器。\n台下静了三秒。",
  "toxic_cross_negation": "不是嚎啕大哭。\n\n也不是扯着嗓子喊不舍。\n\n只是一个人走远了，留在原地的人还站着。",
  "toxic_cross_negation_dialogue_ok": "“不是嚎啕大哭。”\n\n“也不是扯着嗓子喊不舍。”\n\n“只是舍不得。”",
  "toxic_reverse_notis": "是真嗓子，不是修音修出来的。\n他清了清嗓子接着唱。",
  "toxic_forward_notis": "不是没有想过退路，而是根本没有退路。\n他把门关上了。",
  "toxic_trailer": "他放下麦克风朝台下鞠了一躬。\n没人知道，这才刚刚开头。",
  "toxic_trailer_summary": "他放下麦克风朝台下鞠了一躬。\n这一切都结束了。",
  "toxic_trailer_summary_fate": "她把账单折好塞回包里。\n这一夜注定无人入眠。",
  "toxic_bare_realize_ok": "那一刻我终于明白，母亲当年为什么总在夜里哭。\n我抓起外套就往门口走。",
  "toxic_summary_subclause_ok": "等这一切结束了，我们就能过上平静幸福的生活了。\n他把门带上了。",
  "toxic_summary_idiom_ok": "世间的这一刻，所有人都接受了命中注定的结局！\n他转身走了。",
  "toxic_dialogue_ok": "「没人知道。」\n他笑了笑接着往前走。",
  "toxic_eitheror_ok": "不是生就是死，他认了。\n他推门走了进去。",
  "toxic_affirm_ok": "是啊，不是他的错。\n他把灯关了。",
  "toxic_shibushi_ok": "他问自己是不是听错了，是不是灯光太晃。\n他揉了揉眼睛。",
  "toxic_question_ok": "是不是他干的，不是我干的。\n他说不清。",
  "toxic_rhetorical_ok": "是挺好的一件事，不是吗。\n他点了点头。",
  "toxic_curtain_ok": "钟声再度响起，比赛正式拉开序幕。\n他站上了台。",
  "toxic_quote_mid_ok": "她的声音不大好听，被人截成“名场面”，但她不在乎。\n台下没有掌声，没有“安可”声，只有此起彼伏的咳嗽。",
  "toxic_multi_tail_ok": "是他的错，不是我的错，不是吗。\n他点了点头。",
  "toxic_exempt_marker_ok": "# 开头\n<!-- 去味:跳过 -->\n没有伴奏，没有和声，没有提词器。",
  "toxic_exempt_fullwidth_ok": "# 开头\n<!-- 去味：跳过 -->\n没有伴奏，没有和声，没有提词器。",
  "toxic_exempt_other_nets": "# 开头\n<!-- 去味:跳过 -->\n没有伴奏，没有和声，没有提词器。\n按照本章小节大纲的情节点他该出场了。",
  "toxic_astral_window_ok": "没人知道他练了多少年。\n“第1排😀😀😀😀😀😀😀😀😀😀”\n“第2排😀😀😀😀😀😀😀😀😀😀”\n“第3排😀😀😀😀😀😀😀😀😀😀”\n“第4排😀😀😀😀😀😀😀😀😀😀”\n“第5排😀😀😀😀😀😀😀😀😀😀”\n“第6排😀😀😀😀😀😀😀😀😀😀”\n“第7排😀😀😀😀😀😀😀😀😀😀”\n“第8排😀😀😀😀😀😀😀😀😀😀”\n“第9排😀😀😀😀😀😀😀😀😀😀”\n“第10排😀😀😀😀😀😀😀😀😀😀”\n“第11排😀😀😀😀😀😀😀😀😀😀”\n“第12排😀😀😀😀😀😀😀😀😀😀”\n“第13排😀😀😀😀😀😀😀😀😀😀”\n“第14排😀😀😀😀😀😀😀😀😀😀”\n“第15排😀😀😀😀😀😀😀😀😀😀”\n“第16排😀😀😀😀😀😀😀😀😀😀”\n“第17排😀😀😀😀😀😀😀😀😀😀”\n“第18排😀😀😀😀😀😀😀😀😀😀”\n“第19排😀😀😀😀😀😀😀😀😀😀”\n“第20排😀😀😀😀😀😀😀😀😀😀”\n“第21排😀😀😀😀😀😀😀😀😀😀”\n“第22排😀😀😀😀😀😀😀😀😀😀”\n“第23排😀😀😀😀😀😀😀😀😀😀”\n“第24排😀😀😀😀😀😀😀😀😀😀”\n“第25排😀😀😀😀😀😀😀😀😀😀”\n“第26排😀😀😀😀😀😀😀😀😀😀”\n“第27排😀😀😀😀😀😀😀😀😀😀”\n“第28排😀😀😀😀😀😀😀😀😀😀”\n“第29排😀😀😀😀😀😀😀😀😀😀”\n“第30排😀😀😀😀😀😀😀😀😀😀”",
  "toxic_trailer_window_ok": "没人知道他练了多少年。\n江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。江晨把这段视频剪了又剪从凌晨剪到天亮每一帧都抠得死死的。\n他把琴盖合上，起了身。"
}
EOF

  python3 - "$CODEX" "$tmp/fixtures.json" > "$tmp/py.txt" <<'PY'
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("ch", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fx = json.load(open(sys.argv[2], encoding='utf-8'))
# 用 stdout.buffer 直写 UTF-8 字节：Windows runner 上 python<3.15 的文本 stdout 是 cp1252，
# 含中文 findings 的 print 会 UnicodeEncodeError（与 node 侧 console.log 的 UTF-8 输出对齐）。
for k in sorted(fx):
    line = k + " | " + " ;; ".join(m.prose_net_findings(fx[k]))
    sys.stdout.buffer.write((line + "\n").encode("utf-8"))
PY

  # 毒句式 fixture 防空转断言（两端同错也能 diff 通过，故对期望输出显式断言）：
  # 正例（用户实抓的真实毒句）须命中对应规则；反例（对话内/either-or/确认语/是不是/
  # 窗口外 trailer）须完全静默。
  grep -q '^toxic_voice | 第2行 毒句式\[voice-contrast\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 voice-contrast 未命中「声音不高…却」" >&2; return 3; }
  grep -q '^toxic_negation | 第1行 毒句式\[negation-parade\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 negation-parade 未命中「没有…没有…」" >&2; return 3; }
  grep -q '^toxic_cross_negation | $' "$tmp/py.txt" || { echo "FAIL: 跨段「不是/也不是/只是」应由深扫语义复核，不应进轻量 blocking 网" >&2; return 3; }
  grep -q '^toxic_reverse_notis | 第1行 毒句式\[reverse-not-is\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 reverse-not-is 未命中「是真嗓子，不是修音」" >&2; return 3; }
  grep -q '^toxic_forward_notis | 第1行 毒句式\[not-is-comparison\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 not-is-comparison 未命中「不是…，而是…」" >&2; return 3; }
  grep -q '^toxic_trailer | 第2行 毒句式\[trailer-ending\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 trailer-ending 未命中「没人知道，这才刚刚开头」" >&2; return 3; }
  grep -q '^toxic_trailer_summary | 第2行 毒句式\[trailer-summary\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 trailer-summary 未命中「这一切都结束了」" >&2; return 3; }
  grep -q '^toxic_trailer_summary_fate | 第2行 毒句式\[trailer-summary\]' "$tmp/py.txt" || { echo "FAIL: 毒句式正例 trailer-summary 未命中「这一夜注定无人入眠」" >&2; return 3; }
  grep -q '^toxic_bare_realize_ok | $' "$tmp/py.txt" || { echo "FAIL: 「那一刻…终于明白」审判金句被误报（短篇卖点，本规则不收认知节拍）" >&2; return 3; }
  grep -q '^toxic_summary_subclause_ok | $' "$tmp/py.txt" || { echo "FAIL: 条件从句「等这一切结束了，…」被误报（未落句末断言位）" >&2; return 3; }
  grep -q '^toxic_summary_idiom_ok | $' "$tmp/py.txt" || { echo "FAIL: 成语「命中注定」被跨匹配成 trailer-summary" >&2; return 3; }
  grep -q '^toxic_dialogue_ok | $' "$tmp/py.txt" || { echo "FAIL: 对话内「没人知道」被误报（成对引号应剥除）" >&2; return 3; }
  grep -q '^toxic_cross_negation_dialogue_ok | $' "$tmp/py.txt" || { echo "FAIL: 三段对话内否定被写后 hook 误报（语义审查负责台词 advisory）" >&2; return 3; }
  grep -q '^toxic_eitheror_ok | $' "$tmp/py.txt" || { echo "FAIL: either-or「不是A就是B」被误报" >&2; return 3; }
  grep -q '^toxic_affirm_ok | $' "$tmp/py.txt" || { echo "FAIL: 确认语「是啊，不是…」被误报" >&2; return 3; }
  grep -q '^toxic_shibushi_ok | $' "$tmp/py.txt" || { echo "FAIL: 疑问「是不是」被误报" >&2; return 3; }
  grep -q '^toxic_question_ok | $' "$tmp/py.txt" || { echo "FAIL: 「是不是…」问句起头被误报" >&2; return 3; }
  grep -q '^toxic_rhetorical_ok | $' "$tmp/py.txt" || { echo "FAIL: 反问尾巴「…，不是吗」被误报" >&2; return 3; }
  grep -q '^toxic_curtain_ok | $' "$tmp/py.txt" || { echo "FAIL: 报幕式「正式拉开序幕」被误报" >&2; return 3; }
  grep -q '^toxic_trailer_window_ok | $' "$tmp/py.txt" || { echo "FAIL: 文末 600 字窗口外的「没人知道」被误报" >&2; return 3; }
  grep -q '^toxic_quote_mid_ok | $' "$tmp/py.txt" || { echo "FAIL: 句中引号段未按等长占位截断，规则跨引号拼出假命中" >&2; return 3; }
  grep -q '^toxic_multi_tail_ok | $' "$tmp/py.txt" || { echo "FAIL: 带中间对比项的反问尾巴「…，不是吗」被误报" >&2; return 3; }
  grep -q '^toxic_exempt_marker_ok | $' "$tmp/py.txt" || { echo "FAIL: 标「去味:跳过」的正文毒句式未被写后网豁免" >&2; return 3; }
  grep -q '^toxic_exempt_fullwidth_ok | $' "$tmp/py.txt" || { echo "FAIL: 全角冒号豁免标记「去味：跳过」未生效" >&2; return 3; }
  grep -q '^toxic_exempt_other_nets | 第4行 工程词泄漏' "$tmp/py.txt" || { echo "FAIL: 豁免标记不应连带关掉毒句式以外的网（工程词漏检）" >&2; return 3; }
  grep '^toxic_exempt_other_nets' "$tmp/py.txt" | grep -q '毒句式' && { echo "FAIL: 豁免标记在场时毒句式仍被推回" >&2; return 3; }
  grep -q '^toxic_astral_window_ok | $' "$tmp/py.txt" || { echo "FAIL: 引号内 emoji 的占位长度未按 UTF-16 码元对齐，trailer 窗口切点漂移" >&2; return 3; }
  grep -q '^toxic_quote_codename_ok | $' "$tmp/py.txt" || { echo "FAIL: 引号占位替 trailer-summary 的句末 [。！] 伪造终止符（占位字符落进了规则接受位）" >&2; return 3; }

  # AI 自指（软信号）防空转：带型号后缀的最典型退化开场必须命中，且不带拒绝语也要命中
  # （此前 refuse fixture 是被「生成拒绝语」规则接住的，AI 自指规则零覆盖）；复合名词不误报。
  grep -q '^ai_selfref_model | 第2行 元信息泄漏（AI 自指）' "$tmp/py.txt" || { echo "FAIL: AI 自指未命中「作为一个AI语言模型」（无拒绝语）" >&2; return 3; }
  grep -q '^ai_selfref_assistant | 第2行 元信息泄漏（AI 自指）' "$tmp/py.txt" || { echo "FAIL: AI 自指未命中「作为一个AI助手」" >&2; return 3; }
  grep -q '^ai_selfref_era_ok | $' "$tmp/py.txt" || { echo "FAIL: 复合名词「人工智能时代的产物」被 AI 自指误报" >&2; return 3; }

  # 截断收尾标点：】（章尾系统播报模板的收束符）与 ASCII " （ascii 引号模式的收引号）都算收束，
  # 与深扫 oracle check-degeneration.js 的 findTruncation 一致；真截断另由 truncate fixture 锁。
  grep -q '^terminal_banner_ok | $' "$tmp/py.txt" || { echo "FAIL: 以【…】收尾的章末系统播报被误判疑似截断" >&2; return 3; }
  grep -q '^terminal_ascii_quote_ok | $' "$tmp/py.txt" || { echo "FAIL: 以 ASCII 收引号收尾的对话被误判疑似截断" >&2; return 3; }
  grep -q '^truncate | 第2行 疑似截断' "$tmp/py.txt" || { echo "FAIL: 真截断（结尾无标点）未被检出" >&2; return 3; }

  return 0
}

# ── C. 命令函数断言（codex python），CI 硬保证 ───────────────────────────────
# 正文目标抽取（重定向/tee/touch/cp·mv）、apply-patch 目标、git commit 侦测三个纯函数
# （命令串 → 值）在下列 fixture 上逐字相等。此前只在 py/js 手抄、无守卫，已漂移（cp·mv
# 元数、git 控制词 then/do/else/elif、子 shell 括号）。node+python3 在 CI 全平台都在，故为硬门。
# 注：fixture 取两端已收敛的子集；引号内分隔符（echo "a; git commit"）与命令替换（$(git commit)）
# 两端本就不等（py 用 shlex 尊重引号，js 裸拆），非本网职责，且只影响 advisory 不影响拦截。
run_cmd_parity() {
  command -v node >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  cat > "$tmp/cmd.json" <<'EOF'
{
  "redirect": "echo x > short/正文.md",
  "redirect_clobber": "echo x >| short/正文.md",
  "redirect_both": "echo x >& short/正文.md",
  "redirect_fd_dup": "echo short/正文.md >&2",
  "append": "cat a >> 正文.md",
  "tee": "echo x | tee short/正文.md",
  "tee_a": "printf y | tee -a 正文.md",
  "tee_double_dash": "printf y | tee -- short/正文.md",
  "tee_multi": "printf y | tee notes.md short/正文.md",
  "touch": "touch short/正文.md",
  "touch_multi": "touch notes.md short/正文.md",
  "touch_reference": "touch -r short/正文.md notes.md",
  "cp": "cp src.md short/正文.md",
  "cp_command_wrapper": "command cp src.md short/正文.md",
  "cp_command_p_wrapper": "command -p cp src.md short/正文.md",
  "cp_command_double_dash_wrapper": "command -- cp src.md short/正文.md",
  "cp_env_unset_short": "env -u FOO cp src.md short/正文.md",
  "cp_env_unset_long": "env --unset FOO cp src.md short/正文.md",
  "cp_absolute_binary": "/bin/cp src.md short/正文.md",
  "cp_destination_directory": "cp draft/正文.md short/",
  "cp_target_directory": "cp --target-directory=short draft/正文.md",
  "install": "install draft.md short/正文.md",
  "mv2": "mv 正文.md",
  "cp_flag": "cp -f a.md 正文.md",
  "mention": "grep -n short/正文.md notes.md",
  "redirect_quoted_space": "cat draft.md > \"my short/正文.md\"",
  "redirect_fullwidth_space": "cat draft.md > short/正文　补白.md",
  "tee_quoted_space": "printf x | tee 'my short/正文.md'",
  "cp_quoted_space": "cp draft.md \"my short/正文.md\"",
  "cp_quoted_operator": "cp draft.md \"short|archive/正文.md\"",
  "literal_quoted_redirect": "echo '> short/正文.md'",
  "heredoc_mention": "cat <<EOF\n> short/正文.md\nEOF",
  "multiple_heredoc_mention": "cat <<A <<B\nfirst\nA\n> short/正文.md\nB",
  "escaped_heredoc_mention": "cat <<\\EOF\n> short/正文.md\nEOF",
  "escaped_heredoc_then_redirect": "cat <<\\EOF\nliteral\nEOF\necho x > short/正文.md",
  "escaped_quote_tee_mention": "printf '%s\\n' \"literal \\\" | tee short/正文.md\"",
  "nested_shell_redirect": "sh -c 'echo x > short/正文.md'",
  "nested_shell_combined_flags": "bash -lc 'echo x > short/正文.md'",
  "quoted_command_substitution_redirect": "echo \"$(echo x > short/正文.md)\"",
  "quoted_backtick_substitution_redirect": "echo \"`echo x > short/正文.md`\"",
  "patch_add": "*** Begin Patch\n*** Add File: short/正文.md\n+正文\n*** End Patch",
  "patch_move": "*** Begin Patch\n*** Update File: draft.md\n*** Move to: short/正文.md\n+正文\n*** End Patch",
  "patch_move_delete": "*** Begin Patch\n*** Delete File: draft.md\n*** Move to: short/正文.md\n*** End Patch",
  "patch_move_out": "*** Begin Patch\n*** Update File: short/正文.md\n*** Move to: draft.md\n+x\n*** End Patch",
  "patch_delete_only": "*** Begin Patch\n*** Delete File: short/正文.md\n*** End Patch",
  "patch_multi_move": "*** Begin Patch\n*** Add File: notes.md\n+x\n*** Update File: draft.md\n*** Move to: short/正文.md\n+正文\n*** End Patch",
  "patch_context_move": "*** Begin Patch\n*** Update File: short/正文.md\n@@\n *** Move to: notes.md\n+正文\n*** End Patch",
  "commit_plain": "git commit -m x",
  "commit_chain": "git add . && git commit -m x",
  "commit_if": "if true; then git commit -m x; fi",
  "commit_for": "for f in *; do git commit -am x; done",
  "commit_subshell": "(cd sub && git commit)",
  "commit_env": "FOO=1 git commit",
  "commit_config": "git -c user.name=x commit",
  "commit_C": "git -C sub commit -m y",
  "noncommit_echo": "echo git commit docs",
  "noncommit_status": "git status && echo done"
}
EOF
  python3 - "$CODEX" "$tmp/cmd.json" > "$tmp/cpy.txt" <<'PY'
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("ch", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fx = json.load(open(sys.argv[2], encoding='utf-8'))
for k in sorted(fx):
    c = fx[k]
    line = f"{k} :: pros=[{'|'.join(m.extract_prose_targets_from_command(c))}] patch=[{'|'.join(m.extract_apply_patch_targets(c))}] commit={'1' if m.is_git_commit_command(c) else '0'}"
    sys.stdout.buffer.write((line + "\n").encode("utf-8"))
PY
  # 防空转：带空格/全角空格的目标必须整段取出（两端同错也能 diff 通过）。字符类排 \s 会把
  # 「正文　补白.md」截成「正文」、把引号排除在类外会让引号路径整条抽不到目标 → 静默放行。
  grep -q 'redirect_quoted_space :: pros=\[my short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 带空格的引号重定向目标未被整段取出（引号未被尊重）" >&2; return 3; }
  grep -q 'redirect_fullwidth_space :: pros=\[short/正文　补白.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 全角空格文件名被 \\s 截断（U+3000 不是 shell 分词符）" >&2; return 3; }
  grep -q 'tee_quoted_space :: pros=\[my short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 带空格的引号 tee 目标未被整段取出" >&2; return 3; }
  grep -q 'cp_quoted_space :: pros=\[my short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: cp 的引号目标被按空白切碎，末位取到了另一本书的路径" >&2; return 3; }
  grep -q 'cp_quoted_operator :: pros=\[short|archive/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: cp 引号目标里的 | 被误当 shell 管道切段，正文守卫会静默放行" >&2; return 3; }
  grep -q 'tee_double_dash :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: tee -- 的正文目标未被提取" >&2; return 3; }
  grep -q 'tee_multi :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: tee 的第二个正文输出目标未被提取" >&2; return 3; }
  grep -q 'touch_multi :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: touch 的第二个正文目标未被提取" >&2; return 3; }
  grep -q 'touch_reference :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: touch -r 的参考源被误判成写入目标" >&2; return 3; }
  grep -q 'literal_quoted_redirect :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 引号内的重定向示例被误判成真实写入" >&2; return 3; }
  grep -q 'heredoc_mention :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: heredoc 正文中的路径提及被误判成真实写入" >&2; return 3; }
  grep -q 'multiple_heredoc_mention :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 多 heredoc 的后续正文被误判成真实写入" >&2; return 3; }
  grep -q 'escaped_heredoc_mention :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 反斜杠引用 heredoc 正文中的路径提及被误判成真实写入" >&2; return 3; }
  grep -q 'escaped_heredoc_then_redirect :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 反斜杠引用 heredoc 吞掉了其后的真实正文写入" >&2; return 3; }
  grep -q 'escaped_quote_tee_mention :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 转义引号内的 tee 示例被误判成真实写入" >&2; return 3; }
  grep -q 'nested_shell_redirect :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: sh -c 内的真实正文重定向绕过了守卫" >&2; return 3; }
  grep -q 'nested_shell_combined_flags :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: bash -lc 内的真实正文重定向绕过了守卫" >&2; return 3; }
  grep -q 'quoted_command_substitution_redirect :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 双引号内的 \$(...) 正文写入绕过了守卫" >&2; return 3; }
  grep -q 'quoted_backtick_substitution_redirect :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 双引号内的反引号正文写入绕过了守卫" >&2; return 3; }
  grep -q 'cp_command_wrapper :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: command cp 的正文目标未被提取" >&2; return 3; }
  grep -q 'cp_command_p_wrapper :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: command -p cp 的正文目标未被提取" >&2; return 3; }
  grep -q 'cp_command_double_dash_wrapper :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: command -- cp 的正文目标未被提取" >&2; return 3; }
  grep -q 'cp_env_unset_short :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: env -u 包装的 cp 正文目标未被提取" >&2; return 3; }
  grep -q 'cp_env_unset_long :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: env --unset 包装的 cp 正文目标未被提取" >&2; return 3; }
  grep -q 'cp_absolute_binary :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 绝对路径 cp 的正文目标未被提取" >&2; return 3; }
  grep -q 'cp_destination_directory :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: cp 到正文目录时未按源文件名还原落盘目标" >&2; return 3; }
  grep -q 'cp_target_directory :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: cp --target-directory 的正文目标未被提取" >&2; return 3; }
  grep -q 'install :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: install 的正文目标未被提取" >&2; return 3; }
  grep -q 'redirect_clobber :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: >| 正文重定向绕过了守卫" >&2; return 3; }
  grep -q 'redirect_both :: pros=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: >& 文件 正文重定向绕过了守卫" >&2; return 3; }
  grep -q 'redirect_fd_dup :: pros=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: >&2 文件描述符复制被误判成正文写入" >&2; return 3; }
  # 防空转（apply_patch 搬家形态）：`*** Move to:` 是 Update/Delete File 段的子指令，落盘路径是
  # 目的地。只认 Add/Update File 时「Update draft.md + Move to short/正文.md」抽到的是源
  # draft.md → 大纲门整条空过、写后兜底网扫的是已不存在的源（两端同错，diff 也看不出来）。
  grep -q 'patch_move :: pros=\[\] patch=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: apply_patch 的 *** Move to: 目的地未进目标表（源被搬走，只有目的地落盘）" >&2; return 3; }
  grep -q 'patch_move_delete :: pros=\[\] patch=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: *** Delete File: + *** Move to: 的目的地未进目标表" >&2; return 3; }
  grep -q 'patch_move_out :: pros=\[\] patch=\[draft.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 搬出 正文/ 时源仍被当写入目标（源已不存在，只有目的地该被判）" >&2; return 3; }
  grep -q 'patch_delete_only :: pros=\[\] patch=\[\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 纯 *** Delete File: 不该进目标表（删除不是写入，认它只会给删稿误报）" >&2; return 3; }
  grep -q 'patch_multi_move :: pros=\[\] patch=\[notes.md|short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: 一份补丁里 Add 段与 Move 段的目标未同时取全（Move 只该顶替同段的源）" >&2; return 3; }
  grep -q 'patch_context_move :: pros=\[\] patch=\[short/正文.md\]' "$tmp/cpy.txt" \
    || { echo "FAIL: patch 上下文行里的字面 *** Move to 被误当控制指令，实际正文目标被顶掉" >&2; return 3; }

  # ReDoS 回归（shellWords）：调用方先按 [;&|\n] 拆段会拆开引号内的 |，留下一个不闭合的 "。
  # 旧的 /"(?:\\.|[^"])*"|'[^']*'|[^\s]+/ 里 \\. 与 [^"] 都能吃反斜杠，每个反斜杠让搜索空间翻倍，
  # 这条百余字的提交命令实测烧掉数十秒 CPU（超过宿主 hook 的 timeoutMs 15000 被杀）。
  # 线性手写分词必须毫秒级判完，故给 2 秒预算（Python 侧 shlex 本就线性，一并计时防漂移）。
  python3 - "$CODEX" > "$tmp/redos.txt" <<'PY' || return 3
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("ch", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cmd = 'git commit -m "fix: 正则转义覆盖 ' + " ".join([r"\\x"] * 18) + ' covered | see README"'
t0 = time.time()
hit = m.is_git_commit_command(cmd)
ms = int((time.time() - t0) * 1000)
# 失败文案走 stderr.buffer 直写 UTF-8：Windows python 的文本 stderr 是 cp1252，中文会 UnicodeEncodeError
if not hit:
    sys.stderr.buffer.write("FAIL: py 侧 git commit 侦测漏判带转义/管道的提交命令\n".encode("utf-8")); sys.exit(3)
if ms > 2000:
    sys.stderr.buffer.write(f"FAIL: py 侧 git commit 侦测退化成非线性（{ms}ms > 2000ms）\n".encode("utf-8")); sys.exit(3)
PY
  return 0
}

# ── E. staged warnings 与大纲阻断断言（codex python），CI 硬保证 ────────────────
# staged markdown warnings 与大纲阻断判定在 codex python（staged_markdown_warnings /
# prose_block_reason）单处实现，fixture 上锚死命中/静默与中文文案，防回退。
# fixture 至少覆盖：① 正文.md 硬编码角色属性的中文警告文案（含头尾框线）逐字一致、非正文
# 不告警；② 短篇阻断判定 5 组：缺 小节大纲.md（有 设定.md 信号）拦、有 小节大纲.md 放、
# 无 设定.md 信号放、拆文库 导入窗口放、已存在正文放——阻断文案逐字一致。
run_uncored_parity() {
  command -v node >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  command -v git >/dev/null 2>&1 || return 1
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # E1: staged markdown warnings —— 建独立 git 仓库并 stage 固定文件集
  local repo="$tmp/repo"
  mkdir -p "$repo/short"
  git -C "$repo" init -q
  printf '身高: 180\n他推门而入。\n年龄　：18\n' > "$repo/short/正文.md"   # 硬编码属性：告警
  printf '# 设定\n' > "$repo/short/设定.md"                                # 非正文：不告警
  printf 'TODO\n' > "$repo/notes.md"                                       # 非正文 md：不告警
  git -C "$repo" add -A

  python3 - "$CODEX" "$repo" > "$tmp/spy.txt" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("ch", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
out = m.staged_markdown_warnings(Path(sys.argv[2]))
sys.stdout.buffer.write((out + "\n").encode("utf-8"))
PY
  # 防空转（两边都输出空串也会 diff 通过）：断言命中/未命中与统一后的中文文案确实在场
  grep -q '正文硬编码角色属性，应引用设定文件' "$tmp/spy.txt" || { echo "FAIL: staged warnings 未按统一文案报硬编码属性" >&2; return 3; }
  grep -q 'short/正文.md' "$tmp/spy.txt" || { echo "FAIL: staged warnings 未点名硬编码属性的正文文件" >&2; return 3; }
  grep -q '设定.md' "$tmp/spy.txt" && { echo "FAIL: 非正文文件 设定.md 不应报硬编码属性" >&2; return 3; }
  grep -q 'notes.md' "$tmp/spy.txt" && { echo "FAIL: 非正文文件 notes.md 不应报硬编码属性" >&2; return 3; }

  # E2: 大纲阻断判定 —— 短篇 正文.md 首建缺 小节大纲.md(拦)/有(放)/无 设定.md 信号(放)/
  #     拆文库 导入窗口(放)/已存在正文(放)，文案逐字一致
  local blk="$tmp/blk"
  mkdir -p "$blk/nooutline" "$blk/withoutline" "$blk/nosignal" "$blk/import" "$blk/拆文库/import" "$blk/existing"
  : > "$blk/nooutline/设定.md"
  : > "$blk/withoutline/设定.md"
  : > "$blk/withoutline/小节大纲.md"
  : > "$blk/import/设定.md"
  : > "$blk/existing/设定.md"
  printf '正文。\n' > "$blk/existing/正文.md"

  python3 - "$CODEX" "$blk" > "$tmp/bpy.txt" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("ch", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
root = Path(sys.argv[2])
for rel in ["nooutline/正文.md", "withoutline/正文.md", "nosignal/正文.md", "import/正文.md", "existing/正文.md"]:
    reason = m.prose_block_reason(root, root / rel)
    sys.stdout.buffer.write((f"{rel} :: {reason if reason else '-'}\n").encode("utf-8"))
PY
  grep -q 'nooutline/正文.md :: ⛔' "$tmp/bpy.txt" || { echo "FAIL: 短篇缺小节大纲未被拦截" >&2; return 3; }
  grep -q 'withoutline/正文.md :: -' "$tmp/bpy.txt" || { echo "FAIL: 短篇有小节大纲被误拦" >&2; return 3; }
  grep -q 'nosignal/正文.md :: -' "$tmp/bpy.txt" || { echo "FAIL: 无设定.md 信号的正文.md 被误拦" >&2; return 3; }
  grep -q 'import/正文.md :: -' "$tmp/bpy.txt" || { echo "FAIL: 拆文库 导入窗口内的首建正文被误拦" >&2; return 3; }
  grep -q 'existing/正文.md :: -' "$tmp/bpy.txt" || { echo "FAIL: 已存在的正文.md 被误拦（续写/改稿）" >&2; return 3; }

  return 0
}

set +e
run_functional
rc=$?
set -e
case "$rc" in
  0) echo "功能断言：codex python 网（39 fixtures，毒句式正反例/AI 自指/截断收尾/豁免标记全部命中或静默）。" ;;
  *) fails=$((fails + 1)) ;;
esac

set +e
run_cmd_parity
rc_cmd=$?
set -e
case "$rc_cmd" in
  0) echo "命令函数断言：codex python（正文抽取/apply-patch/git commit 侦测扩展 fixtures，含包装器/命令替换/多 heredoc/转义引号、apply_patch 搬家与 ReDoS 预算）。" ;;
  1) echo "命令函数断言：跳过（无 python3 运行时）。" ;;
  *) fails=$((fails + 1)) ;;
esac


set +e
run_uncored_parity
rc_uncored=$?
set -e
case "$rc_uncored" in
  0) echo "staged warnings + 大纲阻断断言：codex python（硬编码属性中文文案 + 短篇 5 组判定：缺小节大纲/有纲/无信号/导入窗口/已存在）。" ;;
  1) echo "staged warnings + 大纲阻断断言：跳过（无 python3/git 运行时）。" ;;
  *) fails=$((fails + 1)) ;;
esac


if [ "$fails" -ne 0 ]; then
  echo "Prose net parity tests FAILED ($fails)." >&2
  exit 1
fi
echo "Prose net parity tests passed."
