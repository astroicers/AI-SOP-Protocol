# SPEC-013：PreToolUse commit gate for asp-ship enforcement

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-013 |
| **關聯 ADR** | ADR-020 |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

新增 PreToolUse hook 攔截 `git commit`：若無**測試痕跡**（`.asp-test-result.json` passed 且新鮮，且未走 escape hatch）→ **deny** 並提示先跑 `/asp-ship`，把「commit 前跑過測試（asp-ship Step 1，最高後果步驟）」從散文升為硬強制；同時寫 `SHIP-GATE` 遙測，補 (c) 層「應觸發未觸發」盲區（ADR-020 P1+P2）。

> **誠實能力邊界（G2 F1）**：本 hook 檢查的是「**測試痕跡**」，擋的是「連 `make test` 都沒跑就 commit」——**非**完整 asp-ship 10 步。Steps 2-9（CHANGELOG、ADR 狀態、SPEC Traceability、敏感掃描…）仍靠 AI 自律（ADR-020 已知殘留，語意型義務不機械化）。但測試（Step 1）是最高後果步驟，硬強制它已大幅降低最痛的遺忘。「完整 ship 痕跡」本身也得靠 skill 寫 sidecar = 又一散文義務，故刻意選測試結果（由 `make test` 機械寫）作可靠底線。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| hook stdin | JSON | Claude Code PreToolUse（FC-002） | 含 `tool_name`、`tool_input.command` |
| `.asp-test-result.json` | JSON | asp-ship Step 10 寫入 | ship 痕跡：`passed:true` + mtime |
| `.git/index` | file mtime | git staging | 最後一次 `git add` 的時間基準 |
| `ASP_SHIP_OK` | env var | 使用者 | escape hatch：`=1` 放行（避免死鎖） |

---

## 📤 輸出規格（Expected Output）

hook 解析 `tool_input.command`，輸出 **方式 A**（FC-002：`exit 0` + JSON）：

| 情境 | permissionDecision | 遙測 |
|------|-------------------|------|
| command 非 `git commit`（status/add/log/其他 Bash） | `defer`（交回預設，不干擾） | 不寫 |
| `git commit` + ship 痕跡新鮮（`.asp-test-result.json` passed=true 且 mtime ≥ `.git/index`） | `defer`（放行） | `SHIP-GATE` pass |
| `git commit` + `ASP_SHIP_OK=1`（escape hatch） | `defer`（放行） | `SHIP-GATE` bypass |
| `git commit` + 無/stale ship 痕跡 | **`deny`** + reason「commit 前未見 asp-ship 痕跡，請先跑 `/asp-ship`（或 `make test`）；確認要跳過設 `ASP_SHIP_OK=1`」 | `SHIP-GATE` block |
| jq 缺 / 腳本異常 | （fail-open）`defer` + stderr WARN | 不寫 |

