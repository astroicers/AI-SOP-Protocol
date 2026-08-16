#!/usr/bin/env bash
# ⚠️ 由 `asp render gate` 產生 — 勿手改(單一事實源:asp-gate.yaml)
# source sha256: 21b638b613ee217c873ae4ecfa5e1006591d33c6d922dcdcd123120973ee721b
# gate 子集:test-fresh
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
  if "$@" >/dev/null 2>&1; then
    echo "✅ $id"
  else
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

echo "gate 通過(warnings=$WARNINGS)"
exit 0
