# [ADR-020]: Treat AI forgetting as a first-class threat and mechanize process-obligation enforcement

| 欄位 | 內容 |
|------|------|
| **狀態** | `FIRM` |
| **日期** | 2026-06-12 |
| **決策者** | ASP framework maintainers |

> ⬆️ 由 `Draft` 升 `FIRM`：使用者 2026-06-12 透過 asp-plan HITL（AskUserQuestion）明確授權「升 FIRM + 實作 P1+P1b+P3」並放行實作（非 AI 自行升級，符合 ADR 狀態變更鐵則）。G1/G2 auto-gate 雙 PASS_WITH_WARN，findings 已修補。

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

ASP 對 AI 的「義務」分三層強制力（外部評估 + 一手驗證）：

| 層 | 條數 | 機制 | 忘記後果 |
|----|------|------|---------|
| (a) 硬強制 | 8 | Draft ADR dynamic deny、Iron Rule A/B、session briefing BLOCKER | 機械擋下，遺漏率 <1% |
| (b) 後驗兜底 | 7 | asp-ship Step 9/9.6、FIRM 標註、bypass log | 前提是「有呼叫 skill」 |
| (c) **純散文** | 9 | commit 前 asp-ship、Assumption Checkpoint、bug 後全專案 grep、SPEC Traceability、CONTEXT 術語… | **零機械兜底，忘了無人知** |

三個結構性弱點（皆一手驗證）：
1. **SessionStart 是唯一 hook**（`jq '.hooks|keys'` → `["SessionStart"]`）：無 PreToolUse/UserPromptSubmit/PreCompact/Stop → session 中途零機械提醒。「commit 前 asp-ship」只是散文，dynamic deny 只在 Draft ADR/測試未過時注入，平常忘跑 asp-ship 直接 commit **不會被擋**。
2. **Context 壓縮不對稱**：CLAUDE.md 由 harness 每 session 注入（壓縮後仍在）；`.asp-compiled-profile.md`（2082 行）是 Read 進 context，長對話壓縮後消失 → 只存在 profile 的義務最先蒸發。
3. **遙測盲區**：`rule-hits.jsonl` 只由 session-audit 機械寫（25 處 metric）；`asp-ship`/`asp-gate` skill **不寫遙測** → `make rule-stats`「90 天零命中」無法區分「用不到」與「一直被忘」。

**現場活證據**：本 session 開了 6 個 PR（#28–#33）。只有 #28 跑完整 asp-ship。**#29–#33 連續 5 次 commit 漏跑完整 asp-ship、未顯式宣告 trivial 豁免、未記 bypass** —— 而 `.asp-bypass-log.json` 11 筆 asp-ship 記錄全是更早 session 的，本 session 那 5 次「簡化」一筆未留。乾淨的 bypass log 是**倖存者偏差**，不是健康證據。

ADR-019 把「竄改（說謊的 AI）」設為威脅並加 hash-chain；但 ASP 威脅模型**缺「遺忘（健忘的 AI / context 熵）」這個類別**。本 ADR 補上。

---

## 評估選項（Options Considered）

### 選項 A：維持現狀（純散文 + 唯一 SessionStart hook）
- **優點**：零工作量；瘦身（v5 精神）。
- **缺點**：(c) 層 9 條義務持續隱形遺忘，且遺忘不留痕、無訊號。
- **風險**：關鍵過程義務（commit 前 asp-ship）長期靠 AI 自律，已被本 session 證實會忘。

### 選項 B：所有義務都用 hook 硬強制
- **優點**：理論上零遺忘。
- **缺點**：許多 (c) 層義務**無法機械判定**——「Assumption Checkpoint」「需求變更 L1-L4 分級」是語意判斷，hook 無法可靠偵測「該做卻沒做」；強行 hook 會製造大量誤擋與假強制。
- **風險**：enforcement theater——看似全防，實則對語意義務無效，反增噪音。

