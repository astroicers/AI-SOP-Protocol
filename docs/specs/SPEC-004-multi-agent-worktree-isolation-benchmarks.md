# SPEC-004 Benchmarks — Multi-Agent Worktree 效能實測

> ℹ️ **本檔為 `SPEC-004-multi-agent-worktree-isolation` 的效能交付子文件（Done When #15），非獨立 SPEC**。
> （2026-06-08 TD-003：由 `SPEC-004-benchmarks.md` 更名，以消除「兩個獨立 SPEC-004」的命名歧義，並如實標示其交付物身分。）
>
> SPEC-004 Done When #15 交付物。提供基準環境的實測數據與離開基準環境時的偏差說明。
>
> **重要原則**：基準環境內 NFR 數字必須達標；離開基準環境時，**功能正確性仍需保證**，但 NFR 指標不適用。

---

## 1. SPEC NFR 與實測對照

| 指標 | SPEC budget | 量測方法 | 本次實測（基準環境） | 結果 |
|------|-------------|---------|----------------|------|
| dispatch p95（單一 worktree） | < 5 s | `tests/perf/test_spec_004_perf.sh`，10 樣本 | **0.021 s** | ✅ 超出 240× |
| converge p95（單一 task，無衝突） | < 10 s | 同上 | **0.015 s** | ✅ 超出 660× |
| 10 worker × 1000 entry 並行壓測（S18） | NDJSON 完整、jq 可解析 | `tests/perf/test_spec_004_perf.sh`（不可 `--skip-stress`） | **10,000 行 / 0 invalid / 3.657 s** | ✅ pass |
| Stale worktree GC（10 stale）| < 2 s | manual | （未獨立量測，session-audit 整合測試擔保 hook 路徑 < 2s）| ⏳ 留 v4.1.0 補 |

---

## 2. 基準環境（本次量測）

| 維度 | SPEC §基準環境設定 | 本次實際 |
|------|------------------|---------|
| OS | Linux x86_64 / Ubuntu 22.04 LTS+ 或 macOS 13+ | Ubuntu on WSL2，kernel 5.15.167.4-microsoft-standard-WSL2 |
| 檔案系統 | ext4 / APFS（**不**接受 NTFS / NFS） | ext4 在 WSL2 Linux 檔案系統路徑（`/home/ubuntu`，**非** `/mnt/c`） |
| 磁碟 | 本地 SSD，可用 ≥ 5 × repo size | 本地（VHD），可用 881 GB／repo 9 MB ≈ 100,000× 餘裕 |
| CPU / RAM | ≥ 4 cores / ≥ 8 GB | 16 cores / 62 GB（過於充裕） |
| Repo 大小 | ≤ 500 MB checkout | 9 MB（遠小於上限）|
| git 版本 | ≥ 2.20 | 2.34.1 |
| bash 版本 | ≥ 4.4 | 5.1.16 |
| jq 版本 | ≥ 1.6 | 1.6 |

> ⚠️ **過於充裕的環境警示**：本次量測的硬體（16C/62G/SSD/小 repo）顯著優於 SPEC §基準環境最低要求。實際數字（毫秒級）反映的是 **理想上限**，不是普通開發機的可預期表現。
>
> **保守估計推論**：在 SPEC §基準環境最低配置（4C/8G/SATA SSD/500MB repo）上，效能可能慢 5-10×：dispatch p95 ~ 0.1-0.2 s、converge p95 ~ 0.1-0.15 s。仍遠低於 SPEC budget。

---

## 3. 離開基準環境的行為

SPEC §基準環境明確列出三種**不適用 NFR** 但仍須保證功能正確的環境。本節記錄已知狀況：

