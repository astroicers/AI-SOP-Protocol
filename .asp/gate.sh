#!/usr/bin/env bash
# ⚠️ 由 `asp render gate` 產生 — 勿手改(單一事實源:asp-gate.yaml)
# source sha256: 56550d176f516cf63c06fcfd5eade4bdedfd8476d0028592d778657130a7cf5b
# gate 子集:test-fresh, vendor-verify
set -u
STRICT="${ASP_GATE_STRICT:-0}"
WARNINGS=0

skip() { echo "⏭  $1: 略過($2)"; }

run_check() {  # id severity required_bin cmd...
  local id="$1" sev="$2" req="$3"; shift 3
  if ! command -v "$req" >/dev/null 2>&1; then
    if [ "$STRICT" = "1" ] && [ "$sev" = "blocker" ]; then
      echo "❌ BLOCKER $id: 工具缺失 $req(strict 模式)"; exit 1
    fi
    skip "$id" "工具未安裝:$req(vendoring 由 P2 base image 落地)"; return 0
  fi
  # 輸出捕捉後透傳(issue #33):失敗必印診斷。skip 契約 = exit 200
  # (ASP 自有檢查專用,與輸出內容無關——對雜訊雙向免疫,QA 輪裁定)
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 200 ]; then
    [ -n "$out" ] && printf "%s\n" "$out" || skip "$id" "子檢查自報跳過"
  elif [ "$rc" -eq 0 ]; then
    echo "✅ $id"
  else
    [ -n "$out" ] && printf "%s\n" "$out"
    case "$sev" in
      blocker) echo "❌ BLOCKER $id"; exit 1 ;;
      warning) echo "⚠️  $id(warning)"; WARNINGS=$((WARNINGS+1)) ;;
      *)       echo "ℹ️  $id(info)" ;;
    esac
  fi
}

if [ -f "${ASP_GATE_HOME:-.}/.asp/checks/test-fresh.sh" ]; then
  run_check 'test-fresh' blocker bash bash "${ASP_GATE_HOME:-.}/.asp/checks/test-fresh.sh"
else
  skip 'test-fresh' '檢查腳本未落地(.asp/checks/test-fresh.sh)'
fi
if [ -f "${ASP_GATE_HOME:-.}/.asp/checks/vendor-verify.sh" ]; then
  run_check 'vendor-verify' blocker bash bash "${ASP_GATE_HOME:-.}/.asp/checks/vendor-verify.sh"
else
  skip 'vendor-verify' '檢查腳本未落地(.asp/checks/vendor-verify.sh)'
fi

echo "gate 通過(warnings=$WARNINGS)"
exit 0