### 選項 C（選擇）：分層機械化 + 把「遺忘」設為一級威脅
只機械化「**可機械判定 + 高後果**」的義務（首推 commit 前 asp-ship），語意型義務誠實留為殘留：
- PreToolUse hook 攔 `git commit`，無 asp-ship 新鮮痕跡則 deny（散文 → 硬強制）。
- hook 順便寫 SHIP 遙測（補 (c) 層盲區）。
- 高風險「只在 profile」義務一行版提升進 CLAUDE.md（compaction-safe）。
- **優點**：覆蓋最常忘、後果最實的義務；遙測首次能偵測遺忘；不假裝能機械化語意義務（誠實邊界，同 ADR-019）。
- **缺點**：PreToolUse 增加 commit 延遲 + 需可靠 ship-trace 判定避免誤擋；只覆蓋部分 (c) 層。
- **風險**：hook 腳本本身須納入 Iron Rule A 保護（同 ADR-019 bypass-hash「看守者的看守者」教訓）。

### 選項 D：靠更長的 CLAUDE.md / 更多散文提醒
- **優點**：實作簡單。
- **缺點**：散文正是失效的東西；加長違背 v5 瘦身（ADR-013~018）。
- **風險**：把問題本身當解法。

---

## 決策（Decision）

採 **選項 C**。

1. **把「遺忘（context 熵 / 健忘的 AI）」加入 ASP 威脅模型一級類別**，與 ADR-019 的「竄改」並列。審查/驗證從此須問「規則在需要時還在 context 嗎」，而非只審規則內容。
2. **機械化關鍵過程義務（P1）**：新增 PreToolUse hook 攔 `git commit`；檢查**測試痕跡**（`.asp-test-result.json` passed=true 且 **mtime ≥ `.git/index`** —— 即最後一次 `git add` 之後跑過測試），無痕跡 → deny + 提示先跑 `/asp-ship`。
   - **誠實能力邊界（G1 F4 / G2 F1）**：hook 擋的是「連 `make test` 都沒跑就 commit」（asp-ship Step 1，最高後果步驟），**非**完整 10 步 ship；Steps 2-9（CHANGELOG/敏感掃描/Traceability）仍散文自律（本 ADR 已知殘留）。選測試結果作底線，因它由 `make test` 機械寫、可靠；「完整 ship 痕跡」得靠 skill 寫 sidecar = 又一散文義務，不可靠。
   - **死鎖防護（G1 F6）**：escape hatch（`ASP_SHIP_OK=1` / `make asp-unlock-commit`，留 bypass 痕跡）；且 **hook 腳本自身異常（jq 缺、stdin 非預期、腳本 crash）→ fail-open**（defer 放行 + WARN）——強制力讓位於可用性，此時退回散文（誠實殘留，由 Iron Rule A 防「故意改壞 hook 繞過」）。
3. **遙測補洞（P2）**：commit 閘判定時寫 `SHIP-GATE` metric → `rule-stats` 能看見「應觸發未觸發」。
4. **壓縮存活（P1b）**：高風險「只在 profile」義務的一行版提升進 CLAUDE.md（compaction-safe）。
5. **能力邊界（誠實界定）**：語意型義務（Assumption Checkpoint、需求變更分級等）**不強行 hook**，留為已知殘留 + 後續追蹤；本 ADR 不聲稱消除所有 (c) 層遺忘，只把「可機械判定 + 高後果」的那幾條從散文升為硬強制。

選 C 不選 B：B 對語意義務是 theater。選 C 不選 A/D：A/D 讓已證實的遺忘持續。

---

## 後果（Consequences）

**正面影響：**
- 最常忘、後果最實的「commit 前 asp-ship」從散文升為硬強制（PreToolUse deny）。
- 遙測首次能偵測「應觸發未觸發」（rule-stats 可見 SHIP-GATE）。
- 壓縮後關鍵義務仍存活於 CLAUDE.md。
- 威脅模型補上「遺忘」類別，未來審查有此維度。

