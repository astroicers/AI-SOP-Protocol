<!-- Last Updated: 2026-06-06 | Status: Draft | Audience: Maintainers -->
# [ADR-010]: 借鑒 Understand-Anything 的 orchestration 模式（精簡採納）

| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
| **日期** | 2026-06-06 |
| **決策者** | astroicers（待確認） |
| **觸發事件** | 評估 `Lum1104/Understand-Anything`（UA）在 multi-agent orchestration 的優勢，是否有選擇地吸收進 ASP v4.0 |
| **關聯 ADR** | ADR-002（**Iron Rule B** append-only audit；本 ADR Pattern B 修補其執行缺口）；ADR-007（精簡理念）；SPEC-004（multi-agent worktree 隔離）。⚠️ **註**：crypto / customer-facing / high-stakes 的 HITL 權威來源是 **production-ops-playbook 鐵則 6/7 + CLAUDE.md 鐵則**，**非** ADR-002 的 Iron Rule A/B/C（那是 Hook 完整性 / append-only log / tool-output UNTRUSTED） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

`Lum1104/Understand-Anything`（UA）與 ASP 是**同物種**——都是 CLAUDE.md 驅動、跑 multi-agent pipeline 的 orchestration 系統。UA 在 production 壓力下對「相同問題」做出了一些 ASP 尚未採取的取捨，因此價值在於**照鏡子**：有選擇地吸收已驗證的優勢，而非當外部工具引入。

對 UA 原始碼（`SKILL.md`、`file-analyzer.md`、`graph-reviewer.md`、`merge-batch-graphs.py`、`extract-structure.mjs`、repo CLAUDE.md）精讀後，歸納出 8 個可借鑒模式。對照 ASP 現況得到兩個**已驗證事實**：

1. **ASP 在「agent 產出 → converge 合併」之間沒有確定性（非 LLM）的結構完整性 pass**（兩個獨立探索各自確認）。這對應 UA Pattern 3（`merge-batch-graphs.py` 的 deterministic safety-net）。
2. **一個真實的 latent bug**（UA Pattern 7 的鏡像 / issue #133）：[`_validate_audit_root.sh:44-52`](../../.asp/scripts/multi-agent/_validate_audit_root.sh) 用 `[ ! -e "$ASP_AUDIT_ROOT/.git" ]` 判斷 git repo，但 **git worktree 的 `.git` 是「檔案」不是「目錄」** → `-e` 為真 → 跳過 `git rev-parse` 檢查 → **worktree 被當成 main repo 通過驗證**。配合 `converge.sh` 把 worktree 建在 `ASP_AUDIT_ROOT` 底下並以 `git worktree remove --force` 銷毀，任何 worker 在 worktree 內以文件化的 `ASP_AUDIT_ROOT="$(git rev-parse --show-toplevel)"` 寫 audit/bypass/escalation NDJSON，**session 結束即被靜默銷毀 → 破壞 Iron Rule B（append-only audit trail）**。值得注意：[`SPEC-004 §🔒 共享狀態檔案路徑策略`](../specs/SPEC-004-multi-agent-worktree-isolation.md) **已明文規定** worker 必須寫主 repo（非 worktree），但 `_validate_audit_root.sh` 從未強制執行——**這是「既有規範存在、實作未落實」的缺口，而非新需求**。

**關鍵約束**：採納 UA 任何模式時，下列 hard constraints 優先於一切效率/一致性考量，不得弱化：crypto/backup-encryption 永遠 HITL（AI 不碰 bytes，失敗模式為 silent corruption）；customer-facing 永遠人審；high-stakes（auth/crypto/customer-facing）= cross-vendor 4/4 + human。**亦不得違反 ASP 精簡/分級理念**（CLAUDE.md 92 行、L0–L5 分級、Design Principle 13「獨立性是光譜，依 stakes 選擇」、ADR-002 選項 C 已明示「過度工程反讓使用者繞過框架」）。

---

## 評估選項（Options Considered）

### 選項 A：完整採納 UA（含 Pattern 3 完整 deterministic 層 C0–C6）

在 converge 前新增一整層確定性閘門：crypto 偵測 + scope 包含性 + conflict-marker + test-smuggling + test-artifact 比對 + secrets 掃描。