| 環境 | 預期 NFR 影響 | 功能正確性 |
|------|-------------|----------|
| WSL2 跨 `/mnt/c/...`（NTFS via 9P） | 慢 10-100×，dispatch 可能超過 5 s | git worktree 仍能建立；audit log 寫入仍 atomic（O_APPEND 跨 9P 行為由 host filesystem 決定，**v4.1 不擔保**） |
| 網路掛載（NFS / SMB） | 慢 50-1000×，rebase / merge 可能超時 | 同上；S18 並行寫入可能因 NFS 缺乏 POSIX O_APPEND atomicity 出現 interleaved writes（**會 fail**）|
| 大型 repo（≥ 5 GB checkout） | dispatch 可能超過 5 s（git worktree add 對大 repo 較慢） | 功能正確 |
| LFS 巨檔 | dispatch 可能慢 10× | 功能正確；worktree 不重複下載 LFS object（git ≥ 2.42）|

> 用戶責任：偏離基準環境時，使用前先跑 `bash tests/perf/test_spec_004_perf.sh --runs 3 --skip-stress` 量測自己環境的數字，並評估是否可接受。

---

## 4. 量測方法

### 4.1 dispatch / converge p95

```bash
bash tests/perf/test_spec_004_perf.sh --runs 10
```

每次量測都是新建 git repo + 1 個 task manifest，避免 cache 影響：

- **dispatch**：建 1 個 worktree，含 ASP_AUDIT_ROOT 驗證、scope 重疊偵測、git worktree add、manifest 持久化、telemetry 寫入
- **converge**：rebase task branch onto base、merge --no-ff、worktree remove、telemetry 寫入

p95 用 nearest-rank percentile（10 樣本中第 10 名）。

### 4.2 S18 並行壓測

```bash
bash tests/perf/test_spec_004_perf.sh        # 預設啟用
bash tests/perf/test_spec_004_perf.sh --skip-stress    # 開發時跳過
```

10 個 background subshell，每個迴圈 1000 次呼叫 `audit-write.sh bypass`。驗證：

1. 最終 NDJSON 行數 == 10,000（無 truncation）
2. `jq -r -c .` 對每行可解析（無 interleaved writes）

POSIX `O_APPEND` 對 < `PIPE_BUF=4096 bytes` 的 write 是 atomic（Linux）。`audit-write.sh` 拒絕 ≥ 4096 bytes 的 payload，因此單次 append 必定原子。

---

## 5. JSON 報告格式

`--json` 模式輸出機器可讀格式，供 CI / dashboard 整合：

```json
{
  "runs": 10,
  "dispatch": {"p50": 0.019, "p95": 0.021, "max": 0.021},
  "converge": {"p50": 0.013, "p95": 0.026, "max": 0.026},
  "stress": {"result": "pass", "expected": 10000, "actual_lines": 10000,
             "invalid_json": 0, "duration_seconds": 3.406}
}
```

退出碼：
- `0`：dispatch p95 < 5 s 且 converge p95 < 10 s 且 stress pass（或 skipped）
- `1`：任一指標未達標

可直接接入 release gate：`bash tests/perf/test_spec_004_perf.sh --json > perf.json && cat perf.json`

---

## 6. 何時應重跑 benchmark

- ✅ Release 前（v4.1.0、v4.2.0、…）
- ✅ 改動 dispatch.sh / converge.sh / audit-write.sh 任一 hot path
- ✅ 改動 telemetry 結構（多寫入欄位 → 影響 single-call 開銷）
- ✅ 升級 git 主版本
- ❌ 改 docs / 改測試 / 改 .gitignore（不影響 hot path）

---

## 7. 歷史紀錄

| 日期 | Commit | dispatch p95 | converge p95 | S18 stress | 量測者 |
|------|--------|-------------|-------------|----------|-------|
| 2026-05-10 | 5a91b8e (B6) | 0.021 s | 0.015 s | pass (10,000/0 in 3.66s) | astroicers @ WSL2 16C/62G |

未來每次跑 benchmark，append 一行到本表。Commit message 中也記錄 perf 摘要。
