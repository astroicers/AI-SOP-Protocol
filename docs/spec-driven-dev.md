# SPEC 驅動開發

ASP 的 SPEC（規格書）不只是文件——它定義了**需求、邊界條件、測試驗收標準**，是一體的。

```
SPEC 定義「Done When」（驗收標準）
  → TDD 先寫測試（基於 Done When）
    → 實作讓測試通過
      → 驗收
```

| 情境 | 是否需要 SPEC |
|------|-------------|
| 新功能開發 | **是**（預設），Done When 必須含測試條件 |
| 非 trivial Bug 修復 | **是**（`make spec-new TITLE="BUG-..."`) |
| trivial（單行/typo/配置） | 可跳過，需說明理由 |
| 原型驗證 | 可延後，需標記 `tech-debt: test-pending` |

---

## ADR↔SPEC 連動（架構變更時）

```
ADR（Accepted）→ SPEC（關聯 ADR-NNN）→ TDD → 實作
                    ↑ ADR 為 Draft 時不建 SPEC、不寫生產代碼
```

- SPEC 的「關聯 ADR」欄位必須填入對應 ADR 編號
- 非架構變更的 SPEC 不需要關聯 ADR

---

## Done When 模板

SPEC 模板中的 **✅ Done When** 區塊就是測試定義（**必須含至少一項測試條件**）：

```markdown
## ✅ Done When
> 必須包含至少一項可驗證的測試條件。

- [ ] `make test-filter FILTER=spec-000` all pass
- [ ] `make lint` has no errors
- [ ] Response time < ____ms
- [ ] Updated CHANGELOG.md
```

SPEC 最低必填欄位：**Goal、Inputs、Expected Output、Done When（含測試條件）、Edge Cases**。

> 測試不是另外寫的文件，而是 SPEC 的一部分。SPEC 完成 = 驗收標準已定義。
