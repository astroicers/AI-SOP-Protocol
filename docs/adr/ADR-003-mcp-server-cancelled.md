# [ADR-003]: MCP Server 實作取消 — 改採 User-level Skill 架構

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-05-09 |
| **決策者** | astroicers |

---

## 背景（Context）

ASP v4.0 重構計劃（SPEC-003、v4-refactor-prompts.md Prompt 4）原本預定實作一個 MCP server，提供至少 5 個 stateful tool（session log、bypass log query、trust tier lookup 等），讓 AI agent 在 session 中透過 MCP protocol 存取 ASP 狀態。

在 v4.0 重構執行過程中，評估了 MCP server 相對於已完成的 user-level skill 架構的增量價值。

---

## 評估選項（Options Considered）

### 選項 A：實作 MCP Server（原計劃）

- **優點**：stateful tool call、可跨 session 累積狀態、標準 MCP protocol
- **缺點**：增加部署複雜度（需要常駐 server process）；user 需要額外設定 MCP endpoint；維護成本高；與 user-level skill 架構有功能重疊
- **風險**：若 Claude Code 的 MCP 整合行為變更，整個子系統可能失效

### 選項 B：取消 MCP，改採 User-level Skill（本決策）

- **優點**：零額外部署需求；23 個 asp-*.md skill 已涵蓋所有原定 MCP tool 的功能；skill 是純 markdown，可版控、可 diff、可 grep；install.sh 一鍵安裝到 `~/.claude/skills/asp/`
- **缺點**：無法做到真正的 stateful cross-session 狀態（skill 是 stateless）；bypass log 查詢仍需手動 grep
- **風險**：若未來有強烈的 stateful 需求，需要在 v4.1 重新評估

### 選項 C：延後到 v4.1 實作（混合）

- **優點**：不完全放棄 MCP 選項
- **缺點**：會讓 v4.0 的 Done-When 條件持續未達成，造成 SPEC-003 狀態混亂
- **風險**：「延後」往往變成「永遠不做」

---

## 決策（Decision）

**選擇選項 B**：v4.0 取消 MCP server 實作，改採已完成的 user-level skill 架構。

理由：
1. 23 個 skill 已提供 MCP 原定 5 個 tool 的全部功能，且更容易維護
2. User-level 架構（`~/.claude/skills/asp/`）比 stateful server 更符合 ASP 的「zero-extra-infra」設計原則
3. SPEC-003 的 Done-When 條件 6（MCP server 5 個 tool）正式標記為 CANCELLED

---

## 後果（Consequences）

**正面：**
- SPEC-003 Done-When 條件 6 改為 CANCELLED（非 FAILED），不阻擋 v4.0 發布
- 安裝流程不需要 MCP server 設定步驟
- skill 架構可以 `asp-sync.sh` 一鍵更新，比 server 更易維護

**負面：**
- 跨 session stateful 查詢（如「過去 30 天 bypass 了多少次」）仍需手動 `grep .asp-bypass-log.ndjson`
- 若未來需要 stateful tool，需要在 v4.1 重新做架構評估

**v4.1 重新評估條件：**
若以下任一條件成立，v4.1 應重新評估 MCP 實作：
- 手動 grep bypass log 變成明顯的用戶痛點
- Claude Code MCP 整合成熟度提升，部署複雜度降低
- AI Performance Review System 需要跨 session 的即時查詢

---

## 關聯文件

- `docs/ROADMAP.md` — v4.1 計劃項目（重新評估 MCP）
- `docs/specs/SPEC-003-asp-v4-architecture-refactor.md` — Done-When 條件 6 標記 CANCELLED
- `docs/v4-refactor-prompts.md` — Prompt 4 原始需求（已取消）
