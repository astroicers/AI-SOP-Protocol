# [ADR-017]: Separate daily-driver core from experimental multi-agent and showcase components

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-11 |
| **決策者** | astroicers（v5 簡報 Phase 4）+ AI（連動面設計） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

ASP 預設安裝面混雜三類成熟度不同的元件：(1) **Daily-driver core**（hooks、skills、gates、profiles——每天用）；(2) **multi-agent worktree 並行**（8 支腳本 + 10 角色 yaml + 3 skills + Part G profile——SPEC-004 完成後缺乏「單 session 無法完成」的實際使用案例，維護成本持續發生）；(3) **展示/研究用途**（telemetry、RAG、ai-performance——量測與檢索基礎設施，非治理核心）。v5 原則 4：Daily-driver 與 Showcase 明確分離，後者不進預設安裝路徑。

關鍵架構事實：install.sh 只複製 `.asp/*` 與 `.claude/skills/*` ——**把元件移出 `.asp/` 即自動脫離安裝路徑**，無需安裝器白名單邏輯。

---

## 評估選項（Options Considered）

### 選項 A：保留原位，install.sh 加排除清單

- **優點**：repo 結構不動，git 歷史最乾淨。
- **缺點**：安裝器要維護排除規則（與「移出即排除」相比是持續成本）；repo 結構不反映元件定位，README 矩陣與目錄不對應；asp-sync rsync 全量同步也要同套排除。
- **風險**：排除清單漂移 → 凍結元件悄悄回到安裝面。

### 選項 B：實體目錄分離——`experimental/` 與 `showcase/`（採用，簡報定案）

- **優點**：目錄即定位（README 矩陣 ↔ 目錄一一對應）；安裝面由「`.asp/` 內 = 安裝」單一規則決定；`-include` 讓 make targets 隨目錄存在自動載入/消失，零 stub。
- **缺點**：~30 檔 git mv；隨遷測試需 1-2 行路徑修正；asp-sync 需 marker 機制保護使用者裝回的 showcase。
- **風險**：升級殘留（舊安裝的 ~/.claude/asp/ 仍有 telemetry/rag/agents）→ install.sh 升級路徑顯式清理。

### 選項 C：直接刪除 multi-agent 與 showcase 元件

- **優點**：最大瘦身。
- **缺點**：SPEC-004 的工程投資（worktree 隔離、crypto gate、audit-write）直接報廢；違反簡報指示「等待實際案例後解凍」。
- **風險**：解凍時要從 git 歷史考古重建。

---

## 決策（Decision）

選擇 **選項 B**。

### 1. 移動表（全部 `git mv`，內容零修改除路徑修正）

| 來源 | 去向 | 性質 |
|------|------|------|
| `.asp/scripts/multi-agent/`（8 支） | `experimental/multi-agent/scripts/` | FROZEN |
| `.asp/agents/`（10 角色 + team_compositions.yaml） | `experimental/multi-agent/agents/` | FROZEN |
| `.claude/skills/asp/{asp-dispatch,asp-team-pick,asp-handoff}.md` | `experimental/multi-agent/skills/` | FROZEN |
| `.asp/profiles/orchestrator_multi_agent.md` | `experimental/multi-agent/profiles/` | FROZEN |
| `tests/test_spec_004_*.sh` ×7、`test_validate_audit_root.sh`、`test_converge_crypto_gate.sh`、`tests/perf/` | `experimental/multi-agent/tests/`（路徑變數 1-2 行修正，斷言不動） | FROZEN |
| `.asp/scripts/telemetry/` | `showcase/telemetry/` | Showcase |
| `.asp/ai-performance/` + `tests/test_monthly_review.py` | `showcase/ai-performance/`（tests/ 子目錄） | Showcase |
| `.asp/scripts/rag/` + `.asp/hooks/rag-auto-index.sh` + `.asp/profiles/rag_context.md` + `tests/test_build_index.py` | `showcase/rag/`（scripts/hooks/profiles/tests/） | Showcase |

凍結宣告：`experimental/multi-agent/README.md` 標 `Status: FROZEN (v5.0)`——解凍條件 =「出現單一 session 無法完成的實際案例」；長期方向 = 改建於 Claude Code 原生 subagent。

### 2. Makefile：`-include` 機制（擇「偵測目錄存在才生效」案）

core `Makefile.inc` 末尾 `-include experimental/multi-agent/Makefile.inc` + `-include showcase/Makefile.inc`（缺檔靜默跳過）→ 安裝到一般專案 targets 自然消失、本 repo 與解凍者零設定。agent-*/rag-*/asp-telemetry-*/asp-performance-review* targets 搬入各自 Makefile.inc 並修路徑；core lint 移除 multi-agent 硬引用；**`make test` 不掃 experimental**（frozen 語意——凍結代碼不阻擋日常 commit），`make test-experimental` 為手動入口（Phase 4 收尾一次性跑綠記入 PR）。順手刪除 v3.7 deprecated stubs（agent-unlock/agent-locks/agent-lock-gc/agent-memory-*）。

### 3. 安裝/同步連動

- install.sh：`--with-showcase` 旗標 + `ASP_WITH_SHOWCASE=1` env（curl|bash 場景）——把 showcase 內容**按原始佈局**裝回 `~/.claude/asp/`（scripts/telemetry、scripts/rag、hooks/rag-auto-index.sh、profiles/rag_context.md、ai-performance），`touch ~/.claude/asp/.showcase-installed` marker；dir 複製迴圈移除 `agents`；升級路徑（無旗標）顯式清理 stale（舊 agents/telemetry/rag/3 skills）；experimental 永不安裝。install.ps1 同步 dirs 清單（Windows showcase 裝回延後，`tech-debt: MED test-pending`）。
- asp-sync.sh：rsync `--delete` 後若 marker 存在 → 自 `showcase/` 補同步裝回內容（防抹掉使用者安裝）；marker 加 exclude。
- uninstall.sh：整目錄移除已涵蓋，僅修 skill 數量文案。