- **優點**：功能最全、defense-in-depth 最厚。
- **缺點**：與 ASP **既有多層**大量重疊——scope 已由 `scope-guard.sh`（PreToolUse）攔截、smuggling 已由 `auto_fix_loop` checksum guard 偵測、secrets 已由 `asp-ship` Step 9 掃描；重做只增維護面與定義漂移。且在 converge 疊多個 fail-closed 卡點 → autopilot 更易卡住、需人介入 → **諷刺地降低自動化程度**。
- **風險**：**過度工程**，與 ADR-002 選項 C、本專案精簡理念衝突；正是 UA 評估 briefing 第 6 節警告的 over-borrow。UA 需要 `merge-batch-graphs.py` 是因為它合併「N 個 LLM 各自吐的 graph JSON」（結構錯誤頻繁且廉價可修）；ASP 合併的是「已過多層把關的 code branch」，邊際價值遠低。

### 選項 B：精簡採納（Pattern B + A + Pattern 3-僅 C0 + C）（建議）

只取「修漏洞」與「低成本精簡」的部分，拒絕重疊的確定性層：

- **B（worktree audit guard）**：`_validate_audit_root.sh` 加 Stage D2，比較 `--git-dir` vs `--git-common-dir`，worktree 作 `ASP_AUDIT_ROOT` → exit 7（fail-closed），env `ASP_ALLOW_WORKTREE_AUDIT_ROOT=1` 覆寫。落實 SPEC-004 §🔒 既有規範。
- **A（handoff naming）**：formalize `.asp-worktrees/<task>/.asp-out/` 輸出契約 + 檔名規範 + 「只回傳一行 summary」紀律。validator **只 log 不擋**（不新增卡點）。refinement 既有 v4.1 D-001 scratchpad 慣例。
- **Pattern 3（僅 C0 crypto gate）**：converge 在 rebase 前**只**偵測 diff 是否觸及 crypto/backup-encryption 路徑 → 若是，不 merge、寫 P0 escalation、`continue`（其他 task 續跑）。**analyze-only，永不改 bytes。** 補 converge 階段目前缺的鐵則硬執行；C1/C3/C5 交既有層，不重做。
- **C（trivial-tier binary gate，⚠️ 目前 doc-only / 待接線）**：`trust-tier.yaml` 加 `auto_merge_gate.precondition: zero_critical_findings`。**正確 framing（經審查更正）**：TIER_3/TIER_2 現況已是 `auto_merge: true` 無條件，本 gate 是**新增阻擋條件（收緊以提升安全）**，**不是**放寬或減摩擦。**現況無執行力**：repo 無任何 parser 消費 `auto_merge_gate`、`touches_sensitive_path` 在 code 中不存在、`ai_classification` 是 AI 自填標籤無強制——故「high-stakes 永不繞過」目前僅為 YAML 宣告 + AI 自律。**升 Accepted 為「採納」的前提**：trivial 分類與 sensitive-path early-return 必須由**確定性 code** 強制（沿用 production-ops-playbook §4 硬規則 + 與 C0 同款 path regex）；否則本項僅列為 doc-only 意圖（同 Pattern 8 等級）。

- **優點**：B/C0 修補兩個真實漏洞、A 精簡 handoff 約定；**相對選項 A 不重做既有 C1/C3/C5 三層**（避免過度工程）；全部低成本；嚴格不弱化 hard constraints。（原稱「淨減摩擦 / 不增治理層數淨值」經獨立審查更正：Pattern C 實為收緊、B/C0 為新增 fail-closed 卡點——見後果與成功指標。）
- **缺點**：未取得完整 defense-in-depth（接受——既有層已覆蓋）。
- **風險**：B 為 fail-closed，誤設 `ASP_AUDIT_ROOT` 的舊流程會由「靜默錯誤」變「明確 exit 7」（有 env 覆寫與正確調用範例緩解）；C 的 auto-merge 本質有風險（由 sensitive-path block + trivial 分類 + 既有 trust-score 回饋夾制）。

### 選項 C：完全不採納，維持現狀

- **優點**：零改動、零維護。
- **缺點**：留下 **Pattern B 確認 bug**（audit trail 靜默丟失，破壞 Iron Rule B）與 **converge 階段無 crypto 偵測**（依賴 worker 端自律）；放棄 A/C 的低成本自動化便利提升。
- **風險**：Iron Rule B 在 multi-agent 並行場景的審計完整性實際上未被保障；安全治理出現「文件聲稱、實作缺口」的 false sense of security（與 ADR-002 動機相同的反模式）。

---

## 決策（Decision）

我們選擇 **選項 B（精簡採納）**。

理由：核心價值是 **B/C0 修補兩個真實漏洞**（B 落實 SPEC-004 §🔒 既有規範、C0 把 crypto 鐵則從 worker 自律提升為 converge 硬執行）+ **明確拒絕 Pattern 3 完整版 C1–C6**（與 `scope-guard.sh` / `auto_fix_loop` / `asp-ship` Step 9 重疊、在 converge 增多個 fail-closed 卡點，違反精簡理念——ADR-002 選項 C 教訓）。所有 hard constraints（crypto HITL、customer-facing 人審、high-stakes cross-vendor + human）均不被弱化。

