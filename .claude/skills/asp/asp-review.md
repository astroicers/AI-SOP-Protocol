---
name: asp-review
description: |
  Use when reviewing code, PRs, or specific changes for quality and compliance.
  Covers ADR compliance, test coverage, bug taxonomy, tech-debt, and doc sync.
  Triggers: review, code review, pr review, 審查, 幫我看, 程式碼審查, 看一下這段,
  check my code, review this, review PR, 幫我審查, 審核代碼, 這樣寫對嗎.
---

# ASP Review — 程式碼審查（流程控制）

> **工具庫**：6 個審查面向定義、反模式、輸出格式 → 見 `asp-review-checklist`

## 適用場景

用戶提交代碼、PR 或特定變更，需要系統性審查。也適用於偷渡偵測的人工判斷場景。

---

## Step 1：確認範圍

詢問（或從上下文推斷）：
- **審查目標**：特定檔案？PR？整個 branch？
- **審查重點**：全面審查 或 特定面向（如只看安全性）

```bash
git diff main...HEAD --stat   # 若審查 branch
git show --stat               # 若審查最新 commit
```

---

## Step 2：執行 6 個審查面向

依序執行 `asp-review-checklist` 中定義的面向 1–6：

1. ADR 合規性
2. 測試覆蓋
3. Bug 分類（發現 bug → 強制 grep 全專案，無豁免）
4. DEPRECATED 掃描
5. Tech Debt 標記品質
6. 文件同步

每個面向必須附帶**可觀測證據**（執行指令 + 輸出摘要）。

---

## Step 3：偷渡偵測人工判斷

若審計工具觸發偷渡偵測警告：

**排除誤報條件（全部滿足才算正常重構）：**
1. 測試邏輯未改變（只改了結構，沒有移除/修改 assertion）
2. 測試數量未減少
3. 覆蓋的業務場景集合未縮小

全部滿足 → 誤報，繼續。任一不滿足 → 真正偷渡，需回滾測試改動。

---

## Step 4：輸出審查結論

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
     1. [finding id] [位置] [問題] → [建議修法]

     建議修復（非阻擋）：
     1. [建議]
```

每個必須修復項使用 `asp-review-checklist` 定義的 finding 格式（含 id、severity、evidence、remediation）。

---

## 注意事項

- 遇到藉口或想跳步驟 → 先查閱 `asp-review-checklist` 的 Common Rationalizations 表
- 審查完成後如有 bug → 強制 grep 全專案（見 `asp-review-checklist` 審查後強制動作）