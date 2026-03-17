---
name: asp-ship
description: |
  Use before every git commit to run the pre-commit checklist.
  Executes 7 ordered checks and outputs a Go/No-Go report.
  Triggers: ship, commit, pre-commit, ready to commit, 提交, 準備提交, 提交前, 送出,
  commit check, before commit, 我要提交, 可以 commit 了嗎.
---

# ASP Ship — 提交前檢查

## 適用場景

用戶準備提交代碼（git commit）前，執行完整的 7 步驟驗證。任何一步失敗即 **BLOCK**，禁止提交。

---

## 7 步驟有序檢查

### Step 1：執行全量測試

```bash
make test
```

**判斷：**
- PASS → 繼續
- FAIL → 🔴 **BLOCK** — 列出失敗的測試，停止後續步驟

---

### Step 2：確認變更範圍

```bash
git status
git diff --stat
```

**判斷：**
- 檢查是否有意外的變更（不屬於此次 commit 的檔案）
- 若有未暫存的相關變更 → 提醒用戶是否要一起加入
- 若有敏感檔案（`.env`, `*.key`, `credentials*`）→ 🔴 **BLOCK**

---

### Step 3：確認 CHANGELOG.md 已更新

```bash
git diff HEAD -- CHANGELOG.md
```

**判斷：**
- 有本次變更的記錄 → 繼續
- 無更新且此次有用戶可見的功能變更 → 🟡 **WARN**，提醒補充後繼續
- 若專案無 CHANGELOG.md → 跳過此步，備註

---

### Step 4：確認 README.md 是否需要更新

對照 `git diff --stat`，判斷此次變更是否影響：
- 公開 API 或 CLI 介面
- 安裝/設定流程
- 功能清單或使用說明

**判斷：**
- 有影響但 README 未更新 → 🟡 **WARN**，提醒用戶確認
- 無影響 → 繼續

---

### Step 5：確認 SPEC Traceability 已更新

若此次 commit 實作了某個 SPEC 中的功能：

```bash
make spec-list
```

查看相關 SPEC 的 `Implementation` 或 `Traceability` 欄位是否填入：
- 實作檔案路徑
- 對應 commit hash（可在 commit 後補填）

**判斷：**
- 有對應 SPEC 但 Traceability 空白 → 🟡 **WARN**
- 無對應 SPEC（trivial 變更）→ 跳過

---

### Step 6：Tech Debt 標記確認

```bash
make tech-debt-list
```

**判斷：**
- 此次新增了 `tech-debt:` 標記 → 確認已記錄格式正確（`[HIGH|MED|LOW] [CATEGORY] description (DUE: YYYY-MM-DD)`）
- HIGH 標記無 DUE 日期 → 🟡 **WARN**
- 發現過期的 HIGH tech-debt（DUE 日期已過）→ 🟡 **WARN**，建議優先處理

---

### Step 7：ADR 合規確認

```bash
make adr-list
```

**判斷：**
- 所有 `Accepted` ADR 的決策是否在此次變更中被遵守
- 是否有 `Draft` ADR 對應的生產代碼被加入 → 🔴 **BLOCK**（鐵則）
- 無違反 → 繼續

---

## 輸出：Go / No-Go 報告

```
📋 Pre-Commit Checklist 結果
================================

Step 1 測試          ✅ PASS（或 🔴 FAIL）
Step 2 變更範圍      ✅ 確認（或 ⚠️  警告）
Step 3 CHANGELOG     ✅ 已更新（或 ⚠️  未更新）
Step 4 README        ✅ 無需更新（或 ⚠️  建議更新）
Step 5 SPEC 追蹤     ✅ 已記錄（或 ⚠️  待補）
Step 6 Tech Debt     ✅ 格式正確（或 ⚠️  警告）
Step 7 ADR 合規      ✅ 無違反（或 🔴 BLOCK）

================================
結論：✅ GO — 可以提交
     或
結論：🔴 NO-GO — 阻擋原因：[說明]
     或
結論：⚠️  WARN-GO — 有警告但可提交，建議：[說明]
```

---

## 快速修復指引

| 問題 | 修復方式 |
|------|---------|
| 測試失敗 | 修復後重新執行 `make test` |
| 敏感檔案 | 加入 `.gitignore` 並從 staging 移除 |
| CHANGELOG 未更新 | 在 `## Unreleased` 下新增條目 |
| Draft ADR 對應生產代碼 | 等 ADR Accept 後再提交，或移除對應代碼 |
| Tech Debt 格式錯誤 | 修正為 `# tech-debt: HIGH test-pending desc (DUE: YYYY-MM-DD)` |
