#!/bin/zsh
# キャプティブポータルに戻されていたら Wi2 のワンタップ認証（規約同意）で再認証する。
# 対象は Wi2 の無料 Wi‑Fi（ドトール・スタバ等）。launchd から定期実行される。詳細は DESIGN.md。
set -u
zmodload zsh/datetime   # EPOCHSECONDS

WI2=https://service.wi2.ne.jp
ST=$HOME/Library/Caches/cafe-wifi-okawari            # 連続失敗回数・次回試行時刻・接続先
PD=$HOME/Library/Caches/cafe-wifi-okawari.pending    # 捕捉中でまだ同意していない接続先
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"   # 利用者が自分で同意した接続先（1行1つ）
log() { print -r -- "$(strftime '%F %T' $EPOCHSECONDS) $*" }
# 通知する。$1=日本語 $2=英語。macOS の優先言語が日本語なら $1、それ以外は $2。
# 引数はコードに書いた固定文言だけにする（外部入力を AppleScript に渡さない）。
notify() {
  local m=$2
  [[ $(/usr/bin/defaults read -g AppleLanguages 2>/dev/null | /usr/bin/awk -F'"' 'NF > 1 { print $2; exit }') == ja* ]] && m=$1
  /usr/bin/osascript -e "display notification \"$m\" with title \"cafe-wifi-okawari\""
}

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

# 接続先の識別子（既定ゲートウェイの MAC。取れなければ IP）を net に入れる。
netid() {
  local gw
  gw=$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/gateway:/{print $2}')
  net=$(/usr/sbin/arp -n "$gw" 2>/dev/null | /usr/bin/awk '{print $4}')
  [[ $net == *:*:* ]] || net=$gw
}

state; s=$?
(( s == 2 )) && exit 0
if (( s == 0 )); then
  rm -f "$ST"
  # 捕捉されていた接続先が認証済みになった = 利用者が自分で同意した。以後この接続先だけ自動で再認証する。
  if [[ -r $PD ]]; then
    netid
    if [[ -n $net && $(<"$PD") == "$net" ]] && ! grep -qxF -- "$net" "$KN" 2>/dev/null; then
      mkdir -p "${KN:h}" && print -r -- "$net" >> "$KN" && log "consent recorded net=$net"
    fi
    rm -f "$PD"
  fi
  exit 0
fi

netid
[[ -n $net ]] || exit 0
grep -qxF -- "$net" "$KN" 2>/dev/null && known=1 || known=0
# 未同意の接続先で、すでに一度確かめたものは、利用者の同意を待つだけ（通信しない）。
(( known )) || [[ ! -r $PD || $(<"$PD") != "$net" ]] || exit 0

jar=$(mktemp) || exit 1
trap 'rm -f "$jar"' EXIT

# ポータルとの通信は HTTPS のみ・証明書検証あり・リダイレクト非追従。
c=("${curl[@]}" -m 10 --proto '=https' -b "$jar" -c "$jar")

# Wi2 の正規サーバーが無料 Wi‑Fi のランディングへ 302 を返したか。0=Wi2 1=対象外の網 2=通信失敗・5xx
wi2() {
  r=$("${c[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "$WI2/wi2auth/redirect"); rc=$?
  (( rc )) || [[ $r == 5* ]] && return 2
  [[ $r == "302 $WI2/freewifi/"*/landing.html ]]
}

# 初めての接続先では同意を送らない。Wi2 なら、最初の1回は自分で同意するよう1回だけ知らせる。
if (( !known )); then
  print -r -- "$net" > "$PD"
  wi2 && notify "この Wi-Fi では最初の1回だけ、ブラウザで規約を読んで同意してください。次からは自動で再接続します。" \
    "For this Wi-Fi, read the terms and accept them in your browser once. After that, it reconnects automatically."
  exit 0
fi

# 失敗が続いているときは 30秒→60秒→…→最大30分 と間隔を空ける。店を移ったら前の待機状態は持ち越さない。
n=0 next=0 prev=
[[ -r $ST ]] && read -r n next prev < "$ST"
[[ $prev == "$net" ]] || n=0 next=0
(( EPOCHSECONDS < next )) && exit 0

# 失敗回数を増やして次の試行を遅らせる。同じ失敗の繰り返しは 1,2,4,8,… 回目だけ記録する。
# $1=事象 $2=詳細 $3=1 なら、失敗が続く間に1回だけ通知する
fail() {
  (( n++, wait = 30 << (n > 7 ? 6 : n - 1), wait > 1800 && (wait = 1800) ))
  print -r -- "$n $(( EPOCHSECONDS + wait )) $net" > "$ST"
  (( n & (n - 1) )) || log "$1 x$n $2"
  (( $3 && n == 1 )) && notify "Wi-Fi に自動で再接続できませんでした。ブラウザで接続画面を確認してください。" \
    "Could not reconnect to Wi-Fi automatically. Check the login page in your browser."
  exit 1
}

# 通信失敗・5xx は障害として失敗扱い（Wi2 以外の網でも起こりうるので通知はしない）。それ以外の応答は対象外の網。
wi2; case $? in
  1) exit 0 ;;
  2) fail "redirect failed" "curl=$rc http=${r%% *}" 0 ;;
esac
grep -q session_id "$jar" || fail "redirect failed" "no session_id" 1

res=$("${c[@]}" -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  --data '{"login_method":"onetap","login_params":{"agree":"1"}}' "$WI2/wi2auth/xhr/login")
/usr/bin/jq -e '.result == true' <<< "$res" &>/dev/null && api=ok || api=ng

sleep 2
state && probe=ok || probe=ng

# API の結果と疎通回復を分けて記録する（OS のポータル画面などによる復旧と区別できる）。
if [[ $api == ok && $probe == ok ]]; then
  rm -f "$ST"
  log "re-authenticated api=ok probe=ok"
  exit 0
fi
# 疎通も戻っていなければ通知する。
[[ $probe == ng ]] && notify=1 || notify=0
fail "login failed" "api=$api probe=$probe res=${res[1,200]}" $notify