**經獨立審查（5/5 accept_with_changes）更正兩點**：(1) 原稱「整體淨減摩擦 / 不增治理層數淨值」不精確——B/C0 是**新增** fail-closed 卡點、Pattern C 是**收緊**現有無條件 auto-merge；正確說法為「相對選項 A 不重做 C1/C3/C5 三層」。(2) **Pattern C 目前為 dead spec**（無 parser、`touches_sensitive_path` 無 code、分類無強制），其「僅 trivial、不繞過 high-stakes」承諾在 code-enforced 之前無執行力 → 降為 doc-only 意圖，待補確定性強制才算正式採納。

落地與 diff 草案詳見 [`docs/research/ua-orchestration-adoption.md`](../research/ua-orchestration-adoption.md)；worktree/converge 範疇的可執行規格見 SPEC-004 addendum（B + C0 + A）。**Pattern C（trust-tier）維持 doc-only**——本 ADR 僅記錄意圖與正確 framing，正式 SPEC + code-enforced 實作待 trust-tier 子系統有 auto-merge executor 時再開。

**本 ADR 維持 `Draft`，依鐵則「Draft 禁止實作」——人類核准升至 `Accepted` 前，不得 commit 對應 production code。**

---

## 後果（Consequences）

**正面影響：**
- 修補 Iron Rule B 在 multi-agent 場景的審計完整性漏洞（B），落實 SPEC-004 §🔒 既有規範。
- converge 階段補上 crypto 硬邊界偵測（C0），不依賴 worker 自律（analyze-only、永不改 bytes）。
- 統一 worker 輸出契約（A），讓 orchestrator 可確定性定位產出，強化 v4.1 D-001。
- 透過明確拒絕 C1–C6，把「對齊 UA」的壓力與「精簡理念」做了可追溯的取捨記錄。
- （Pattern C 待 code-enforced 後）以確定性「0 critical」前提**收緊**現有無條件 auto-merge、提升安全（注意：是收緊非減摩擦——見技術債）。

**負面影響 / 技術債（含獨立審查 5/5 accept_with_changes 的 must-fix）：**
- **[must-fix] Pattern C 目前是 dead spec**：repo 無 parser 消費 `auto_merge_gate`、`touches_sensitive_path` 無 code 實作、`ai_classification` 是 AI 自填無強制 → 「high-stakes 永不繞過」現況無執行力。升 Accepted 前須 code-enforced（production-ops §4 硬規則 + 與 C0 同款 path regex 的 sensitive-path early-return），否則降 doc-only（同 Pattern 8）。framing 亦更正：C 是收緊（增阻擋）非減摩擦。
- **[must-fix] C0 `exit 9` 在 `set -eu` 下會打掛每次正常 converge**：`[ … ] && exit 9` 作末句、`CRYPTO_SKIPPED`≠1 時回 rc=1 → `set -e` → 全腳本 exit 1。須改 `if [ … ]; then exit 9; fi`。
- **[must-fix] C0 false-negative + fail-open**：regex 漏 `encryptor`/`aes`/`rsa`/`secretbox`/`cryptobox`/`keystore` 等真 crypto（前輪只測 false-positive）；CI shallow clone 時 `git diff` 失敗被 `2>/dev/null \|\| true` 吞 → crypto **fail-open 放行**。crypto gate 須 **fail-closed**（diff 失敗即擋）+ 補 false-negative 語料；ADR 載明 C0 為 best-effort 偵測非完整保證。
- **[must-fix] crypto HITL 無 consumer 流程**：C0 `continue` 早於 worktree cleanup → 孤兒 worktree/branch；`crypto_path_touched` escalation 只 emit 無 consumer。須定義人審接手流程（導向 `asp-external-review` 三層）+ worktree/branch 生命週期。
- B 為 fail-closed，需同步更新 `task_orchestrator.md` Part G 文件化的 `ASP_AUDIT_ROOT` 調用（`git rev-parse --show-toplevel` → git-common-dir anchored），否則照舊文件操作會被 Stage D2 擋；Stage D2 須先 `cd "$ASP_AUDIT_ROOT"` 再解析相對 `.git`（見 research §9）。
- filename drift 範圍比預期大（**非單純 sed**）：`asp-ship.md`/`asp-gate.md`/`asp-level.md` 多處 `.asp-bypass-log.json`；且 `CONTEXT.md:133` 把 `.asp-telemetry.jsonl` 定為 canonical 術語、與 SPEC-004 的 `.ndjson` **衝突**（須先決定 canonical 副檔名再改 glossary）。建議獨立成 chore，不夾帶本 ADR。
- `emit_escalation` 簽名無 severity 欄位 → 文中「P0」目前無處可寫；實作 C0 時須擴充簽名或移除 P0 字樣。
- C 新增 `auto_merge_gate` 需輕量擴充 `ai-performance/schema.md`（entry 加 `gate_applied`/`critical_findings`/`warning_findings`、對齊 `ai_classification`；**非**改 `outcome_t30` 結構）+ trust-tier 補機器可讀 `critical_findings` 列舉。僅 Pattern C 實作時做。

