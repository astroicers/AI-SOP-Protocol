#!/usr/bin/env bash
# .asp/checks/vendor-verify.sh — vendored 檢查本體來源對帳(asp-gate.yaml id: vendor-verify)
#
# 動機(asp-ng issue #43):消費端 repo 以 vendoring 持有 asp-ng 的渲染物與檢查本體,
# 兩側之間原本無任何對帳——上游改了消費端不知道、消費端被就地改也沒人發現。
#
# 本檢查負責「本地竄改偵測」:VENDOR.lock 記錄每份 vendored 檔的來源與 vendoring
# 當下的 sha256,實際檔案與記錄不符即紅。**上游變更偵測**是另一格(比的是「lock
# 記錄 vs 上游現況」),住在同目錄的 `vendor-upstream.sh`——它需要跨 repo 讀取,
# 故取得管道可換而判定不換。原定「asp-ng 轉 public 後 raw 比對」之路因 2026-08-25
# 人裁維持 free/private 而失效(ADR-000 §14 P1 列),見該檔檔頭。
#
# 用法:vendor-verify.sh [repo 根目錄]
#   缺參數取 ${ASP_GATE_PROJ:-.};無 VENDOR.lock(未 vendoring 之 repo,含 asp-ng
#   自身作為上游)→ exit 200(skip 契約)。
#
# VENDOR.lock 格式(空白分隔,# 為註解):
#   <檔名> <上游 repo> <上游路徑> <sha256> [<ref>]
# 檔名相對於 VENDOR.lock 所在目錄;第五欄 <ref> 為上游版本座標(tag/commit),
# 上游對帳(`vendor-upstream.sh`)非有它不可,故自 ASP_VENDOR_REF_DEADLINE 起判紅。
set -u

ROOT="${1:-${ASP_GATE_PROJ:-.}}"
LOCK="$ROOT/.asp/checks/VENDOR.lock"

if [ ! -f "$LOCK" ]; then
  echo "⏭  vendor-verify: 無 VENDOR.lock($LOCK),略過"
  exit 200
fi

DIR="$(dirname "$LOCK")"
FAIL=0
COUNT=0
NO_REF=""
REFS=""
NAMES=""

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  # 以 read 分欄:`set -- $line` 未加引號會讓含 glob 的行依「執行時 CWD」展開,
  # 使竄改偵測的判定取決於它從哪個目錄被呼叫(補審 HIGH-4)。
  # 第五欄 <ref> 為選填的**版本座標**(#43):四欄格式沒有任何版本資訊,消費端
  # 無從得知自己「從哪一版 vendored 而來」——那正是本地竄改偵測綠燈、而上游早已
  # 修補的結構原因。向後相容:四欄仍可解析(現存消費端的 lock 就是四欄),
  # 但會提示補 ref。放寬到五欄不是放棄欄數檢查,第六欄照樣紅。
  read -r f1 f2 f3 f4 f5 f6 <<< "$line"
  set -- "$f1" "$f2" "$f3" "$f4"
  if [ -n "$f6" ] || [ -z "$f4" ]; then
    echo "❌ vendor-verify: VENDOR.lock 格式錯誤(需四或五欄:檔名 上游repo 上游路徑 sha256 [ref]):$line"
    FAIL=1
    continue
  fi
  name="$1"; upstream_repo="$2"; upstream_path="$3"; want="$4"; ref="$f5"
  NAMES="$NAMES $name"
  if [ -z "$ref" ]; then
    NO_REF="$NO_REF $name"
  else
    case " $REFS " in *" $ref "*) ;; *) REFS="$REFS $ref" ;; esac
  fi
  target="$DIR/$name"
  COUNT=$((COUNT + 1))

  if [ ! -f "$target" ]; then
    echo "❌ vendor-verify: 缺檔 $name(來源 $upstream_repo:$upstream_path)"
    FAIL=1
    continue
  fi
  got="$(sha256sum "$target" 2>/dev/null | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "❌ vendor-verify: $name sha256 不符(來源 $upstream_repo:$upstream_path)"
    echo "   記錄 $want"
    echo "   實際 $got"
    echo "   → 就地改動請改上游後重新 vendoring 並更新 VENDOR.lock"
    FAIL=1
  fi
done < "$LOCK"

# lock 存在即代表該 repo 有 vendoring;零條目屬異常——清空 lock 原本回報 ✅ rc=0,
# 是停用本檢查最省力的手法且看起來像通過(補審 BLOCKER-3)。
if [ "$COUNT" -eq 0 ] && [ "$FAIL" = 0 ]; then
  echo "❌ vendor-verify: VENDOR.lock 存在但零條目——清空 lock 等同停用檢查;無 vendoring 請刪除 lock 檔"
  exit 1
fi
# ---- 對帳器自身亦須在 lock 內(#43 AC-4)----
# 對帳器本身就是 vendored 物。它不列進自己檢查的清單時,竄改它即可一次停用整套
# 對帳,而且不留痕跡——「守衛自己不受守衛」是這類機制最短的繞道。
for _self in vendor-verify.sh vendor-upstream.sh; do
  if [ -f "$DIR/$_self" ]; then
    case " $NAMES " in
      *" $_self "*) ;;
      *)
        echo "❌ vendor-verify: 對帳器自身 $_self 不在 VENDOR.lock 內——竄改它即可全面停用對帳"
        echo "   → 補一列:$_self <上游 repo> .asp/checks/$_self <sha256> <ref>"
        FAIL=1
        ;;
    esac
  fi
done

# ---- 第五欄 ref:寬限期後判紅(#43)----
# 四欄是既有格式,升級不得讓現存消費端當場全紅,故先提示、逾期才紅。但這一欄
# 不是裝飾:沒有版本座標就做不了上游對帳(AC-3),而「做不了上游對帳」正是本地
# 綠燈、上游早已修補的結構成因。寬限期是給回填用的,不是給豁免用的。
REF_DEADLINE="${ASP_VENDOR_REF_DEADLINE:-2026-09-30}"
REF_OVERDUE=0
if [ -n "$NO_REF" ]; then
  TODAY="$(date -u -d "${ASP_VENDOR_NOW:-now}" +%Y-%m-%d 2>/dev/null || true)"
  if [ -n "$TODAY" ] && [ "$TODAY" \> "$REF_DEADLINE" ]; then
    REF_OVERDUE=1
    FAIL=1
  fi
fi

if [ "$FAIL" = 0 ]; then
  # ref 記了卻不顯示等於沒記——人要看得到自己停在哪一版
  echo "✅ vendor-verify: $COUNT 份 vendored 檔與來源記錄一致${REFS:+(上游版本:${REFS# })}"
fi
if [ -n "$NO_REF" ]; then
  if [ "$REF_OVERDUE" = 1 ]; then
    echo "❌ vendor-verify: 下列條目缺第五欄 ref(版本座標),寬限期 $REF_DEADLINE 已過:${NO_REF# }"
    echo "   → 回填 vendoring 當下的上游 tag 或 commit sha;沒有它就做不了上游變更偵測(#43 AC-3)"
  else
    echo "ℹ️  vendor-verify: 下列條目缺第五欄 ref(版本座標),無法做上游對帳:${NO_REF# }"
    echo "   → 寬限期至 $REF_DEADLINE,逾期判紅"
  fi
fi
exit "$FAIL"
