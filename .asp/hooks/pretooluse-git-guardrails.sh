#!/usr/bin/env bash
# pretooluse-git-guardrails.sh — PreToolUse 本地毀資料護欄（SPEC-016 / ADR-030）
#
# 於 Bash 執行前攔截「本地毀滅性 git 操作」（不可逆銷毀未提交/未合併/未追蹤本地成果）：
# reset --hard / clean(force,!dry-run,!interactive) / branch force-delete /
# checkout|restore|switch 丟工作區 / stash clear|drop / worktree remove --force / rm --force。
# 命中 → permissionDecision:deny（FC-002 方式 A）+ GIT-GUARD block 遙測；ASP_GIT_OK=1（hook
# env）→ defer + bypass 遙測；jq 缺 → defer+WARN；stdin 空/無 command → defer 靜默（no-op）。
# 把 CLAUDE-IR-1（破壞性操作前須人類確認）的本地 git 子集從散文升硬強制。
#
# 判定純由 tool_input.command 的語法/argv 決定（無狀態）。謂詞規範＝SPEC-016 M0/M1；
# 誠實能力邊界（前綴補全/命令替換/包裝前綴/checkout 檔路徑）見 SPEC-016 與 FC-013。
# 本腳本受 Iron Rule A 保護（改它即繞過 → session-audit 偵測）。
set -uo pipefail

# ── fail-open：jq 缺 → defer + WARN ──
command -v jq >/dev/null 2>&1 || { echo "[ASP] git-guardrails: jq 缺，fail-open defer" >&2; exit 0; }

INPUT=$(cat 2>/dev/null) || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0          # stdin 空/無 command → no-op 靜默 defer
# GG-SEC-01：純 bash 逐字元 tokenizer 為 O(n²)；上限防超長 command DoS（→timeout→fail-open
# 繞過向量）。真實 git 命令遠短於此；超長 → 靜默 defer（護欄漏擋超長屬可接受 fail-open）。
[ "${#COMMAND}" -le 8192 ] || exit 0

# ══════════════════════════════════════════════════════════════
# M0：分段與 tokenize（引號感知 best-effort）
# ══════════════════════════════════════════════════════════════

# _split_segments <command> — 引號外的 ; & | 換行 為分段點；保留引號原字元供 tokenize。
_split_segments() {
  local s="$1"; local i=0 n=${#s} c q='' seg=''
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    if [ -n "$q" ]; then
      seg+=$c; [ "$c" = "$q" ] && q=''
    elif [ "$c" = "'" ] || [ "$c" = '"' ]; then
      q=$c; seg+=$c
    elif [ "$c" = ';' ] || [ "$c" = '&' ] || [ "$c" = '|' ] || [ "$c" = $'\n' ]; then
      printf '%s\n' "$seg"; seg=''
    else
      seg+=$c
    fi
    i=$((i+1))
  done
  printf '%s\n' "$seg"
}

# _load_argv <segment> — 引號感知空白切 token 進全域 ARGV[]（去引號）。
_load_argv() {
  local s="$1"; local i=0 n=${#s} c q='' tok='' have=0
  ARGV=()
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=''; else tok+=$c; fi
    elif [ "$c" = "'" ] || [ "$c" = '"' ]; then
      q=$c; have=1
    elif [[ "$c" =~ [[:space:]] ]]; then
      [ "$have" = 1 ] && { printf -v _ '%s' "$tok"; ARGV+=("$tok"); tok=''; have=0; }
    else
      tok+=$c; have=1
    fi
    i=$((i+1))
  done
  [ "$have" = 1 ] && ARGV+=("$tok")
}

# ══════════════════════════════════════════════════════════════
# M1：謂詞 helper（操作全域 SUBARGS[]）
# ══════════════════════════════════════════════════════════════

_arg_has() {                         # 精確 token 比對（case-sensitive）
  local a
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do [ "$a" = "$1" ] && return 0; done
  return 1
}
_bundle_has() {                      # 短旗標捆綁（-xyz，非 --）含字母 $1
  local a rest
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in
      --*) : ;;
      -?*) rest="${a#-}"; case "$rest" in *"$1"*) return 0 ;; esac ;;
    esac
  done
  return 1
}
# _bundle_has_flag <char> <argchars> — 捆綁含「獨立旗標」char；掃到「需參數短旗標」
# （argchars 之一）即停：其後字元是該旗標的參數、非旗標（如 checkout -Bf 的 f＝-B 的分支名，
# switch -cf 的 f＝-c 的分支名）。用於 -f/-C 這類與「需參數建分支旗標」可能同 token 者。
_bundle_has_flag() {
  local char="$1" argchars="$2" a rest i c
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in --*) continue ;; -?*) rest="${a#-}" ;; *) continue ;; esac
    i=0
    while [ "$i" -lt "${#rest}" ]; do
      c="${rest:$i:1}"
      [ "$c" = "$char" ] && return 0
      case "$argchars" in *"$c"*) break ;; esac
      i=$((i+1))
    done
  done
  return 1
}
_positionals() {                     # 子命令後非 - 開頭 token → 全域 POS[]
  local a
  POS=()
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in -*) : ;; *) POS+=("$a") ;; esac
  done
}

