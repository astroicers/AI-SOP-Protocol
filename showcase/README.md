# Showcase：展示 / 研究用途元件（v5 ADR-017）

> 本目錄內容**不進預設安裝路徑**。定位：展示 ASP 的可觀測性與檢索能力、
> 供研究與示範場景使用——非日常治理核心（Daily-driver core = hooks + skills +
> gates + 12 profiles）。

## 內容

| 目錄 | 元件 | 用途 |
|------|------|------|
| `telemetry/` | collect / report / prune（.asp-telemetry.ndjson） | session 事件量測（展示用；**規則命中遙測屬 Core**，見 Phase 5 rule-hits） |
| `rag/` | build_index / search / stats + rag-auto-index hook + rag_context profile | 本地向量知識庫檢索 |
| `ai-performance/` | monthly-review + trust-tier | AI 表現月度回顧 |

## 安裝

```bash
# 全新安裝或升級時帶旗標（或 env ASP_WITH_SHOWCASE=1，curl|bash 場景）
bash .asp/scripts/install.sh --with-showcase
```

裝回後佈局與 v4 相同（`~/.claude/asp/scripts/telemetry/`、`~/.claude/asp/scripts/rag/`、
`~/.claude/asp/hooks/rag-auto-index.sh`、`~/.claude/asp/profiles/rag_context.md`、
`~/.claude/asp/ai-performance/`），既有 make targets（`rag-*`、`asp-telemetry-*`、
`asp-performance-review*`）由 `-include showcase/Makefile.inc` 於 repo 內自動生效。
安裝會 `touch ~/.claude/asp/.showcase-installed`（marker）——`asp-sync.sh` 據此在
rsync --delete 後補同步，避免抹掉你的安裝。

`.ai_profile` 設 `rag: enabled` 但未裝回時，validate-profile 會印 🟡 提示。

## 測試

```bash
pytest showcase/rag/tests showcase/ai-performance/tests   # 不在 make test 快速路徑
```
