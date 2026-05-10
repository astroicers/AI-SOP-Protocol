<!-- Last Updated: 2026-05-10 | Status: Active | Audience: All contributors -->
# `docs/archive/`

> 集中收納 ASP 已完成階段的歷史文件。**不刪除**（保留歷史脈絡），但**不在 active 目錄**（避免污染 contributor 視野）。

---

## 為何要 archive 而不是刪除

ASP 的決策歷史對未來理解「為什麼 v5 不做 X」很重要。完整 git history 雖然永遠在，但 archive 提供：
- **可瀏覽**：直接 `ls docs/archive/` 看歷史快照
- **可搜尋**：`grep -r` 仍能命中
- **不誤導**：active 目錄（`docs/`、`.asp/`、`docs/specs/`）只剩 currently in-effect 的文件，新人讀到的就是現況

---

## 目前的子目錄

### `v4-refactor/`

v3.7 → v4.0 重構期（2026-04 至 2026-05）的內部設計文件，重構已完成且內容已內化到：
- `docs/architecture.md`（v4.x 架構入口）
- `docs/multi-agent-architecture.md`
- `docs/specs/SPEC-004-multi-agent-worktree-isolation.md`

收納內容：
| 檔案 | 原位置 | 角色 |
|------|--------|------|
| `disposition-matrix.md` / `.yaml` | repo root `.asp-disposition-matrix.*` | 33 個元件 KEEP/COMPRESS/REFERENCE/ELIMINATE/CONVERT_TO_SKILL 決策表 |
| `v4-architecture-sds.md` | `docs/v4-architecture-sds.md` | v4.0 SDS 完整版，含 §10 Decision Log + §5.4 worktree 設計 |
| `v4-decision-log.md` | `docs/v4-decision-log.md` | D1-D10 重構期決策（為什麼壓 CLAUDE.md、為什麼抽 8 skill 等） |
| `v4-refactor-prompts.md` | `docs/v4-refactor-prompts.md` | astroicers 自用的 v4.0 重構 prompt pack（Prompt 0-8） |

### `legacy-integrations/`

ASP 嘗試過但未實際 ship 的整合方案。

收納內容：
| 檔案 | 原位置 | 角色 |
|------|--------|------|
| `spectra_integration.md` | `.asp/advanced/spectra_integration.md` | Spectra / OpenSpec 深度整合設計（Binary Shadowing），無人引用 |

---

## 何時會新增 archive 項目

任一條件成立：

1. **SPEC 已 Shipped 且內容已被取代**：例如 SPEC-003（v4 重構）已被 SPEC-004 + v4.1 實作完整取代
2. **Profile 已被 skill 取代且 level yaml 不再載入**：例如 dev_qa_loop.md（v3.x）→ asp-dev-qa-loop skill (v4)
3. **重構期內部文件**：disposition matrix、prompt pack、prerelease design notes
4. **嘗試過但取消的整合**：spectra、舊 MCP 設計等

---

## archive 後仍要保證

- ✅ git mv 而非 cp（保留 git history 與 blame）
- ✅ 下游連結改寫到 archive 路徑（`grep -rln "<old-path>"` 必須清乾淨）
- ✅ 在 `docs/archive/<subdir>/` 與本 README 中列出新增項目
- ✅ archive 文件本身不再更新（如果有更新需求，代表它不該 archive）

---

## archive 不該做的事

- ❌ 用 archive 當「我懶得修連結就丟過去」的垃圾桶
- ❌ archive 後又把連結指回 archive（active 文件不該大量引用 archive）
- ❌ 把 active 在用的文件 archive 掉（會破壞使用者工作流）

---

## 相關清理紀錄

- 2026-05-10：第一波清理（v3.7 baseline + CLAUDE.md backup + asp-verify.sh）→ commit `5402535`
- 2026-05-10：第二波 archive（本目錄首次建立）→ commit (本次)
