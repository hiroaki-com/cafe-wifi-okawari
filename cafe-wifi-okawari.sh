#!/bin/zsh
# キャプティブポータルに戻されていたら Wi2 のワンタップ認証（規約同意）で再認証する。
# 対象は Wi2 の無料 Wi‑Fi（ドトール・スタバ等）。launchd から定期実行される。詳細は DESIGN.md。
set -u
setopt extended_glob   # [A-Za-z0-9_-]## と (|\?*)
zmodload zsh/datetime   # EPOCHSECONDS
zmodload -F zsh/stat b:zstat

WI2=https://service.wi2.ne.jp
ST=$HOME/Library/Caches/cafe-wifi-okawari            # 連続失敗回数・次回試行時刻・接続先
PD=$HOME/Library/Caches/cafe-wifi-okawari.pending    # 捕捉中でまだ同意していない接続先「MAC ブランド [notified]」
SN=$HOME/Library/Caches/cafe-wifi-okawari.seen       # 通信できる状態で Wi2 のブランドを確かめ終えた接続先（MAC）
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"   # 利用者が自分で同意した接続先「MAC ブランド」（1行1つ）
RC=/var/run/resolv.conf   # DNS の設定が変わるたびに書き換わる（接続画面での同意の直後も）。launchd の WatchPaths でもこれを見る
JOIN=300                  # 接続してからこの秒数の間は、同意していない網でも状態を確かめる
REJECT=3                  # 同じ接続先で認証サーバーの拒否がこの回数続いたら、自動の再同意をやめる
log() { print -r -- "$(strftime '%F %T' $EPOCHSECONDS) $*" }
# ダイアログで知らせる。$1=日本語 $2=英語。macOS の優先言語が日本語なら $1、それ以外は $2。
# LaunchAgent からの display notification は表示されない（DESIGN.md §7）ので display alert を使う。最大2分で自動的に閉じる。
# 引数はコードに書いた固定文言だけにする（外部入力を AppleScript に渡さない）。
notify() {
  local m=$2
  [[ $(/usr/bin/defaults read -g AppleLanguages 2>/dev/null | /usr/bin/awk -F'"' 'NF > 1 { print $2; exit }') == ja* ]] && m=$1
  /usr/bin/osascript -e "display alert \"cafe-wifi-okawari\" message \"$m\" giving up after 120" >/dev/null
}
HOWJA='Wi-Fi に接続し直すと出る接続画面か、ブラウザで http://captive.apple.com を開くと出る画面で'
HOWEN='on the login page (reconnect to the Wi-Fi, or open http://captive.apple.com in a browser)'

# -q で ~/.curlrc を無視し、実行条件（証明書検証・リダイレクト非追従）を固定する。-q は先頭必須。
curl=(/usr/bin/curl -q -s)

# 0=認証済み 1=ポータルに捕捉されている 2=無接続・判定不能（HTTP 障害など）。
# code に HTTP コード、loc に転送先（Location）を入れる。
state() {
  local r t
  r=$("${curl[@]}" -m 5 -w '\n%{http_code} %{redirect_url}' http://captive.apple.com/hotspot-detect.html) || return 2
  t=${r##*$'\n'} code=${t%% *} loc=${t#* }
  case $code in
    200) [[ $r == *'<TITLE>Success</TITLE>'* ]] && return 0 || return 1 ;;
    30[1237]) return 1 ;;
    *) return 2 ;;
  esac
}

