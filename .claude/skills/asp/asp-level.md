---
name: asp-level
description: |
  Evaluate and manage ASP maturity levels (loose → standard → autonomous, v5).
  Determines current level, checks graduation criteria, and recommends upgrade/downgrade.
  Triggers: level, maturity, asp-level, what level, upgrade level, downgrade level,
  成熟度, 等級, 升級 ASP, 我該升到哪一級, 現在是哪一級, level check, level upgrade.
---

# ASP Level — 成熟度等級評估與升級（v5 三級制）

## 核心概念

ASP v5 採用 **3 級成熟度模型**（ADR-014：v4 的 L0-L5 六級收斂為三級），
使用者不必面對 profile 的組合爆炸，從 `loose` 開始，滿足 graduation_checklist 後逐級升級。

| Level | 吸收的 v4 等級 | 核心能力 |
|-------|---------------|---------|
| **loose** | L0, L1 | 探索（spike 豁免）+ ADR/SPEC/測試入門（最小治理） |
| **standard** | L2, L3 | + coding_style + pipeline gates G1-G6（品質護欄自動化） |
| **autonomous** | L4, L5 | + orchestrator + autonomous_dev + autopilot + RAG（自主執行） |

**遺留數字值（0-5）**：`.ai_profile` 的 `level:` 仍接受，由 `level-resolve.sh` 自動映射
（0,1→loose｜2,3→standard｜4,5→autonomous）並印 deprecation 提示；數字值將於 v6 移除。

---

## 使用情境

### 情境 1：查詢目前等級

使用者問「我現在是哪一級？」或「level check」時：

1. 執行 `bash .asp/scripts/level-resolve.sh`（讀 `.ai_profile` 的 `level` 並正規化）
2. 若無 `level` 欄位 → 根據已啟用的 profile 推斷（見下方「Level 推斷規則」）
3. 讀取對應 `.asp/levels/{name}.yaml`
4. 顯示：目前等級、已通過的 graduation items、未通過項目

### 情境 2：評估是否可升級

使用者問「我可以升到 standard 嗎？」或「upgrade check」時：

1. 讀取 `.asp/levels/{current}.yaml` 的 `next_level`，再讀該級 yaml
2. 對每個 `graduation_checklist` item 執行 `check` 欄位的 shell 判斷
3. 若 item 標註 `check: "true"`（soft check），則由 AI 檢視專案狀態手動判斷並說明依據
4. 輸出：通過清單（✅）、未通過清單（❌ + 修復建議）、升級建議（GO / NEEDS_WORK）

### 情境 3：執行升級

使用者確認升級後：

1. 備份 `.ai_profile` → `.ai_profile.backup-{current}`
2. 根據 `.asp/levels/{next}.yaml` 的 `ai_profile_hint` 更新 `.ai_profile`
3. 執行 `make asp-refresh` 重新跑 session audit
4. 顯示升級後差異（新增哪些 profile、新增哪些 Makefile target）

### 情境 4：降級

使用者說「降回 standard」或遇到問題需要回退：

1. 警告降級會停用某些 profile 能力
2. 備份當前 `.ai_profile`
3. 根據目標等級 yaml 的 `ai_profile_hint` 更新

---

## Level 推斷規則

當 `.ai_profile` 無 `level` 欄位時（legacy 專案），根據已啟用的欄位推斷（與
`make asp-level-check` 的推斷邏輯一致）：

| 已啟用欄位 | 推斷等級 |
|-----------|---------|
| autopilot: enabled 或 autonomous: enabled 或 mode: multi-agent | autonomous |
| openapi: enabled 或 coding_style: enabled | standard |
| 其他 | loose |

推斷結果僅供參考，建議執行 `make asp-level-check` 後在 `.ai_profile` 補上 `level:` 欄位。

---

## Graduation Checklist 執行

對每個 item：

```bash
# 若 check 是具體 shell
<check command>
# exit 0 → ✅ 通過
# exit 非 0 → ❌ 未通過
```

```yaml
# 若 check 是 "true"（soft check）
# AI 需要讀取相關檔案（如 .asp-bypass-log.json、commit history）並判斷
```

---

## 輸出格式

### Level Check 輸出

```
🎯 ASP Level Check
==================

Current Level: standard (Standard)
Profiles loaded: global_core, system_dev, coding_style, pipeline

📋 standard Graduation Checklist:
  ✅ lint-clean           — make lint 通過
  ✅ no-hardcoded-secrets — 近 30 commit 無洩密事件
  ✅ gate-state-exists    — .asp-gate-state.json 存在
  ❌ spec-has-done-when   — SPEC-003 缺 Done When 欄位

Ready for autonomous? NEEDS_WORK (1/7 items missing)

修復建議：
  - SPEC-003-auth.md：補上 Done When 欄位（可二元測試的驗收條件）

Next Level (autonomous) 會新增：
  - task_orchestrator（統一任務入口 + 健康審計）
  - autonomous_dev + autopilot（自主執行 + ROADMAP 驅動）
  - rag_context（本地知識庫）
```

### Level Upgrade 輸出

```
🚀 升級到 autonomous

已備份 .ai_profile → .ai_profile.backup-standard

新增 profile：
  + task_orchestrator
  + reality_checker
  + autonomous_dev
  + rag_context

執行 make asp-refresh 重新評估專案狀態 ...
✅ 升級完成

下一步：
  1. 跑 /asp-gate status 查看當前 gate 狀態
  2. 建立 ROADMAP.yaml 並執行 make autopilot-init
```

---

## Common Rationalizations（AI 繞過時必讀）

| 藉口 | 反駁 |
|------|------|
| 「graduation item 有點麻煩，直接跳級」 | 不可。每級的設計假設前一級已經穩定。跳級 = 基礎不穩導致的 cascading 問題。 |
| 「使用者說要升到 autonomous，直接改 `.ai_profile` 就好」 | 必須先檢查前置等級的 graduation_checklist。若未通過，向使用者說明缺項，讓使用者決定是否強制升級。強制升級必須寫入 `.asp-bypass-log.json`。 |
| 「legacy 專案沒有 `level` 欄位，預設就算 autonomous」 | 不可。無 `level` 欄位時用「Level 推斷規則」保守估計。寧可推斷低也不要誤判高。 |
| 「數字等級還能用，不用提醒使用者改」 | 能用是過渡相容（ADR-014），不是長期支援。每次遇到數字值都要提示更新為名稱值，並說明 v6 移除。 |
| 「soft check (`check: "true"`) 直接回傳通過」 | Soft check 代表需要 AI 實際檢視專案狀態（例如讀 bypass log、commit history）並**說明判斷依據**。空白通過 = 無效審核。 |
| 「降級會丟資料，不如不要降」 | 降級不刪除檔案，只是停用 profile 載入。若專案確實不需要某級能力，降級可以減少 AI 注意力負擔。 |

---

## 相關檔案

- `.asp/levels/loose.yaml` / `standard.yaml` / `autonomous.yaml` — 等級定義（v4 的 level-0~5.yaml 已歸檔 `docs/archive/levels/`）
- `.asp/scripts/level-resolve.sh` — 數字→名稱中央映射（deprecation 提示）
- `.ai_profile` — 使用者當前等級與啟用設定
- `.asp-bypass-log.json` — 強制升級記錄
- `Makefile` → `make asp-level-check`、`make asp-level-upgrade`、`make asp-level-list`