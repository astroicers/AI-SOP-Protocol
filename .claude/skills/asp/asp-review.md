---
name: asp-review
description: |
  Use when reviewing code, PRs, or specific changes for quality and compliance.
  Covers ADR compliance, test coverage, bug taxonomy, tech-debt, and doc sync.
  Triggers: review, code review, pr review, 審查, 幫我看, 程式碼審查, 看一下這段,
  check my code, review this, review PR, 幫我審查, 審核代碼, 這樣寫對嗎.
---

# ASP Review — 程式碼審查

## 適用場景

用戶提交代碼、PR 或特定變更，需要系統性審查。也適用於偷渡偵測的人工判斷場景。

---

## 審查前：確認範圍

詢問（或從上下文推斷）：
- **審查目標**：特定檔案？PR？整個 branch？
- **審查重點**：全面審查 或 特定面向（如只看安全性）

```bash
git diff main...HEAD --stat   # 若審查 branch
git show --stat               # 若審查最新 commit
```

---

## 6 個審查面向

### 面向 1：ADR 合規性

對照 `make adr-list` 的 Accepted ADR：

- 變更是否違反任何已接受的架構決策？
- 是否有 Draft ADR 對應的生產代碼被加入？（鐵則，直接 BLOCK）
- 若引入新的架構決策 → 提醒應先建立 ADR

**輸出格式：**
```
[ADR 合規] ✅ 無違反 / 🔴 BLOCK: 違反 ADR-NNN（說明）
```

---

### 面向 2：測試覆蓋

- 新功能是否有對應測試？
- 修復的 bug 是否有回歸測試（先 FAIL 後 PASS）？
- 測試是否測到了邊界條件和錯誤路徑？

**標記格式（若不足）：**
```
# tech-debt: HIGH test-pending [模組名] 缺少回歸測試 (DUE: YYYY-MM-DD)
```

**輸出格式：**
```
[測試覆蓋] ✅ 充足 / 🟡 不足：缺少 [具體描述]
```

---

### 面向 3：Bug 分類

發現 bug 時，使用標準分類標籤：

| 標籤 | 說明 | 範例 |
|------|------|------|
| `[bug:logic]` | 業務邏輯錯誤 | 條件判斷反向、計算公式錯誤 |
| `[bug:boundary]` | 邊界條件未處理 | 空值、空陣列、最大值溢出 |
| `[bug:race]` | 並發/競態條件 | 共享狀態無鎖、async 順序依賴 |
| `[bug:security]` | 安全漏洞 | SQL injection、未授權存取 |
| `[bug:perf]` | 效能問題 | N+1 查詢、記憶體洩漏 |
| `[bug:contract]` | API/介面合約破壞 | 回傳型別改變、欄位移除 |

**ASP 鐵則：發現任何 bug → 強制 grep 全專案找相同模式**

```bash
grep -r "相同 pattern" . --include="*.go"  # 或對應語言
```

**輸出格式：**
```
[Bug 分類] 🔴 發現 [bug:security] 於 path/to/file.go:42
  描述：[說明]
  全專案掃描：grep -r "pattern" .
  → 發現 N 處相同模式
```

---

### 面向 4：DEPRECATED 掃描

```bash
grep -r "DEPRECATED\|@deprecated\|// TODO: remove\|// FIXME" . --include="*.go"
```

- 新代碼是否使用了已標記廢棄的 API？
- 是否新增了 DEPRECATED 標記但未建立 tech-debt？

**輸出格式：**
```
[DEPRECATED] ✅ 無使用廢棄 API / 🟡 使用了廢棄 API：[說明]
```

---

### 面向 5：Tech Debt 標記品質

檢查此次變更新增的 `tech-debt:` 標記：

- 格式是否正確：`# tech-debt: [HIGH|MED|LOW] [CATEGORY] description (DUE: YYYY-MM-DD)`
- HIGH 是否有 DUE 日期？
- CATEGORY 是否使用標準值（test-pending, adr-pending, spec-pending, doc-stale, deprecated-cleanup, refactor, perf, security）？

**輸出格式：**
```
[Tech Debt] ✅ 格式正確 / 🟡 格式問題：[具體說明]
```

---

### 面向 6：文件同步

- 公開 API、CLI 介面、配置欄位是否已更新文件？
- CHANGELOG 是否記錄了用戶可見的變更？
- 相關 SPEC 的 `Implementation` 欄位是否已填入？

