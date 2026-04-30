# SPEC-003: ASP v4.0 架構重構整合規格書

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-003 |
| **Status** | Accepted |
| **Date** | 2026-04-29 |
| **關聯 ADR** | ADR-002 (security), ADR-004 (telemetry) |
| **估算複雜度** | 高 |
| **HITL 等級** | standard |

---

## Goal

ASP v4.0 = 憲法壓縮 + Skill 增殖 + 可觀測性層：
把 v3.7 的 token 負擔降低 40%，同時增加 8 個 capability 與 security posture。

---

## v3.7 → v4.0 架構對比

### v3.7 架構

```
使用者 ← → Claude Code
              │
              ├── CLAUDE.md (309 行 / ~4500 tokens)
              ├── .ai_profile → .asp/profiles/ (20 profiles, 6419 行)
              └── .claude/skills/asp/ (13 skills, 2048 行)
```

### v4.0 架構

```
使用者 ← → Claude Code
              │
              ├── CLAUDE.md (92 行 / ~2500 tokens) ← 壓縮 70%
              ├── .ai_profile → .asp/profiles/ (21 profiles, +spike_mode)
              ├── .claude/skills/asp/ (21 skills, +8 新增)
              │        ├── [原有 12 skill]
              │        └── [v4 新增 8: handoff/team-pick/escalate/dev-qa-loop/
              │             fact-verify/assumption-checkpoint/bug-classify/change-cascade]
              ├── .asp/levels/ (6 levels, L0-L5)
              ├── docs/security/threat-model-v4.0.md (STRIDE)
              └── .asp/scripts/telemetry/ (collect/report/prune)
```

---

## 輸入規格

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| `.ai_profile` | YAML | 專案根目錄 | 選填；缺少時只套用鐵則 |
| `CLAUDE.md` | Markdown | 專案根目錄 | 必須 ≤ 100 行 |
| `.asp/profiles/*.md` | Markdown | profiles 目錄 | 依 `.ai_profile` 的 type/mode 欄位載入 |
| `.claude/skills/asp/*.md` | Markdown | skills 目錄 | 依觸發詞按需載入 |

---

## 輸出規格

**成功情境：**
- Session 啟動後 CLAUDE.md 完整載入，token 消耗 ≤ 2500
- 對應 profile 按需載入
- 8 個新 skill 在觸發詞命中時正確路由

**失敗情境：**

| 錯誤類型 | 處理方式 |
|----------|---------|
| `.ai_profile` 欄位缺失 | 套用預設值（見 global_core.md）並警告 |
| Skill 觸發詞 false positive | 輸出所觸發的 skill 名稱，使用者可手動取消 |
| Telemetry 寫入失敗 | 靜默失敗（non-blocking），不影響 ASP 主流程 |

---

## 副作用與連動

| 副作用 | 觸發條件 | 影響的系統/模組 | 驗證方式 |
|--------|---------|----------------|---------|
| CLAUDE.md 壓縮 | v4.0 升級 | 每個 session 的 context 窗口 | `wc -l CLAUDE.md` ≤ 100 |
| 新增 L0 | v4.0 升級 | session-audit.sh 等級判斷邏輯 | `ls .asp/levels/level-0.yaml` 存在 |
| 8 個新 skill 加入 SKILL.md | v4.0 升級 | SKILL.md 路由密度 | `grep -c asp-handoff SKILL.md` ≥ 1 |
| Telemetry JSONL | session_start / commit 事件 | `.asp/telemetry/*.jsonl` | `--dry-run` 輸出 valid JSON |

---

## Migration Guide（v3.7 → v4.0）

### Step 1: 安裝更新
```bash
git pull  # 取得 feature/v4-refactor 的變更
```

### Step 2: 驗證 CLAUDE.md 壓縮
```bash
wc -l CLAUDE.md  # Expected: ≤ 100
```

### Step 3: 確認新 skill 可用
```bash
ls .claude/skills/asp/asp-*.md | wc -l  # Expected: ≥ 20
```

### Step 4: 確認 L0 等級（若需要 Spike 模式）
```yaml
# .ai_profile 加入：
level: 0
# 會自動載入 spike_mode.md profile
```

