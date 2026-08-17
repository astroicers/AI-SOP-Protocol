#!/usr/bin/env bash
# .asp/checks/vendor-verify.sh — vendored 檢查本體來源對帳(asp-gate.yaml id: vendor-verify)
#
# 動機(asp-ng issue #43):消費端 repo 以 vendoring 持有 asp-ng 的渲染物與檢查本體,
# 兩側之間原本無任何對帳——上游改了消費端不知道、消費端被就地改也沒人發現。
#
# 本檢查負責「本地竄改偵測」:VENDOR.lock 記錄每份 vendored 檔的來源與 vendoring
# 當下的 sha256,實際檔案與記錄不符即紅。**上游變更偵測**需跨 repo 讀取,屬 cron
# 家族(ADR-000 §7),待 asp-ng 轉 public 後消費端 CI 可直接 raw 比對(見 #43)。
#
# 用法:vendor-verify.sh [repo 根目錄]
#   缺參數取 ${ASP_GATE_PROJ:-.};無 VENDOR.lock(未 vendoring 之 repo,含 asp-ng
#   自身作為上游)→ exit 200(skip 契約)。
#
# VENDOR.lock 格式(空白分隔四欄,# 為註解):
#   <檔名> <上游 repo> <上游路徑> <sha256>
# 檔名相對於 VENDOR.lock 所在目錄。
set -u

ROOT="${1:-${ASP_GATE_PROJ:-.}}"
LOCK="$ROOT/.asp/checks/VENDOR.lock"

if [ ! -f "$LOCK" ]; then
  echo "⏭  vendor-verify: 無 VENDOR.lock($LOCK),略過"
  exit 200
fi

DIR="$(dirname "$LOCK")"
FAIL=0
COUNT=0

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  # shellcheck disable=SC2086
  set -- $line
  if [ "$#" -ne 4 ]; then
    echo "❌ vendor-verify: VENDOR.lock 格式錯誤(需四欄:檔名 上游repo 上游路徑 sha256):$line"
    FAIL=1
    continue
  fi
  name="$1"; upstream_repo="$2"; upstream_path="$3"; want="$4"
  target="$DIR/$name"
  COUNT=$((COUNT + 1))

  if [ ! -f "$target" ]; then
    echo "❌ vendor-verify: 缺檔 $name(來源 $upstream_repo:$upstream_path)"
    FAIL=1
    continue
  fi
  got="$(sha256sum "$target" 2>/dev/null | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "❌ vendor-verify: $name sha256 不符(來源 $upstream_repo:$upstream_path)"
    echo "   記錄 $want"
    echo "   實際 $got"
    echo "   → 就地改動請改上游後重新 vendoring 並更新 VENDOR.lock"
    FAIL=1
  fi
done < "$LOCK"

if [ "$FAIL" = 0 ]; then
  echo "✅ vendor-verify: $COUNT 份 vendored 檔與來源記錄一致"
fi
exit "$FAIL"