**後續追蹤（開放問題已於 2026-06-06 經 7-agent 證據 + 對抗驗證 workflow 逐一決議）：**
- [x] B 與 A/3-C0/C **併一個 ADR-010**：四項同源自 UA 評估、同屬 worktree/converge + trust-tier 治理面，合併便於一次 review 與可追溯取捨（**非**因相依——四項低耦合、實作層各拆 commit/PR；原引用「ADR-006:67 反碎片化」方向有誤已更正：該條前提為「有依賴者不可分」，本案恰相反）
- [x] converge C0 失敗語意 = **`continue` + loop 後 `CRYPTO_SKIPPED`→`exit 9`**（非 exit 3）
- [x] env 命名 **維持 `ASP_ALLOW_WORKTREE_AUDIT_ROOT`**（符合 `ASP_<動詞>_<名詞>` override 慣例）
- [x] Q4：Pattern C **需**輕量擴充 schema.md（見技術債）
- [x] 3 份 diff 草案經對抗驗證，全 needs_fix 並已修正（見 `docs/research/ua-orchestration-adoption.md` §9）
- [x] 獨立決策審查（5-lens workflow，**5/5 accept_with_changes**）；must-fix 已併入上方技術債、framing 已更正
- [ ] **升 Accepted 前**：處理技術債中標 `[must-fix]` 的 4 項（Pattern C code-enforced 或降 doc-only / exit 9 set-eu / C0 fail-closed+召回語料 / crypto HITL consumer 流程）
- [ ] **人類審核本 ADR → 決定升 `Accepted` 或調整範圍**（鐵則：Draft 禁止實作）
- [ ] Accepted 後依 SPEC-004 addendum 實作並跑 G1–G6

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| worktree 作 audit root 被擋 | exit 7 | `ASP_AUDIT_ROOT=<worktree> bash audit-write.sh telemetry '{}'` → exit 7；main repo → pass；`ASP_ALLOW_WORKTREE_AUDIT_ROOT=1` → 放行 | 實作完成時 |
| C0 crypto task 被擋 | 不 merge + escalation `crypto_path_touched` | 合成含 crypto 路徑改動的 worktree 跑 converge | 實作完成時 |
| C0 偵測 fail-safe | false-negative 語料（aes/rsa/encryptor/secretbox/cryptobox/keystore）全命中；`git diff` 失敗時 **fail-closed**（擋而非放行） | regex 語料測試 + 模擬 base 不可達 | 實作完成時 |
| non-crypto task 不受影響 | converge 行為與改動前一致（exit 0、無新卡點） | 既有矩陣 + 1 個合成 non-crypto worktree 全綠（基準＝改動前矩陣） | 實作完成時 |
| 不重做 C1/C3/C5 | converge 不新增 scope/smuggling/secrets 檢查 | Code Review 對照 §B3-反例 | Code Review |
| Pattern C（**若** code-enforced）| 0 critical → 可 merge；**故意把 crypto/auth diff 標 trivial → 仍被 sensitive-path early-return 擋下**（負向測試） | trust-tier 測試（含負向） | Pattern C 實作時 |

> 重新評估條件：若 C0 crypto path 樣式產生過多 false positive 拖慢 autopilot，或 B 的 fail-closed 對既有正確流程造成非預期阻擋，應重新檢視。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：ADR-002（**Iron Rule B** append-only audit，本 ADR Pattern B 修補其執行缺口）；**production-ops-playbook 鐵則 6/7**（crypto / customer-facing HITL 權威來源）；ADR-007（精簡理念）；SPEC-004（worktree 隔離 + §🔒 路徑策略）；`docs/research/ua-orchestration-adoption.md`（完整對照表、diff 草案、§9 對抗驗證、5-lens 決策審查）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | （待 POC） |
| **驗證日期** | YYYY-MM-DD |
| **驗證者** | （待指派） |
| **驗證摘要** | （待驗證） |
