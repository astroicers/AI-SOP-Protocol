<!-- Last Updated: 2026-07-22 | Status: POC (spike) | Audience: ASP framework maintainers -->
# ADR-021 POC-1 — plugin hook 動態寫 `settings.local.json`

## 問題

ADR-021 把 ASP 改封裝為官方 Claude Code plugin。ASP 的 L2 強制力靠 SessionStart hook（`session-audit.sh`）偵測 Draft ADR 時**動態寫 `settings.local.json` 的 `git commit` deny**。FC-004 確認 plugin 支援 SessionStart/PreToolUse 事件與 `${CLAUDE_PLUGIN_ROOT}`，但**「hook 寫 settings.local.json」官方文件未明載**（FC-004 殘留 #1）。POC-1 要證實：**plugin 承載的 hook 能否把 deny 寫進使用者專案的 `settings.local.json`、且不碰 tracked `settings.json`。**

## 方法

1. **外部事實查證（FC-006）**：官方文件確認 plugin hook 的執行環境（見 `.asp-fact-check.md` FC-006）。
2. **建 local 測試 plugin**（本目錄 `poc1-plugin/`，throwaway、不接真 `.claude/settings.json`/CI）：
   - `.claude-plugin/marketplace.json`（`strict:false` → 免 plugin.json）
   - `asp-hook-poc/hooks/hooks.json`（SessionStart=clean-allow-list+session-audit；PreToolUse(Bash)=ship-gate，皆 `${CLAUDE_PLUGIN_ROOT}/hooks/*.sh`）
   - `asp-hook-poc/hooks/*.sh`＝**真 ASP hook 的副本**（`.asp/hooks/` 的三支）
3. **本機模擬**（`simulate-plugin-hook.sh`，免 `/plugin`）：以 plugin 會設的 env（`CLAUDE_PLUGIN_ROOT`+`CLAUDE_PROJECT_DIR`）跑 bundled `session-audit.sh` + Draft ADR fixture。
4. **端到端定論步**（真 `/plugin install`，需人類跑一次）。

## 結果

### FC-006（官方文件，全數確認）
- **`CLAUDE_PROJECT_DIR` 對 plugin hook 有保證**（與 settings.json hook 相同）→ `session-audit.sh` 定位專案正確、**無需改 hook**。
- plugin hook **不沙箱**、以使用者 OS 權限跑 → 寫 `settings.local.json` 允許。
- `marketplace.json`（`name`/`owner`/`plugins[]`，local `source:"./subdir"`）+ `strict:false` 免 plugin.json；`hooks/hooks.json` 用 `${CLAUDE_PLUGIN_ROOT}`。
- **local marketplace**（`/plugin marketplace add ./path`）→ 就地可測。

### 本機模擬（PASS）
`bash docs/research/poc1-plugin/simulate-plugin-hook.sh`：
```
[settings.local.json written by the BUNDLED hook]
{ "permissions": { "deny": [ "Bash(git commit *)", "Bash(git commit)" ] } }
[deny contains the commit pattern?]  PASS — plugin-bundled hook wrote the ASP L2 deny
[tracked settings.json]              PASS — UNCHANGED
```
→ bundled hook + plugin env 的行為與現行 `.claude/settings.json` 佈線**等同**。

## 端到端定論步（人類跑一次，就地、無需推 GitHub）

```bash
# 在含 poc1-plugin/ 的目錄（repo root）啟動一個 session，然後在 session 內：
/plugin marketplace add ./docs/research/poc1-plugin
/plugin install asp-hook-poc@asp-poc-marketplace
/reload-plugins
# 在本 repo（已有多份 ADR）新開一個 session → session-audit 掃到任何 Draft ADR 就會注入 deny。
# 或：暫時放一份 狀態=Draft 的 ADR fixture，重啟 session，請 Claude 跑 `git commit` → 應被擋。
# 驗畢移除 plugin：/plugin uninstall asp-hook-poc@asp-poc-marketplace
```
> 因 FC-006 已在文件層級確認機制、本機模擬亦 PASS，此步屬「**確認**」而非「賭注」。

### 環境註記（2026-07-22，誠實邊界）
本 session 的執行環境**無 `/plugin` 指令**（實測回「`/plugin` isn't available in this environment」），故真 `/plugin install` 端到端**無法在此環境跑**，移至使用者的**互動式 Claude Code 終端**執行。作為替代的可就地驗證：
- **manifests 已 jq 驗為合法 JSON + schema-sane**：`marketplace.json`（name/owner/plugins、source `./asp-hook-poc`、`strict:false`）、`hooks.json`（SessionStart×2 + PreToolUse `Bash`），且 hooks.json 引用的 3 支腳本**皆存在**。→ 封裝結構正確，互動終端安裝即可用。
- 尚未經驗證的**唯一**環節＝Claude Code plugin loader 是否確實解析 hooks.json 並設 `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PROJECT_DIR`——此為 FC-006 官方文件明載行為，僅缺本地實跑。

## 結論

- **POC-1 = PASS（文件 FC-006 + 本機模擬 + manifest 驗證）**：plugin 承載的 hook 能把 ASP L2 deny 寫進專案 `settings.local.json`、不碰 tracked `settings.json`。
- **loader 實跑（真 `/plugin install`）＝唯一 deferred 環節**，因本環境無 `/plugin`；移至互動式 CC 終端，屬文件已保證的「確認」。
- **ASP hook 無需修改**即可在 plugin 下運作（`CLAUDE_PROJECT_DIR` 有保證）。
- **次要 robustness 觀察（非阻擋，實作輪可選）**：`session-audit.sh:18` 只有 `${CLAUDE_PROJECT_DIR:-.}`，而 `pretooluse-ship-gate.sh:25` 已有 stdin `.cwd` fallback；可補上對稱 fallback 以防未來 env 不保證的邊界（動 Iron-Rule-A 保護檔，走 hash 更新流程）。

## 界定
本 POC 只證機制可行，**不**改真 `.claude/settings.json` 佈線、**不**建 repo-root `.claude-plugin/`、**不**退役測試——那些屬 ADR-021 的實作輪（#41 b/c）。
