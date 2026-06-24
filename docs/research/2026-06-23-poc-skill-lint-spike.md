<!-- Last Updated: 2026-06-23 | Status: Draft | Audience: Maintainers -->

# POC 報告：skill 級品質 lint 可機械化驗證 + baseline（ADR-023）

本報告記錄 ADR-023（asp-skill-author meta-skill + skill 級 lint）的 POC spike 結果。探針：`docs/research/poc-skill-lint-spike.sh`（純 bash/grep，**不接 Makefile/CI/tests**，spike 慣例同 poc1/poc2）。

## 0. 結論（TL;DR）

兩個承重假設**皆通過**，且**校正了 recon A3 的悲觀估計**：

1. **lint 可便宜機械化** ✓ — 探針純 bash/grep、零重依賴、`exit 0`，能逐檔判 R1/R2/R4/R4b 並印 baseline。不需 YAML parser、不需新 orchestration 層 → 支持 ADR-010 摩擦評估「overhead 低」。
2. **baseline 合規率（嚴格 schema）= 11 PASS / 4 FAIL / 15 TOTAL** — 比 A3 預測（嚴格 ≈1 pass/14 fail）**樂觀許多**，印證 friction/fidelity 審查「A3 高估標題變異」的校正。
3. **R1/R2（name / description）= 15/15 全過** → 可直接對全體硬 gate，**不必 advisory 過渡**（採納 friction 審查建議，避免稀釋硬 gate 訊號）。
4. **R4/R4b 有 4 個真 fail** → advisory 分界對 R4/R4b 仍必要（但範圍比預期小）。

## 1. baseline 明細

| skill | R1 | R2 | R4 | R4b | 結果 | 缺漏 |
|-------|:--:|:--:|:--:|:---:|:----:|------|
| SKILL.md (router) | ✓ | ✓ | — | — | PASS | router 豁免 R4/R4b |
| asp-audit | ✓ | ✓ | ✓ | ✗ | FAIL | R4b(步驟) — **疑同義表盲點，見 §2** |
| asp-autopilot | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-context | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-dev-qa-loop | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-external-review | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-gate | ✓ | ✓ | ✗ | ✓ | FAIL | R4(下一步) — 真 fail（A3 已標 N） |
| asp-impact | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-level | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-plan | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-reality-check | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-release | ✓ | ✓ | ✗ | ✓ | FAIL | R4(適用場景) — 真 fail（A3 標「無 heading，靠 blockquote」） |
| asp-review-checklist | ✓ | ✓ | ✗ | ✓ | FAIL | R4(適用場景) — 真 fail（tactics 庫，A3 標 N） |
| asp-review | ✓ | ✓ | ✓ | ✓ | PASS | |
| asp-ship | ✓ | ✓ | ✓ | ✓ | PASS | |

`PASS=11 FAIL=4 TOTAL=15`，`exit 0`。

## 2. 誠實標註：同義標題表盲點（技術債現形）

- **asp-audit 被判 R4b(步驟) fail，疑為假陰性**：A3 盤點指 asp-audit 有「7 維度」步驟結構，但探針的 `STEP_RE` 未含「維度」一詞 → 漏抓。
- **這正是 POC 要暴露的風險**：ADR-023 摩擦評估與後果段都已記「需維護同義標題對照表，表過時 → 假陰性」為已知技術債。本 POC 用一個真實假陰性**證實該技術債存在且必須認列**，而非紙上談兵。
- **對實作的指引**：正式 lint 的同義表須補「維度」等變體；且應提供「申訴/標註豁免」機制（如 skill 內 `<!-- lint:steps=維度 -->` 註記），避免同義表無限膨脹。

## 3. 對 ADR-023 的回饋（已反映於 ADR）

| POC 發現 | 對 ADR-023 的影響 |
|---------|------------------|
| 可機械化 ✓、零依賴 | 支持摩擦評估「overhead 低、無新層」結論 |
| R1/R2 15/15 全過 | 決策 §advisory 分界已採「R1/R2 實測全過 → 直接硬 gate，不必 advisory」 |
| R4/R4b 4 fail | advisory 分界對 R4/R4b 仍必要（asp-gate/asp-release/asp-review-checklist 真缺段；asp-audit 待同義表修） |
| baseline 11/4（非 A3 的 1/14） | Draft 不寫死 A3 估計值，以本 POC 實測為準（已於 ADR baseline 措辭體現） |
| 同義表假陰性 | 「同義標題表維護」技術債已列入 ADR 後果段與成功指標重評條件 |

## 4.5 實作後修正（標題錨定，code-review Finding #1）

production lint（`tests/test_skill_lint.sh`）把 R4/R4b/STEP 一律**錨定到段落標題**（`^#+ .*<同義詞>`），修正本 spike 的寬鬆邏輯——spike 的 VERIFY/NEXT 曾匹配正文字詞（「輸出」「參考」），造成「假精確」。錨定 + 依 14 個 asp skill 的**實際標題**校準同義表後：

- **真實 R4 真缺段 = 4 檔**（非 spike 估的 3，多了 asp-plan）：
  - `asp-gate` 缺「下一步」段標題
  - `asp-plan` 缺「Verification」段標題（其驗證走 Step 5.5 auto-gate，無顯式標題）
  - `asp-release` 缺「適用場景」段標題
  - `asp-review-checklist` 缺三段（適用場景 / Verification / 下一步）
- 同義表已含「維度」→ `asp-audit` 不再假陰性（§2 盲點已修）。
- **R6 @300** 實測 3 檔：`asp-autopilot`(829) / `asp-gate`(419) / `asp-ship`(306)，待 ② 拆。
- R1/R2 既有全 skill 全過 → 直接硬 gate；R3 雙語 advisory（locale-safe 非 ASCII 偵測）；R5 延後。
- production lint 自帶自我測試（含「正文字詞不算標題」的錨定驗證），`make test` exit 0。

## 4. 未驗（留待實作/人類）

- **假設 3（git diff per-skill 偵測零成本複用）**：本 POC 未涵蓋（探針掃全目錄、未做 diff 範圍判定）。已列入 ADR-023 POC 計畫假設 3 與成功指標重評條件，待實作階段確認不會暴露成新元件。
- **R7 Battle-tested**：本就無法靜態驗，誠實標人審，不在 POC 範圍。
- **狀態升級**：本 POC 結果僅記錄事實，**不升級 ADR-023 狀態**；`Draft → FIRM/Accepted` 由人類 `/asp:approve-adr` 核准（驗證日期/驗證者欄留待人類簽）。

## 附錄：重現

```bash
bash docs/research/poc-skill-lint-spike.sh .claude/skills/asp
# 預期：印 baseline 表 + PASS=11 FAIL=4 TOTAL=15 + exit 0
```
