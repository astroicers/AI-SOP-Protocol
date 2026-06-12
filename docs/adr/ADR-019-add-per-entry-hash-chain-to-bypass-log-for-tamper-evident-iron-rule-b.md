# [ADR-019]: Add per-entry hash chain to bypass log for tamper-evident Iron Rule B

| 欄位 | 內容 |
|------|------|
| **狀態** | `FIRM` |
| **日期** | 2026-06-11 |
| **決策者** | ASP framework maintainers |

> ⬆️ 由 `Draft` 升 `FIRM`：使用者 2026-06-11 透過 asp-plan HITL（AskUserQuestion）明確授權升級並放行實作（非 AI 自行升級，符合 ADR 狀態變更鐵則）。

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

Iron Rule B（鐵則之一，registry `exempt: true`）保障 bypass log（`.asp-bypass-log.ndjson`）的 **append-only 稽核完整性** — 任何 ASP 流程跳過 gate/檢查都必須在此留痕，且記錄不可被事後移除。

TD-002（2026-06-08）已修正一個結構性缺陷：bypass log 是 **gitignored（local-only）**，所以 git/HEAD baseline 永遠為空、無法偵測截斷。改用 `.asp-bypass-log.hwm` sidecar 記錄歷史行數高水位（HWM），`awk END{print NR}` 計數，任何低於 HWM 的行數 ⇒ 記錄被移除 → BLOCKER。

但 TD-002 自己明載**兩個 line-count heuristic 無法偵測的殘留**（session-audit.sh:91-93 註解）：
1. **等量替換（equal-count replacement）**：移除一筆真記錄、補一筆假記錄 — 行數不變，HWM 偵測失效。
2. **HWM sidecar 自身被竄改**：直接改 `.hwm` 的數字，偵測基準即被改寫。

這兩個漏洞讓「無痕抹除一筆 bypass 稽核」的成本低到只需改一個數字。對一條鐵則而言，稽核軌跡的完整性保證不應建立在「行數沒變」這種脆弱不變量上。需要把完整性錨定到 **記錄內容本身**。

---

## 評估選項（Options Considered）

### 選項 A：per-entry hash chain（每筆 entry 內嵌 prev-hash + 自身 hash）

每筆 NDJSON entry 增加 `prev`（前一筆的 `h`）與 `h`（本筆規範化內容的 sha256）。session-audit 重算整條 chain，任一筆 `h` 不符或 `prev` 斷裂 → BLOCKER。HWM 保留作截斷的快速路徑（互補）。

- **優點**：等量替換可偵測（改任一筆內容 → 其 `h` 變 → 後續 `prev` 全斷）；HWM 不再是單一信任點；只依賴 `sha256sum`（系統工具，無新依賴）；NDJSON 格式相容（加欄位）。
- **缺點**：寫入端（asp-ship 記 bypass）需算 hash；既有 `.ndjson` 需遷移（補算 chain）；entry schema 變更。
- **風險**：純本地、無 secret → 知道機制的攻擊者可**重算整條一致的假 chain**（見下方威脅模型）。

### 選項 B：HMAC with machine-local secret key

每筆 entry 用本機 secret（如 `~/.claude/.bypass-hmac-key`）做 HMAC，攻擊者無 key 不能偽造。

- **優點**：理論上能防偽造（若 key 保密）。
- **缺點**：ASP 無 secret 管理基礎設施；key 存 `~/.claude` 下，**與 AI/操作者同等可讀** → 在「本地 agent 自我竄改」威脅模型下 key 不構成秘密，防護等於零。
- **風險**：製造「有安全感」的假象（security theater），比誠實的 tamper-evidence 更糟。

### 選項 C：把 chain tip 錨定到 git-tracked 檔（外部信任錨）

每次新增 bypass，把 chain tip hash 寫進一個 git-tracked 檔並 commit，靠 git 歷史 + Iron Rule A 保護。

- **優點**：提供真正的外部信任錨，可防完整重算（攻擊者無法同步改寫 git 歷史而不留痕）。
- **缺點**：把 local-only 的 bypass log 半綁回 git（洩漏「有幾筆 bypass」的 metadata，與 TD-002「local-only」決策直接張力）；每筆 bypass 強制一次 commit，流程沉重。
- **風險**：超出本次收尾範圍，是更大的架構權衡。

### 選項 D：維持現狀（HWM only），接受殘留

- **優點**：零工作量。
- **缺點**：鐵則的完整性保證持續建立在脆弱的行數不變量上；TD-002 殘留無限期遺留。
- **風險**：「改一個數字即可無痕抹除鐵則稽核」的攻擊面持續存在。

---

## 決策（Decision）

選擇 **選項 A（per-entry hash chain）**，並**誠實界定威脅行為者與威脅模型**：

**威脅行為者（G1 F-02）**：主要是對所有專案檔有讀寫權的**本地行為者**（ASP 流程/AI agent 自身、或在本機的操作者），而非無檔案存取權的遠端攻擊者。這個界定是選項 B（HMAC）被否決的關鍵前提 —— secret 存 `~/.claude` 下與威脅行為者同等可讀，故 HMAC 不構成秘密，是 security theater。

