# ASP 定期排程設定指南

`daily-audit.sh` 可透過以下任一方式定期執行：

---

## 選項 A：Linux/macOS cron

```bash
# 每天早上 8:00 執行（伺服器時間）
0 8 * * * cd /path/to/your-project && CLAUDE_PROJECT_DIR=$(pwd) bash .asp/scripts/daily-audit.sh >> /tmp/asp-daily.log 2>&1
```

編輯 crontab：`crontab -e`

---

## 選項 B：GitHub Actions schedule

在你的專案中新增 `.github/workflows/asp-daily.yml`：

```yaml
name: ASP Daily Audit

on:
  schedule:
    - cron: '0 0 * * *'  # UTC 00:00 = 台灣 08:00
  workflow_dispatch:       # 允許手動觸發

jobs:
  daily-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: pip install pyyaml 2>/dev/null || true && sudo apt-get install -y jq 2>/dev/null || true

      - name: Run daily audit
        run: |
          CLAUDE_PROJECT_DIR=$(pwd) bash .asp/scripts/daily-audit.sh

      - name: Upload daily report
        uses: actions/upload-artifact@v4
        with:
          name: asp-daily-report-${{ github.run_number }}
          path: .asp-daily-report.md
          retention-days: 30
```

---

## 輸出格式

`daily-audit.sh` 輸出 `.asp-daily-report.md`，包含：

| 欄位 | 內容 |
|------|------|
| ROADMAP 進度 | pending/in_progress/completed 任務數量 |
| ADR 狀態 | Draft/FIRM/Accepted 數量 |
| 健康審計 | blockers/warnings/infos 數量 |
| Task Inbox | pending/ingested 任務數量 |
| Git 活動 | 過去 24 小時的 commit 數與作者 |
| 今日建議 | 基於 blockers 自動推斷 |

---

## 整合 ASP-Operator（未來）

當 ASP-Operator 上線後，可接收 `.asp-daily-report.md` 並透過 Slack/Feishu webhook 發送。
目前輸出僅為本地 Markdown 檔案，需人工查閱。
