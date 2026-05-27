#!/usr/bin/env bash
# audit-fallback.sh — 7+2 維度健康審計（make audit-health 不存在時使用）
# 由 asp-audit skill 呼叫；與 Makefile.inc audit-health target 邏輯等效
set -uo pipefail

BLOCKERS=0; WARNINGS=0; INFOS=0

echo ""
echo "🏥 專案健康審計（完整掃描）"
echo "================================="
echo ""

# ── 1. 測試覆蓋 ──────────────────────────────────────────────────
echo "── 1. 測試覆蓋 ──"
SRC=0; TEST=0
for ext in go ts tsx js jsx py java rb sh; do
  SRC=$((SRC + $(find . -name "*.$ext" \
    ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/vendor/*' \
    ! -name '*_test.*' ! -name '*.test.*' ! -name '*.spec.*' \
    ! -name 'test_*' ! -path '*/test*/*' ! -path '*/tests/*' \
    2>/dev/null | wc -l)))
  TEST=$((TEST + $(find . \
    \( -name "*_test.$ext" -o -name "*.test.$ext" -o -name "*.spec.$ext" -o -name "test_*.$ext" \) \
    ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null | wc -l)))
done
RATIO=$(echo "scale=0; $TEST * 100 / $SRC" | bc 2>/dev/null || echo "?")
echo "  Source files: $SRC | Test files: $TEST | Coverage ratio: ${RATIO}%"
if [ "$SRC" -gt 0 ]; then
  if [ "$TEST" -eq 0 ] && [ "$SRC" -gt 5 ]; then
    echo "  🔴 BLOCKER: 專案有 $SRC 個 source files 但無任何測試"
    BLOCKERS=$((BLOCKERS + 1))
  elif [ "$RATIO" != "?" ] && [ "$RATIO" -lt 30 ]; then
    echo "  🟡 WARNING: 測試覆蓋率低於 30%"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  ✅ OK"
  fi
else
  echo "  ⚪ 無 source files"
fi
echo ""

# ── 1c. E2E 測試（全端專案）────────────────────────────────────
echo "── 1c. E2E 測試（全端專案）──"
HAS_FE=0; HAS_BE=0
[ -d "frontend" ] && HAS_FE=1
([ -d "backend" ] || [ -d "api" ] || [ -d "server" ]) && HAS_BE=1
if [ "$HAS_FE" -eq 1 ] && [ "$HAS_BE" -eq 1 ]; then
  if [ ! -f "playwright.config.ts" ] && [ ! -f "playwright.config.js" ]; then
    echo "  🔴 BLOCKER: 全端專案缺少 Playwright 設定"
    BLOCKERS=$((BLOCKERS + 1))
  else
    E2E_DIR=""
    for d in e2e tests/e2e frontend/e2e; do [ -d "$d" ] && E2E_DIR="$d" && break; done
    if [ -z "$E2E_DIR" ]; then
      echo "  🔴 BLOCKER: 全端專案缺少 E2E 測試目錄"
      BLOCKERS=$((BLOCKERS + 1))
    else
      E2E_N=$(find "$E2E_DIR" \( -name "*.spec.ts" -o -name "*.e2e.ts" -o -name "*.test.ts" \) 2>/dev/null | wc -l | tr -d ' ')
      if [ "$E2E_N" -eq 0 ]; then echo "  🔴 BLOCKER: E2E 目錄存在但無測試"; BLOCKERS=$((BLOCKERS + 1))
      elif [ "$E2E_N" -lt 3 ]; then echo "  🟡 WARNING: E2E 僅 $E2E_N 個（建議 ≥ 3）"; WARNINGS=$((WARNINGS + 1))
      else echo "  ✅ E2E 測試 $E2E_N 個"; fi
    fi
  fi
else
  echo "  ⚪ 非全端專案，跳過"
fi
echo ""

# ── 2. SPEC 覆蓋 ─────────────────────────────────────────────────
echo "── 2. SPEC 覆蓋 ──"
SPEC_COUNT=$(ls docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' ')
echo "  SPEC 數量: $SPEC_COUNT"
if [ "$SPEC_COUNT" -eq 0 ] && [ "$SRC" -gt 5 ]; then
  echo "  🟡 WARNING: 專案有代碼但無任何 SPEC"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ✅ OK"
fi
echo ""

# ── 3. ADR 覆蓋 ──────────────────────────────────────────────────
echo "── 3. ADR 覆蓋 ──"
ADR_COUNT=$(ls docs/adr/ADR-*.md 2>/dev/null | wc -l | tr -d ' ')
DRAFT_WITH_CODE=0
for f in docs/adr/ADR-*.md; do
  [ -f "$f" ] || continue
  STATUS=$(grep -m1 "狀態" "$f" 2>/dev/null | grep -o '`[^`]*`' | tr -d '`')
  ADR_ID=$(basename "$f" .md | grep -o 'ADR-[0-9]*')
  if [ "$STATUS" = "Draft" ]; then
    if grep -r "$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then
      echo "  🔴 BLOCKER: $ADR_ID 狀態為 Draft 但已有實作代碼（鐵則違反）"
      BLOCKERS=$((BLOCKERS + 1))
      DRAFT_WITH_CODE=$((DRAFT_WITH_CODE + 1))
    fi
  elif [ "$STATUS" = "FIRM" ]; then
    if grep -r "$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then
      echo "  🟡 WARNING: $ADR_ID 狀態為 FIRM（POC 驗證中）— 允許 commit，待人類升級至 Accepted"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
done
echo "  ADR 數量: $ADR_COUNT"
[ "$DRAFT_WITH_CODE" -eq 0 ] && echo "  ✅ OK"
echo ""

# ── 4. 文件完整性 ────────────────────────────────────────────────
echo "── 4. 文件完整性 ──"
for doc in README.md CHANGELOG.md; do
  if [ ! -f "$doc" ]; then
    echo "  🟡 WARNING: 缺少 $doc"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  ✅ $doc exists"
  fi
done
echo ""

# ── 5. 程式碼衛生 ────────────────────────────────────────────────
echo "── 5. 程式碼衛生 ──"
TODO_NO_OWNER=$(grep -rn "TODO[^(]" \
  --include="*.go" --include="*.ts" --include="*.py" --include="*.java" --include="*.js" \
  . 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' ')
FIXME_COUNT=$(grep -rn "FIXME" \
  --include="*.go" --include="*.ts" --include="*.py" --include="*.java" --include="*.js" \
  . 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' ')
if [ "$TODO_NO_OWNER" -gt 0 ]; then echo "  🟡 WARNING: $TODO_NO_OWNER 個 TODO 無 owner"; WARNINGS=$((WARNINGS + 1)); fi
if [ "$FIXME_COUNT" -gt 0 ]; then echo "  🟢 INFO: $FIXME_COUNT 個 FIXME"; INFOS=$((INFOS + 1)); fi
if [ "$TODO_NO_OWNER" -eq 0 ] && [ "$FIXME_COUNT" -eq 0 ]; then echo "  ✅ OK"; fi
echo ""

# ── 6. 依賴健康 ──────────────────────────────────────────────────
echo "── 6. 依賴健康 ──"
LOCK_OK=1
if [ -f "package.json" ] && [ ! -f "package-lock.json" ] && [ ! -f "yarn.lock" ] && [ ! -f "pnpm-lock.yaml" ]; then
  echo "  🟡 WARNING: 有 package.json 但無 lock file"; WARNINGS=$((WARNINGS + 1)); LOCK_OK=0
fi
if [ -f "pyproject.toml" ] && [ ! -f "poetry.lock" ] && [ ! -f "requirements.txt" ]; then
  echo "  🟡 WARNING: 有 pyproject.toml 但無 lock file"; WARNINGS=$((WARNINGS + 1)); LOCK_OK=0
fi
if [ -f "go.mod" ] && [ ! -f "go.sum" ]; then
  echo "  🟡 WARNING: 有 go.mod 但無 go.sum"; WARNINGS=$((WARNINGS + 1)); LOCK_OK=0
fi
[ "$LOCK_OK" -eq 1 ] && echo "  ✅ OK"
echo ""

# ── 7. 文件新鮮度 ────────────────────────────────────────────────
echo "── 7. 文件新鮮度 ──"
STALE=0
if [ "$SPEC_COUNT" -gt 0 ]; then
  HAS_TRACE=$(grep -rl "追溯性\|Traceability" docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$HAS_TRACE" = "0" ]; then
    echo "  🟡 WARNING: $SPEC_COUNT 個 SPEC 均無 Traceability 資料，無法驗證新鮮度"
    WARNINGS=$((WARNINGS + 1)); STALE=1
  fi
fi
[ "$STALE" -eq 0 ] && echo "  ✅ OK（或無 SPEC）"
echo ""

# ── 8. 測試品質 ──────────────────────────────────────────────────
echo "── 8. 測試品質（v3.3）──"
EMPTY_TESTS=0
for ext in go ts js py java; do
  while IFS= read -r tf; do
    case $ext in
      go) A=$(grep -c "assert\|require\.\|t\.Error\|t\.Fatal" "$tf" 2>/dev/null || echo 0);;
      py) A=$(grep -c "assert\|assertEqual\|assertTrue" "$tf" 2>/dev/null || echo 0);;
      ts|js) A=$(grep -c "expect(\|assert\." "$tf" 2>/dev/null || echo 0);;
      java) A=$(grep -c "assert\|assertEquals" "$tf" 2>/dev/null || echo 0);;
      *) A=1;;
    esac
    if [ "$A" = "0" ]; then
      echo "  🟡 WARNING: $tf 沒有 assertion（空測試）"
      WARNINGS=$((WARNINGS + 1)); EMPTY_TESTS=$((EMPTY_TESTS + 1))
    fi
  done < <(find . \( -name "*_test.$ext" -o -name "*.test.$ext" -o -name "*.spec.$ext" \) \
    ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null)
done
[ "$EMPTY_TESTS" -eq 0 ] && echo "  ✅ 無空測試"
echo ""

# ── 9. SPEC 場景覆蓋 ─────────────────────────────────────────────
echo "── 9. SPEC 場景覆蓋（v3.2）──"
NO_MATRIX=0
for spec in docs/specs/SPEC-*.md; do
  [ -f "$spec" ] || continue
  HM=$(grep -c "測試矩陣\|Test Matrix" "$spec" 2>/dev/null || echo 0)
  if [ "$HM" = "0" ]; then
    echo "  🟡 WARNING: $(basename "$spec") 缺少測試矩陣"
    WARNINGS=$((WARNINGS + 1)); NO_MATRIX=$((NO_MATRIX + 1))
  fi
done
if [ "$NO_MATRIX" -eq 0 ] && [ "$SPEC_COUNT" -gt 0 ]; then echo "  ✅ 所有 SPEC 有測試矩陣"
elif [ "$SPEC_COUNT" -eq 0 ]; then echo "  ⚪ 無 SPEC"; fi
echo ""

# ── 摘要 ─────────────────────────────────────────────────────────
echo "================================="
echo "🏥 審計摘要：🔴 $BLOCKERS blocker | 🟡 $WARNINGS warning | 🟢 $INFOS info"
if [ "$BLOCKERS" -gt 0 ]; then
  echo "⚠️  有 blocker 需先修復才能開始主任務"
fi
echo ""