### Step 5: 啟用 Telemetry（可選）
```bash
python3 .asp/scripts/telemetry/collect.py  # 開始記錄 session 事件
python3 .asp/scripts/telemetry/report.py   # 查看統計
```

---

## Backward Compatibility Matrix

| 元件 | v3.7 行為 | v4.0 行為 | 相容性 |
|------|---------|---------|------|
| 現有 13 個 skill | 照常觸發 | 照常觸發（未修改） | 完全相容 |
| 現有 20 個 profile | 照常載入 | 照常載入（+spike_mode） | 完全相容 |
| 現有 5 個 level (L1-L5) | 照常使用 | 照常使用（+L0） | 完全相容 |
| CLAUDE.md 內容 | 309 行 | 92 行（鐵則完整保留） | 鐵則不變 |
| session-audit.sh | 照常執行 | 照常執行（未修改） | 完全相容 |

---

## Done When（8 條 binary checks）

- [ ] `wc -l CLAUDE.md` 輸出 ≤ 100
- [ ] `ls .claude/skills/asp/asp-*.md | wc -l` 輸出 ≥ 20
- [ ] `ls .asp/levels/level-*.yaml | wc -l` 輸出 = 6
- [ ] `ls docs/adr/ADR-*.md | wc -l` 輸出 = 4
- [ ] `ls docs/specs/SPEC-*.md | wc -l` 輸出 = 3
- [ ] `python3 .asp/scripts/telemetry/collect.py --dry-run` exit 0 且輸出 valid JSON
- [ ] `grep -c 'asp-handoff\|asp-team-pick' .claude/skills/asp/SKILL.md` ≥ 2
- [ ] `grep -E "ADR 未定案|外部事實|敏感資訊|破壞性操作" CLAUDE.md | wc -l` = 4

---

## v4.0 不解決什麼（5 條）

1. **不取代 Superpowers skills**：ASP 和 Superpowers 互補——Superpowers 管理開發流程，ASP 管理治理約束
2. **不為 enterprise 多人協作優化**：v4.0 仍是個人/小團隊（1-3 人）定位；multi-tenant RBAC 留 v5.0
3. **不解決 AI 幻覺問題**：asp-fact-verify 提供結構化查證框架，但不保證 AI 完全準確
4. **不取代 test framework**：ASP 治理流程（TDD 先後、gate 通過），不撰寫測試代碼

---

## Edge Cases（v4.0 可能的回退情境）

- CLAUDE.md 壓縮後，第一次使用 ASP 的人可能需要讀更多層文件（CLAUDE.md → profiles → skills）
- 8 個新 skill 增加 SKILL.md router 的觸發詞密度，可能出現 false positive routing
- L0 可能被濫用，讓使用者永遠停在 Spike 模式而不升級

---

## Rollback Plan

```bash
# 回退 CLAUDE.md
cp CLAUDE.md.v3.7-backup CLAUDE.md

# 移除新 skill（保留原有 13 個）
rm .claude/skills/asp/asp-handoff.md .claude/skills/asp/asp-team-pick.md \
   .claude/skills/asp/asp-escalate.md .claude/skills/asp/asp-dev-qa-loop.md \
   .claude/skills/asp/asp-fact-verify.md .claude/skills/asp/asp-assumption-checkpoint.md \
   .claude/skills/asp/asp-bug-classify.md .claude/skills/asp/asp-change-cascade.md

# 移除 L0
rm .asp/levels/level-0.yaml .asp/profiles/spike_mode.md

# Telemetry 是純 additive，可保留或移除
```

| 項目 | 說明 |
|------|------|
| **回滾步驟** | 見上方 bash 指令 |
| **資料影響** | Telemetry JSONL 保留不影響；profile/skill 刪除後立即生效 |
| **回滾驗證** | `wc -l CLAUDE.md` 回到 ≥ 300 且 `ls asp-*.md \| wc -l` = 13 |
| **回滾已測試** | 否（回滾步驟已文件化，實際測試留 v4.1 CI） |
