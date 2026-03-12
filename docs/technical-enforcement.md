# 技術強制層（Hooks + 內建權限）

ASP 使用 Claude Code **內建權限系統** + **SessionStart Hook** 保護危險操作：

```
.claude/settings.json
  └── SessionStart hook → clean-allow-list.sh（清理 allow list）

每次 session 啟動 → 自動清理 allow list 中的危險規則
  → 危險指令不在 allow list → 內建權限系統彈出「Allow this bash command?」確認框
```

| 機制 | 說明 |
|------|------|
| **內建權限系統** | 危險指令（git push/rebase, docker push, rm -rf 等）不在 allow list 中時，Claude Code 自動彈出確認框 |
| **SessionStart Hook** | `clean-allow-list.sh` 每次 session 啟動時自動清理 allow list 中的危險規則，確保內建權限系統持續生效 |

> 使用者可在確認框中選擇 "Allow"（一次性）或 "Always allow"（永久），但後者會在下次 session 啟動時被自動清理。
> 設定檔位於 `.claude/settings.json`，hook 腳本位於 `.asp/hooks/`。
