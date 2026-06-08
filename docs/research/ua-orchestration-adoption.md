<!-- Last Updated: 2026-06-06 | Status: Draft | Audience: Maintainers -->
# UA ↔ ASP v4.0 Orchestration 對照與採納提案

> 配套決策：[ADR-010](../adr/ADR-010-adopt-ua-orchestration-patterns-minimal.md)（`Draft`）。本報告為評估交付物：完整對照表、自動化摩擦評估、採納清單、diff 草案、開放問題。
> **狀態 `Draft`：所有 diff 草案待人類核准 ADR-010 升 `Accepted` 後方可實作。本報告不含已落地的 production code。**

---

## 0. 摘要

`Lum1104/Understand-Anything`（UA）與 ASP 是同物種（CLAUDE.md 驅動的 multi-agent orchestration）。本報告精讀 UA 原始碼，逐項對照 ASP v4.0 的 locked decisions，**有選擇地**提出採納。核心結論：

- 真正值得做的只有 4 項，且整體 **淨減摩擦 / 修漏洞，不增治理層數**：
  1. **Pattern B**（worktree audit guard）— 修一個已驗證 latent bug（落實 SPEC-004 §🔒 既有規範）
  2. **Pattern A**（handoff naming）— refine v4.1 scratchpad，log-only 不新增卡點
  3. **Pattern 3 精簡（僅 C0）**— converge 補 crypto 偵測 → HITL（analyze-only）
  4. **Pattern C**（trivial-tier binary auto-merge gate）— 減人工 review，限 trivial
- **明確拒絕 Pattern 3 完整版 C1–C6**：與 `scope-guard.sh` / `auto_fix_loop` / `asp-ship` Step 9 重疊，且在 converge 增多個 fail-closed 卡點 → 過度工程（ADR-002 選項 C 的教訓）。
- Pattern 5/1 ASP 已對齊；Pattern 6 延後；Pattern 8 僅文件化。

---

## 1. UA 七個模式（具體機制摘要，以原始碼為準）

| # | 模式 | 具體機制（檔案 / 識別符） |
|---|---|---|
| 1 | 兩階段 deterministic→LLM | `extract-structure.mjs`（web-tree-sitter WASM）做確定性抽取 → `file-analyzer` agent 只在結構化結果上做 summary/tag/edge。腳本輸出視為「結構真相」，LLM 只做語意層。 |
| 2 | disk handoff + 一行 summary | 中間產物寫 `.understand-anything/intermediate/`，**強制檔名 regex** `batch-(\d+)(?:-part-(\d+))?\.json`——不符者被 merge 腳本**靜默丟棄**。subagent 寫 JSON 到 disk，只回傳一行 summary（不傳 context）。 |
| 3 | deterministic merge safety-net | `merge-batch-graphs.py`：normalize node id（剝雙重 prefix、`func:`→`function:`）、complexity 正規化、edge 重寫、node dedupe（keep-last）、tested-by linker、edge dedupe（key 含 direction）、drop dangling。假設 LLM 會犯結構錯，用確定性 pass 修。 |
| 4 | review gate（critical/warning binary） | `graph-reviewer`：先寫並執行確定性 validation 腳本（`ua-inline-validate.cjs`），issues 分 critical（擋）/ warning（放），輸出 binary `approved`。「NEVER approve a graph that has critical issues」。 |
| 5 | stakes-tiered review | 預設跑 inline 確定性 validator（毫秒、無 LLM 成本）；加 `--review` flag 才動用完整 LLM `graph-reviewer`。 |
| 6 | git-diff 增量 | `git diff <lastCommitHash>..HEAD --name-only` → `compute-batches.mjs --changed-files` 只重算改動批次 → prune 舊 nodes/edges → re-merge。`meta.json` 記 `lastCommitHash`；偵測 detached/rebase 進行中則中止增量。 |
| 7 | worktree redirect（#133）+ model 欄位（#167） | 比較 `git rev-parse --git-common-dir` vs `--git-dir`（絕對路徑）；不同 → worktree → 把持久輸出 redirect 回 main repo root；env `UNDERSTAND_NO_WORKTREE_REDIRECT=1` 覆寫。agent frontmatter **刻意省略 `model` 欄位**，因 `inherit` 為 Claude-Code-only，opencode 會報 `ProviderModelNotFoundError`。 |

