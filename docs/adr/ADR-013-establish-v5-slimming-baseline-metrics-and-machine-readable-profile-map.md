# [ADR-013]: Establish v5 slimming baseline metrics and machine-readable profile map

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-11 |
| **決策者** | astroicers（v5 重構簡報）+ AI（實作設計） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

外部架構審查結論：ASP 押對了 hooks 強制層，但散文治理層過度設計。實測（2026-06-11，main@eb07438）：Markdown 28,846 行、腳本 9,618 行。v5 瘦身重構（Phase 0-5）將大量刪減與合併 profile/skill/level——**沒有量化基線，所有刪減都無法證明成效，規則存留也無從以數據裁決**（v5 原則 5：任何規則的存留以命中率數據為準）。

另一個 v5 全程依賴的缺口：`.ai_profile` 欄位 → profile 載入集合的映射目前以散文存在三處（CLAUDE.md 啟動程序映射表、`validate-profile.sh` 載入清單 heredoc、各 level yaml 的 `ai_profile_hint`），由 LLM 在 runtime「自覺解析」。Phase 0 量測 context 稅、Phase 1 level 重映射、Phase 3 asp-compile 都需要同一份映射——若各自硬編碼，三處必然漂移。

本 ADR 決策 Phase 0 的兩個基礎設施：基線量測腳本與機械可讀的映射資料檔。

---

## 評估選項（Options Considered）

### 選項 A：量測腳本內建映射常數（不建共用資料檔）

- **優點**：Phase 0 交付最快，單一檔案自包含。
- **缺點**：Phase 3 asp-compile 必須重寫同一份映射 → 兩處漂移；Phase 3 Done When「編譯產物 vs baseline 同組態 ≥30% 下降」要求兩者的 profile 選擇邏輯一致，內建常數無法機械保證。
- **風險**：對照組與實驗組量尺不同，30% 驗收失去意義。

### 選項 B：建立 `.asp/config/profile-map.yaml` 單一映射來源，量測/編譯/驗證共用（採用）

- **優點**：映射只存在一處；Phase 0 metrics 與 Phase 3 compile 讀同一檔，量尺機械一致；`.asp/config/` 已在 install.sh 複製清單內，零安裝改動；扁平 `when/load` 文法可用 awk/grep 解析，不引入 yq/PyYAML 依賴。
- **缺點**：CLAUDE.md 散文映射表與 map 並存至 Phase 3（CLAUDE.md 改讀編譯產物）前，期間需人工保持同步。
- **風險**：map 與實檔脫鉤 → 以測試斷言「三組態 missing_profiles 為空」防護。

### 選項 C：直接以 validate-profile.sh 的載入清單為準，metrics 解析其輸出

- **優點**：不新增檔案。
- **缺點**：validate-profile.sh 的載入清單是給人看的 echo 文字，非穩定契約；Phase 1 改三級制時該段必改，輸出格式漂移會無聲破壞 metrics。
- **風險**：把展示層當資料層，正是 v5 要消除的反模式。

---

## 決策（Decision）

選擇 **選項 B**：

1. 新增 `.asp/config/profile-map.yaml`（version 欄位 + `rules:` 扁平規則：`when: "field=value[&field=value]"` AND 條件 → `load: "profile ..."`；`level_aliases:` 段預留 Phase 1 數字→名稱映射）。內容與 CLAUDE.md 映射表、validate-profile.sh :168-208 雙向核對。
2. 新增 `.asp/scripts/asp-metrics.sh`（簡報路徑 `scripts/` 按 repo 慣例落於 `.asp/scripts/`，**偏差在此記錄**）：
   - 各 profile / skill / level 行數與總行數；
   - 規則清點：`grep -cE 'MUST|禁止|🔴'` 逐檔計數（pattern 寫入輸出 JSON，保證 v5 前後同基準）；
   - 三種典型組態的 context 稅 = 依 profile-map 展開後的 Markdown 行數合計。組態完整欄位集如下（G1 review F-2：install.sh preset 不設 type、preset 3 無 design，故此處顯式定義，preset 僅為出發點）：
     - `L1_content`：`type=content, level=1, mode=auto, workflow=standard, hitl=standard`
     - `L3_system_design`：`type=system, level=3, mode=auto, workflow=standard, hitl=standard, design=enabled, frontend_quality=enabled, guardrail=enabled, coding_style=enabled`（= preset 3 + 簡報指定的 design 組合）
     - `L5_autonomous`：`type=system, level=5, mode=multi-agent, workflow=vibe-coding, hitl=minimal, autonomous=enabled, orchestrator=enabled, autopilot=enabled, rag=enabled, guardrail=enabled, coding_style=enabled`（= preset 5 + type=system）
   - 組態模擬的唯一資料來源 = profile-map.yaml，**腳本內禁止硬編碼任何 field→profile 映射**；
   - `--compare BASELINE` 輸出對照表；`--assert-reduction N` 預留給 Phase 3 驗收（exit 5 = 未達標）。
