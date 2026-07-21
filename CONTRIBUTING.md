# Contributing to AI-SOP-Protocol

> 本文件為 ASP 專案本身的開發指引，適用於 ASP repo 的貢獻者。
> 使用 ASP 的專案不需要此檔案。

---

## 專案概述

AI-SOP-Protocol (ASP) 是一套行為約束框架，讓 AI coding assistant 自動遵循開發紀律。

核心組成：
- `CLAUDE.md`：行為憲法（鐵則 + Profile 對應表）
- `.asp/profiles/`：分層 Profile（全域 → 專案類型 → 選配）
- `.asp/templates/`：ADR / SPEC / 設計工作流範本
- `.asp/scripts/install.sh`：一鍵安裝腳本
- `.asp/hooks/`：SessionStart Hook

---

## 開發環境

```bash
# 本專案本身不需要 build/test
# 主要驗證方式：
bash -n .asp/scripts/install.sh    # 安裝腳本語法檢查
```

---

## 架構原則

### Profile 分層

```
Layer 1: 鐵則（CLAUDE.md）          — 不可覆蓋
Layer 2: 全域準則（global_core.md）   — 所有專案
Layer 3: 專案類型（system/content）   — 依 .ai_profile type
Layer 4: 作業模式（multi-agent/committee） — 可選
Layer 5: 開發策略（vibe-coding）      — 可選
Layer 5.5: 自主開發（autonomous）      — 可選，可與 multi-agent 組合（分層套用）
Layer 5.6: Autopilot（autopilot）       — 可選，autonomous 的上層調度（ROADMAP 驅動）
Layer 6: 選配（rag/guardrail/design/coding_style/openapi/frontend_quality） — 可選
```

### 修改原則

1. **新增 Profile** 時：
   - 在 `.asp/profiles/` 建立檔案
   - 在 `CLAUDE.md` 加入 `.ai_profile` 欄位和 Profile 對應表條目
   - 在 `README.md` 更新 `.ai_profile` 範例和專案結構
   - 在 `install.sh` 加入互動提示和 `.ai_profile` 生成邏輯
   - 在 `.asp/templates/example-profile-*.yaml` 範例中加入欄位
   - 更新 `.asp/VERSION`

2. **修改既有 Profile** 時：
   - 確認是否影響其他 Profile 的交叉引用
   - Pseudocode 的 INVARIANT 放在函數頂部
   - 更新 `.asp/VERSION`

3. **install.sh 修改** 時：
   - 必須通過 `bash -n` 語法檢查
   - 升級邏輯必須保留使用者既有設定
   - 新增欄位必須在升級時自動補充到既有 `.ai_profile`

### 複雜度預算（ADR-022）

治理產物（`.asp/profiles/`、skills、levels）受**複雜度預算棘輪**約束，避免治理層無限自我增生（治理劇場）。提交涉及治理面的 PR 前：

1. **先問**：新增任何一層強制前，先問「能不能用**簡化需求**取代？」——這是複雜度預算的核心啟發式。
2. **量測**：`make asp-metrics-compare`（對照已 commit 的 `.asp-metrics-baseline.json`）。若你的 PR 使 `profiles.total_lines` / `skills.total_lines` 等**超過當前 baseline**，代表新增了治理複雜度。
3. **超標 → 附理由**：超過 baseline 的 PR 必須附一份**明確認列複雜度增加理由的 ADR**（逃生門，與 `FIRM` ADR → audit 🟡 同構）。
4. **豁免**：四條鐵則 + Iron Rule A/B/C（registry `exempt: true`）**永不進入棘輪**——鐵則的價值正在於不退場。
5. **去重**：可推導性/去重**不做每-commit 機械閘**（語意判斷無法機械近似，POC-2）；改由 `reality-checker` 定期 advisory review 列候選給人類判斷，**不阻擋 commit**。

---

## Commit 慣例

```
feat: 新增功能或 Profile
fix: 修正 bug
docs: 文件更新（README、CONTRIBUTING 等）
chore: 版本升級、維護性修改
refactor: 重構（不影響功能）
```

---

## 版本策略

- 版本號存放在 `.asp/VERSION`
- 新增 Profile / 修改既有 Profile 行為 → minor version（1.x.0）
- Bug 修正 / 文件微調 → patch version（1.0.x）
- Breaking change（Profile 格式不相容）→ major version（x.0.0）
