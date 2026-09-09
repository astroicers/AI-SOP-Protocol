#!/usr/bin/env bash
# test_gate_gitleaks.sh — 密鑰掃描這一格的端到端釘樁（CLAUDE-IR-2 的機械承接）
#
# 為何需要這支（2026-09-09，獨立複審 F5）：`gitleaks` 檢查進 gate 後，`tests/` 對它
# **零覆蓋**——「有 staged 密鑰 → gate 判紅」這條核心宣稱只活在 .asp-fact-check.md
# FC-016 的散文裡，是一次性的人工 probe，不是可重跑的證據。
#
# ⚠️ **fixture 必須用高熵假 token**：規則庫 `[extend] useDefault = true` 會帶進 gitleaks
# 的預設 allowlist，低熵 dummy（如 `sk-ant-oat01-abcdefghijklmnop…`）會被當測試資料濾掉
# 而 rc=0。照低熵配方寫的測試會**恆綠**——正是本輪一直在抓的那種假證據。
# 故本檔以 /dev/urandom 產生 token，並先自我驗證「這個 fixture 真的會被抓到」。
#
# 同時釘住 F1 的迴歸面：檢查須錨定 ASP_GATE_HOME/ASP_GATE_PROJ，
# **不得吃 CWD**——原版兩個路徑都是裸相對路徑，CWD 一換就假紅（載不到 config）
# 或假綠（掃錯 repo）。
#
# Run: bash tests/test_gate_gitleaks.sh
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ASP_ROOT/.asp/checks/gitleaks.sh"
command -v gitleaks >/dev/null 2>&1 || { echo "SKIP: gitleaks 未安裝"; exit 0; }
[ -f "$CHECK" ] && pass "檢查腳本存在（$CHECK）" || { fail "檢查腳本缺席"; exit 1; }
mk_test_dir gate-gitleaks

# ── 造一個獨立的受檢 repo，staged 一個高熵假 token ──
PROJ="$TEST_DIR/proj"
mkdir -p "$PROJ" && git -C "$PROJ" init -q .
git -C "$PROJ" config user.email t@t && git -C "$PROJ" config user.name t
TOKEN="sk-ant-oat01-$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
printf 'KEY = "%s"\n' "$TOKEN" > "$PROJ/leak.txt"
git -C "$PROJ" add leak.txt

run_check() {  # $1=cwd  → 印 rc
  ( cd "$1" && ASP_GATE_HOME="$ASP_ROOT" ASP_GATE_PROJ="$PROJ" bash "$CHECK" >/dev/null 2>&1; echo $? )
}

# ── (1) fixture 自我驗證：這個 token 真的會被規則庫抓到（防恆綠）──
rc=$(run_check "$PROJ")
[ "$rc" = "1" ] && pass "(1) staged 高熵假 token → rc=1（fixture 有效，非恆綠）" \
                || fail "(1) staged 假 token 未被攔下（rc=$rc）——fixture 失效，此測試等於沒驗"

# ── (2) F1 迴歸：CWD 不在受檢 repo 也不在 ASP 根，仍須正確判紅 ──
rc=$(run_check "$TEST_DIR")
[ "$rc" = "1" ] && pass "(2) CWD 在別處仍判紅（規則庫與掃描標的都靠 env 錨定，不吃 CWD）" \
                || fail "(2) CWD 一換就失準（rc=$rc）——F1 迴歸：路徑未錨定"

# ── (3) 掃描標的須是 ASP_GATE_PROJ，不是 CWD（假綠面）──
# 在一個「自己乾淨」的 repo 裡執行，但指向有密鑰的 PROJ：仍須判紅。
CLEAN="$TEST_DIR/clean"
mkdir -p "$CLEAN" && git -C "$CLEAN" init -q .
git -C "$CLEAN" config user.email t@t && git -C "$CLEAN" config user.name t
rc=$(run_check "$CLEAN")
[ "$rc" = "1" ] && pass "(3) 於乾淨 repo 內執行、指向有密鑰的 PROJ → 仍判紅（不掃錯 repo）" \
                || fail "(3) 掃到 CWD 的 repo 而非 ASP_GATE_PROJ（rc=$rc）——假綠"