3. 產出 `.asp-metrics-baseline.json` 並 **commit**（作為 v5 前後對照證據；不得加入 install.sh 的 ASP_GITIGNORE_ENTRIES）。

回滾方式：Phase 0 為純新增（兩個新檔 + 一個產出物 + Makefile 三個 target），`git revert` 單一 commit 即完全回滾，不影響任何既有行為。

---

## 後果（Consequences）

**正面影響：**
- v5 所有後續刪減（Phase 1-4）取得機械可重現的對照組；PR description 的成效宣稱可驗證。
- 映射機械化是 Phase 3 asp-compile 的前置依賴，提前在 Phase 0 落地可被 metrics 測試先行驗證。

**負面影響 / 技術債：**
- CLAUDE.md 散文映射表與 profile-map.yaml 在 Phase 0-2 期間雙軌並存，需人工同步（Phase 3 收斂為單軌）。
- 規則清點 pattern（`MUST|禁止|🔴`）是近似值——會漏掉未用這三種標記的規範句。接受：它量測的是「強規則標記密度」趨勢，非規則語意全集。

**後續追蹤：**
- [ ] Phase 1 落地後更新 profile-map.yaml（vibe_coding→loose_mode、刪 guardrail/escalation 條目、level_aliases 啟用）
- [ ] Phase 3 asp-compile 改讀同一 map；CLAUDE.md 散文映射表收斂

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 可重複執行 | 連跑兩次輸出（去 generated_at/git_commit）diff 為空 | `tests/test_asp_metrics.sh` T4 | 實作完成時 |
| 映射不脫鉤 | 三組態 `missing_profiles` 為空 | `tests/test_asp_metrics.sh` T7 | 每次 `make test` |
| 三組態 context 稅可量測 | baseline JSON 含 L1/L3/L5 三組 `total` 數值 | `jq .context_tax` | Phase 0 結束 |
| 對照可用 | `--compare` 對自身輸出全零差值、exit 0 | T5 | 實作完成時 |

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：ADR-006（feature audit roadmap §v5.0.0「需子 ADR」授權）、ADR-007（v4.3 整併，合併量測先例）
- v5 規劃來源（G1 review F-10）：v5 瘦身重構簡報由維護者於 2026-06-11 提供（外部架構審查結論 + Phase 0-5 工作指示），repo 內以 **ADR-013（Phase 0）～ADR-018（Phase 5）** 逐階段落地為可追溯記錄；總對照（行數/context 稅/數量變化）見 v5 PR description 與 `.asp-metrics-baseline.json`。

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | branch `asp/v5-slimming`：`tests/test_asp_metrics.sh` 全綠（含可重複性 T4、真 repo 煙霧測 T7）；`.asp-metrics-baseline.json` 已產出 |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（2026-06-11 對話明確授權，AI 代筆狀態變更；Accepted：2026-06-11 使用者明確指示「幫我同意，修改成 Accepted」，AI 代筆） |
| **驗證摘要** | asp-metrics.sh 對真實 repo 產出確定性基線，三組態 context 稅與 profile-map 展開一致 |
