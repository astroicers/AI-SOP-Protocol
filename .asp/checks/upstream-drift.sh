#!/usr/bin/env bash
# upstream-drift.sh — vendored 上游漂移偵測的**節流＋逾時**包裝
#
# 【為何需要這一層】(2026-09-09，第三輪複審 C2)
# `vendor-upstream.sh`（vendored，不得就地修）本身是對的，但把它直接掛進 commit gate
# 有兩個實測出來的成本：
#
#   ① **延遲**：一支就 6.5s（5 條 lock × 兩道 = 10 次 `gh api`），而 gate 的其餘三支
#      合計 0.4s。它是 `warning` 級——**擋不了任何東西**，純延遲，而且每一次
#      `git commit` 都付。成本與收益不成比例。
#   ② **離線時不收斂**：實測單次 `gh api` 在連不上時 10 秒未收斂（gh 自身重試），
#      而 `vendor-upstream.sh` 零 timeout、`gate.sh` 的 `run_check` 零 timeout、
#      hook 也零 timeout。於是離線／VPN 斷線時要嘛 commit 卡數分鐘，要嘛 hook 被
#      harness 逾時砍掉——**後者代表整個 commit 閘連同密鑰掃描一起靜默失效**，
#      比慢嚴重得多。等於把一個安全閘的可用性綁在網路上。
#
# 本包裝做兩件事，兩件都在 repo 自有的碼裡，vendored 檔一個位元組都不動：
#   - **節流**：以 `$PROJ/.asp-upstream-checked`（gitignored）記「上次成功對帳的日期」，
#     今天已經對過就 skip(200)。漂移偵測的價值不隨「一天內跑幾次」增加。
#     ⚠️ 戳記**不放 VENDOR.lock**：那支 vendored 腳本只「建議」回填、自己不寫檔，
#     所以拿 lock 當戳記等於節流永遠不生效（初版就踩了這個洞）；而由本包裝去寫 lock
#     會在每次 commit 弄髒工作樹。故比照 `.asp-test-result.json` 走 gitignored 的旁路檔。
#   - **逾時**：`timeout` 包住整支。逾時視為 skip 而非失敗——它是 informational
#     檢查，網路抖動不該變成紅燈噪音；但**必須印出來**，不讓「沒在跑」隱形
#     （沿用 vendor-upstream 自己的「取不到 ≠ 通過」哲學）。
#
# 輸入(env)：ASP_GATE_HOME / ASP_GATE_PROJ（原樣轉交）
#            ASP_UPSTREAM_TIMEOUT（秒，預設 20）
#            ASP_UPSTREAM_FORCE=1 忽略節流，強制跑一次
# 結束碼：轉交被包裝者的 0/1；節流或逾時 → 200（skip 契約）
set -uo pipefail

HOME_DIR="${ASP_GATE_HOME:-.}"
PROJ="${ASP_GATE_PROJ:-.}"
INNER="$HOME_DIR/.asp/checks/vendor-upstream.sh"
LOCK="$PROJ/.asp/checks/VENDOR.lock"
TIMEOUT="${ASP_UPSTREAM_TIMEOUT:-20}"

[ -f "$INNER" ] || { echo "⏭  upstream-drift: 被包裝者未落地（$INNER）"; exit 200; }
[ -f "$LOCK" ]  || { echo "⏭  upstream-drift: 無 VENDOR.lock，略過"; exit 200; }

# ── 節流：今天對過就不再對 ──
STAMP="$PROJ/.asp-upstream-checked"
TODAY="$(date -u +%Y-%m-%d)"
if [ "${ASP_UPSTREAM_FORCE:-0}" != "1" ] && [ -f "$STAMP" ]; then
  if [ "$(head -1 "$STAMP" 2>/dev/null)" = "$TODAY" ]; then
    echo "⏭  upstream-drift: 今日（$TODAY）已對過帳，略過（ASP_UPSTREAM_FORCE=1 可強制）"
    exit 200
  fi
fi

if ! command -v timeout >/dev/null 2>&1; then
  # 沒有 timeout 可用就不跑——寧可不對帳，也不要讓 commit 卡在網路上。
  echo "⏭  upstream-drift: 系統無 timeout 指令，略過（不冒讓 commit 無限等待的風險）"
  exit 200
fi

OUT=$(ASP_GATE_HOME="$HOME_DIR" ASP_GATE_PROJ="$PROJ" \
      timeout "$TIMEOUT" bash "$INNER" "$PROJ" 2>&1); RC=$?

if [ "$RC" -eq 124 ]; then
  echo "⏭  upstream-drift: ${TIMEOUT}s 內未完成，略過本次對帳"
  echo "   → 多半是離線或上游不可達。**這代表本次沒有對過帳**，不是「與上游一致」。"
  echo "   → 網路恢復後 ASP_UPSTREAM_FORCE=1 bash .asp/checks/upstream-drift.sh 補跑。"
  exit 200
fi

printf '%s\n' "$OUT"
# 只有**真的跑完**才推進戳記（逾時走上面的 exit 200，不會到這裡）。
# rc=1（發現漂移）也算跑完：漂移要靠人處理，不該每次 commit 重報一次。
{ printf '%s\n' "$TODAY" > "$STAMP"; } 2>/dev/null || true
exit "$RC"
