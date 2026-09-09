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
# 只看 rc 會恆真：gitleaks 自己對缺 config 也回 1，斷言分辨不出是哪個機制擋的。
# 故一併驗本腳本專屬的診斷句。
OUT5=$( ASP_GATE_HOME="$TEST_DIR/nowhere" ASP_GATE_PROJ="$PROJ" bash "$CHECK" 2>&1 ); rc=$?
if [ "$rc" = "1" ] && grep -q "規則庫缺席" <<<"$OUT5"; then
  pass "(5) 規則庫缺席 → rc=1 且由本腳本的守衛擋下（不降級成 gitleaks 內建規則）"
else
  fail "(5) 規則庫缺席的處置不符（rc=$rc）— 「$(head -c 160 <<<"$OUT5")」"
fi

# ── (5b) PROJ 不是 git repo → fail-closed（第三輪複審：初版此處 rc=0 假綠）──
mkdir -p "$TEST_DIR/notarepo"
OUT5B=$( ASP_GATE_HOME="$ASP_ROOT" ASP_GATE_PROJ="$TEST_DIR/notarepo" bash "$CHECK" 2>&1 ); rc=$?
if [ "$rc" = "1" ] && grep -q "不是 git repo" <<<"$OUT5B"; then
  pass "(5b) PROJ 非 git repo → rc=1 fail-closed（不把「什麼都沒掃」當成「無命中」）"
else
  fail "(5b) PROJ 非 git repo 卻放行（rc=$rc）——假綠 — 「$(head -c 160 <<<"$OUT5B")」"
fi

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

# ── (8) deny 訊息不得把密鑰本身帶出去 ──
# hook 會把 gate 的診斷行併進 permissionDecisionReason（複審 F2 的修法），而 gitleaks
# 命中時的原始輸出**含密鑰明文**。目前靠「只取 ❌/⚠️/✅/⏭ 開頭的行」把它濾掉——
# 這條過濾是承載安全性質的，不能只靠人工驗過一次。
HOOK="$ASP_ROOT/.asp/hooks/pretooluse-ship-gate.sh"
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
  REASON=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$PROJ" \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$TEST_DIR/m.jsonl" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
  # ⚠️ 斷言必須綁 case dispatch 產生的**前綴**，不能只 grep "gitleaks"——
  # `_DETAIL` 必然把 `❌ BLOCKER gitleaks` 原樣帶進 reason，拿那個詞當斷言會恆真
  # （第三輪複審變異實測：把 sed+case 整組廢掉，舊斷言照樣綠）。
  if grep -q "ASP commit 閘（gitleaks）" <<<"$REASON"; then
    pass "(8a) deny 訊息的謂詞由 dispatch 產生並指向 gitleaks"
  else
    fail "(8a) deny 訊息未由 dispatch 指向 gitleaks — 「${REASON:0:200}」"
  fi
  # (8b) 密鑰不得出現在 deny 訊息。
  # ⚠️ 誠實記：這條**目前是縱深防禦而非唯一屏障**——實測 `gitleaks protect` 預設輸出
  # 只印計數（`leaks found: 1`），**不印 finding 明細**，所以現階段根本沒有密鑰可外洩。
  # 變異測試證實：把 hook 的診斷行過濾整個拿掉，本條仍綠。
  # 保留它是因為那個前提會變：一旦有人給 gitleaks 加上 -v／--report-format，
  # finding（含 `Secret:`）就會進 gate 輸出。屆時本條會是唯一擋住它的斷言。
  if grep -qF "${TOKEN: -16}" <<<"$REASON"; then
    fail "(8b) **密鑰明文外洩到 deny 訊息**"
  else
    pass "(8b) 密鑰未出現在 deny 訊息（縱深防禦；目前 gitleaks 預設輸出本就不含明細）"
  fi

  # (8c) 真正釘住那條過濾：用 stub gate 吐一行**非標記開頭**的內容，
  # 斷言它不會被帶進 reason。(8b) 驗不到這件事，這條才驗得到。
  STUB="$TEST_DIR/stub"; mkdir -p "$STUB/.asp/hooks"
  cp "$HOOK" "$STUB/.asp/hooks/"
  cat > "$STUB/.asp/gate.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "SENTINEL-MUST-NOT-REACH-REASON"
echo "❌ BLOCKER gitleaks"
exit 1
STUBEOF
  R2=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$PROJ" \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$TEST_DIR/m.jsonl" bash "$STUB/.asp/hooks/pretooluse-ship-gate.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
  if grep -q "SENTINEL-MUST-NOT-REACH-REASON" <<<"$R2"; then
    fail "(8c) 非標記行被帶進 deny 訊息——診斷行過濾失效（任意 gate 輸出都會外流）"
  elif grep -q "BLOCKER gitleaks\|gitleaks" <<<"$R2"; then
    pass "(8c) 只有標記行進 reason，非標記行被濾掉（過濾機制有效）"
  else
    fail "(8c) stub gate 未產生預期的 deny — 「${R2:0:200}」"
  fi

  # (8d) 反向釘樁：stub 印**別的** check id，reason 必須跟著改。
  # 沒有這條的話，「永遠說 gitleaks」也會讓 (8a) 綠——dispatch 是否真的在分派驗不到。
  cat > "$STUB/.asp/gate.sh" <<'STUBEOF2'
#!/usr/bin/env bash
echo "❌ BLOCKER vendor-verify"
exit 1
STUBEOF2
  R3=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$PROJ" \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$TEST_DIR/m.jsonl" bash "$STUB/.asp/hooks/pretooluse-ship-gate.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
  if grep -q "ASP commit 閘（vendor-verify）" <<<"$R3" && ! grep -q "ASP commit 閘（gitleaks）" <<<"$R3"; then
    pass "(8d) 換一個 check id，reason 的謂詞跟著換（dispatch 真的在分派）"
  else
    fail "(8d) dispatch 未跟著換 — 「${R3:0:200}」"
  fi

  # (8e) 未列名的 id 須保留原名，不得一律改寫成 unknown
  cat > "$STUB/.asp/gate.sh" <<'STUBEOF3'
#!/usr/bin/env bash
echo "❌ BLOCKER lint:yaml"
exit 1
STUBEOF3
  R4=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$PROJ" \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$TEST_DIR/m.jsonl" bash "$STUB/.asp/hooks/pretooluse-ship-gate.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
  if grep -q "lint:yaml" <<<"$R4"; then
    pass "(8e) 含冒號的未列名 id 保留原名（不被截斷、不被改寫成 unknown）"
  else
    fail "(8e) 未列名 id 的處置不符 — 「${R4:0:200}」"
  fi
else
  echo "  ⏭  (8) 略過：hook 或 jq 不可用"
fi

# ── 總數守衛：(6)(6b) 與 (8*) 都有條件式跳過分支，跳過時 TOTAL 會跟著縮，
# 於是「10/10 passed」看起來完全正常而其實少驗了兩條。分母自己也要被釘住。
EXPECTED_TOTAL=15
if [ "$TOTAL" -ne "$EXPECTED_TOTAL" ]; then
  echo "  ⚠️  本次只跑了 $TOTAL / $EXPECTED_TOTAL 條（有分支被跳過；上方 ⏭ 說明原因）"
fi

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed（預期 ${EXPECTED_TOTAL} 條）"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