---

## 2. 自動化摩擦評估（反 over-engineering 自檢）

**ASP 理念**：CLAUDE.md 92 行（刻意精簡）、L0–L5 分級、Design Principle 13「獨立性是光譜，依 stakes 選擇」、鐵則僅 4 條、`auto_fix_loop` 「max 3 次即 pause」。核心＝**分級、精簡、按風險、不過度**。

| Pattern | 性質 | 對自動化摩擦的淨影響 | 維護負擔 | 與既有機制重疊 |
|---|---|---|---|---|
| **B** worktree guard | bug fix（fail-closed） | 中性偏正（修靜默失敗，正常流程不觸發） | 極低 | 無 |
| **A** handoff naming | 約定 + log-only validator | 正面（orchestrator 可自動定位產出） | 低 | 補強 v4.1 |
| **3 完整版 C0–C6** | 新增一整層確定性閘門 | **負面**（converge 多 fail-closed 卡點 → autopilot 易卡） | **高** | **高**（C1↔scope-guard、C3↔auto_fix_loop、C5↔asp-ship Step 9） |
| **3 精簡版 只 C0** | 補一個鐵則漏洞 | 中性（只在 crypto 觸發 HITL，本就該 HITL） | 低 | 無（converge 目前無 crypto 偵測） |
| **C** binary gate | 放寬 trivial auto-merge | 正面（減人工 review trivial） | 低 | 對齊 trust-tier |

**結論**：使用者「會不會設計太多導致不方便」的擔憂正確，但只命中 **Pattern 3 完整版**。ASP 的 code branch 進 converge 前已過 worker 內 `auto_fix_loop` + test-pass + `scope-guard`(PreToolUse) + `asp-ship` Step 9 多層把關；再疊 C0–C6 只帶來重複維護與更多卡點。

> **關鍵洞察**：UA 需要 `merge-batch-graphs.py`，是因為它合併「N 個 LLM 各自吐的 graph JSON」（結構錯誤頻繁且廉價可修）。ASP 合併的是「已過多層把關的 code branch」，再加一層的邊際價值遠低於 UA 場景。這正是評估 briefing 第 6 節警告的 over-borrow。

---

## 3. UA ↔ ASP v4.0 逐項對照表（已填滿）

| # | UA 模式 | ASP 對應 locked decision | 判定 | 落地方式 / hard-constraint 相容性 |
|---|---|---|---|---|
| 1 | 兩階段 deterministic→LLM | crypto 硬邊界；ASP 已有片段（`auto_fix_loop`、`validate-profile.sh`） | **UA 更成熟** | 理念已由既有層體現。**不新增通用兩階段層**（避免過度）；僅 crypto 由確定性偵測 → HITL（= Pattern 3 精簡 C0）。crypto **LLM 永不改 bytes**。 |
| 2 | disk handoff + 一行 summary | v4.1 D-001：`/clear` + scratchpad（路徑 + hash） | **一致（UA naming 更嚴）** | **Pattern A**：formalize `.asp-out/` 契約 + 檔名 + 一行回傳。validator **只 log 不擋**。欄位對應現有 `TASK_COMPLETE.yaml`（diff/test_output/test_checksums）。不碰 review gate / HITL。 |
| 3 | deterministic merge safety-net | ASP 無對應（gap），但 converge 前已多層把關 | **新點子（需節制）** | **降規**：只補 **C0 crypto→HITL**（converge 目前無）。C1（scope）/C3（smuggling）/C5（secrets）已被既有層覆蓋，**不重做**。 |
| 4 | review gate critical/warning binary | Design Principle 13；`trust-tier.yaml` | **一致 / ASP 更嚴格** | **Pattern C**：`zero_critical_findings` 作 **trivial-tier ONLY** auto-merge 前提。**嚴禁取代** high-stakes 的 cross-vendor 4/4 + human；`touches_sensitive_path` early-return + `iron_rules` 雙重把關。 |
| 5 | stakes-tiered（inline vs `--review`） | L0–L5 + Design Principle 13 + production-ops pair modes | **一致（ASP 更完整）** | 無需新增；ASP 的 Routine/Complex/High-Stakes pair mode 已超越 UA 兩層。僅借用其表述法寫進文件。 |
| 6 | git-diff 增量 | standard bug fix / production monitoring | **UA 更成熟** | **Defer**：後續對該二子系統用 `git diff <hash>..HEAD` 限縮 scope。中槓桿中成本。 |
| 7 | worktree redirect（#133） | ASP 用 worktree 隔離（SPEC-004 §🔒 已規範寫主 repo） | **UA 更成熟 / ASP 有確認 bug** | **Pattern B**：`_validate_audit_root.sh` 加 Stage D2 guard。**落實既有 SPEC 規範**，純正確性修復，強化（非弱化）審計完整性。 |
| 8 | agent `model` 欄位省略（#167） | ASP 跨 Anthropic + OpenAI（cross-vendor review） | **相關** | **Doc-only**：cross-vendor agent 設定避免 literal model id / `inherit`，注意 portability。寫入 `asp-external-review.md` 或 agent 定義規範。 |

