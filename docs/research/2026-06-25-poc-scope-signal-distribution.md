<!-- Last Updated: 2026-06-25 | Status: Draft | Audience: Maintainers -->

# POC 報告：scope 信號閾值校準（ADR-025 / 借鏡點 ④）

探針：`docs/research/poc-scope-signal-distribution.sh`（純 bash/git，**不接 Makefile/CI/tests**，spike 慣例同 poc1/poc2/poc-skill-lint/poc-megaskill）。

## 0. 結論（TL;DR）

用 ASP 自身近 40 個 non-merge commit 的「每 commit 改檔數」分佈校準 ④ 的 scope 信號：

```
SCOPE_DIST: total=40  <=8檔=29  >8檔=11  max=142檔
```

→ (1) 閾值 **>8 檔** 把「正常工作（29/40, 72.5%）」與「可能多任務（11/40）」分開；(2) **max=142 檔** 證實 ASP 有合法大 commit（installer / v5 批次 / 大合併）→ scope 信號**必須 advisory，不能硬 gate**。

## 1. 分佈明細（改檔數 → commit 數）

| 改檔數 | commit 數 |
|--------|----------|
| 1 | 8 |
| 2 | 5 |
| 3 | 3 |
| 4 | 3 |
| 5 | 3 |
| 6 | 5 |
| 7 | 2 |
| 9 | 2 |
| 14–19 | 5 |
| 26 | 1 |
| 47 | 1 |
| **142** | 1 |

- ≤8 檔：29（正常單一任務工作）。
- >8 檔：11（大批次——多為 installer / v5 重構 / 大合併，**合法**）。

## 2. 對 ADR-025 的回饋

- **閾值 >8**：advisory 觸發點。borrow addyosmani「scope 過大＝警訊」精神；**不照搬**二手「≤5 檔」（FC-005，一手未載；且 ASP 分佈顯示 ≤5 會過度觸發）。
- **必 advisory 不可硬 gate**：max=142 證實合法大 commit 存在 → 硬擋會誤傷、撞 ADR-020 偽硬 gate。
- **決策 B（增強 asp-ship Step 2）**：Step 2 已用 `git diff --stat`，加一條閾值 advisory 即可，零新機制/層（ADR-010 通過）。

## 3. 未驗 / 界定

- 閾值 8 為當下校準，分佈漂移時需重校（advisory 容忍誤差）。
- 只量測「改檔數」；行數維度可作未來增強（本 POC 不含）。
- 「拆得對不對」仍需人審——advisory 只 nudge，不判斷。

## 附錄：重現

```bash
bash docs/research/poc-scope-signal-distribution.sh 40 8
# 預期：印分佈 + SCOPE_DIST total=40 <=8檔=29 >8檔=11 max=142檔 + exit 0
```
