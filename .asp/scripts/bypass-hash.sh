#!/usr/bin/env bash
# bypass-hash.sh — Iron Rule B per-entry hash chain（SPEC-012 / ADR-019）
#
# 單一實作點（FIND-1）：canonical / hash / rechain / verify 共用同一規範，
# 避免寫入/驗證/遷移三端格式不一致 → 同內容算出不同 hash → 全 chain 假陽性。
#
# canonical = jq -cS（去掉 prev/h 欄，key 字典序 + 緊湊）
# material   = prev + "\n" + canonical
# h          = sha256(material) 小寫 hex
# 首筆 prev  = "GENESIS"
#
# 用法：
#   bypass-hash.sh canonical <entry_json>     → 印 canonical
#   bypass-hash.sh hash <prev> <entry_json>   → 印 h
#   bypass-hash.sh rechain <ndjson_file>      → 原子重算整檔 chain（去舊 prev/h 重算）
#   bypass-hash.sh verify <ndjson_file>       → 完整 exit 0；斷裂 exit 1 + stderr 首斷行號
#
# 能力邊界（ADR-019 誠實界定）：chain 偵測「中間竄改/刪除、等量替換」；
# 「末尾截斷」由 HWM sidecar 偵測（互補）；對「知道機制的完整重算」非 tamper-proof。

set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

GENESIS="GENESIS"

canonical() { printf '%s' "$1" | jq -cS 'del(.prev, .h)'; }

hash_entry() { # $1=prev $2=entry → h
  local prev="$1" canon
  canon=$(canonical "$2") || return 1
  printf '%s\n%s' "$prev" "$canon" | sha256sum | cut -d' ' -f1
}

cmd="${1:-}"
case "$cmd" in
  canonical)
    canonical "${2:?entry json required}"
    ;;
  hash)
    hash_entry "${2:?prev required}" "${3:?entry json required}"
    ;;
  rechain)
    f="${2:?ndjson file required}"
    [ -f "$f" ] || { echo "ERROR: file not found: $f" >&2; exit 2; }
    tmp=$(mktemp); prev="$GENESIS"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      h=$(hash_entry "$prev" "$line") || { rm -f "$tmp"; echo "ERROR: hash failed" >&2; exit 3; }
      printf '%s\n' "$line" | jq -c --arg p "$prev" --arg h "$h" \
        'del(.prev,.h) + {prev:$p, h:$h}' >> "$tmp" || { rm -f "$tmp"; exit 3; }
      prev="$h"
    done < "$f"
    mv "$tmp" "$f"
    ;;
  verify)
    f="${2:?ndjson file required}"
    [ -f "$f" ] || { echo "ERROR: file not found: $f" >&2; exit 2; }
    prev="$GENESIS"; n=0; rc=0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      n=$((n+1))
      eprev=$(printf '%s' "$line" | jq -r '.prev // ""')
      eh=$(printf '%s' "$line" | jq -r '.h // ""')
      if [ -z "$eh" ] || [ -z "$eprev" ]; then
        echo "broken at line $n: missing prev/h" >&2; rc=1; break
      fi
      if [ "$eprev" != "$prev" ]; then
        echo "broken at line $n: prev mismatch (expected $prev)" >&2; rc=1; break
      fi
      calc=$(hash_entry "$eprev" "$line")
      if [ "$calc" != "$eh" ]; then
        echo "broken at line $n: hash mismatch" >&2; rc=1; break
      fi
      prev="$eh"
    done < "$f"
    exit $rc
    ;;
  *)
    echo "usage: bypass-hash.sh {canonical|hash|rechain|verify} ..." >&2; exit 2
    ;;
esac