---

## 4. 採納清單（依 槓桿 / 成本 / 風險 / 摩擦淨影響）

| 排序 | 項目 | 槓桿 | 成本 | 風險 | 摩擦淨影響 | 動作 |
|---|---|---|---|---|---|---|
| **①** | Pattern B worktree guard | High | Low | Med（fail-closed；env 覆寫緩解） | 中性偏正 | 做（確認 bug） |
| **②** | Pattern A handoff naming | Med | Low | Low | 正面 | 做（log-only） |
| **③** | Pattern 3（精簡 C0）crypto gate | Med-High | Low | Low | 中性 | 做（只 C0） |
| **④** | Pattern C binary auto-merge gate | Med | Low | Med | 正面 | 做（trivial only） |
| ⑤ | Pattern 6 git-diff 增量 | Med | Med | Low | — | Defer |
| ⑥ | Pattern 8 model portability | Low | Low | Low | — | Doc-only |
| ✗ | Pattern 3 完整版 C1–C6 | Low（重疊） | High | Med | **負面** | **不做** |

> 建議先做 2–3 項：**B + A + 3(C0)**。B/A 便宜快速；3(C0) 補 converge 鐵則漏洞。C 次之。

---

## 5. 具體 diff 草案（DRAFT — 待 ADR Accepted）

### 5.1 Pattern B：`_validate_audit_root.sh` Stage D2（worktree guard）
於 [`_validate_audit_root.sh`](../../.asp/scripts/multi-agent/_validate_audit_root.sh) line 52（`return 0` 前）插入：

```bash
# DRAFT — Stage D2: 拒絕以 git worktree 作 ASP_AUDIT_ROOT（落實 SPEC-004 §🔒；UA Pattern 7 / #133）
# 持久 audit artifacts 必須落 MAIN repo，不可落 converge/session 結束即被
# `git worktree remove --force` 銷毀的 ephemeral worktree（保護 Iron Rule B）。
# ⚠️ 對抗驗證修正：git --git-dir 對 main repo 回傳相對 ".git"，cd 會錨定到 caller CWD
#    而非 ASP_AUDIT_ROOT（原草案「對的結果、錯的理由」latent bug）→ 必須先 cd 進 ASP_AUDIT_ROOT；
#    且 git 失敗時 cd "" 會退化成 $PWD，故先把原始輸出存變數檢查非空。相容 git < 2.31。
if [ "${ASP_ALLOW_WORKTREE_AUDIT_ROOT:-}" != "1" ]; then
    _raw_gd=$(git -C "$ASP_AUDIT_ROOT" rev-parse --git-dir 2>/dev/null) || _raw_gd=""
    _raw_gc=$(git -C "$ASP_AUDIT_ROOT" rev-parse --git-common-dir 2>/dev/null) || _raw_gc=""
    if [ -n "$_raw_gd" ] && [ -n "$_raw_gc" ]; then
        _gd=$(cd "$ASP_AUDIT_ROOT" 2>/dev/null && cd "$_raw_gd" 2>/dev/null && pwd -P) || _gd=""
        _gc=$(cd "$ASP_AUDIT_ROOT" 2>/dev/null && cd "$_raw_gc" 2>/dev/null && pwd -P) || _gc=""
        if [ -n "$_gd" ] && [ -n "$_gc" ] && [ "$_gd" != "$_gc" ]; then
            echo "ASP_AUDIT_ROOT is a git worktree ($_gd != $_gc); audit artifacts must" >&2
            echo "  write to the MAIN repo. Use the common root, e.g.:" >&2
            echo "    ASP_AUDIT_ROOT=\"\$(cd \"\$(git rev-parse --git-common-dir)/..\" && pwd -P)\"" >&2
            echo "  Override (not recommended): ASP_ALLOW_WORKTREE_AUDIT_ROOT=1" >&2
            return $ASP_AUDIT_ROOT_FAIL_EXIT
        fi
    fi
fi
```

