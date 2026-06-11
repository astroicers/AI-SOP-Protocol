# [ADR-014]: v5 taxonomy convergence merge loose-governance profiles and collapse maturity levels to three

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-11 |
| **決策者** | astroicers（v5 重構簡報 Phase 1）+ AI（合併裁決設計） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

v5 瘦身重構原則 3：「分類學收斂：組合空間從數百種降到個位數」。現況兩個維度都過度切分：

1. **Profiles 16 個**，其中 4 個是低治理場景的碎片：`vibe_coding`（177 行，workflow 維度）與 `spike_mode`（84 行，level 維度）描述同一族「鬆治理」行為卻分屬兩個欄位；`escalation`（91 行）v4.1 縮版後只剩路由表，自身載入條件（multi-agent 或 autonomous）使其 fallback 分支「永遠不會觸發」（其檔內 :84 自承）；`guardrail`（65 行）只有一個三層回應函數，與 user-level CLAUDE.md 鐵則「敏感資訊保護」重複一半。
2. **Levels 6 級**（L0-L5），相鄰級差異小（L2 vs L3 只差 pipeline；L4 vs L5 只差 autonomous/autopilot/rag），使用者面對六選一的決策負擔與 `.ai_profile` 組合爆炸（簡報：組合空間數百種）。

---

## 評估選項（Options Considered）

### 選項 A：只併 profiles、不動 levels

- **優點**：改動面小，level 解析點（5 處）不用動。
- **缺點**：六級制的決策負擔與 yaml 維護成本仍在；level yaml 的 `profiles:` 清單仍引用被併掉的檔案，反而增加失配。
- **風險**：分類學收斂只做半套，v5 目標（組合空間個位數）不達。

### 選項 B：profiles 16→13 + levels 6→3，舊值自動映射（採用）

- **優點**：兩個維度同步收斂；數字 level 由 `level-resolve.sh` 中央映射（0,1→loose；2,3→standard；4,5→autonomous）+ deprecation 提示，既有專案零中斷；映射資料放 `profile-map.yaml`（ADR-013 的單一來源），不新增散文。
- **缺點**：所有 level 解析點（validate-profile.sh、Makefile.inc×3、install.sh/ps1、l0-audit.sh、asp-level skill）都要改走 resolve；舊 L2 專案映射到 standard 後會多載 pipeline（升嚴）。
- **風險**：解析點漏改 → 以 grep 驗收組 + 測試防護。

### 選項 C：levels 砍到 3 但沿用新數字（1/2/3）

- **優點**：解析點改動較小（仍是數字）。
- **缺點**：`level: 3` 在 v4（Test-First）與 v5（最高級）語意完全不同，靜默誤映射比報錯更危險。
- **風險**：語意衝突無法被機器偵測，違反 v5「規則越少越鐵」。

---

## 決策（Decision）

選擇 **選項 B**。

### 1. Profile 合併對照表（16 → 13）

| 來源 | 去向 | 歸檔 |
|------|------|------|
| `vibe_coding.md` (177) + `spike_mode.md` (84) | 新 `loose_mode.md`（~150 行） | `docs/archive/profiles/` |
| `escalation.md` (91) | `global_core.md` 新「升級路徑（Escalation）」節 | 同上 |
| `guardrail.md` (65) | `global_core.md` 新「範疇與敏感資訊三層回應」節 | 同上 |

### 2. 合併裁決（衝突保留較嚴格者，逐條記錄）