# 接続先の識別子（既定ゲートウェイの MAC。取れなければ IP）を net に、そのインターフェースを ifc に入れる。通信はしない。
# macOS は一度つないだことのある認証画面つきの網では、接続画面で同意するまで既定経路を作らない（DESIGN.md §1）。
# その間は net が空になり、何もしない。
netid() {
  local r gw
  r=$(/sbin/route -n get default 2>/dev/null)
  gw=${${(M)${(f)r}:#*gateway:*}##* } ifc=${${(M)${(f)r}:#*interface:*}##* }
  net=$(/usr/sbin/arp -n "$gw" 2>/dev/null | /usr/bin/awk '{print $4}')
  [[ $net == *:*:* ]] || net=$gw
}
# URL のうち、ホストとパスだけ（ログ用。クエリには端末の MAC・IP が入るので残さない）
path() { print -r -- "${1%%\?*}" }

netid
[[ -n $net ]] || exit 0
# 同じ MAC の網を同意済みとして持っているか。ブランドまでの照合は Wi2 に問い合わせてから行う。
/usr/bin/awk -v n="$net" '$1 == n { f = 1 } END { exit !f }' "$KN" 2>/dev/null && kmac=1 || kmac=0
# DHCP で配られたドメイン名が wi2.ne.jp なら Wi2 の網（ドトールで実測。手元の情報で、通信はしない）
[[ -n $ifc && $(/usr/sbin/ipconfig getoption "$ifc" domain_name 2>/dev/null) == wi2.ne.jp ]] && wi2net=1 || wi2net=0
zstat -A joined +mtime $RC 2>/dev/null || joined=(0)
pd=(); [[ -r $PD ]] && pd=(${=$(<"$PD")})
# 関係のない網（自宅など）では通信しない。確かめるのは、Wi2 の網・同意済みの網・同意待ちのとき・接続した直後だけ。
(( wi2net || kmac || $#pd || EPOCHSECONDS - joined[1] < JOIN )) || exit 0

jar=$(mktemp) || exit 1
trap 'rm -f "$jar"' EXIT
# ポータルとの通信は HTTPS のみ・証明書検証あり・リダイレクト非追従。
c=("${curl[@]}" -m 10 --proto '=https' -b "$jar" -c "$jar")

# Wi2 の正規サーバーが無料 Wi‑Fi のランディングへ 302 を返すまで、Wi2 の認証サーバー内（/wi2auth/）の 302 だけをたどる（最大3回）。
# 0=ランディングに着いた（brand にブランド名） 1=想定外の応答（to に転送先） 2=通信失敗・5xx
wi2() {
  local u=$1 p i
  for i in 1 2 3; do
    r=$("${c[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "$u"); rc=$?
    (( rc )) || [[ $r == 5* ]] && return 2
    to=${r#* } p=${to#"$WI2/freewifi/"}
    if [[ $r == "302 $WI2/freewifi/"* && $p == [A-Za-z0-9_-]##/landing.html(|\?*) ]]; then
      brand=${p%%/*}
      return 0
    fi
    [[ $r == "302 $WI2/wi2auth/"* && $to != "$WI2/wi2auth/error/"* ]] || return 1
    u=$to
  done
  return 1
}

state; s=$?
(( s == 2 )) && exit 0
if (( s == 0 )); then
  rm -f "$ST"
  # 捕捉されていた接続先が認証済みになった = 利用者が自分で同意した。以後この接続先だけ自動で再認証する。
  if (( $#pd >= 2 )) && [[ $pd[1] == "$net" ]] && ! grep -qxF -- "$pd[1,2]" "$KN" 2>/dev/null; then
    mkdir -p "${KN:h}" && print -r -- "$pd[1,2]" >> "$KN" && log "consent recorded net=$pd[1,2]"
  fi
  rm -f "$PD"
  # Wi2 の無料 Wi‑Fi に、本ツールが同意を送っていないのに通信できている = 利用者が接続画面で同意した
  # （macOS は同意するまでこの網を使わせないので、接続直後の捕捉は本ツールからは見えない）。
  # ブランドを確かめるのは接続先ごとに1回（失敗したら3回まで）。
  sn=(); [[ -r $SN ]] && sn=(${=$(<"$SN")})
  t=0; [[ ${sn[1]-} == "$net" ]] && t=${sn[2]-3}
  (( wi2net && t < 3 )) || exit 0
  wi2 "$WI2/wi2auth/redirect"; case $? in
    0) print -r -- "$net 3" > "$SN"
       grep -qxF -- "$net $brand" "$KN" 2>/dev/null && exit 0
       mkdir -p "${KN:h}" && print -r -- "$net $brand" >> "$KN" && log "consent recorded net=$net $brand (online)" ;;
    1) print -r -- "$net $(( t + 1 ))" > "$SN"; log "not free wi-fi x$(( t + 1 )) net=$net http=${r%% *} to=$(path $to)" ;;
    2) print -r -- "$net $(( t + 1 ))" > "$SN"; log "redirect failed x$(( t + 1 )) net=$net curl=$rc http=${r%% *}" ;;
  esac
  exit 0
fi

# 同意待ちの接続先では通信しない。捕捉が2回続いたら（OS の接続画面で済ませていなければ）1回だけ知らせる。
if [[ ${pd[1]-} == "$net" ]]; then
  if (( $#pd == 2 )); then
    print -r -- "$pd[1,2] notified" > "$PD"
    notify "この Wi-Fi では最初の1回だけ、${HOWJA}規約を読んで同意してください。次からは自動で再接続します。" \
      "For this Wi-Fi, read and accept the terms yourself once, $HOWEN. After that, it reconnects automatically."
  fi
  exit 0
fi

# 失敗が続いているときは 30秒→60秒→…→最大30分 と間隔を空ける。店を移った・つなぎ直したら前の待機状態は持ち越さない。
# 拒否の回数（rej）は、つなぎ直しても同じ接続先なら持ち越す。
n=0 next=0 prev= rej=0
[[ -r $ST ]] && read -r n next prev rej < "$ST"
[[ $prev == "$net" ]] || rej=0
[[ $prev == "$net" && ! $RC -nt $ST ]] || n=0 next=0
(( EPOCHSECONDS < next )) && exit 0

# 失敗回数を増やして次の試行を遅らせる。同じ失敗の繰り返しは 1,2,4,8,… 回目だけ記録する。
# $1=事象 $2=詳細 $3=1 なら、失敗が続く間に1回だけ知らせる
fail() {
  (( n++, wait = 30 << (n > 7 ? 6 : n - 1), wait > 1800 && (wait = 1800) ))
  print -r -- "$n $(( EPOCHSECONDS + wait )) $net ${rej:-0}" > "$ST"
  (( n & (n - 1) )) || log "$1 x$n $2"
  (( $3 && n == 1 )) && notify "Wi-Fi に自動で再接続できませんでした。${HOWJA}確認してください。" \
    "Could not reconnect to Wi-Fi automatically. Check the login page (reconnect to the Wi-Fi, or open http://captive.apple.com in a browser)."
  exit 1
}

# captive.apple.com が Wi2 の認証サーバーへ転送したときだけ Wi2 に問い合わせる。それ以外のポータル（ホテルなど）には何も送らない。
# 転送先には、Wi2 が見ている端末の MAC と IP が入る（<date omitted> 実測）。自分のものと違えば、他人の端末の認証になりうるので送らない。
if [[ $loc != "$WI2/wi2auth/redirect?"* ]]; then
  (( wi2net || kmac )) && fail "portal unknown" "http=$code to=$(path $loc)" 0
  exit 0
fi
q=${loc#*\?}; q=${q//\%3[Aa]/:}
qm=${${(M)${(s:&:)q}:#mac=*}#mac=} qi=${${(M)${(s:&:)q}:#ip=*}#ip=}
mymac=$(/sbin/ifconfig "$ifc" 2>/dev/null | /usr/bin/awk '$1 == "ether" { print $2; exit }')
myip=$(/usr/sbin/ipconfig getifaddr "$ifc" 2>/dev/null)
# MAC は大文字小文字・区切り（: と -）・先頭の 0 の有無の違いを吸収して比べる
hex() { local o; for o in ${(s.:.)${${1:l}//-/:}}; do printf '%02x' 0x$o 2>/dev/null; done }
if [[ -z $qm || -z $qi || $(hex $qm) != $(hex $mymac) || $qi != "$myip" ]]; then
  fail "portal mismatch" "mac=$([[ $(hex $qm) == $(hex $mymac) ]] && print ok || print ng) ip=$([[ $qi == $myip ]] && print ok || print ng)" 0
fi

# 通信失敗・5xx は障害として失敗扱い（通知はしない）。Wi2 から想定外の応答が来たら、同意済みの網なら知らせる。
wi2 "$loc"; case $? in
  1) fail "redirect failed" "http=${r%% *} to=$(path $to)" $kmac ;;
  2) fail "redirect failed" "curl=$rc http=${r%% *}" 0 ;;
esac
# 同じ MAC でもブランドが違えば別の網（ルーターの冗長化用の共通 MAC は店やブランドをまたいで重なる）。
# 初めての接続先では同意を送らず、利用者が自分で同意するのを待つ。
if ! grep -qxF -- "$net $brand" "$KN" 2>/dev/null; then
  print -r -- "$net $brand" > "$PD"
  log "consent pending net=$net $brand"
  exit 0
fi
grep -q session_id "$jar" || fail "redirect failed" "no session_id" 1

# 接続画面の JS（ランディングから呼ぶ XHR）と同じ要求を送る。
res=$("${c[@]}" -w '\n%{http_code}' -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  -H "Origin: $WI2" -e "$WI2/freewifi/$brand/landing.html" \
  --data '{"login_method":"onetap","login_params":{"agree":"1"}}' "$WI2/wi2auth/xhr/login"); lrc=$?
http=${res##*$'\n'} res=${res%$'\n'*}
/usr/bin/jq -e '.result == true' <<< "$res" &>/dev/null && api=ok || api=ng

# 疎通の回復を最大10秒待つ（2秒ごとに確かめる）
probe=ng
for i in {1..5}; do sleep 2; state && { probe=ok; break }; done

# API の結果と疎通回復を分けて記録する（OS の接続画面などによる復旧と区別できる）。
if [[ $api == ok && $probe == ok ]]; then
  rm -f "$ST"
  log "re-authenticated api=ok probe=ok net=$net $brand t=$(( i * 2 ))s"
  exit 0
fi
# 疎通も戻っていなければ知らせる。
[[ $probe == ng ]] && notify=1 || notify=0
# サーバーが応答したのに同意を受け付けず、疎通も戻らない = 拒否（利用上限・利用停止・条件の変更などを含む。
# 一時的な障害と見分けられないので、回数で判断する）。続いたらこの接続先の自動の再同意をやめ、
# 利用者が接続画面を確かめて自分で同意し直すのを待つ（同意し直せば、最初の同意と同じく記録して再開する）。
if (( lrc == 0 )) && [[ $api == ng && $probe == ng && $http == [1-4]?? ]] && (( ++rej >= REJECT )); then
  grep -vxF -- "$net $brand" "$KN" > "$KN.tmp"; mv -f "$KN.tmp" "$KN"
  print -r -- "$net $brand notified" > "$PD"
  rm -f "$ST"
  log "auto stopped net=$net $brand rejected x$rej http=$http res=${res[1,200]}"
  notify "認証が続けて拒否されたため、この Wi-Fi での自動再接続を止めました。${HOWJA}確認してください。" \
    "Stopped reconnecting to this Wi-Fi automatically because the login was refused repeatedly. Check the login page (reconnect to the Wi-Fi, or open http://captive.apple.com in a browser)."
  exit 1
fi
fail "login failed" "api=$api probe=$probe http=$http res=${res[1,200]}" $notify