**配套**：`task_orchestrator.md` Part G 文件化的調用改為 main-repo-anchored：
```bash
ASP_AUDIT_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"
```
**順手修 filename drift**：`audit-write.sh` 寫 `.asp-bypass-log.ndjson`，`asp-ship.md` 仍引用 `.asp-bypass-log.json` → 統一為 `.ndjson`。

### 5.2 Pattern 3 精簡：`converge.sh` Step 0（僅 C0 crypto gate）
於 [`converge.sh`](../../.asp/scripts/multi-agent/converge.sh) **行 147 worktree 存在檢查的 `fi` 之後、行 149 `REBASE_STDERR=$(mktemp)` 之前**插入（⚠️ 對抗驗證修正：須在 mktemp 之前，否則 `continue` 會跳過迴圈內的 `rm` 而洩漏暫存檔）：

```bash
# DRAFT — Step 0: crypto gate（analyze-only；其餘 scope/secrets/smuggling 交既有層）
# ⚠️ regex 經對抗驗證修正：原 'cipher' 無字界誤中 decipher_log.go、'/kms' 誤中 kmstore.go。
#    改為 crypto/kms/encryption 目錄加錨點、encrypt/decrypt/kms 加分隔字界、cipher 排除 decipher、補齊憑證副檔名。
CRYPTO=$(git -C "$ASP_AUDIT_ROOT" diff --name-only "$BASE_BRANCH..$TASK_BRANCH" 2>/dev/null \
         | grep -Ei '(^|/)(crypto|kms|encryption)/|(_|-|\.|/|^)(encrypt|decrypt|kms)(_|-|\.|/|s|$)|(^|[^e])cipher|\.(key|pem|p12|pfx|crt|jks|keystore|gpg|asc)$' \
         || true)
if [ -n "$CRYPTO" ]; then
    emit_escalation "$tid" "crypto_path_touched" "$CRYPTO"   # P0 → 強制 HITL（參數序對照 converge.sh:77）
    emit_telemetry "multi_agent.fail" "$tid" "crypto_hitl"   # extra_kv 省略=OK（對照 converge.sh:68）
    CRYPTO_SKIPPED=1                                          # 標記：loop 後據此回非零 exit（見下）
    continue                                                 # 不 merge，永不 auto-repair bytes（迴圈內 129-204）
fi
```
> **不**實作 C1（已有 `scope-guard.sh` PreToolUse）、C3（已有 `auto_fix_loop`）、C5（已有 `asp-ship` Step 9）。避免重複層 = 避免 over-engineering。
> **失敗語意已決：`continue`**（per-task 跳過、其他續跑，符合 partial-success）。⚠️ 對抗驗證盲點：其他 task 全成功時 loop 會 fall-through `exit 0`，**遮蔽 P0 escalation**。故在 for 迴圈結束後加：`[ "${CRYPTO_SKIPPED:-}" = "1" ] && exit 9`（dedicated `crypto_hitl_pending`，**不**沿用 conflict 的 exit 3）。

