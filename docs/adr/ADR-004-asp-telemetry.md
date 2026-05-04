# ADR-004: ASP Telemetry 採用 JSONL Append-Only 格式

**Status:** Accepted
**Date:** 2026-04-29
**Deciders:** astroicers

## Context

ASP v3.7 無法量測：
- 哪些 gate 真的抓到問題（gate_fail rate）
- 哪些 skill 被最多 bypass（bypass frequency）
- session 啟動時平均有多少 blocker

沒有 telemetry，v4.0 的效果驗證只能靠主觀感受，無法做 evidence-based 的規則調整。

## Decision

採用 **JSONL append-only 格式**（`.asp-telemetry.jsonl`）。

理由：
1. 無 runtime 依賴（純 Python stdlib，無 pip packages）
2. grep-able：`grep gate_fail .asp-telemetry.jsonl | wc -l`
3. git diff-able：每個 session 只 append，不覆寫，diff 可讀
4. 失敗 silent：telemetry 腳本 crash 不影響主流程
5. Archive-friendly：prune.py 按月歸檔，不無限成長

## Alternatives Considered

1. **SQLite database** — Pro: structured queries; Con: 需要 sqlite3 依賴（雖然是 stdlib，但需要 DB schema migration）；binary format 不 grep-able
2. **JSON array file** — Pro: 單一文件；Con: append 需要讀全檔重寫，大文件慢；concurrent write 有 race condition
3. **Prometheus / OpenTelemetry** — 過重，ASP 是單人/小團隊工具，不需要監控基礎設施

## Consequences

**Positive:**
- 零依賴，任何有 Python 的環境都能運行
- 可輕鬆 grep 分析
- append-only 天然支援未來的「寫入完整性」audit

**Negative:**
- 無 real-time dashboard（只有 report.py 的 terminal 輸出）
- 無 structured query（只能 grep + Python 腳本分析）
- 每個 event 都是 flat JSON（無 schema 強制）

## Makefile Targets

```makefile
asp-telemetry-collect: python3 .asp/scripts/telemetry/collect.py
asp-telemetry-report: python3 .asp/scripts/telemetry/report.py --days 7
asp-telemetry-prune: python3 .asp/scripts/telemetry/prune.py --days 90
```

## Related Documents

- `.asp/scripts/telemetry/README.md` — 實作說明
