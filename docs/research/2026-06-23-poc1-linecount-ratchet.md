<!-- Last Updated: 2026-06-23 | Status: POC result | Audience: Maintainers -->

# POC-1：行數棘輪 gate（ADR-022）

**探索性 POC，非生產強制。** 證明 ADR-022 收窄後唯一的機械 gate——「治理產物 `profiles.total_lines` 只進不退」——可確定性、exit-code 化地實作，作為升 FIRM 的證據。**未接進 CI / commit gate**（生產強制屬 ADR Accepted 後）。

## 實作

探針 `poc1-linecount-ratchet-probe.sh`（同目錄）：
- **複用既有真實 metric**：current 值取自 `asp-metrics.sh` 的 `profiles.total_lines`，不重實作行數計算（避免 metric 漂移）。
- baseline 取自 `.asp-metrics-baseline.json` 的 `profiles.total_lines`。
- 邏輯：`current > baseline 且無豁免 → exit 1`；否則 `exit 0`。
- 豁免：`ASP_COMPLEXITY_BUDGET_OK=1`（ADR 認列逃生門的 POC 代理）。`--current N` 覆寫供 demo violation（不必真灌肥檔案）。

## 跑通結果（三情境，可重現）

| 情境 | 輸入 | 結果 | exit |
|------|------|------|------|
| 1 真實狀態 | current=3626, baseline=5177 | ✅ PASS | **0** |
| 2 合成 violation | current=5200 > 5177 | ❌ VIOLATION（gate red）| **1** |
| 3 violation + 豁免 | current=5200, `ASP_COMPLEXITY_BUDGET_OK=1` | ⚠️ 放行（須附認列 ADR）| **0** |

確定性、無 LLM、無非確定性——與 POC-2（可推導性無法機械化）成對比：**行數軸是棘輪唯一能全自動的一條腿**，POC-1 證實它成立。

## 結論

**POC-1 通過。** ADR-022 收窄後的機械 gate（行數棘輪）可行性已驗證。生產化僅剩「把這段邏輯接成 CI step / Makefile target」的工程，無技術未知。

## 附帶 finding（tuning，非 POC 範圍）

實測 current `profiles.total_lines` = **3626**（12 檔，v5 已移除 vibe_coding/spike_mode 等），但 baseline 凍結在 **5177**（16 檔的舊快照）。**棘輪現在鬆了 1551 行**——要咬得緊，生產化時應把 baseline re-freeze 到當前 3626（或 v5 後的正確值）。這是 baseline 維護決策，建議在 ADR-022 生產化（Accepted 後）時一併處理，不影響 POC-1 可行性結論。