_pred_reset()  { _arg_has "--hard" && { MATCHED="reset --hard"; return 0; }; return 1; }
_pred_rm()     { { _arg_has "--force" || _bundle_has f; } && { MATCHED="rm --force"; return 0; }; return 1; }

_pred_clean() {
  local force=0 dry=0 inter=0
  { _arg_has "--force" || _bundle_has f; } && force=1
  { _arg_has "--dry-run" || _bundle_has n; } && dry=1
  { _arg_has "--interactive" || _bundle_has i; } && inter=1
  [ "$force" = 1 ] && [ "$dry" = 0 ] && [ "$inter" = 0 ] && { MATCHED="clean --force"; return 0; }
  return 1
}

_pred_branch() {
  { _arg_has "-D" || _bundle_has D; } && { MATCHED="branch -D"; return 0; }
  local del=0 frc=0
  { _arg_has "-d" || _arg_has "--delete" || _bundle_has d; } && del=1
  { _arg_has "-f" || _arg_has "--force" || _bundle_has f; } && frc=1
  [ "$del" = 1 ] && [ "$frc" = 1 ] && { MATCHED="branch --delete --force"; return 0; }
  return 1
}

_pred_checkout() {
  # -f/--force/捆綁含 f（獨立旗標；-b/-B 為需參數建分支旗標，其後字母是分支名非旗標）
  { _arg_has "-f" || _arg_has "--force" || _bundle_has_flag f "bB"; } && { MATCHED="checkout --force"; return 0; }
  { _arg_has "-p" || _arg_has "--patch"; } && return 1                       # 先決：互動
  { _arg_has "-b" || _arg_has "-B" || _arg_has "--orphan"; } && return 1     # 先決：建分支
  _arg_has "--" && { MATCHED="checkout -- (pathspec 丟棄)"; return 0; }
  _positionals
  [ "${#POS[@]}" -ge 2 ] && { MATCHED="checkout <ref> <pathspec>"; return 0; }
  [ "${#POS[@]}" = 1 ] && [ "${POS[0]}" = "." ] && { MATCHED="checkout ."; return 0; }
  return 1
}

_pred_restore() {
  { _arg_has "-p" || _arg_has "--patch"; } && return 1                       # 先決：互動
  local hasW=0 hasS=0
  { _arg_has "-W" || _arg_has "--worktree" || _bundle_has W; } && hasW=1
  { _arg_has "-S" || _arg_has "--staged" || _bundle_has S; } && hasS=1
  [ "$hasW" = 1 ] && { MATCHED="restore --worktree"; return 0; }
  [ "$hasS" = 0 ] && [ "$hasW" = 0 ] && { MATCHED="restore (預設工作區)"; return 0; }
  return 1
}

_pred_switch() {
  # -C/捆綁含 C（force-create；-c 為需參數安全建分支，其後字母是分支名）
  { _arg_has "-C" || _bundle_has_flag C "c"; } && { MATCHED="switch --force-create"; return 0; }
  # -f/--force/--discard-changes/--force-create/捆綁含 f（-c/-C 需參數，其後非旗標）
  { _arg_has "--force-create" || _arg_has "--discard-changes" \
    || _arg_has "-f" || _arg_has "--force" || _bundle_has_flag f "cC"; } && { MATCHED="switch (force/discard)"; return 0; }
  return 1
}

