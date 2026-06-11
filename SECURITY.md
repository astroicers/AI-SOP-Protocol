# 安全政策 Security Policy

## 支援版本 Supported Versions

ASP 採語意化版本（major.minor.patch）。安全性修補僅針對**目前 major 版本**提供。

| 版本 | 是否支援 |
|------|---------|
| 5.x  | ✅ |
| < 5.0 | ❌（請升級至最新版） |

## 回報漏洞 Reporting a Vulnerability

**請勿透過公開 Issue 回報安全性問題。**

請使用 GitHub 私密漏洞回報：

1. 前往本 repo 的 **Security** 分頁
2. 點選 **Report a vulnerability**
3. 描述問題、重現步驟與影響範圍

我們會在 **72 小時內**初步回覆，並於確認後協調修補與揭露時程。

## ASP 特性提醒 Scope Notes

ASP 透過 **bash hooks**（SessionStart、commit gate）與 **install 腳本**（`.asp/scripts/install.sh` / `install.ps1`）在使用者環境執行。回報時若涉及下列情境，請特別註明：

- 安裝 / 升級腳本的任意指令執行或權限提升
- SessionStart / commit hook 的注入或繞過（例如繞過鐵則 deny）
- 範本（ADR / SPEC）或 profile 編譯產物中的不安全內容
- 敏感資訊掃描（`/asp-ship` Step 9）的誤判或遺漏

感謝你協助維護 ASP 使用者的安全。