### 4. 引用面收斂

- SKILL.md router：移除 asp-dispatch/asp-team-pick/asp-handoff 條目與觸發詞；「角色 ↔ Skill 映射」表移至 experimental README；escalate/P0/P1 路由改一行「依 global_core『升級路徑』章節處理」（Phase 1 已自含）。
- `.ai_profile` 相容警告：`mode: multi-agent` → 🟡「已凍結為 Experimental，預設不安裝；建議 mode: auto」（validate-profile + session-audit A1.4 改字，不升 ERROR）；`rag: enabled` → 🟡「Showcase 元件，--with-showcase 裝回」（偵測 marker 則維持原提示）。
- profile-map：移除 `rag=enabled → rag_context` 與 mode=multi-agent 的 `orchestrator_multi_agent`（兩檔已不在 `.asp/profiles/`，避免常態幽靈 WARNING）。
- levels `autonomous.yaml`：profiles 清單移除 rag_context；hint 改 `mode: auto`、移除 `rag: enabled`（test_levels_schema T3 幽靈防護把關）。
- 本 repo `.claude/settings.json`：移除 scope-guard PreToolUse hook（重新啟用方式記入 experimental README）。
- docs/multi-agent-architecture.md、runbooks：檔頭加 FROZEN 標注；歷史內文與 ADR/SPEC/CHANGELOG 字樣不改（E2 慣例）。
- README：新增功能矩陣（Core / Experimental / Showcase）。

### 5. 回滾方式

單 commit revert：全部為 `git mv` + 文字修改，revert 還原所有路徑；marker/`--with-showcase` 為純新增邏輯。已安裝環境由 install/asp-sync 重跑還原。

---

## 後果（Consequences）

**正面影響：**
- 全新安裝的 `~/.claude/` 不含 multi-agent/telemetry/rag 任何檔案（Done When 一）；profiles 14 → **12**（rag_context、orchestrator_multi_agent 移出），與簡報最終目標一致。
- L5_autonomous context 稅再降（mode=multi-agent 不再拉入 orchestrator_multi_agent 257 行、rag_context 136 行）→ 預估 -34%，補足 Phase 3 遞延的 ≥30% 驗收。

**負面影響 / 技術債：**
- 凍結測試移出 `make test` 後可能腐化——freeze 語意即接受；解凍前先 `make test-experimental` 重建綠基準（README 明示）。
- 既有使用者升級後 `mode: multi-agent` / `rag: enabled` 變警告（功能需手動裝回）——Breaking，記入 CHANGELOG。
- install.ps1 的 showcase 裝回未實作（Windows）→ `tech-debt: MED test-pending`。

**後續追蹤：**
- [ ] 解凍評估：收到「單 session 無法完成」實際案例 → 解凍 ADR + make test-experimental 重建基準
- [ ] 收尾：assert-reduction 30（L3+L5）統一驗收

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 安裝面乾淨 | 暫存 HOME 全新安裝後 `find ~/.claude -path '*multi-agent*' -o -name '*telemetry*' -o -path '*rag*'` = 0 | 手動驗證記入 PR + test_separation.sh 靜態斷言 | Phase 4 結束 |
| 裝回完整 | `--with-showcase` 後 rag/telemetry 檔案就位（佈局與 v4 相同） | 暫存 HOME 實測 | Phase 4 結束 |
| profiles = 12 | `ls .asp/profiles/*.md \| wc -l` | test_profile_merge.sh T1（12 為合法值） | 每次 make test |
| core 測試綠 | `make test` 不含 experimental 仍全綠 | make test | 每次 |
| 凍結測試一次性綠 | `make test-experimental` 全綠（移動本身無破壞） | 一次性，記入 PR | Phase 4 結束 |
| 無殘留引用 | `.asp/` 內無 multi-agent/telemetry/rag 路徑；SKILL.md 無凍結 skill 條目 | test_separation.sh | 每次 |

---

## 關聯（Relations）

- 取代：（無——multi-agent 為凍結非廢棄；SPEC-004 維持 Accepted 歷史地位，標注 Experimental）
- **Partial supersede：ADR-010/SPEC-004 的「安裝面與維護承諾」**（G1 review F-6）——其技術決策（worktree 隔離、crypto gate、audit-write）與驗收（21/21）**不被否定**，被取代的只有「隨預設安裝、持續維護」這一面；凍結理由 = SPEC-004 GA 後至今（2026-05-10 → 06-11）零實際 multi-agent 任務案例，維護成本（每次 core 重構的連動修改 + lint + 測試面）持續發生而效益為零。解凍條件與長期方向見 experimental README
- 被取代：（無）
- 參考：ADR-015（orchestrator_multi_agent 抽出的預告）、ADR-016（L5 驗收遞延的承接）、ADR-006（feature audit 中 multi-agent 使用率的原始觀察）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | branch `asp/v5-slimming`：test_separation.sh 38/38；make test 綠（core）；make test-experimental 9/9 一次性綠；L5 稅 -34.5%（達 ADR-016 遞延之 ≥30%）；暫存 HOME 安裝驗證於 Phase 4 commit 後重跑（clone 取 committed 狀態），結果記入 PR |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（2026-06-11 對話 blanket 授權 ADR-015~018；AI 代筆狀態變更；Accepted：2026-06-11 使用者明確指示「幫我同意，修改成 Accepted」，AI 代筆） |
| **驗證摘要** | Core/Experimental/Showcase 實體分離；安裝面由目錄結構單一規則決定；profiles 達 12 |