_pred_stash() {                      # 第一個 positional 為 clear/drop（-- 後皆 pathspec）
  local a
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in
      --) return 1 ;;                # 選項終止符：其後為 pathspec，非子命令（OB-01）
      -*) continue ;;
      clear|drop) MATCHED="stash $a"; return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}

_pred_worktree() {                   # 第一個非選項參數 = remove 且有 force
  local a first=""
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in -*) continue ;; *) first="$a"; break ;; esac
  done
  [ "$first" = "remove" ] || return 1
  { _arg_has "-f" || _arg_has "--force" || _bundle_has f; } && { MATCHED="worktree remove --force"; return 0; }
  return 1
}

# _analyze_segment <segment> — 命中本地毀滅性 git → return 0（設 MATCHED）
_analyze_segment() {
  _load_argv "$1"
  local n=${#ARGV[@]} i=0 t sub
  [ "$n" -gt 0 ] || return 1
  while [ "$i" -lt "$n" ]; do                # M0.3：跳 VAR=val 前綴
    case "${ARGV[$i]}" in [A-Za-z_]*=*) i=$((i+1)) ;; *) break ;; esac
  done
  [ "$i" -lt "$n" ] && [ "${ARGV[$i]}" = "git" ] || return 1
  i=$((i+1))
  while [ "$i" -lt "$n" ]; do                # M0.4：跳全域選項
    t="${ARGV[$i]}"
    case "$t" in
      --exec-path) i=$((i+1)) ;;                                             # 不吃下一 token
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix) i=$((i+2)) ;;  # 吃參數
      --*=*) i=$((i+1)) ;;
      -*) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  sub="${ARGV[$i]}"
  SUBARGS=("${ARGV[@]:$((i+1))}")
  case "$sub" in
    reset)    _pred_reset ;;
    clean)    _pred_clean ;;
    branch)   _pred_branch ;;
    checkout) _pred_checkout ;;
    restore)  _pred_restore ;;
    switch)   _pred_switch ;;
    stash)    _pred_stash ;;
    worktree) _pred_worktree ;;
    rm)       _pred_rm ;;
    *) return 1 ;;
  esac
}

# ══════════════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════════════
MATCHED=""; HIT=0
while IFS= read -r _seg; do
  [ -n "$_seg" ] || continue
  if _analyze_segment "$_seg"; then HIT=1; break; fi
done < <(_split_segments "$COMMAND")

[ "$HIT" = 1 ] || exit 0             # 無命中 → defer

METRICS_FILE="${ASP_METRICS_FILE:-$HOME/.claude/asp/metrics/rule-hits.jsonl}"
write_metric() {                     # $1=action(block|bypass)
  local line
  line=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg p "$(basename "${CLAUDE_PROJECT_DIR:-.}")" --arg a "$1" \
    '{ts:$ts,project:$p,rule_id:"GIT-GUARD",action:$a}' 2>/dev/null) || return 0
  { mkdir -p "${METRICS_FILE%/*}" && printf '%s\n' "$line" >>"$METRICS_FILE"; } 2>/dev/null || true
}

# escape hatch：命中但 ASP_GIT_OK=1（hook env）→ defer + 留痕
if [ "${ASP_GIT_OK:-}" = "1" ]; then
  write_metric bypass
  exit 0
fi

write_metric block
REASON="ASP git-guardrails：偵測到本地毀滅性操作（${MATCHED}），將不可逆銷毀本地成果（未提交變更/未合併分支/未追蹤檔）。破壞性操作前須人類確認（鐵則 CLAUDE-IR-1）。確認要執行 → 在 Claude Code 啟動環境設 ASP_GIT_OK=1 後重試（會留 GIT-GUARD 遙測）；否則請改用非破壞替代（git stash 代 reset --hard、git clean -n 先預覽、git branch -d 代 -D）。"
jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