> deny 用 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`，`exit 0`。

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| `.claude/settings.json` 加 `PreToolUse`（matcher `Bash`） | 安裝後每次 Bash 工具呼叫 | Claude Code hook 系統 | `jq '.hooks.PreToolUse'` 結構正確 |
| 新 hook 腳本 `.asp/hooks/pretooluse-ship-gate.sh` | 每次 Bash 呼叫 | commit 強制力 | `test_pretooluse_ship_gate.sh` |
| 寫 `SHIP-GATE` 至 `rule-hits.jsonl` | git commit 判定時 | 遙測（rule-stats） | `make rule-stats` 含 SHIP-GATE |
| hook 納入 Iron Rule A `CRITICAL_FILE` | session-audit 每次 | 防「改 hook 繞過」 | `test_iron_rule_a_coverage.sh` 含此 hook |
| rule-registry 登記 `SHIP-GATE` | 一次性 | 規則治理 | `test_rule_registry.sh` 仍綠 |

---

## ⚠️ 邊界條件（Edge Cases）

- **非 commit 的 git**（`git status`/`add`/`log`/`diff`）→ `defer`，零干擾。
- **指令位置偵測（G2 F5，防 grep 誤判）**：用正則 `(^|[;&|]+[[:space:]]*)git[[:space:]]+commit` 偵測 `git commit` 出現在**指令位置**（行首或 `;`/`&&`/`|` 之後），**非**字串內 → 不誤觸 `git log --grep="git commit"`、不誤觸 commit message 含 `"git commit"` 字串（該情境第一個 `git commit` 在指令位置已正確匹配，message 內的不影響判定結果）。
- **複合 command**（`git add . && git commit -m ...`）→ 上述正則命中 `&&` 後的 `git commit` → 進入判定。
- **`git commit --amend`（G2 F2）** → 視同 commit 需痕跡；但 `--amend` 不保證更新 `.git/index` mtime → 新鮮度判定退回「`.asp-test-result.json` passed=true 即放行」（保守 fail-open，避免 amend 誤擋）。
- **ship 痕跡新鮮**（asp-ship 剛跑、`.asp-test-result.json` 比 `.git/index` 新）→ 放行，0 誤擋。
- **無 staged（`.git/index` 不存在或空）** → 只要 `.asp-test-result.json` passed=true 即放行（避免無謂擋）。
- **escape hatch**：`ASP_SHIP_OK=1 git commit ...` → 放行 + 記 `SHIP-GATE` bypass（誠實留痕，非無聲跳過）。
- **fail-open**：jq 不存在 / 腳本錯誤 / stdin 非預期 → `defer` + stderr WARN，**絕不死鎖**（強制力讓位於可用性，誠實殘留：此時退回散文）。
- **hook 自身被改繞過** → 由 Iron Rule A 保護（納入 CRITICAL_FILE，同 ADR-019 教訓）。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | 移除 `.claude/settings.json` 的 `PreToolUse` 區塊（hook 腳本留著無害）→ 退回散文義務 |
| **資料影響** | 無（hook 唯讀 ship 痕跡 + 寫遙測；不改 repo 內容） |
| **回滾驗證** | 移除後 git commit 不再被攔；`make test` 綠 |
| **回滾已測試** | ☑ 是（等效）：`test_pretooluse_ship_gate.sh` 的「fail-open / 非 commit defer」案例證明 hook 不存在/失效時行為等同無 hook |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 場景 |
|---|------|---------|---------|------|
| P1 | ✅ 正向 | command=`git status` | defer（放行，不寫遙測） | S1 |
| P2 | ✅ 正向 | `git commit` + ship 新鮮 | defer（放行）+ SHIP-GATE pass | S1 |
| P3 | ✅ 正向 | `ASP_SHIP_OK=1` + 無痕跡 commit | defer（放行）+ SHIP-GATE bypass | S1 |
| N1 | ❌ 負向 | `git commit` + 無 ship 痕跡 | **deny** + reason + SHIP-GATE block | S2 |
| N2 | ❌ 負向 | `git commit` + stale ship（mtime < index） | **deny** | S2 |
| N3 | ❌ 負向 | `git add . && git commit` 複合 + 無痕跡 | **deny**（偵測複合） | S2 |
| B1 | 🔶 邊界 | jq 缺 / 異常 stdin | defer（fail-open）+ WARN | S3 |
| B2 | 🔶 邊界 | 無 staged + ship passed | defer（放行） | S3 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: PreToolUse commit gate（把 commit 前 asp-ship 從散文升硬強制）
  作為 ASP 強制力架構
  我想要 在無 asp-ship 痕跡時擋下 git commit
  以便 防止 AI 遺忘 commit 前驗證義務（ADR-020 遺忘威脅）

  Scenario: S1 - 合法 commit / 非 commit 放行
    Given ship 痕跡新鮮、或 command 非 commit、或設了 ASP_SHIP_OK
    When PreToolUse hook 判定
    Then permissionDecision=defer（放行）

  Scenario: S2 - 遺忘 ship 的 commit 被擋
    Given 無或 stale 的 .asp-test-result.json
    When AI 對 git commit 發起 Bash 呼叫
    Then permissionDecision=deny 且 reason 指示先跑 /asp-ship
    And 寫一筆 SHIP-GATE block 遙測

  Scenario Outline: S3 - 邊界不死鎖
    When hook 遇到 "<cond>"
    Then 結果為 "<result>"

    Examples:
      | cond          | result        |
      | jq 缺         | defer+WARN    |
      | 無 staged     | defer（放行） |
```

---

## ✅ 驗收標準（Done When）

- [ ] `bash tests/test_pretooluse_ship_gate.sh` 全綠（P1-3/N1-3/B1-2）
- [ ] hook 納入 Iron Rule A → `test_iron_rule_a_coverage.sh` 含 `pretooluse-ship-gate.sh`
- [ ] `SHIP-GATE` 登記於 rule-registry → `test_rule_registry.sh` 綠
- [ ] `make test` 全綠（既有零回歸）+ `make lint`（hook 納入 shellcheck）
- [ ] `.claude/settings.json` PreToolUse 結構正確（`jq` 驗證）
- [ ] 手動驗證：無痕跡 `git commit` 被擋、跑 `make test` 後放行
- [ ] CHANGELOG 更新

---

## 🚫 禁止事項（Out of Scope）

- 不機械化語意型 (c) 層義務（Assumption Checkpoint 等）— ADR-020 列後續。
- 不做 PreCompact/UserPromptSubmit hook（P1b）— ADR-020 後續。
- 不改 asp-ship skill 的 10 步內容（只新增「痕跡檢查」這個外部閘）。

---

## 📎 參考資料（References）

- ADR-020（遺忘威脅模型 + 機械化決策）
- FC-002（`.asp-fact-check.md`：PreToolUse hook 介面查證）
- ADR-019（hook 納入 Iron Rule A 的「看守者的看守者」教訓）
- `.asp/hooks/session-audit.sh`（asp_metric 遙測寫法 + Iron Rule A CRITICAL_FILE）