| # | 衝突/裁決點 | 裁決 | 理由 |
|---|------------|------|------|
| D1 | vibe `hitl: minimal` 可自主 vs spike「強制 hitl: strict」 | **spike 豁免活動期間強制 strict**（spike 範疇內較嚴格者勝）；spike 範疇外依 HITL 等級 | spike 的 strict 動機是「探索未知」；合併後 loose 也涵蓋舊 L1 正常開發，全程 strict 過度 |
| D2 | `autonomous_dev requires vibe_coding` vs `spike_mode conflicts autonomous_dev`（合併後自我矛盾） | HITL 等級定義（`should_pause()` + minimal 行為規範表）**上移 global_core**；`autonomous_dev` requires 降為 `global_core, system_dev`；loose_mode 保留 spike 的 conflicts 全列 | autonomous 真正依賴的是 HITL 定義，不是 vibe 的角色分工表 |
| D3 | loose_mode conflicts 是否保留 `pipeline` | **保留**（沿 spike 全列：autonomous_dev, autopilot, pipeline, multi_agent） | 簡化勝於精細：舊「L2/L3 + workflow: vibe-coding」組合在 v5 由消費端衝突規則「丟較鬆者 + WARNING」處理（vibe 的可重用內容——HITL——已上移 global_core，損失有限）。**已知行為變更，記入 CHANGELOG Breaking** |
| D4 | `/asp-escalate` 幽靈引用（該 skill v4.3 已併入 asp-handoff；斷鏈現存於 escalation.md ×5、`asp-dev-qa-loop.md:165`、`asp-team-pick.md:104`——G1 review F-2 盤點） | 併入 global_core 時全部改指 `/asp-handoff`（ESCALATION 類型）；**兩個 skill 檔的斷鏈一併修正**，驗收 grep 加掃 `asp-escalate` | 修正既有斷鏈，驗收面涵蓋 skill 名稱本身 |
| D5 | escalation 的 `IF escalation_loaded` fallback 分支（autonomous_dev、task_orchestrator Part G） | **刪除 fallback**——前提：**與 escalation 併入 global_core 在同一個 Phase 1 commit 落地**（G1 review F-3），升級路徑自此永遠載入，不存在空窗 | escalation.md :84 自承 multi-agent/autonomous 場景下 fallback 永不觸發；單獨啟用場景（L2/L3）由「永遠載入」直接取代 |
| D6 | guardrail Layer 1 敏感清單 vs user-level CLAUDE.md 鐵則 2 重複 | global_core 保留完整三層回應（含敏感清單與偽裝模式——較完整側）；標注鐵則 2 為其上位規則 | 鐵則語意不變（紅線 1），global_core 提供執行細節 |
| D7 | 舊 L2（無 pipeline）映射到 standard（含 pipeline） | **接受升嚴**（保留較嚴格者原則的層級版） | L2/L3 合併必然二選一；選鬆會讓舊 L3 失去 gates，違反紅線 2 |
| D8 | 舊 L5 preset `workflow: vibe-coding` 撞 loose_mode conflicts | 新 autonomous 等級 hint/preset 改 `workflow: standard`；舊 profile 由消費端「丟較鬆者 + WARNING」容錯 | vibe 對 autonomous 的價值（HITL）已在 global_core |
| D9 | 幽靈引用 `multi_agent`（level-4/5 yaml `profiles:` 清單、各 profile optional 清單） | 新 level yaml 不再列；消費端（map/metrics/compile）一律容錯忽略 | v4.3 已併入 task_orchestrator Part G |

### 3. Levels 6 → 3

| 新等級 | 吸收 | 核心 profiles（yaml 清單） | hint 要點 |
|--------|------|------|------|
| `loose` | L0, L1 | global_core, system_dev*, loose_mode | hitl: standard（spike 豁免活動強制 strict） |
| `standard` | L2, L3 | + coding_style, pipeline | coding_style: enabled（guardrail 欄位 deprecated→INFO 已內建） |
| `autonomous` | L4, L5 | + task_orchestrator, reality_checker, autonomous_dev, rag_context | mode: multi-agent、autonomous/autopilot/rag: enabled、**workflow: standard**（D8） |

*`type: content` 時由 type 映射載 content_creative，修掉舊 L1 yaml 對 content 專案硬列 system_dev 的失配。

- 新檔 `.asp/levels/{loose,standard,autonomous}.yaml`（schema 沿用 + 新欄位 `aliases: [N, M]`）；舊 6 檔歸檔 `docs/archive/levels/`。
- `.ai_profile` 的 `level:` 同時接受名稱與舊數字 0-5；數字由 `.asp/scripts/level-resolve.sh`（讀 profile-map.yaml `level_aliases:` 段，缺檔 fallback 內建表）映射並印 deprecation 提示（預告 v6 移除），**不報錯**。
- 解析點全數改走 level-resolve：validate-profile.sh、Makefile.inc（asp-level-check/-upgrade/-list）、install.sh preset（5→3）/互動選單/非互動 ASP_LEVEL、install.ps1、l0-audit.sh（語意改為 loose lifecycle audit，檔名與 target 不動）。session-audit.sh 不解析 level，不在改動面。

### 4. 回滾方式

