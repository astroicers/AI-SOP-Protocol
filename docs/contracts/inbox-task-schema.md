# Inbox Task Schema — ASP 單一真理來源（contract）

> 蒸餾自 asp-operator `src/task_translator.py::translate_issue()`（ADR-032 Locus D-A）。
> asp-operator 已凍結（ADR-032），但本 schema 仍是**消費端**（`asp-autopilot.md` 的 `is_external_provenance` / SPEC-008）所依賴的介面，也是任何**未來生產者**（解凍的 operator／手寫腳本／別的 harness）的目標。**此檔為 inbox task 形狀的唯一真理來源。**

## 欄位

| 欄位 | 型別 | 說明 | 範例 |
|------|------|------|------|
| `id` | string | `INBOX-<issue_number>` | `INBOX-42` |
| `type` | enum | `BUGFIX` / `NEW_FEATURE` / `GENERAL`（`classify_type()`） | `BUGFIX` |
| `priority` | enum | `P0`–`P3` | `P2` |
| `status` | enum | `pending`（held，SPEC-007 起惰性；不自動注入 ROADMAP） | `pending` |
| `sla_hours` | number | 依 priority 對映（`map_sla()`） | `48` |
| `source` | object | `{ type: "github_issue", ref: <url> }`（**巢狀**） | `{type:"github_issue", ref:"...#42"}` |
| `triggered_by` | string | 授權 provenance；operator 硬寫 `"customer"`（外部） | `customer` |
| `description` | string | issue body，截斷 500 字 | `...` |

## Provenance 判定（消費端）

`asp-autopilot.md::is_external_provenance(task)`（SPEC-008 / ADR-012 INV-2）判為外部來源的條件：

```
(task.source_type EXISTS AND task.source_type != "manual")
  OR (task.triggered_by EXISTS AND task.triggered_by NOT IN ["human","maintainer"])
```

## ⚠️ 已知 drift（ADR-032 POC-2 揭露，凍結下無害）

**消費端讀扁平 `task.source_type`，生產端卻寫巢狀 `source.type`。** 兩者名稱不一致 → `source_type` 這條判斷對 operator 產出的任務**恆為 false**，實際全靠 `triggered_by="customer"`（∉ human/maintainer）才正確分類為 external。

- **凍結下影響**：無（無 live 生產者，gate dormant）。
- **若日後解凍**：應統一命名（擇一：生產端改寫扁平 `source_type`，或消費端改讀 `source.type`），並以本 schema 為唯一真理，避免再度 drift。屬「生產者↔閘一致性」原則的具體案例，見 [threat-model 生產者↔閘一致性原則](../security/threat-model-v4.0.md)。

**相關**：ADR-032（凍結＋蒸餾）、ADR-012（信任模型，dormant）、SPEC-008（provenance gate）。
