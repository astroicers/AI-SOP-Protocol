<!-- Last Updated: 2026-06-25 | Status: Draft | Audience: Maintainers -->

# POC 報告：mega-skill 拆分破壞半徑（ADR-024 / 借鏡點 ②）

探針：`docs/research/poc-megaskill-split-risk.sh`（純 bash/grep，**不接 Makefile/CI/tests**，spike 慣例同 poc1/poc2/poc-skill-lint）。

## 0. 結論（TL;DR）

量測「big-bang 拆 `asp-autopilot`/`asp-gate`/`asp-ship`」的硬編引用破壞半徑，作為 ADR-024 選項取捨的證據：

```
BLAST_RADIUS: hooks=2  tests=12  skills=6  router_lines=17   （~37 處）
```

→ **全拆（選項 A）高破壞，明確排除**；採 ADR-024 選項 D（**生命週期分階索引純加 + lint-gated 漸進拆**）。

## 1. 破壞半徑明細

| 類別 | 數量 | 代表 | 拆名/段落的後果 |
|------|------|------|----------------|
| **hooks** | 2 | `session-audit.sh`、`pretooluse-ship-gate.sh` | L1/L1.5 強制力硬編 mega-skill 名/段落 → 拆即**失效**（最嚴重） |
| **tests** | 12 | `test_ship_step96`、`test_auto_gate_*`、`test_autopilot_*`、`test_separation`… | 釘住名稱/段落 → 拆 → **測試紅**（make test 破） |
| **skills** | 6 | `asp-plan`、`asp-external-review`、`asp-level`、`asp-context`、`asp-skill-author`、SKILL.md | 跨 skill 互引 → 拆 → 交叉引用漂移 |
| **router** | 17 | SKILL.md 內引用列（含 ADR-024 分階索引新增 3 列） | 路由列需同步改 |

> **數字註記**：首次量測（ADR-024 決策當下）`router_lines=14`；選項 D 的分階索引上線後自身新增 3 列 mega-skill 引用 → **17**（總 ~34→~37）。重現本探針得 17；結論不變（遠超 big-bang 閾值）。

## 2. 對 ADR-024 的回饋

- **選項 A（big-bang 全拆）**：~37 處 churn、hook 硬編一拆即失強制力 → **排除**（撞 ADR-010「不為抄形式而動既有層」、撞鐵則「改 hook 強制力」）。
- **選項 D（採用）**：分階索引是 SKILL.md **純加**（零破壞、不動 mega-skill 與引用）；拆分改為 ① lint R6 advisory 信號下的**機會式漸進**（每次小、過 lint 門檻）。
- **選項 B（references 漸進揭示）**：Claude Code「skill + references/ 按需載入」機制未驗 → **另案 spike**，本 ADR 不納入。

## 3. 未驗（留待）

- 選項 B 的 references 載入機制（另案 spike）。
- 漸進拆的逐案安全性（每次拆時由 ① lint + 人審把關，非本 POC 範圍）。
- 本 POC 僅量測**事實上的引用數**，不對「拆得對不對」做語意判斷（仍需人審）。

## 附錄：重現

```bash
bash docs/research/poc-megaskill-split-risk.sh .
# 預期：印各類別清單 + BLAST_RADIUS: hooks=2 tests=12 skills=6 router_lines=17 + exit 0
```
