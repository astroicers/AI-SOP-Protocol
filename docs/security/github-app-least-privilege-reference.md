# GitHub App 最小權限樣式 — ASP security reference

> 蒸餾自 asp-operator `ADR-001`（PAT → GitHub App，ADR-032 Locus D-B）。
> asp-operator 已凍結（ADR-032）；ASP 本身目前**無自有 bot**。本檔為「未來 ASP 若長出需要機器身分的自動化（CI bot、跨 repo 服務）」時的可複用安全原則與教訓。

## 原則

當自動化流程需以**機器身分**（非人類帳號）觸碰 repo 時：

1. **用 GitHub App，不用 classic PAT。** PAT 是帳號全域、全 scope、長效、綁個人身分——爆炸半徑大。App 有獨立身分與逐 repo installation。
2. **最小權限 installation token。** 只給實際需要的 scope（asp-operator 例：`contents:write` + `issues:read`，**明確無** `pull_requests`／`admin`），與「該服務不可做什麼」的鐵則對齊（operator 鐵則：只寫 inbox、不 merge PR）。
3. **短效 token（~1h），in-workflow 鑄造。** 用 `actions/create-github-app-token` 於 workflow 內即時換 token，不存長效憑證。
4. **opt-in guard。** 逐 repo 以設定（asp-operator 例：`.ai_profile operator.enabled`）明確啟用，預設不作用。
5. **私鑰永不進 git。** 存 `~/secrets/`（或等效秘密庫），檔案模式 600。

## 教訓（為何重要）

最小權限 + 短效 + opt-in 把「一個對外常駐的機器身分」的爆炸半徑壓到最小——這正是 ADR-012 **T-14**（external-artifact → autopilot trust）威脅的容器邊界。ADR-032 凍結 operator 時，卸載 App、封存私鑰即依此原則使殘留攻擊面歸零。

**相關**：asp-operator ADR-001（原始決策，已隨 repo 凍結/archive）、ADR-032、[threat-model T-14](./threat-model-v4.0.md)。
