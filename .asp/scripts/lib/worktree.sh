#!/usr/bin/env bash
# .asp/scripts/lib/worktree.sh — worktree 解析共用 lib（SPEC-017 DP1=b：單一真相）
#
# 供 session-audit.sh 與 pretooluse-ship-gate.sh source；受 Iron Rule A hash 保護
# （已列入 session-audit CRITICAL_FILE 清單，T10）。
# 語意錨（#72 兩輪審查定案）：anchor-first + 絕對 git-common-dir 相等 + 同 superproject
# 血緣守衛。本檔取代 ADR-029 L66-67 草稿 snippet（SPEC-017 Expected Output 1 為準）。
#
# 僅定義函式、無副作用；被 source 於 `set -uo pipefail` 環境下須安全。

# _abs_common_dir — 逐字取自 pretooluse-ship-gate.sh #72 實作（cd+pwd 手動正規化，
# 非 --path-format=absolute 旗標——後者未經 #72 兩輪審查；勿自創第三種正規化變體）。
_abs_common_dir(){ # $1=dir → 絕對 git-common-dir（失敗印空）
  local d; d="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$d" ] || return 0
  case "$d" in
    /*) printf '%s\n' "$d" ;;
    *)  ( cd "$1" 2>/dev/null && cd "$d" 2>/dev/null && pwd ) ;;
  esac
}

# asp_resolve_worktree — SPEC-017 Expected Output 1。
# 解析「本 session 實際所在的 worktree 頂層」：
#   cwd 非 git / 解析失敗          → anchor（fail-open 退錨）
#   cwd 頂層 == anchor（含子目錄）  → anchor（短路）
#   cwd 為同 superproject worktree → cwd 的 worktree 頂層
#   cwd 為無關 repo（planted）     → anchor（血緣守衛）
# 已知限制（SH-02，方向保守）：anchor 路徑含 symlink 時 logical/physical 路徑比不相等
# → 恆退錨（僅失去 worktree 感知、不誤放 planted）；修復需動 _abs_common_dir 正規化
# 語意，違反「逐字取自 #72」鐵律，故列已知限制不修。
asp_resolve_worktree() {           # $1 = cwd 訊號（SessionStart 傳 stdin .cwd）
  local anchor="${CLAUDE_PROJECT_DIR:-$PWD}" cwd="${1:-$PWD}" top a c
  anchor="${anchor%/}"; [ -n "$anchor" ] || anchor="/"   # 去尾斜線（SH-01：防主樹誤判 worktree）
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { printf '%s' "$anchor"; return; }
  [ "$top" = "$anchor" ] && { printf '%s' "$anchor"; return; }
  a=$(_abs_common_dir "$anchor")
  c=$(_abs_common_dir "$cwd")
  [ -n "$c" ] && [ "$c" = "$a" ] && printf '%s' "$top" || printf '%s' "$anchor"
}