單一 commit `git revert`：被併檔案以 `git mv` 歸檔（內容無損），revert 即還原原路徑；level yaml 同理；無資料破壞。已安裝環境（~/.claude/asp/）由 install/asp-sync rsync 還原。

---

## 後果（Consequences）

**正面影響：**
- profiles 16→13（Phase 4 再到 12）；levels 6→3；`.ai_profile` 組合空間大幅收斂。
- escalation/guardrail 行為從「條件載入」變「永遠載入」（global_core），消除「fallback 永不觸發」的死代碼與漏載風險。

**負面影響 / 技術債：**
- global_core 435→~550 行：所有等級常駐 context 稅 +~115 行（接受：global_core 是 v5 唯一常駐稅；Phase 3 編譯產物整體仍大幅下降）。
- 「L2/L3 + workflow: vibe-coding」組合不再載入角色分工表/Context 管理內容（D3，Breaking）。
- **install preset 最高級的 `workflow` 由 `vibe-coding` 改為 `standard`**（D8，Breaking——新安裝的 autonomous 專案行為改變；G1 review F-8）。
- 改動面明列：`autonomous_dev.md` requires 檔頭與「與其他 Profile 的關係」樹（F-5）、`asp-dev-qa-loop.md`/`asp-team-pick.md` 的 asp-escalate 斷鏈（F-2）、validate-profile.sh 對 `level: 0` 誤報 ERROR 的既有不一致（F-6，由 level-resolve 接管後修正）。
- install.ps1 無法本機驗證 → grep 契約測試 + `tech-debt: MED test-pending`。

**後續追蹤：**
- [ ] Phase 3：asp-compile 落地後驗證 D3/D8 衝突裁決（loose×autopilot 顯式衝突 exit 1；workflow 衍生衝突降級 WARNING）
- [ ] Phase 4：rag_context 移 showcase 後，autonomous.yaml 移除 rag_context 條目
- [ ] v6：移除數字 level 支援（deprecation 文案已預告）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| Profile 數 | `ls .asp/profiles/*.md \| wc -l` = 13 | `tests/test_profile_merge.sh` | Phase 1 結束 |
| 活引用零殘留 | `grep -rn "vibe_coding\|spike_mode\|escalation\.md\|guardrail\.md\|asp-escalate"` 於 .asp/.claude/CLAUDE.md/CONTEXT.md = 0（archive 除外；含 skill 名稱本身——F-2） | grep 驗收組 + `test_profile_merge.sh` T5 | Phase 1 結束 |
| 舊值相容 | `level: 3` 載入正常 + stderr 含 DEPRECATED、exit ≠ 1 | `tests/test_level_resolve.sh`、`test_validate_profile.sh` | 每次 make test |
| 紅線 4 | `grep -c "繞過藉口" global_core.md` ≥ 3 | `test_profile_merge.sh` | 每次 make test |
| levels schema | 恰 3 檔、profiles 清單逐項有實檔、next_level 鏈完整 | `tests/test_levels_schema.sh` | 每次 make test |

---

## 關聯（Relations）

- 取代：（無——但 supersede 舊 level-0~5.yaml 與 4 個 profile 檔，全部歸檔非刪除）
- **Partial supersede：ADR-006 item 13 與 KEEP-AS-IS 清單之 `level-0.yaml`**（G1 review F-1/F-4）——ADR-006 原規劃「6→4 級、保留獨立 L0」；本 ADR 依 v5 簡報明確指示改採 6→3（L0,L1→loose）。L0 的辨識價值（timebox、spike 紀律、`[spike]` 標記）**完整保留於 loose_mode.md 的「探索豁免」節**，`l0-audit.sh` 續存為 loose lifecycle audit；犧牲的只是獨立等級編號。
- 被取代：（無）
- 參考：ADR-013（profile-map 單一來源 + v5 規劃來源記載）、ADR-007（v4.3 整併先例）、ADR-006 §v5.0.0

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | branch `asp/v5-slimming`：test_level_resolve / test_levels_schema / test_profile_merge 全綠；grep 驗收組零殘留；`make asp-level-check` 三級制輸出正常 |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（2026-06-11 對話授權，含 ADR-015~018 同模式授權；AI 代筆狀態變更；Accepted：2026-06-11 使用者明確指示「幫我同意，修改成 Accepted」，AI 代筆） |
| **驗證摘要** | 合併後 13 profiles + 3 levels，舊 .ai_profile 數字值映射相容，紅線 1-4 全數保留 |