**負面影響 / 技術債：**
- PreToolUse hook 增加每次 commit 延遲（ship-trace 檢查）；ship-trace 判定不可靠會誤擋 → 須謹慎設計新鮮度判定 + escape hatch。
- hook 腳本須納入 Iron Rule A `CRITICAL_FILE`（否則改 hook 即繞過，同 ADR-019 教訓）。
- **`tech-debt: MED`**：只覆蓋可機械判定的義務；語意型 (c) 層義務仍靠自律（誠實殘留）。
- PreToolUse hook 是 harness 層行為，跨 repo 邊界，須在 install/sync 流程同步。

**後續追蹤：**
- [ ] SPEC：PreToolUse commit 閘 + ship-trace + 遙測（P1+P2）
- [ ] P1b：評估 PreCompact / UserPromptSubmit hook 重注入義務摘要（更強的壓縮存活，環境中 rust-skills 有 UserPromptSubmit 先例）
- [ ] P3：CONTEXT.md 術語檢查併入 G1/G2 gate subagent checklist（ADR-009 機制已存在）
- [ ] hook 腳本納入 Iron Rule A CRITICAL_FILE
- [ ] 事故歸檔強制標注「失效類別」（遺忘 vs 竄改 vs drift）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 無 ship 痕跡直接 git commit → 被擋 | 100% | `test_pretooluse_ship_gate.sh`（模擬無痕跡 commit） | 實作完成時 |
| ship 痕跡新鮮時 commit 放行 | 0 誤擋 | 同上（跑 asp-ship 後 commit 應放行） | 實作完成時 |
| escape hatch 有效（避免死鎖） | 是 | 同上（ASP_SHIP_OK=1 / unlock 後放行） | 實作完成時 |
| rule-stats 出現 SHIP-GATE 命中 | 是 | `make rule-stats` 含 SHIP-GATE | 實作完成時 |
| hook 腳本受 Iron Rule A 保護 | 是 | `test_iron_rule_a_coverage.sh` 含該 hook | 實作完成時 |
| 既有測試零回歸 | bash+pytest 全綠 | `make test` | 實作完成時 |

> 重新評估條件：若 PreToolUse 誤擋率過高（影響正常開發），重審 ship-trace 新鮮度判定或退回 WARN 級。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：ADR-019（威脅模型「竄改」+ hash-chain；本 ADR 加「遺忘」並列，並沿用「誠實界定能力邊界」「hook 納入 Iron Rule A」原則）；外部評估報告（jiggly-coalescing-babbage，2026-06-12）；`.claude/settings.json`（目前僅 SessionStart）；CLAUDE.md「強制力架構」表
- 實作 SPEC：SPEC-013（PreToolUse commit 閘）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | 本 session 實作於 `asp/adr020-forgetting-threat`；`test_pretooluse_ship_gate.sh` **12/12 PASS**（擋無痕跡/放行新鮮/escape hatch/複合偵測/F5 不誤判/amend/fail-open）；`test_iron_rule_a_coverage.sh` **8/8**（hook 受保護）；`test_rule_registry.sh` **24/24**（SHIP-GATE 登記）；`make test` 全綠（bash 45/45、pytest 16/16）+ `make lint` pass |
| **驗證日期** | 2026-06-12 |
| **驗證者** | astroicers（使用者經 asp-plan HITL 授權升 FIRM + 實作 P1+P1b+P3） |
| **驗證摘要** | PreToolUse commit 閘擋住無痕跡 commit、放行新鮮測試痕跡、escape hatch（ASP_SHIP_OK）+ fail-open 防死鎖、SHIP-GATE 遙測寫入、hook 受 Iron Rule A 保護；誠實邊界：擋的是「連測試都沒跑」非完整 10 步 ship（Steps 2-9 仍自律，已知殘留） |