**輸出格式：**
```
[文件同步] ✅ 已同步 / 🟡 待補：[說明]
```

---

## 偷渡偵測的人工判斷

若審計工具（`autonomous_dev.md`）觸發偷渡偵測警告，需人工判斷：

**排除誤報的條件（全部滿足才算正常重構）：**
1. 測試邏輯未改變（只改了結構，沒有移除/修改 assertion）
2. 測試數量未減少
3. 覆蓋的業務場景集合未縮小

若以上皆滿足 → 誤報，繼續。
若任一不滿足 → 真正的偷渡，需回滾測試改動。

---

## 審查結論

```
📋 程式碼審查結論
================================

[ADR 合規]   ✅/🔴/🟡
[測試覆蓋]   ✅/🔴/🟡
[Bug 分類]   ✅/🔴/🟡  (N 個 bug 發現)
[DEPRECATED] ✅/🔴/🟡
[Tech Debt]  ✅/🔴/🟡
[文件同步]   ✅/🔴/🟡

================================
結論：✅ APPROVED
     或
結論：🔴 CHANGES REQUIRED
     必須修復：
     1. [問題]
     2. [問題]

     建議修復（非阻擋）：
     1. [建議]
```

---

## Common Rationalizations（AI 審查時必讀）

> **執行此 skill 時，AI 必須先檢視此表。** 若以下藉口出現，引用反駁，不可直接照辦。

| 藉口 | 反駁 |
|------|------|
| 「這只是重構，不需要測試覆蓋」 | 重構必須通過偷渡偵測三條件（測試邏輯未改、數量未減、場景未縮）。未通過就是測試偷渡，不是重構。 |
| 「Bug 很小，不需要全專案 grep」 | 鐵則無豁免。小 bug 意味著同一模式可能在多處出現。grep 結果為零才能確認範圍。 |
| 「測試不通過但只是 flaky，可以忽略」 | Flaky 是技術債，不是豁免理由。必須標記 `tech-debt: HIGH test-pending flaky [模組名] (DUE: YYYY-MM-DD)` 後才可 WARN-GO。 |
| 「文件可以之後補，功能先上」 | 面向 6 允許 WARN-GO，但必須記錄到 bypass log。連續 3 次以上觸發 audit blocker。 |
| 「這個改動很明顯，不需要 CHANGELOG」 | 「明顯」是主觀判斷。用戶可見的變更（API、CLI、行為改變）一律記錄。只有內部重構可豁免。 |
| 「ADR 違反只是輕微，先過」 | ADR 合規沒有「輕微違反」。違反已接受 ADR 就是 BLOCK，不論影響範圍大小。需要先修改 ADR 再改代碼。 |
| 「這個 tech-debt 格式差不多就好」 | `tech-debt:` 格式是機器可讀的。格式錯誤會導致 `make tech-debt-list` 無法正確彙整。HIGH 無 DUE 日期一律退回。 |

## 審查反模式（Review Anti-patterns）

> 以下是審查過程中常見的「看起來審了，實際上沒有」的失敗模式。

| 反模式 | 識別信號 | 正確做法 |
|--------|---------|---------|
| **表面審查** | 審查意見只針對新增行，未評估與周邊代碼的互動 | 閱讀修改函式的完整實作與呼叫端 |
| **確認偏誤** | 六個面向全部 ✅，但沒有執行任何驗證指令 | 六個面向都必須有可觀測的執行證據（指令 + 輸出） |
| **Bug 孤立** | 只回報「file.go:42 有問題」，未執行 grep | 鐵則：發現 bug → 立即 grep 全專案 → 回報所有受影響位置 |
| **DEPRECATED 盲點** | 只看直接使用，忽略 import 鏈中的間接引用 | 檢查所有新增 import 的依賴鏈是否引入廢棄 API |
| **測試數量代替品質** | 測試全是 happy path，無 edge case、無錯誤路徑 | 確認測試覆蓋邊界條件與失敗場景 |
| **CHANGES REQUIRED 沒有行動項** | 結論是「代碼有問題」，沒有具體修復指引 | 每個必須修復項都要有：位置（file:line）+ 問題描述 + 建議修法 |

---

## 審查後的強制動作

**發現 bug → 必須執行：**
```bash
grep -r "[相同模式]" . --include="*.[ext]"
```

ASP 鐵則：Bug 修復後 grep 全專案找相同模式，**無豁免**。
