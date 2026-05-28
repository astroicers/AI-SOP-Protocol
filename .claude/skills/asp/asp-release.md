---
name: asp-release
description: |
  ASP Release skill — semantic versioning, CHANGELOG auto-update, and Release PR.
  Use when: preparing a release, bumping version, tagging, or creating a release PR.
  Triggers: release, 發布, 版本, version bump, tag, changelog, CHANGELOG.
---

# asp-release — ASP 版本發布 Skill

> **目的**：從 git log 自動判斷版本 bump → 更新 CHANGELOG.md → 建立 Release PR（Draft）
>
> **HITL 原則**：AI 推薦版本並準備所有變更，**人類審查後才能 merge + push tag**

---

## Step 1 — 判斷版本 Bump

讀取 `CHANGELOG.md` 最新版本號（格式 `## [X.Y.Z]`），再讀取 git log since that version：

```bash
LAST_TAG=$(grep -m1 '## \[' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
git log --oneline "v${LAST_TAG}..HEAD" 2>/dev/null || git log --oneline -20
```

### Bump 規則（Conventional Commits）

| 條件 | Bump | 範例 |
|------|------|------|
| 任何 commit 含 `BREAKING CHANGE` 或 `feat!:` | **major** | `feat!: redesign API` |
| 有 `feat:` commit（無 BREAKING） | **minor** | `feat(inbox): add dedup` |
| 只有 `fix:` / `chore:` / `docs:` | **patch** | `fix(jq): correct todate` |
| 只有 meta commits（版本 bump、CI） | **patch** | 最小遞增 |

**輸出推薦版本**：
```
目前版本：X.Y.Z
推薦版本：X.Y.(Z+1) [patch] / X.(Y+1).0 [minor] / (X+1).0.0 [major]
理由：[列出關鍵 commits]
```

**等待人類確認版本號後再繼續。**

---

## Step 2 — 更新 CHANGELOG.md

將 `## [Unreleased]` 段落（若存在）重命名為 `## [NEW_VERSION] - YYYY-MM-DD`，
或從 git log 自動產生新段落。

格式：
```markdown
## [X.Y.Z] - 2026-05-28

### Added
- feat(P1): Task Inbox — inbox-ingest + session-audit integration

### Fixed
- fix(jq): correct todate syntax in inbox-ingest.sh

### Changed
- ...
```

提取規則：
- `feat:` → **Added**
- `fix:` → **Fixed**
- `docs:` → **Documentation**
- `chore:` / `ci:` → **Chore**
- `refactor:` → **Changed**
- `BREAKING CHANGE` → **⚠️ Breaking Changes**（置頂）

---

## Step 3 — 建立 Release PR（Draft）

```bash
# 建立 release branch
git checkout -b "release/v${NEW_VERSION}"

# Stage CHANGELOG.md 變更
git add CHANGELOG.md
git commit -m "chore(release): bump to v${NEW_VERSION}"

# Push branch
git push origin "release/v${NEW_VERSION}"

# 建立 Draft PR
gh pr create --draft \
  --title "Release v${NEW_VERSION}" \
  --base main \
  --body "$(cat <<'BODY'
## Release v${NEW_VERSION}

### Summary
[從 CHANGELOG 提取]

### Checklist
- [ ] CHANGELOG.md 已更新
- [ ] 版本號正確
- [ ] 所有測試通過（`make test`）
- [ ] 健康審計通過（`make audit-quick`）

### After Merge
1. 人工執行：`git tag v${NEW_VERSION} -m "Release v${NEW_VERSION}"`
2. 人工執行：`git push origin v${NEW_VERSION}`
3. （可選）在 GitHub 建立 Release

> 此 PR 由 asp-release skill 自動建立，需人類審查後 merge。
BODY
)"
```

---

## Step 4 — 輸出摘要

```
✅ Release PR 已建立：
   版本：v${OLD_VERSION} → v${NEW_VERSION}
   Branch：release/v${NEW_VERSION}
   PR：[Draft] Release v${NEW_VERSION}

下一步（人工）：
1. 審查 CHANGELOG.md 內容
2. 確認測試/審計通過
3. Merge PR
4. git tag v${NEW_VERSION} && git push origin v${NEW_VERSION}
```

---

## 鐵則

| 禁止 | 原因 |
|------|------|
| `git push origin main` | 鐵則：永遠禁止 push to main |
| `gh pr merge` | HITL：AI 不得自動 merge |
| `git tag` + `git push tag` | 發布 tag 由人類執行，確保版本最終確認 |

---

## 使用範例

```
用戶：/asp-release
ASP：讀取 git log... 推薦 patch bump: v4.1.1 → v4.1.2
     [列出 commits]
     確認版本號？

用戶：確認，v4.1.2

ASP：更新 CHANGELOG.md...
     建立 release/v4.1.2 branch...
     開 Draft PR...
     ✅ PR #42 已建立
```