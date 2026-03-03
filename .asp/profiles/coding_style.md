# Coding Style Profile — 通用編碼風格規範

適用：需要統一程式碼風格的系統開發專案。
載入條件：`coding_style: enabled`

> **設計原則**：一致性優先於個人偏好。
> 既有 codebase 的慣例優先於本 profile 的建議——先觀察再修改，不要強加風格。

---

## 命名慣例

| 對象 | 規則 | 範例 |
|------|------|------|
| 變數 / 函式 | 依語言慣例（Go: camelCase, Python: snake_case, JS/TS: camelCase） | `getUserName`, `get_user_name` |
| 常數 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| 類別 / 型別 | PascalCase | `UserRepository` |
| 布林值 | is / has / can / should 前綴 | `isActive`, `hasPermission` |
| 檔名 | snake_case 或 kebab-case（依語言慣例） | `user_service.go`, `user-service.ts` |
| 私有成員 | 依語言慣例（Go: unexported, Python: `_prefix`, JS/TS: `#prefix` 或 `_prefix`） | `_internal_cache` |

---

## 函式設計

- **單一職責**：一個函式只做一件事，函式名稱即說明用途
- **長度**：函式體 ≤ 40 行為佳，超過時考慮拆分
- **參數**：≤ 4 個為佳，超過時使用 options object / struct
- **巢狀**：避免超過 3 層縮排——用 early return、guard clause 降低巢狀
- **回傳值**：避免回傳 null/nil 作為正常流程的一部分，優先使用明確的錯誤型別

---

## 檔案結構

- 每個檔案單一職責，檔名反映內容
- import / require 排序：`stdlib → 外部套件 → 內部模組`，群組間空一行
- 檔案內部排序建議：`type/interface → constants → constructor → public methods → private methods`

---

## 註解風格

- 解釋 **why**，不解釋 **what**——程式碼本身應該說明 what
- 公開 API / 匯出函式需 docstring（Go: godoc, Python: docstring, TS: JSDoc）
- TODO 格式：`// TODO(owner): description`
- 過時註解比沒有註解更糟——修改邏輯時同步更新註解

---

## 錯誤處理

- 不吞掉 error（禁止空 catch / 忽略 err）
- 不用 generic catch-all（如 `catch (Exception e)`）——捕捉具體的錯誤型別
- 錯誤訊息包含上下文：`failed to create user: {reason}`，不只是 `error occurred`
- 區分可恢復錯誤與不可恢復錯誤——不可恢復的應 fail fast

---

## 風格審查決策流程

```
FUNCTION review_code_style(file, codebase_conventions):

  // ─── 不可違反的約束 ───
  INVARIANT: 一致性優先於個人偏好
  INVARIANT: 既有 codebase 的慣例優先於本 profile 的建議

  // ─── 第 1 步：識別既有慣例 ───
  existing = detect_conventions(codebase_conventions)
  // 既有 codebase 的命名、縮排、import 風格

  // ─── 第 2 步：遵循既有慣例 ───
  IF file.style CONFLICTS_WITH existing:
    RETURN follow_existing(
      reason = "一致性優先。此 codebase 使用 {existing.convention}，應保持一致。"
    )

  // ─── 第 3 步：檢查本 profile 規則 ───
  violations = []

  IF any_function.line_count > 40:
    violations.append("函式 {name} 超過 40 行，建議拆分")

  IF any_function.param_count > 4:
    violations.append("函式 {name} 參數超過 4 個，建議使用 options object")

  IF any_block.nesting_depth > 3:
    violations.append("巢狀超過 3 層，建議用 early return 降低")

  IF imports NOT sorted_by(stdlib, external, internal):
    violations.append("import 順序不符慣例")

  IF violations:
    RETURN suggest_improvements(violations)
  ELSE:
    RETURN approve()
```