### 5.3 Pattern A：worker 輸出契約（`.asp-out/`）
canonical 目錄（與既有 `.asp-worktrees/<task>/` 並列）：
```
.asp-worktrees/<task-id>/.asp-out/
  summary.txt      # 一行 summary（agent 回傳唯一內容）
  diff.txt         # → TASK_COMPLETE.artifacts.diff_summary
  test-output.txt  # → TASK_COMPLETE.artifacts.test_output
  checksums.json   # → TASK_COMPLETE.artifacts.test_checksums（smuggling 偵測）
  handoff.yaml     # TASK_COMPLETE.yaml 實例
```
強制檔名 regex（ASP 風格：log 不擋，經 `audit-write.sh` telemetry）：
```
^(summary|diff|test-output|checksums|handoff)\.(txt|json|yaml)$
```
worker 對 orchestrator 只回一行：`TASK-NNN <status> | out=<path> | files=<n> | tests=<summary>`。文件落點：`task_orchestrator.md` Part G「Worker 輸出契約」+ `TASK_COMPLETE.yaml` 標頭註解。

### 5.4 Pattern C：`trust-tier.yaml` binary gate（trivial only）
```yaml
# DRAFT — documentation-only（目前無 parser 消費；待實作 SPEC 才接線）
# 僅作用於 auto-merge 的 trivial tier；high-stakes 永遠不適用
auto_merge_gate:
  applies_to: [TIER_3_FULL_AUTO, TIER_2_STANDARD]   # 對應 trust-tier.yaml:8 / :15
  classification_required: "trivial"                # 須與 schema.md ai_classification enum 對齊
  precondition_zero_critical: true                  # 0 critical → 可 merge；≥1 → 擋
  warnings_non_blocking: true                       # warning 記 log 不擋
  # ⚠️ 對抗驗證修正：用結構欄位顯式引用既有頂層 iron_rules key（trust-tier.yaml:38-39），不只註解承諾
  respects_iron_rules: [crypto_always_hitl, customer_facing_always_hitl]

# ⚠️ 對抗驗證（high）：critical 集合原散落 scope-guard.sh / asp-ship Step 9，無機器可讀列舉
#    → precondition 無從 evaluate。補單一 source of truth：
critical_findings:
  - test_failure        # asp-ship / test gate
  - lint_error          # quality-thresholds
  - secret_leak         # asp-ship Step 9
  - scope_violation     # scope-guard.sh (PreToolUse)
  - smuggling_mismatch  # checksums.json 比對
  - iron_rule_touch     # crypto / customer-facing 路徑命中
```
CRITICAL = 上列 `critical_findings`（machine-readable）；WARNING = ASP 既有非阻擋集合（lint warning / 無主 TODO / doc-stale）。

---

## 6. Hard-constraint 相容性總結

| Hard constraint | 本批採納如何尊重 |
|---|---|
| crypto 永遠 HITL，AI 不碰 bytes | C0 只偵測路徑 → 寫 P0 escalation → `continue`（不 merge），**無 `git apply`/rewrite/amend**；不採納任何 crypto auto-repair。 |
| customer-facing 永遠人審 | 本批不觸及 customer-facing 路徑；Pattern C 明確排除 sensitive path。 |
| high-stakes = cross-vendor 4/4 + human | Pattern C binary gate **僅 trivial tier**；`touches_sensitive_path` early-return + `iron_rules` 雙重把關，永不取代 cross-vendor + human。 |
| 不違反精簡/分級理念 | 明確拒絕 Pattern 3 C1–C6；整體不增治理層數淨值。 |
| ADR 未定案禁止實作 | 本報告 + ADR-010 維持 `Draft`，所有 diff 為草案，待人類核准。 |

---

## 7. 開放問題 — 已逐一決議（2026-06-06，經 7-agent 證據 workflow）

**已定案**：Pattern 3 = 只補 C0 crypto gate；Pattern B = 走 Draft ADR gated。