# ── (4) 乾淨 staging → 放行 ──
git -C "$PROJ" rm --cached -q leak.txt && rm -f "$PROJ/leak.txt"
printf 'hello\n' > "$PROJ/ok.txt" && git -C "$PROJ" add ok.txt
rc=$(run_check "$PROJ")
[ "$rc" = "0" ] && pass "(4) 乾淨 staged 內容 → rc=0（不過度攔截）" \
                || fail "(4) 乾淨內容被誤擋（rc=$rc）"

# ── (5) 規則庫缺席 → fail-closed（不靜默降級成內建規則）──
rc=$( ASP_GATE_HOME="$TEST_DIR/nowhere" ASP_GATE_PROJ="$PROJ" bash "$CHECK" >/dev/null 2>&1; echo $? )
[ "$rc" = "1" ] && pass "(5) 規則庫缺席 → rc=1 fail-closed（不降級成 gitleaks 內建規則）" \
                || fail "(5) 規則庫缺席卻放行（rc=$rc）——密鑰掃描無聲降級"

# ── (6) 工具缺席 → skip 200（fail-open，刻意；STRICT 轉 fail-closed）──
# PATH 只留系統路徑：bash/coreutils 仍在，但 gitleaks（裝在 ~/.local/bin 之類）不在。
# 不可把 PATH 清空——那樣連 `bash` 都找不到，rc=127 驗到的是別的東西。
BAREPATH="/usr/bin:/bin"
command -v gitleaks >/dev/null 2>&1 && case "$(command -v gitleaks)" in
  /usr/bin/*|/bin/*) echo "  ⏭  (6) 略過：gitleaks 裝在系統路徑，無法以 PATH 排除"; BAREPATH="" ;;
esac
if [ -n "$BAREPATH" ]; then
rc=$( PATH="$BAREPATH" ASP_GATE_HOME="$ASP_ROOT" ASP_GATE_PROJ="$PROJ" bash "$CHECK" >/dev/null 2>&1; echo $? )
[ "$rc" = "200" ] && pass "(6) 工具未安裝 → rc=200 skip（fail-open，刻意）" \
                  || fail "(6) 工具未安裝時行為不符 skip 契約（rc=$rc）"
rc=$( PATH="$BAREPATH" ASP_GATE_STRICT=1 ASP_GATE_HOME="$ASP_ROOT" ASP_GATE_PROJ="$PROJ" bash "$CHECK" >/dev/null 2>&1; echo $? )
[ "$rc" = "1" ] && pass "(6b) ASP_GATE_STRICT=1 + 工具未安裝 → rc=1 fail-closed" \
                || fail "(6b) STRICT 未生效（rc=$rc）"
fi

# ── (7) gate 整合：staged 密鑰 → 輸出含 BLOCKER gitleaks ──
# test-fresh 會先跑，故先在受檢 repo 造一份新鮮痕跡，讓 gate 走得到 gitleaks 那一格。
rm -f "$PROJ/ok.txt"; git -C "$PROJ" rm --cached -q ok.txt 2>/dev/null
printf 'KEY = "%s"\n' "$TOKEN" > "$PROJ/leak2.txt"; git -C "$PROJ" add leak2.txt
printf '{"passed":true,"timestamp":"%s","test_command":"fixture"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PROJ/.asp-test-result.json"
OUT=$(cd "$TEST_DIR" && ASP_GATE_HOME="$ASP_ROOT" ASP_GATE_PROJ="$PROJ" bash "$ASP_ROOT/.asp/gate.sh" 2>&1)
if grep -q "BLOCKER gitleaks" <<<"$OUT"; then
  pass "(7) gate 整合：staged 密鑰 → ❌ BLOCKER gitleaks"
else
  fail "(7) gate 未在 gitleaks 這一格擋下 — 輸出：$(tr '\n' ' ' <<<"$OUT" | head -c 300)"
fi

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
