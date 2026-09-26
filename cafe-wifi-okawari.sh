#!/bin/zsh
# キャプティブポータルに戻されていたら Wi2 のワンタップ認証（規約同意）で再認証する。
# 対象は Wi2 の無料 Wi‑Fi（ドトール・スタバ等）。launchd から定期実行される。詳細は DESIGN.md。
set -u
zmodload zsh/datetime   # EPOCHSECONDS

WI2=https://service.wi2.ne.jp
ST=$HOME/Library/Caches/cafe-wifi-okawari   # 連続失敗回数と次回試行時刻
log() { print -r -- "$(strftime '%F %T' $EPOCHSECONDS) $*" }

# -q で ~/.curlrc を無視し、実行条件（証明書検証・リダイレクト非追従）を固定する。-q は先頭必須。
curl=(/usr/bin/curl -q -s)

# 0=認証済み 1=ポータルに捕捉されている 2=無接続・判定不能（HTTP 障害など）
state() {
  local r
  r=$("${curl[@]}" -m 5 -w '\n%{http_code}' http://captive.apple.com/hotspot-detect.html) || return 2
  case ${r##*$'\n'} in
    200) [[ $r == *'<TITLE>Success</TITLE>'* ]] && return 0 || return 1 ;;
    30[1237]) return 1 ;;
    *) return 2 ;;
  esac
}

state; case $? in
  0) rm -f "$ST"; exit 0 ;;
  2) exit 0 ;;
esac

# 失敗が続いているときは 30秒→60秒→…→最大30分 と間隔を空ける。
n=0 next=0
[[ -r $ST ]] && read -r n next < "$ST"
(( EPOCHSECONDS < next )) && exit 0

jar=$(mktemp) || exit 1
trap 'rm -f "$jar"' EXIT

# ポータルとの通信は HTTPS のみ・証明書検証あり・リダイレクト非追従。
c=("${curl[@]}" -m 10 --proto '=https' -b "$jar" -c "$jar")

# Wi2 の正規サーバーが無料 Wi‑Fi のランディングへ 302 を返したときだけ先へ進む。それ以外は対象外の網。
[[ $("${c[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "$WI2/wi2auth/redirect") \
   == "302 $WI2/freewifi/"*/landing.html ]] && grep -q session_id "$jar" || exit 0

res=$("${c[@]}" -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  --data '{"login_method":"onetap","login_params":{"agree":"1"}}' "$WI2/wi2auth/xhr/login")
[[ $res == *'"result":true'* ]] && api=ok || api=ng

sleep 2
state && probe=ok || probe=ng

# API の結果と疎通回復を分けて記録する（OS のポータル画面などによる復旧と区別できる）。
if [[ $api == ok && $probe == ok ]]; then
  rm -f "$ST"
  log "re-authenticated api=ok probe=ok"
  exit 0
fi

(( n++, wait = 30 << (n > 7 ? 6 : n - 1), wait > 1800 && (wait = 1800) ))
print -r -- "$n $(( EPOCHSECONDS + wait ))" > "$ST"
# 同じ失敗の繰り返しは 1,2,4,8,… 回目だけ記録する。疎通も戻っていなければ固定文言で通知する。
if (( !(n & (n - 1)) )); then
  log "login failed x$n api=$api probe=$probe res=${res[1,200]}"
  [[ $probe == ng ]] && /usr/bin/osascript -e \
    'display notification "Wi-Fi の自動再認証に失敗しました。ブラウザで接続してください。" with title "cafe-wifi-okawari"'
fi
exit 1