| # | 問題 | 決議 | 依據 |
|---|---|---|---|
| 1 | 單一 ADR vs 拆分 | **併一個 ADR-010**（實作層仍各拆 commit/PR） | ADR-002/006/007 先例 + ADR-006:67 反碎片化原則 |
| 2 | converge C0 失敗語意 | **`continue`** + loop 後 `CRYPTO_SKIPPED` 旗標 → **dedicated `exit 9`**（不沿用 conflict exit 3，避免 fall-through exit 0 遮蔽 P0） | converge.sh:23/129-204/204；SPEC-004 §S8 |
| 3 | env 命名 | **維持 `ASP_ALLOW_WORKTREE_AUDIT_ROOT`** | 符合 `ASP_<動詞>_<名詞>` override 慣例（ASP_SKIP_PRECHECK/DRY_RUN/AUTO_YES） |
| 4 | Pattern C 是否動 schema.md | **YES，輕量擴充**：entry 加 `gate_applied`/`critical_findings`/`warning_findings` + 對齊 `ai_classification`；**非**改 outcome_t30 結構；只在 Pattern C 實作時做 | schema.md:7-18,15,20；trust-tier.yaml:7-21 |
| 5 | `.asp-out/` 是否未來由 converge 消費 | 暫定**僅約定 + log**；未來如需自動收集再接線 | （非阻擋） |

**仍須人類拍板**：ADR-010 是否升 `Accepted`（鐵則：Draft 禁止實作）。

---

## 8. 驗證方式（實作後）

- **Pattern B**：`shellcheck`；regression — `git worktree add /tmp/wt` → `ASP_AUDIT_ROOT=/tmp/wt bash audit-write.sh telemetry '{...}'` 應 **exit 7**；main repo 應 pass；加 `ASP_ALLOW_WORKTREE_AUDIT_ROOT=1` 應放行。
- **Pattern 3 (C0)**：合成 worktree 含 crypto 路徑改動 → converge 跳過該 task、寫 P0 escalation、其他 task 仍 merge；非 crypto task 不受影響（確認**未增日常摩擦**）。
- **Pattern C**：trivial fix 0 critical → 自動 merge；有 critical / 觸 sensitive path → 擋並要求 cross-vendor + human。
- **治理**：`/asp-gate G1,G2`；ADR 維持 `Draft` 直到人類核准。

---

## 9. 對抗驗證摘要（2026-06-06，7-agent workflow）

4 份 diff 草案經獨立對抗驗證（預設懷疑、嘗試反駁），**全部 needs_fix 並已套用修正**（見 §5）：

| 草案 | 驗證發現（已修正） |
|---|---|
| Stage D2 (B) | `git --git-dir` 對 main repo 回傳相對 `.git`，`cd` 錨定到 caller CWD 而非 ASP_AUDIT_ROOT（「對的結果、錯的理由」latent bug）；`cd ""` 失敗時退化為 `$PWD`。→ 先 `cd "$ASP_AUDIT_ROOT"` 並先檢查原始輸出非空。submodule **不**誤判（已實測 git 2.34.1）。 |
| converge C0 (3) | regex `cipher` 誤中 `decipher_log.go`、`/kms` 誤中 `kmstore.go`（但原擔心的 `keyboard`/`monkey`/`turnkey` 因 `\.key$` 副檔名錨定**不會**誤中）；插入點須在 `mktemp` 前否則 `continue` 洩漏暫存檔；`continue` 後 loop fall-through `exit 0` 遮蔽 P0。→ 精準 regex + 插入點前移 + `CRYPTO_SKIPPED`→`exit 9`。變數與 `emit_*` 簽名皆驗證正確。 |
| trust-tier (C) | `zero_critical_findings` 的 critical 集合從未機器可讀列舉（**high**，懸空符號）；只在註解承諾尊重 iron_rules、無結構引用；新造欄位無 parser 消費。→ 補 `critical_findings` 列舉 + `respects_iron_rules` 結構欄位 + 標 documentation-only。 |
| Pattern A | 未送驗證（純約定 + log，風險低）。 |

> 此驗證確保草案落地時不引入新 bug，且不增日常摩擦：crypto gate 對非 crypto task 零影響、修正後 regex 對 `keyboard`/`monkey`/`key_value`/`turnkey` 等零 false-positive。
