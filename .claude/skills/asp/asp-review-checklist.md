---
name: asp-review-checklist
description: |
  6-dimension review checklist, bug taxonomy, anti-pattern catalog, and structured finding format.
  Used by asp-review as the tactics library. Load directly when you need checklist details.
  Triggers: review checklist, 審查清單, review dimensions, finding format, 面向定義.
---

# ASP Review Checklist — 審查工具庫

> **流程控制**：由 `asp-review` 載入並調用。本檔案定義「查什麼」與「怎麼輸出」。

---

## 結構化 Finding 格式

每個發現使用以下標準格式輸出（機器可讀）：

```
finding:
  id:          review-NNN
  dimension:   adr|test|bug|deprecated|tech-debt|doc
  severity:    HIGH | MED | LOW
  status:      FAIL | WARN | PASS
  location:    path/to/file.ext:行號
  title:       一句話描述問題
  description: 詳細說明
  evidence:    執行的指令 → 關鍵輸出（≤3 行）
  remediation: 具體修復步驟（位置 + 做什麼）
```

**severity 判斷標準：**
| severity | 條件 |
|----------|------|
| HIGH | 直接影響正確性、安全性、或違反鐵則 |
| MED | 降低可維護性、潛在風險、格式不符 |
| LOW | 建議優化、文件補充、非阻擋 |

---

## 面向 1：ADR 合規性

對照 `make adr-list` 的 Accepted ADR：

- 變更是否違反任何已接受的架構決策？
- 是否有 Draft/FIRM ADR 對應的生產代碼被加入而未附驗證證據？（鐵則，直接 BLOCK）
- 若引入新的架構決策 → 提醒應先建立 ADR

**Finding 範例：**
```
finding:
  id:          review-001
  dimension:   adr
  severity:    HIGH
  status:      FAIL
  location:    src/auth/session.go:15
  title:       違反 ADR-002（禁止 JWT 儲存於 localStorage）
  description: session token 寫入 localStorage，違反已接受的安全架構決策
  evidence:    grep -r "localStorage" src/ → src/auth/session.go:15
  remediation: 改用 httpOnly cookie，參考 ADR-002 §Decision
```

---

## 面向 2：測試覆蓋

- 新功能是否有對應測試？
- 修復的 bug 是否有回歸測試（先 FAIL 後 PASS）？
- 測試是否覆蓋邊界條件和錯誤路徑？

**不足時的 tech-debt 標記：**
```
# tech-debt: HIGH test-pending [模組名] 缺少回歸測試 (DUE: YYYY-MM-DD)
```

**Finding 範例：**
```
finding:
  id:          review-002
  dimension:   test
  severity:    HIGH
  status:      WARN
  location:    tests/auth/
  title:       缺少 LoginFailure 回歸測試
  description: 修復了 login 空密碼 bug，但無對應 FAIL→PASS 測試
  evidence:    ls tests/auth/ → 無新測試檔案
  remediation: 新增 TestLoginEmptyPassword，確認先 FAIL 再實作後 PASS
```

---

## 面向 3：Bug 分類

發現 bug 時，使用標準分類標籤：

| 標籤 | 說明 | 範例 |
|------|------|------|
| `[bug:logic]` | 業務邏輯錯誤 | 條件判斷反向、計算公式錯誤 |
| `[bug:boundary]` | 邊界條件未處理 | 空值、空陣列、最大值溢出 |
| `[bug:race]` | 並發/競態條件 | 共享狀態無鎖、async 順序依賴 |
| `[bug:security]` | 安全漏洞 | SQL injection、未授權存取 |
| `[bug:perf]` | 效能問題 | N+1 查詢、記憶體洩漏 |
| `[bug:contract]` | API/介面合約破壞 | 回傳型別改變、欄位移除 |

**🔴 鐵則：發現任何 bug → 強制 grep 全專案找相同模式，無豁免**

```bash
grep -r "相同 pattern" . --include="*.go"  # 或對應語言
```

**Finding 範例：**
```
finding:
  id:          review-003
  dimension:   bug
  severity:    HIGH
  status:      FAIL
  location:    src/db/query.go:42
  title:       [bug:security] SQL 字串拼接
  description: 用戶輸入直接拼入 SQL，存在 injection 風險
  evidence:    grep -r "fmt.Sprintf.*SELECT" src/ → 3 處相同模式
  remediation: 改用 prepared statement；同步修復其他 2 處（query.go:87, report.go:23）
```

---

## 面向 4：DEPRECATED 掃描

```bash
grep -r "DEPRECATED\|@deprecated\|// TODO: remove\|// FIXME" . --include="*.go"
```

- 新代碼是否使用了已標記廢棄的 API？
- 是否新增了 DEPRECATED 標記但未建立 tech-debt？

