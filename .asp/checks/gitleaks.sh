#!/usr/bin/env bash
# gitleaks.sh — 對 staged 內容做密鑰掃描（CLAUDE-IR-2 敏感資訊保護的機械承接）
#
# 【為何需要這層薄包裝】(2026-09-09，獨立複審 F1)
# 本檢查原本以 `tool: gitleaks` 直接寫在 asp-gate.yaml，渲染成
#   run_check 'gitleaks' blocker 'gitleaks' 0 'gitleaks' 'protect' '--staged' '--config' '.asp/gitleaks.toml'
# 兩個路徑都是**裸相對路徑**，而同一份 gate.sh 的其餘三支檢查都用 `${ASP_GATE_HOME:-.}` 錨定。
# 後果實測兩項：
#   ① CWD 不在 repo 根時 → `FTL unable to load gitleaks config` → 誤判 BLOCKER（假紅）。
#   ② `protect --staged` 的掃描標的是 **CWD 的 git repo**，不是 `ASP_GATE_PROJ`——
#      於 A repo 下帶 `ASP_GATE_PROJ=B` 執行，掃的是 A。**掃錯 repo 而報綠是假綠**，
#      比假紅危險得多：hook 呼叫 gate 時全程不 cd（pretooluse-ship-gate.sh），
#      故這條在 hook 路徑上是真實可觸發的。
# 改為 builtin-script 後兩個路徑都由本腳本錨定，與其餘三支一致。
#
# 輸入(env)：ASP_GATE_HOME=ASP 安裝根（規則庫位置）、ASP_GATE_PROJ=受檢 repo 頂層
# 結束碼：0=無命中／1=命中(blocker)／200=自跳過(skip 契約)
#
# **fail-open 的那一格明說**：gitleaks 未安裝 → exit 200(skip)，依據＝消費端可用性優先
# （同 gate.sh 對 `command -v` 缺席的既有處置）。要轉 fail-closed 設 ASP_GATE_STRICT=1。
# 這是刻意取捨，不是疏漏：沒裝 gitleaks 的機器上這條鐵則只剩散文，該事實已寫進
# asp-gate.yaml 的 notes 與 CLAUDE.md 的鐵則表，不讓它隱形。
set -uo pipefail

HOME_DIR="${ASP_GATE_HOME:-.}"
PROJ="${ASP_GATE_PROJ:-.}"
CONFIG="$HOME_DIR/.asp/gitleaks.toml"

if ! command -v gitleaks >/dev/null 2>&1; then
  if [ "${ASP_GATE_STRICT:-0}" = "1" ]; then
    echo "❌ gitleaks: 工具未安裝，STRICT 模式不放行"
    exit 1
  fi
  echo "⏭  gitleaks: 略過（工具未安裝；設 ASP_GATE_STRICT=1 可轉 fail-closed）"
  exit 200
fi

# 規則庫缺席 → fail-closed。理由與工具缺席不同:工具缺席是「這台機器沒裝」,
# 規則庫缺席是「該裝的東西不見了」——後者多半代表 vendoring 壞掉或被刪,
# 靜默放行會讓密鑰掃描無聲降級成 gitleaks 內建規則(少掉各家模型金鑰 pattern)。
if [ ! -f "$CONFIG" ]; then
  echo "❌ gitleaks: 規則庫缺席（$CONFIG）——vendoring 壞掉或被刪，不靜默降級"
  exit 1
fi

# PROJ 必須真的是 git repo（2026-09-09，第三輪複審）。
# 初版直接把 $PROJ 餵給 `--source` 就掃，而 **gitleaks 對非 git 目錄回 rc=0**
# （只在 stderr 留 `ERR error="stderr is not empty"`），於是「PROJ 解析失敗」＝靜默綠燈。
# 這是本檔上一版修掉的那個假綠換了個形狀：從「掃到 CWD 的 repo」變成「什麼都沒掃」。
# 檔頭寫著「掃錯 repo 而報綠比假紅危險得多」——那句話對這個形狀一樣適用，故補守衛。
if ! git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1; then
  echo "❌ gitleaks: ASP_GATE_PROJ 不是 git repo（$PROJ）——無從掃描 staged 內容"
  echo "   → 這是呼叫端傳錯路徑，不是「沒有密鑰」;fail-closed 而非靜默放行"
  exit 1
fi

OUT=$(gitleaks protect --staged --source "$PROJ" --config "$CONFIG" 2>&1); RC=$?

# rc=0 但 gitleaks 自己報了 ERR → 它其實沒掃成功，不能當「無命中」。
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'ERR '; then
  printf '%s\n' "$OUT"
  echo "❌ gitleaks: rc=0 但輸出含 ERR——掃描未真正完成，不採信這個綠燈"
  exit 1
fi
if [ "$RC" -eq 0 ]; then
  exit 0
fi
printf '%s\n' "$OUT"
echo "❌ gitleaks: staged 內容命中密鑰規則（規則庫 $CONFIG，受檢 $PROJ）"
echo "   → 把密鑰移出 staged 內容;確認是誤判請在規則庫加 allowlist(需走 vendoring,勿就地改)"
exit 1
