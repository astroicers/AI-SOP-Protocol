---
name: asp-gate
description: |
  Pipeline gate evaluator — validates G1-G6 quality gates.
  Runs checks defined in pipeline.md and outputs structured GATE_PASS/GATE_FAIL verdict.
  Results are written to .asp-gate-state.json for cross-skill coordination.
  Triggers: gate, quality gate, G1, G2, G3, G4, G5, G6, 品質門檻, 關卡,
  evaluate gate, check gate, gate status, gate check.
---

# ASP Gate — Pipeline 品質門檻評估

## 適用場景

在 Pipeline 的各階段轉換點評估品質門檻。每個 Gate 有明確的通過條件，
評估結果寫入 `.asp-gate-state.json` 供 `asp-ship` 和 `session-audit` 讀取。

---

## 使用方式

```
/asp-gate G1        — 評估 Architecture Gate
/asp-gate G1,G2     — 同時評估多個 gate
/asp-gate status    — 查看所有 gate 狀態
```

---

## Gate 定義

### G1: Architecture Gate（SPECIFY → PLAN）

**檢查項目：**
1. 是否需要 ADR？（判斷標準：影響 2+ 模組、引入新依賴、變更 API 介面）
   - 需要且已存在 Accepted ADR → PASS
   - 需要但 ADR 為 Draft → FAIL
   - 不需要（trivial 變更）→ PASS（記錄理由）
2. 相關 ADR 無衝突

**通過條件：** 所有 production code 相關的 ADR 狀態為 Accepted 或不需要 ADR

---

### G2: Specification Gate（PLAN → FOUNDATION）

**檢查項目：**
1. SPEC 存在（`make spec-list` 有對應條目）
2. SPEC 7 個必填欄位完整：Goal, Inputs, Expected Output, Side Effects, Edge Cases, Done When, Traceability
3. Done When 條件可二元測試（非主觀描述）
4. 非 trivial 功能有 Gherkin 場景
5. 用戶面向功能有 Observability 欄位

**通過條件：** SPEC 完整且 Done When 可測試

---

### G3: Test Readiness Gate（FOUNDATION → BUILD）

**檢查項目：**
1. 測試檔案存在（對應 SPEC 的每個 Done When）
2. 執行測試 — 部分或全部測試 **必須 FAIL**（證明測試確實測試了尚未實作的功能）
3. Assertion 數量 > 0
4. Assertion 數量 >= Gherkin scenario 數量

**通過條件：** 測試存在、有 assertion、且至少部分 FAIL

```bash
make test   # 預期有 FAIL
```

---

### G4: Implementation Gate（BUILD → HARDEN）

**檢查項目：**
1. `make test` 全部 PASS
2. `make lint` 無 error（warning 可接受）
3. 變更範圍符合 SPEC scope（未修改 SPEC 未提及的核心模組）
4. 無新增 TODO/FIXME 無 owner

**通過條件：** 測試通過 + lint clean + scope 合規

```bash
make test
make lint
```

---

### G5: Verification Gate（HARDEN → DELIVER）

**檢查項目：**
1. `make test` 通過（再次確認）
2. 測試檔案 checksum 無異常（smuggling detection）
   - 比對 G3 時記錄的 test checksum vs 當前
   - 如果 assertion 數量減少 → FAIL + 觸發 Reality Checker
3. Side Effects 均已驗證
4. Rollback plan 已測試（如有 schema 變更）
5. lint warning 未增加（與 baseline 比對）

**通過條件：** 獨立驗證通過 + 無竄改

**自動觸發 Reality Checker：** 如果 smuggling_risk 為 true，
必須啟動 `reality-checker` subagent 進行獨立交叉驗證。

---

### G6: Delivery Gate（DELIVER → DONE）

**檢查項目：**
1. `/asp-ship` 10 步驟全部通過
2. SPEC Traceability 已填入 impl_files 和 test_files
3. Traceability 中列出的檔案全部存在
4. CHANGELOG.md 已更新
5. Health score 未退步（與 `.asp-audit-baseline.json` 比對）

**通過條件：** asp-ship GO + traceability 完整 + health score 不退步

---

## 輸出格式

### 單一 Gate 評估

```
🚦 Gate G4 (Implementation) 評估
================================
[1] make test          ✅ PASS (23/23 tests passed)
[2] make lint          ✅ PASS (0 errors, 2 warnings)
[3] Scope compliance   ✅ 3 files changed, all within SPEC scope
[4] TODO/FIXME audit   ⚠️  1 new TODO without owner (non-blocking)
================================
結果：✅ GATE_PASS
```

### Gate FAIL

```
🚦 Gate G3 (Test Readiness) 評估
================================
[1] Test files exist   ✅ 3 test files found
[2] Tests should FAIL  🔴 FAIL — All 23 tests PASS (tests may not be testing new functionality)
[3] Assertion count    ✅ 15 assertions found
[4] Assertion >= Gherkin ✅ 15 >= 5 scenarios
================================
結果：🔴 GATE_FAIL
原因：測試全部通過表示可能未覆蓋新功能。請確認測試確實測試了 SPEC 中的 Done When 條件。
```

---

## Gate State 檔案

評估結果寫入 `.asp-gate-state.json`：

```json
{
  "version": "1.0",
  "lastUpdated": "<ISO 8601>",
  "currentPhase": "BUILD",
  "gates": {
    "G1_ARCH":    { "status": "PASSED", "timestamp": "...", "evidence": "ADR-001 Accepted" },
    "G2_SPEC":    { "status": "PASSED", "timestamp": "...", "evidence": "SPEC-001 7/7 fields" },
    "G3_TEST":    { "status": "PASSED", "timestamp": "...", "evidence": "3 tests FAIL as expected" },
    "G4_IMPL":    { "status": "PENDING", "timestamp": null, "evidence": null },
    "G5_VERIFY":  { "status": "NOT_STARTED", "timestamp": null, "evidence": null },
    "G6_DELIVER": { "status": "NOT_STARTED", "timestamp": null, "evidence": null }
  },
  "testIntegrity": {
    "checksums": {},
    "assertionCounts": {},
    "smuggling_risk": false
  }
}
```

---

## Invalidation 規則

當 `.asp-gate-state.json` 存在時，以下操作應自動 invalidate 相關 gate：

| 操作 | Invalidate |
|------|-----------|
| 修改 production code (src/, lib/) | G4, G5, G6 → PENDING |
| 修改 test code (*_test.*, *.spec.*) | G3, G5 → PENDING |
| 修改 SPEC | G2, G3 → PENDING |
| 修改 ADR | G1 → PENDING |
| 新增依賴 | G4, G5 → PENDING |

**注意**：在 VSCode 環境中，invalidation 由 AI 在每次編輯後自行更新 gate state（無 PostToolUse hook）。
CLAUDE.md 中的「強制 Skill 調用點」確保 gate 在關鍵時機被重新評估。
