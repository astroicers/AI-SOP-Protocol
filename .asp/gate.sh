#!/usr/bin/env bash
# ⚠️ 由 `asp render gate` 產生 — 勿手改(單一事實源:asp-gate.yaml)
# source sha256: 2855b339a4a0f20175aaf3f36fad8a18f0a5c1a561d9ede04b91cf78218fddde
# gate 子集:test-fresh, gitleaks, vendor-verify, vendor-upstream
set -u
STRICT="${ASP_GATE_STRICT:-0}"
WARNINGS=0
ALL_CHECKS=('test-fresh' 'gitleaks' 'vendor-verify' 'vendor-upstream')
_SUM_SEEN=" "

# ---- 可觀測性(全部 env-guarded;未設 GITHUB_* 時本機輸出逐字不變)----
_on_actions() { [ "${GITHUB_ACTIONS:-}" = "true" ]; }
_group()    { if _on_actions; then echo "::group::$1"; fi; }
_endgroup() { if _on_actions; then echo "::endgroup::"; fi; }
_ann() {  # level id message —— 失敗浮到 PR conversation 與 Checks 分頁
  if _on_actions; then printf '::%s title=%s::%s\n' "$1" "$2" "$3"; fi
}
_sum() {  # id 結果 —— 同一 id 只記一列
  case "$_SUM_SEEN" in *" $1 "*) return 0 ;; esac
  _SUM_SEEN="$_SUM_SEEN$1 "
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '| %s | %s |\n' "$1" "$2" >> "$GITHUB_STEP_SUMMARY"
  fi
}
_sum_open() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo "### gate 檢查"; echo; echo "| check | 結果 |"; echo "| --- | --- |"; } >> "$GITHUB_STEP_SUMMARY"
  fi
}
_sum_close() {  # blocker 早退後剩下沒跑的那幾支,要在表格裡看得見
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    for _c in "${ALL_CHECKS[@]}"; do
      case "$_SUM_SEEN" in *" $_c "*) continue ;; esac
      printf '| %s | ⛔ 未執行(前一支 blocker 早退) |\n' "$_c" >> "$GITHUB_STEP_SUMMARY"
    done
  fi
}
_sum_open
trap _sum_close EXIT

skip() { echo "⏭  $1: 略過($2)"; _sum "$1" "⏭ 略過"; }

missing_blocker() {  # id 腳本路徑 —— blocker 級檢查不得因缺檔而停用
  _ann error "$1" "檢查腳本缺席($2)——blocker 級檢查不得因缺檔而停用"
  _sum "$1" "❌ 檢查腳本缺席"
  echo "❌ BLOCKER $1: 檢查腳本缺席($2)——blocker 級檢查不得因缺檔而停用"
  exit 1
}

run_check() {  # id severity required_bin skip200 cmd...
  local id="$1" sev="$2" req="$3" skip200="$4"; shift 4
  if ! command -v "$req" >/dev/null 2>&1; then
    if [ "$STRICT" = "1" ] && [ "$sev" = "blocker" ]; then
      _ann error "$id" "工具缺失 $req(strict 模式)"; _sum "$id" "❌ 工具缺失"
      echo "❌ BLOCKER $id: 工具缺失 $req(strict 模式)"; exit 1
    fi
    skip "$id" "工具未安裝:$req(vendoring 由 P2 base image 落地)"; return 0
  fi
  # 輸出捕捉後透傳(issue #33):失敗必印診斷。skip 契約 = exit 200,
  # **僅 ASP 自有檢查(builtin-script)適用**——第三方工具若回 200 應依
  # severity 處置,否則 blocker 會靜默 fail-open(issue #46)
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  _group "$id"
  if [ "$rc" -eq 200 ] && [ "$skip200" = "1" ]; then
    [ -n "$out" ] && printf "%s\n" "$out" || skip "$id" "子檢查自報跳過"
    _sum "$id" "⏭ 略過"
  elif [ "$rc" -eq 0 ]; then
    echo "✅ $id"; _sum "$id" "✅ 通過"
  else
    [ -n "$out" ] && printf "%s\n" "$out"
    case "$sev" in
      blocker) _sum "$id" "❌ BLOCKER"; _ann error "$id" "blocker 檢查失敗(rc=$rc)"
               echo "❌ BLOCKER $id"; _endgroup; exit 1 ;;
      warning) _sum "$id" "⚠️ warning"; _ann warning "$id" "warning 檢查失敗(rc=$rc)"
               echo "⚠️  $id(warning)"; WARNINGS=$((WARNINGS+1)) ;;
      *)       _sum "$id" "ℹ️ info"; echo "ℹ️  $id(info)" ;;
    esac
  fi
  _endgroup
}

if [ -f "${ASP_GATE_HOME:-.}/.asp/checks/test-fresh.sh" ]; then
  run_check 'test-fresh' blocker bash 1 bash "${ASP_GATE_HOME:-.}/.asp/checks/test-fresh.sh"
else
  missing_blocker 'test-fresh' '.asp/checks/test-fresh.sh'
fi
run_check 'gitleaks' blocker 'gitleaks' 0 'gitleaks' 'protect' '--staged' '--config' '.asp/gitleaks.toml'
if [ -f "${ASP_GATE_HOME:-.}/.asp/checks/vendor-verify.sh" ]; then
  run_check 'vendor-verify' blocker bash 1 bash "${ASP_GATE_HOME:-.}/.asp/checks/vendor-verify.sh"
else
  missing_blocker 'vendor-verify' '.asp/checks/vendor-verify.sh'
fi
if [ -f "${ASP_GATE_HOME:-.}/.asp/checks/vendor-upstream.sh" ]; then
  run_check 'vendor-upstream' warning bash 1 bash "${ASP_GATE_HOME:-.}/.asp/checks/vendor-upstream.sh"
else
  skip 'vendor-upstream' '檢查腳本未落地(.asp/checks/vendor-upstream.sh)'
fi

echo "gate 通過(warnings=$WARNINGS)"
exit 0