**Finding 範例：**
```
finding:
  id:          review-004
  dimension:   deprecated
  severity:    MED
  status:      WARN
  location:    src/cache/client.go:8
  title:       引用已廢棄的 RedisV2 client
  description: RedisV2 標記 @deprecated，應改用 RedisV3
  evidence:    grep "@deprecated" vendor/redis/ → redis_v2.go:1
  remediation: 替換為 RedisV3 client，參考 migration guide
```

---

## 面向 5：Tech Debt 標記品質

檢查此次變更新增的 `tech-debt:` 標記：

- 格式：`# tech-debt: [HIGH|MED|LOW] [CATEGORY] description (DUE: YYYY-MM-DD)`
- HIGH 必須有 DUE 日期
- CATEGORY 標準值：`test-pending` `adr-pending` `spec-pending` `doc-stale` `deprecated-cleanup` `refactor` `perf` `security`

**Finding 範例：**
```
finding:
  id:          review-005
  dimension:   tech-debt
  severity:    MED
  status:      WARN
  location:    src/payment/processor.go:100
  title:       tech-debt HIGH 缺少 DUE 日期
  description: "# tech-debt: HIGH refactor 支付模組需重構" 缺少 DUE
  evidence:    grep "tech-debt: HIGH" src/payment/ → processor.go:100
  remediation: 補充 (DUE: YYYY-MM-DD)，建議 30 天內
```

---

## 面向 6：文件同步

- 公開 API、CLI 介面、配置欄位是否已更新文件？
- CHANGELOG 是否記錄了用戶可見的變更？
- 相關 SPEC 的 `Implementation` 欄位是否已填入？

**Finding 範例：**
```
finding:
  id:          review-006
  dimension:   doc
  severity:    LOW
  status:      WARN
  location:    CHANGELOG.md
  title:       新增 API endpoint 未記錄於 CHANGELOG
  description: POST /api/v2/refresh 為用戶可見新 API，未在 Unreleased 記錄
  evidence:    git diff HEAD -- CHANGELOG.md → 無新增
  remediation: 在 ## [Unreleased] ### Added 補上該 endpoint 說明
```

---

## Common Rationalizations（AI 審查時必讀）

> 若以下藉口出現，引用反駁，不可直接照辦。

| 藉口 | 反駁 |
|------|------|
| 「這只是重構，不需要測試覆蓋」 | 重構必須通過偷渡偵測三條件（邏輯未改、數量未減、場景未縮）。未通過就是測試偷渡。 |
| 「Bug 很小，不需要全專案 grep」 | 鐵則無豁免。grep 結果為零才能確認範圍，不能靠「感覺」。 |
| 「測試 flaky，可以忽略」 | Flaky 是技術債，不是豁免。必須標記 `tech-debt: HIGH test-pending flaky` 後才可 WARN-GO。 |
| 「文件之後補」 | 面向 6 允許 WARN-GO，但必須記錄到 bypass log。連續 3 次觸發 audit blocker。 |
| 「這改動很明顯，不需要 CHANGELOG」 | 用戶可見的變更（API、CLI、行為改變）一律記錄。只有內部重構可豁免。 |
| 「ADR 違反只是輕微」 | ADR 合規沒有「輕微違反」。違反就是 BLOCK，需先修改 ADR 再改代碼。 |
| 「tech-debt 格式差不多就好」 | 格式是機器可讀的，錯誤格式導致 `make tech-debt-list` 無法彙整。HIGH 無 DUE 一律退回。 |

---

## Review Anti-patterns（審查失敗模式）

| 反模式 | 識別信號 | 正確做法 |
|--------|---------|---------|
| **表面審查** | 意見只針對新增行，未評估周邊互動 | 閱讀修改函式的完整實作與呼叫端 |
| **確認偏誤** | 六面向全 ✅，但沒執行任何驗證指令 | 每個面向都要有 evidence（指令 + 輸出） |
| **Bug 孤立** | 只回報「file.go:42 有問題」，未 grep | 發現 bug → 立即 grep 全專案 → 回報所有受影響位置 |
| **DEPRECATED 盲點** | 只看直接使用，忽略 import 鏈間接引用 | 檢查新增 import 的依賴鏈是否引入廢棄 API |
| **測試數量代替品質** | 全是 happy path，無 edge case、無錯誤路徑 | 確認覆蓋邊界條件與失敗場景 |
| **CHANGES REQUIRED 無行動項** | 結論「有問題」，沒有具體修復指引 | 每個必須修復項都要有 location + 問題 + 建議修法 |

---

## 審查後的強制動作

**發現 bug → 必須執行：**
```bash
grep -r "[相同模式]" . --include="*.[ext]"
```

**🔴 ASP 鐵則：Bug 修復後 grep 全專案找相同模式，無豁免。**
