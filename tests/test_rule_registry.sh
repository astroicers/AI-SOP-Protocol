#!/usr/bin/env bash
# test_rule_registry.sh — registry ↔ 程式碼雙向防漂移（v5 ADR-018）。
# 斷言：session-audit 內 asp_metric 的 id 集合 ⊆ registry；registry 中
# observed_by=session-audit 的 AUDIT-* id ⊆ session-audit 程式碼；DENY 條數 =
# denied-commands.json 長度；GATE-G1..G6 / IRON-A/B/C / CLAUDE-IR-1..4 必在。
# Run: bash tests/test_rule_registry.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REG="$ASP_ROOT/.asp/config/rule-registry.yaml"
HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
DENY="$ASP_ROOT/.asp/hooks/denied-commands.json"

REG_IDS=$(grep -E '^  - id: ' "$REG" | awk '{print $3}' | sort -u)
HOOK_IDS=$(grep -oE 'asp_metric "[A-Z0-9._-]+"' "$HOOK" | sed 's/asp_metric "//; s/"//' | sort -u)

echo ""
echo "T1: hook 內 asp_metric id ⊆ registry"
MISSING=""
for id in $HOOK_IDS; do
  grep -qx "$id" <<<"$REG_IDS" || MISSING="$MISSING $id"
done
[ -z "$MISSING" ] && pass "hook 全部 id 已註冊（$(echo "$HOOK_IDS" | wc -l) 個）" || fail "未註冊 id:$MISSING"

echo ""
echo "T2: registry 中 observed_by=session-audit 的 AUDIT-*/IRON-*/DENY-DYNAMIC ⊆ hook 程式碼"
SA_IDS=$(awk '/^  - id: /{id=$3} /observed_by: session-audit/{print id}' "$REG" | grep -E '^(AUDIT-|IRON-|DENY-DYNAMIC)' | sort -u)
DRIFT=""
for id in $SA_IDS; do
  grep -qx "$id" <<<"$HOOK_IDS" || DRIFT="$DRIFT $id"
done
[ -z "$DRIFT" ] && pass "registry session-audit ids 全部在 hook 中（$(echo "$SA_IDS" | wc -l) 個）" || fail "registry 漂移（hook 無此 id）:$DRIFT"

echo ""
echo "T3: DENY-NN 條數 = denied-commands.json 長度"
REG_DENY=$(grep -cE '^DENY-[0-9]+$' <<<"$REG_IDS")
JSON_DENY=$(jq 'length' "$DENY")
[ "$REG_DENY" = "$JSON_DENY" ] && pass "DENY 條數一致（$REG_DENY）" || fail "registry=$REG_DENY json=$JSON_DENY"

echo ""
echo "T4: 必在 id（gates / 鐵則）"
for id in GATE-G1 GATE-G2 GATE-G3 GATE-G4 GATE-G5 GATE-G6 IRON-A IRON-B IRON-C CLAUDE-IR-1 CLAUDE-IR-2 CLAUDE-IR-3 CLAUDE-IR-4 DENY-DYNAMIC; do
  grep -qx "$id" <<<"$REG_IDS" && pass "$id" || fail "$id 缺席"
done

echo ""
echo "T5: 鐵則全部 exempt（紅線 1）"
for id in CLAUDE-IR-1 CLAUDE-IR-2 CLAUDE-IR-3 CLAUDE-IR-4 IRON-A IRON-B IRON-C; do
  awk -v target="$id" '/^  - id: /{id=$3; ex=0} /exempt: true/{if (id==target) found=1} END{exit !found}' "$REG" \
    && pass "$id exempt" || fail "$id 未標 exempt"
done

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