**Hash chain 提供 tamper-EVIDENCE，不是 tamper-PROOF。** 它把「無痕移除一筆 bypass 記錄」的成本，從 TD-002 現狀的「改一個 HWM 數字」提高到「重算自竄改點起的整條 chain」。它能偵測：
- 天真/意外的記錄移除或截斷（chain 斷裂）；
- 等量替換（改內容 → hash 不符）；
- 單獨竄改 HWM（chain 提供與 HWM 獨立的第二驗證）。

它**不聲稱**防禦「知道機制、且對所有檔有寫入權的攻擊者完整重算假 chain」 — 在純本地、無外部信任錨、AI 自身可讀寫一切的環境下，這個保證在密碼學上不可能（選項 B 的 key 同樣可讀，是假保證）。要達成需外部信任錨（選項 C，git/遠端），列為後續追蹤的獨立權衡。

選 A 不選 B：B 在本威脅模型下是 security theater。
選 A 不選 C：C 與 local-only 決策張力大、流程沉重，超出 TD-002 收尾範圍；但其外部錨思路保留為後續。
選 A 不選 D：D 讓鐵則完整性持續依賴脆弱不變量。

A 是「在 local-only 約束內可達的最強 tamper-evidence」，且為 C 鋪路（chain tip 已具備，未來只需把 tip 外部錨定）。

---

## 後果（Consequences）

**正面影響：**
- 等量替換與單點 HWM 竄改可被偵測，收尾 TD-002 兩項已記殘留。
- 完整性錨定到記錄內容（hash），不再單靠行數。
- chain tip 為未來外部錨定（選項 C）預留升級點，無需重設計。

**負面影響 / 技術債：**
- bypass-log entry schema 變更（加 `prev`/`h`）→ 既有 `.ndjson` 需一次性遷移（補算 chain）。
- 寫入端（asp-ship bypass 記錄路徑、`make asp-bypass-record`）需計算並串接 hash。
- **canonical 假陽性風險（G1 F-01）**：hash 格式（key 排序/緊湊/串接/hex 大小寫）若寫入/驗證/遷移三端不一致，會對**正常** log 觸發假陽性 BLOCKER — 此影響頻率遠高於攻擊。SPEC-012 強制抽共用 `bypass-hash.sh` 單一實作點消除此風險。
- **容錯降級殘留（G2 FIND-2）**：為避免升級假陽性需對純舊 log 容錯，但「刪 hash 欄降級回容錯」會還原攻擊面 → 以 HWM sidecar `chained=1` marker 嚴格化（啟用後缺 hash 即 BLOCKER）緩解；惟 marker 本地仍可竄改 → 非 tamper-proof（同下方選項 C 限制）。
- `tech-debt: MED` — 不防「知道機制的完整重算」；真正 tamper-proof 需外部信任錨（選項 C），本 ADR 範圍外。

**後續追蹤：**
- [ ] SPEC：hash chain 的規範化（canonical）格式、遷移腳本、session-audit 驗證邏輯、asp-ship 寫入端
- [ ] 既有 `.asp-bypass-log.ndjson`（2 筆）遷移補算 chain
- [ ] 評估選項 C（chain tip 外部錨定）作為獨立 ADR — 需重新權衡 local-only vs tamper-proof
- [ ] 升級 Iron Rule B 註解 + rule-registry desc 反映 hash-chain

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 等量替換偵測 | 100%（改一筆內容保持行數 → BLOCKER） | 新測試 `test_iron_rule_b_hashchain.sh` | 實作完成時 |
| chain 斷裂偵測 | 100%（竄改任一筆 → BLOCKER） | 同上 | 實作完成時 |
| 正常 append 無誤報 | 0 false positive | 同上 + `make test` 全綠 | 實作完成時 |
| 既有測試零回歸 | bash + pytest 全綠 | `make test` | 實作完成時 |

> 重新評估條件：若決定採用外部信任錨（選項 C），或 bypass-log 改為非 local-only，本 ADR 的威脅模型需重審。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 實作 SPEC：SPEC-012（bypass log hash chain）
- 參考：TD-002（`docs/tech-debt-2026-06-08.md`，HWM sidecar 與已記殘留）；Iron Rule B（`.asp/hooks/session-audit.sh` §Iron Rule B）；rule-registry `IRON-B`

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | 本 session 實作（main，待 commit）；`tests/test_iron_rule_b_hashchain.sh` **15/15 PASS**（P1/P2/N1–N7/B1/B2 + 整合）；`make test` 全綠（bash 42/42、pytest 16/16），含既有 7 個 HWM 截斷測試零回歸 |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（使用者經 asp-plan HITL 授權升 FIRM 並放行實作） |
| **驗證摘要** | hash-chain 偵測等量替換 / chain 斷裂 / HWM 竄改獨立性 / 容錯降級繞過；正常 append 與空 log 無誤報；既有 7 個 HWM 截斷測試零回歸 |
