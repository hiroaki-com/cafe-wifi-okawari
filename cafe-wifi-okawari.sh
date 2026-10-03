#!/bin/zsh
# キャプティブポータルに戻されていたら、規約への同意を送り直して再認証する。
# 対象は Wi2 のワンタップ認証（ドトール・スタバ等）と USEN（USPOT-02）。launchd から定期実行される。詳細は DESIGN.md。
set -u
setopt extended_glob   # [A-Za-z0-9_-]## と (|\?*)、<0-255>
zmodload zsh/datetime   # EPOCHSECONDS・strftime
zmodload -F zsh/stat b:zstat

VERSION=1.0.0   # 版。Release のタグ（v1.0.0）と一致させる（.github/workflows/release.yml で確かめる。DESIGN.md §6.1）
WI2=https://service.wi2.ne.jp
ST=$HOME/Library/Caches/cafe-wifi-okawari            # 連続失敗回数・次回試行時刻・接続先・拒否回数・知らせたか・拒否したブランド
PD=$HOME/Library/Caches/cafe-wifi-okawari.pending    # 捕捉中でまだ同意していない接続先「MAC ブランド [notified]」。USEN は「MAC usen 基準時刻 [notified]」
SN=$HOME/Library/Caches/cafe-wifi-okawari.seen       # 通信できる状態で Wi2 のブランドを確かめた接続先と回数「MAC 回数」
DG=$HOME/Library/Caches/cafe-wifi-okawari.probe      # 接続の状態を確かめられないことが続いている接続先と回数「MAC 回数」
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"   # 利用者が自分で同意した接続先「MAC ブランド」（1行1つ）。USEN は「MAC usen [規約のハッシュ]」
WT="$HOME/Library/Application Support/cafe-wifi-okawari/watched"     # 認証画面での同意をシステムログで確かめた網「MAC 記録した時刻」（24時間有効・新しい50件まで）
RC=/var/run/resolv.conf   # DNS の設定が変わるたびに書き換わる（認証画面での同意の直後も）。launchd の WatchPaths でもこれを見る
JOIN=300                  # 接続してからこの秒数の間は、同意していない網でも状態を確かめる
REJECT=3                  # 同じ接続先で認証サーバーの拒否がこの回数続いたら、自動の再同意をやめる
log() { print -r -- "$(strftime '%F %T' $EPOCHSECONDS) $*" }
# macOS の優先言語が日本語か
jp() { [[ $(/usr/bin/defaults read -g AppleLanguages 2>/dev/null | /usr/bin/awk -F'"' 'NF > 1 { print $2; exit }') == ja* ]] }
# ダイアログで知らせる。$1=日本語 $2=英語。macOS の優先言語が日本語なら $1、それ以外は $2。
# LaunchAgent からの display notification は表示されない（DESIGN.md §7）ので display alert を使う。最大2分で自動的に閉じる。
# 引数はコードに書いた固定文言だけにする（外部入力を AppleScript に渡さない）。
notify() {
  local m=$2
  jp && m=$1
  /usr/bin/osascript -e "display alert \"cafe-wifi-okawari\" message \"$m\" giving up after 120" >/dev/null
}
HOWJA='Wi-Fi に接続し直すと出る認証画面か、ブラウザで http://captive.apple.com を開くと出る画面で'
HOWEN='the login page (reconnect to the Wi-Fi, or open http://captive.apple.com in a browser)'

# -q で ~/.curlrc を無視し、実行条件（証明書検証・リダイレクト非追従）を固定する。-q は先頭必須。
# 環境変数のプロキシ（http_proxy・ALL_PROXY など）も使わない（端末の MAC を含む平文の要求を外へ出さず、プローブの判定も狂わせない）。
curl=(/usr/bin/curl -q -s --noproxy '*')

# 0=認証済み 1=ポータルに捕捉されている 2=無接続・判定不能（HTTP 障害など）。
# code に HTTP コード、loc に転送先（Location）、prc に curl の終了値を入れる。
state() {
  local r t
  r=$("${curl[@]}" -m 5 -w '\n%{http_code} %{redirect_url}' http://captive.apple.com/hotspot-detect.html); prc=$?
  (( prc )) && { code=000 loc=; return 2 }
  t=${r##*$'\n'} code=${t%% *} loc=${t#* }
  case $code in
    200) [[ $r == *'<TITLE>Success</TITLE>'* ]] && return 0 || return 1 ;;
    30[1237]) return 1 ;;
    *) return 2 ;;
  esac
}

# 接続先の識別子（既定ゲートウェイの MAC。取れなければ IP）を net に、そのインターフェースを ifc に入れる。通信はしない。
# macOS は一度つないだことのある認証画面つきの網では、認証画面で同意するまで既定経路を作らない（DESIGN.md §1）。
# その間は net が空になり、何もしない。
netid() {
  rt default; gw=$rg ifc=$ri
  net=$(/usr/sbin/arp -n "$gw" 2>/dev/null | /usr/bin/awk '{print $4}')
  [[ $net == *:*:* ]] || net=$gw
}
# 宛先 $1 への経路のゲートウェイを rg に（直結なら空）、インターフェースを ri に入れる。通信はしない。
rt() {
  local r=$(/sbin/route -n get "$1" 2>/dev/null)
  rg=${${(M)${(f)r}:#*gateway:*}##* } ri=${${(M)${(f)r}:#*interface:*}##* }
}
# URL のうち、ホストとパスだけ（ログ用。クエリには端末の MAC・IP が入るので残さない）
path() { print -r -- "${1%%\?*}" }
# 応答の本文（ログ用）。URL のクエリと、MAC・IPv4 アドレスに見える部分を伏せ、200文字までにする
mask() {
  local s=${1//\?[^\"\'[:space:]]#/?}
  s=${s//[[:xdigit:]](#c1,2)((:|-|%3[Aa])[[:xdigit:]](#c1,2))(#c5)/<mac>}
  s=${s//<0-255>.<0-255>.<0-255>.<0-255>/<ip>}
  print -r -- "${s[1,200]}"
}
# 接続先・インターフェース・端末の IP が、始めたときのままか（テザリングへの切り替えなどで途中で変わっていないか）
same() {
  local n0=$net i0=$ifc g0=$gw r
  netid; [[ $net == "$n0" && $ifc == "$i0" && $(/usr/sbin/ipconfig getifaddr "$ifc" 2>/dev/null) == "$myip" ]]; r=$?
  net=$n0 ifc=$i0 gw=$g0
  return r
}
# USEN の分岐で、記録を書く・同意を送る・結果を数える前に使う。網が変わっていたら何も書かずに終える。
samenet() { same || { log "network changed net=$net $*"; exit 0 } }
# 記録ファイル $1 のうち、先頭の列がキー $2 の行を扱う（consented のキーは「MAC ブランド」、watched は「MAC」）。
# 引数が2つなら照合: あれば 0 で、キーに続く列（USEN の規約のハッシュ・見張りの時刻）を rest に入れる。
# 3つなら置き換え: その行をすべて消し、$3 が空でなければ $3 を末尾に足す。
rec() {
  if (( $# == 2 )); then
    rest=$(/usr/bin/awk -v k="$2 " 'index($0 " ", k) == 1 { f = 1; r = substr($0, length(k) + 1) } END { print r; exit !f }' "$1" 2>/dev/null)
  else
    mkdir -p "${1:h}" && { /usr/bin/awk -v k="$2 " 'index($0 " ", k) != 1' "$1" 2>/dev/null; [[ -z $3 ]] || print -r -- "$3" } > "$1.tmp" &&
      mv -f "$1.tmp" "$1"
  fi
}
# 今の接続で、利用者が認証画面で同意したか（システムログの websheet: success。行の中身は保存しない）。
# 数えるのは、今のリース開始と $1 のどちらよりも後の行だけ。$1 が 0（入店時の確認）なら、リース開始が
# resolv.conf の更新より5分以上前のときは今の接続のリースと見なせないので読まない。
# 0=あった 1=なかった 2=読めない（リース開始・ログ） 3=まだ読まない（resolv.conf の更新から15秒。ログへの書き込みの遅れを待つ）
websheet() {
  local a s
  (( EPOCHSECONDS - joined[1] >= 15 )) || return 3
  a=(${(M)${(f)"$(/usr/sbin/ipconfig getsummary "$ifc" 2>/dev/null)"}:#*LeaseStartTime :*})
  s=$(strftime -r '%m/%d/%Y %H:%M:%S' "${a[1]##* : }" 2>/dev/null) && (( $1 || s > joined[1] - 300 )) || return 2
  (( s > $1 )) || s=$1
  a=$(/usr/bin/log show --style compact --start "$(strftime '%F %T' $s)" \
    --predicate 'subsystem == "com.apple.captive" AND eventMessage CONTAINS "websheet: success"' 2>/dev/null) || return 2
  [[ $a == *'websheet: success'* ]]
}

netid
[[ -n $net ]] || exit 0
# 同じ MAC の網を同意済みとして持っているか。ブランドまでの照合は Wi2 に問い合わせてから行う。
rec "$KN" "$net" && kmac=1 || kmac=0
# 認証画面での同意をシステムログで確かめて見張っている網か（記録から24時間以内）
rec "$WT" "$net" && (( EPOCHSECONDS - rest < 86400 )) && watched=1 || watched=0
# DHCP で配られたドメイン名が wi2.ne.jp なら Wi2 の網（ドトール・ガストで実測。手元の情報で、通信はしない）
[[ -n $ifc && $(/usr/sbin/ipconfig getoption "$ifc" domain_name 2>/dev/null) == wi2.ne.jp ]] && wi2net=1 || wi2net=0
zstat -A joined +mtime $RC 2>/dev/null || joined=(0)
# 同意待ちの記録と、その更新からの秒数（pda）。起動の間隔（10秒）に依らず、知らせる・確かめ直す間隔を時間で決める。
pd=() pda=0; [[ -r $PD ]] && { pd=(${=$(<"$PD")}); zstat -A m +mtime $PD 2>/dev/null && pda=$(( EPOCHSECONDS - m[1] )) }
# USEN の同意待ちの網から離れている間は、同意待ちの基準時刻を今に進める（別の網での認証画面の同意を、戻ってから数えない）。
# 既定経路がないだけ（macOS が認証画面を開いている）では進めない（上で終わる）。USEN の同意待ちを数えるのはその網にいるときだけ。
# 進めるのは resolv.conf が基準時刻以後に書き換わったときだけ（認証画面で同意した網は、そのあと既定経路になって resolv.conf が
# 書き換わるので、同意の行はその前になる）。同じ網にいる間は書き直さない（DESIGN.md §3.1）。
npd=$#pd
if [[ ${pd[2]-} == usen && $pd[1] != "$net" ]] && (( joined[1] >= ${pd[3]-0} )); then
  pd[3]=$EPOCHSECONDS
  print -r -- "$pd" > "$PD"
fi
[[ ${pd[2]-} == usen && $pd[1] != "$net" ]] && npd=0
# 関係のない網（自宅など）では通信しない。確かめるのは、Wi2 の網・同意済みの網・見張り中の網・同意待ちのとき・接続した直後だけ。
(( wi2net || kmac || watched || npd || EPOCHSECONDS - joined[1] < JOIN )) || exit 0
myip=$(/usr/sbin/ipconfig getifaddr "$ifc" 2>/dev/null)   # 始めたときの端末の IP（same で途中の回線の切り替わりを見分ける）

jar=$(mktemp) || exit 1
trap 'rm -f "$jar"' EXIT
# ポータルとの通信は HTTPS のみ・証明書検証あり・リダイレクト非追従。
c=("${curl[@]}" -m 10 --proto '=https' -b "$jar" -c "$jar")

# Wi2 の正規サーバーが無料 Wi‑Fi のページへ 302 を返すまで、Wi2 の認証サーバー内（/wi2auth/）の 302 だけをたどる（最大3回）。
# 着くページは、捕捉中なら同意ページ（index.html）、認証済みならランディング（landing.html）（どちらも現地で実測）。
# 0=どちらかに着いた（brand にブランド名、page にページ名） 1=想定外の応答（to に転送先） 2=通信失敗・5xx
wi2() {
  local u=$1 p i
  for i in 1 2 3; do
    r=$("${c[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "$u"); rc=$?
    (( rc )) || [[ $r == 5* ]] && return 2
    to=${r#* } p=${to#"$WI2/freewifi/"}
    if [[ $r == "302 $WI2/freewifi/"* && $p == [A-Za-z0-9_-]##/(landing|index).html(|\?*) ]]; then
      brand=${p%%/*} page=${${p#*/}%%\?*}
      return 0
    fi
    [[ $r == "302 $WI2/wi2auth/"* && $to != "$WI2/wi2auth/error/"* ]] || return 1
    u=$to
  done
  return 1
}

state; s=$?
# 確かめられない（通信失敗・想定外の HTTP）ときは何も送らない。ただし Wi2 の網・同意済み・同意待ちの接続先では、
# 現地で「動いていない理由」を切り分けられるよう、続いた回数の 1,2,4,8… 回目だけ記録する（自宅などでは記録しない）。
if (( s == 2 )); then
  (( wi2net || kmac )) || [[ ${pd[1]-} == "$net" ]] || exit 0
  dg=(); [[ -r $DG ]] && dg=(${=$(<"$DG")})
  [[ ${dg[1]-} == "$net" ]] && k=$(( ${dg[2]-0} + 1 )) || k=1
  print -r -- "$net $k" > "$DG"
  (( k & (k - 1) )) || log "probe failed x$k net=$net if=$ifc curl=$prc http=$code"
  exit 0
fi
[[ -e $DG ]] && rm -f "$DG"
if (( s == 0 )); then
  rm -f "$ST"
  # 捕捉されて同意待ちだった接続先が認証済みになった = 利用者が自分で同意した。以後この接続先だけ自動で再認証する。
  # 同じ MAC で別ブランドの古い同意待ちを取り違えないよう、どのブランドかは Wi2 に確かめてから記録する（下記）。
  # USEN の同意待ちは、別の網で通信できても消さない（消すと入口で終わり、そのあとの利用者の同意を拾えない）。
  (( $#pd >= 2 )) && [[ $pd[1] == "$net" ]] && pdn=1 || { pdn=0; [[ ${pd[2]-} == usen ]] || rm -f "$PD" }
  # USEN の同意待ちの網が Wi2 の網なら、同意待ちを消して、Wi2 の網としてブランドを確かめる
  if (( pdn && wi2net )) && [[ $pd[2] == usen ]]; then
    samenet "before recording"
    rm -f "$PD"; pdn=0
  fi
  # Wi2 の無料 Wi‑Fi に、本ツールが同意を送っていないのに通信できている = 利用者が認証画面で同意した
  # （macOS は同意するまでこの網を使わせないので、接続直後の捕捉は本ツールからは見えない）。
  # ブランドを確かめるのは接続ごとに1回（失敗したら 30秒・60秒 と空けて3回まで）。つなぎ直したら（resolv.conf が新しい）確かめ直す。
  # 同意待ちのときは、確認に失敗しても保留を消さず、30秒→60秒→…→最大30分 と間隔を空けて確かめ続ける
  # （保留を書くとき・自動を止めるときに確認の記録を消すので、入店時の確認済みの記録には妨げられない）。
  sn=(); [[ -r $SN ]] && sn=(${=$(<"$SN")})
  t=0; [[ ${sn[1]-} == "$net" && ! $RC -nt $SN ]] && t=${sn[2]-3}
  # Wi2 の網でも見張り中・同意待ちでもない網（入店時の USEN など）: 接続から5分以内に1回だけ、認証画面で
  # 同意したかをシステムログで確かめる。同意済みの網なら、60秒以内の同意だけをログに書く（次の時間切れの目安の起点。
  # 遅れた時刻を起点にしないため。DESIGN.md §3.2）。そうでなければ見張る。USEN への同意として記録するのは、
  # 最初の捕捉で USPOT-02 と確かめてから。
  if (( ! pdn && ! wi2net )); then
    (( watched || t || EPOCHSECONDS - joined[1] >= JOIN )) && exit 0
    websheet $(( kmac ? EPOCHSECONDS - 60 : 0 )); w=$?
    (( w == 3 )) && exit 0
    if (( w == 0 )); then
      samenet "before watching"
      if (( kmac )); then rec "$KN" "$net usen" && ub=' usen' || ub=
      else rec "$WT" "$net" "$net $EPOCHSECONDS" && /usr/bin/tail -n 50 "$WT" > "$WT.tmp" && mv -f "$WT.tmp" "$WT"; ub=; fi
      log "captive login seen net=$net$ub"
    fi
    print -r -- "$net 3" > "$SN"   # この接続では読み直さない
    exit 0
  fi
  (( ! pdn && (! wi2net || t >= 3) )) && exit 0
  if (( t )); then
    zstat -A m +mtime $SN 2>/dev/null || m=(0)
    (( EPOCHSECONDS - m[1] >= (t > 6 ? 1800 : 30 << (t - 1)) )) || exit 0
  fi
  k=$(( t + 1 ))
  # USEN の同意待ち: 基準時刻と今のリース開始のどちらよりも後に、認証画面での同意がシステムログにあれば記録する。
  # 平文の Success だけでは記録しない（偽れる）。なければ同意待ちを残し、Wi2 と同じ間隔を空けて読み直す。
  # 自動の停止（拒否3回・規約の変更）からの再開もここだけ（停止の時刻が基準時刻）。
  if (( pdn )) && [[ $pd[2] == usen ]]; then
    websheet $(( pd[3] + 1 )); w=$?
    (( w == 3 )) && exit 0
    (( w )) && { print -r -- "$net $k" > "$SN"; exit 0 }
    samenet "before recording"
    rec "$KN" "$net usen" "$net usen"; rm -f "$PD"
    log "consent recorded net=$net usen"
    exit 0
  fi
  # 同意済みの MAC では、この接続の最初の確認のときだけ、60秒以内の認証画面での同意もシステムログで確かめる
  # （同意済みのブランドなら下の 0 でログに書く。DESIGN.md §3.2）。ログへの書き込みの遅れを待つ間（websheet の 3）は、
  # ブランドの確認も待つ。
  ws=1; (( kmac && ! t )) && { websheet $(( EPOCHSECONDS - 60 )); ws=$?; (( ws == 3 )) && exit 0 }
  wi2 "$WI2/wi2auth/redirect"; w=$?
  # 疎通できていても同意ページへ転送されたら、Wi2 ではまだ認証されていない（時間切れの境目など）。同意の証拠にしない。
  (( w == 0 )) && [[ $page != landing.html ]] && w=1
  # 確かめている間に別の回線（認証済みの別の Wi2 など）へ切り替わっていたら、その答えを元の接続先の同意や失敗として記録しない。
  same || { log "network changed net=$net before recording"; exit 0 }
  case $w in
    0) print -r -- "$net 3" > "$SN"; (( pdn )) && rm -f "$PD"   # 別の網の USEN の同意待ちは残す
       rec "$KN" "$net $brand" && { (( ws )) || log "captive login seen net=$net $brand"; exit 0 }
       [[ ${pd[1,2]} == "$net $brand" ]] && how= || how=' (online)'
       mkdir -p "${KN:h}" && print -r -- "$net $brand" >> "$KN" && log "consent recorded net=$net $brand$how" ;;
    1) print -r -- "$net $k" > "$SN"; (( k <= 3 || !(k & (k - 1)) )) && log "not free wi-fi x$k net=$net http=${r%% *} to=$(path $to)" ;;
    2) print -r -- "$net $k" > "$SN"; (( k <= 3 || !(k & (k - 1)) )) && log "redirect failed x$k net=$net curl=$rc http=${r%% *}" ;;
  esac
  exit 0
fi

# 同意待ち。保留を書いてから30秒以上たっても捕捉が続いていたら（OS の認証画面で済ませていなければ）1回だけ知らせる。
waiting() {
  local k=2; [[ ${pd[2]-} == usen ]] && k=3   # USEN は「MAC usen 基準時刻」
  (( $#pd == k && pda >= 30 )) || return 0
  print -r -- "$pd[1,k] notified" > "$PD"
  notify "この Wi-Fi では最初の1回だけ、${HOWJA}規約を読んで同意してください。次からは自動で再接続します。" \
    "For this Wi-Fi, read and accept the terms yourself once, on $HOWEN. After that, it reconnects automatically."
}
# 同意待ちの接続先では通信しない。ただし同じ MAC で同意済みのブランドがあるときは、どのブランドかを Wi2 に確かめる
# （ルーターの冗長化用の共通 MAC では、別ブランドの古い同意待ちが残っていることがある）。確かめるのは30秒に1回まで
# （保留の更新時刻で測る。古い保留なら待たずに確かめるので、同意済みのブランドの再認証は遅れない）。
if [[ ${pd[1]-} == "$net" ]]; then
  (( kmac )) || { waiting; exit 0 }
  (( pda >= 30 )) || exit 0
  touch "$PD"
fi

# 失敗が続いているときは 30秒→60秒→…→最大30分 と間隔を空ける。店を移った・つなぎ直したら前の待機状態は持ち越さない。
# 拒否の回数（rej）は、つなぎ直しても同じ接続先・同じブランド（rb）なら持ち越す。知らせたか（told）は、失敗が続く間は持ち越す。
n=0 next=0 prev= rej=0 told=0 rb=
[[ -r $ST ]] && read -r n next prev rej told rb < "$ST"
[[ $prev == "$net" ]] || rej=0 rb=
[[ $prev == "$net" && ! $RC -nt $ST ]] || n=0 next=0 told=0
(( EPOCHSECONDS < next )) && exit 0

# 失敗回数を増やして次の試行を遅らせる。試行の間隔が空いていくので、失敗は毎回記録する（途中で失敗の種類が変わっても分かる）。
# $1=事象 $2=詳細 $3=1 なら、失敗が続く間に1回だけ知らせる（通知しない失敗が先にあっても、まだなら知らせる）
fail() {
  local tell=0
  (( n++, wait = 30 << (n > 7 ? 6 : n - 1), wait > 1800 && (wait = 1800) ))
  (( $3 && ! ${told:-0} )) && tell=1 told=1
  print -r -- "$n $(( EPOCHSECONDS + wait )) $net ${rej:-0} ${told:-0} $rb" > "$ST"
  log "$1 x$n $2"
  (( tell )) && notify "Wi-Fi に自動で再接続できませんでした。${HOWJA}確認してください。" \
    "Could not reconnect to Wi-Fi automatically. Check $HOWEN."
  exit 1
}

mymac=$(/sbin/ifconfig "$ifc" 2>/dev/null | /usr/bin/awk '$1 == "ether" { print $2; exit }')
# MAC は大文字小文字・区切り（: と -）・先頭の 0 の有無の違いを吸収して比べる。1〜2桁の16進数が6つでなければ空にする。
hex() {
  local o h= a=(${(s.:.)${${1:l}//-/:}})
  (( $#a == 6 )) || return
  for o in $a; do [[ $o == [0-9a-f](|[0-9a-f]) ]] || return; h+=${(l:2::0:)o}; done
  print -r -- $h
}
hm=$(hex $mymac)
# USEN（USPOT-02）の誘導先の形か: http://<プライベート IPv4>[:<ポート>]/captive/?… で、その IP への経路が既定経路と同じ
# インターフェースで、既定のゲートウェイを通る（か直結）。VPN の先の社内網もプライベート IP を使うので、経路でも確かめる。
# 機器（IP[:ポート]）を dev に、stamac（機器が見ている端末の MAC）を sm に入れる。
uspot() {
  dev=${${loc#http://}%%/*}
  [[ $loc == "http://$dev/captive/?"* && .$dev != *.0[0-9]* &&
     $dev == (10.<0-255>|172.<16-31>|192.168).<0-255>.<0-255>(|:<1-65535>) ]] || return
  rt ${dev%:*}
  [[ $ri == "$ifc" && ( -z $rg || $rg == "$gw" ) ]] || return
  q=${loc#*\?}; q=${q//\%3[Aa]/:}
  sm=${${(M)${(s:&:)q}:#stamac=*}#stamac=}
}
# 機器から $2 を GET する（平文 HTTP のみ・リダイレクト非追従・5秒・大きさの上限 $1 バイト）。本文を b に入れ、通信成功かつ 200 なら 0。
get() {
  b=$("${curl[@]}" -m 5 --proto '=http' --max-filesize $1 -w '\n%{http_code}' "http://$dev$2"); rc=$?
  http=${b##*$'\n'} b=${b%$'\n'*} url=http://$dev$2
  (( ! rc )) && [[ $http == 200 ]]
}
unwatch() { samenet "before unwatching"; rec "$WT" "$net" '' }

# captive.apple.com の転送先で Wi2 と USEN を見分ける。それ以外のポータル（ホテルなど）には何も送らない。
if [[ $loc == "$WI2/wi2auth/redirect?"* ]]; then
  (( watched )) && unwatch   # 見張り中の網が Wi2 の網だった
  # 転送先には、Wi2 が見ている端末の MAC と IP が入る（現地で実測）。自分のものと違えば、他人の端末の認証になりうるので送らない。
  q=${loc#*\?}; q=${q//\%3[Aa]/:}
  qm=${${(M)${(s:&:)q}:#mac=*}#mac=} qi=${${(M)${(s:&:)q}:#ip=*}#ip=}
  if [[ -z $hm || $(hex $qm) != "$hm" || -z $qi || $qi != "$myip" ]]; then
    fail "portal mismatch" "mac=$([[ -n $hm && $(hex $qm) == $hm ]] && print ok || print ng) ip=$([[ -n $qi && $qi == $myip ]] && print ok || print ng)" 0
  fi

  # 通信失敗・5xx は障害として失敗扱い（通知はしない）。Wi2 から想定外の応答が来たら、同意済みの網なら知らせる。
  wi2 "$loc"; case $? in
    1) fail "redirect failed" "http=${r%% *} to=$(path $to)" $kmac ;;
    2) fail "redirect failed" "curl=$rc http=${r%% *}" 0 ;;
  esac
  # 同じ MAC でもブランドが違えば別の網（ルーターの冗長化用の共通 MAC は店やブランドをまたいで重なる）。
  # 初めての接続先では同意を送らず、利用者が自分で同意するのを待つ。
  if ! rec "$KN" "$net $brand"; then
    [[ ${pd[1,2]} == "$net $brand" ]] && { waiting; exit 0 }
    print -r -- "$net $brand" > "$PD"
    rm -f "$SN"   # 利用者が同意したら、同じ接続のうちでもブランドを確かめて記録できるように
    log "consent pending net=$net $brand"
    exit 0
  fi
  # 拒否の回数はブランドごとに数える（共通 MAC で、別ブランドの拒否を持ち越さない）
  [[ -z $rb || $rb == "$brand" ]] || rej=0; rb=$brand
  grep -q session_id "$jar" || fail "redirect failed" "no session_id" 1
  same || { log "network changed net=$net $brand before login"; exit 0 }

  # 認証画面の JS（同意ページの「同意する」ボタンから呼ぶ XHR）と同じ要求を送る。Referer は着いたページ。
  t0=$EPOCHSECONDS
  res=$("${c[@]}" -w '\n%{http_code}' -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
    -H "Origin: $WI2" -e "$WI2/freewifi/$brand/$page" \
    --data '{"login_method":"onetap","login_params":{"agree":"1"}}' "$WI2/wi2auth/xhr/login"); lrc=$?
  http=${res##*$'\n'} res=${res%$'\n'*}
  # 通信が成功し、HTTP 2xx で、JSON の result が真偽値 true のときだけ ok
  (( lrc == 0 )) && [[ $http == 2?? ]] && /usr/bin/jq -e '.result == true' <<< "$res" &>/dev/null && api=ok || api=ng
elif uspot; then
  # stamac がこの Mac の MAC でなければ、他人の端末の同意になりうるので送らない。
  [[ -n $hm && $(hex $sm) == "$hm" ]] || fail "portal mismatch" "mac=ng" 0
  # 転送先は平文なので偽れる。画面と page.js の中身で USPOT-02 と確かめ、日本語の規約の文面を取り出す。
  get 65536 /captive/ && [[ $b == *'<title>USPOT-02</title>'* ]] && get 1048576 /captive/dist/page.js &&
    [[ $b == *DAVOLINK_* && $b == *株式会社USEN* && $b == *'term:{title:"利用規約"'*']}'* ]]; v=$?
  samenet "usen before recording"   # 以下、書く・送るまで通信しない
  if (( v )); then
    # 取れたのに目印がない・上限を超えた（curl 63）なら対象外。通信失敗・200 以外なら確かめられなかった（見張りは残して待機する）。
    (( rc == 63 )) || { (( ! rc )) && [[ $http == 200 ]] } || fail "portal check failed" "curl=$rc http=$http to=$(path $url)" 0
    (( watched )) && rec "$WT" "$net" ''
    fail "portal unknown" "http=$http to=$(path $url)" 0
  fi
  b=${b#*'term:{title:"利用規約"'} b=${b%%']}'*}
  hs=$(/sbin/sha256 -q -s "$b")
  # 同意済みか照合する。規約の文面のハッシュは最初に送るときに記録し、以後違えば送らない（画面を表示せずに同意するので、読み直してもらう）。
  if ! rec "$KN" "$net usen"; then
    if (( watched )); then   # 入店時に、利用者がこの網の認証画面で同意している
      rec "$KN" "$net usen" "$net usen $hs"; rec "$WT" "$net" ''
      log "consent recorded net=$net usen (captive login)"
    else
      [[ ${pd[1,2]} == "$net usen" ]] && { waiting; exit 0 }
      print -r -- "$net usen $EPOCHSECONDS" > "$PD"
      rm -f "$SN"   # 利用者が同意したら、同じ接続のうちでもシステムログを読んで記録できるように
      log "consent pending net=$net usen"
      exit 0
    fi
  elif [[ -z $rest ]]; then   # 同意し直したあとの最初の送信
    rec "$KN" "$net usen" "$net usen $hs"
  elif [[ $rest != "$hs" ]]; then
    rec "$KN" "$net usen" ''
    print -r -- "$net usen $EPOCHSECONDS notified" > "$PD"   # 基準時刻は今。これより後の認証画面での同意だけで再開する
    rm -f "$ST" "$SN"
    log "terms changed net=$net usen"
    notify "利用規約が変わったため、この Wi-Fi での自動再接続を止めました。${HOWJA}規約を読んで同意し直してください。" \
      "Stopped reconnecting to this Wi-Fi automatically because its terms of use changed. Read and accept them again on $HOWEN."
    exit 1
  fi
  [[ -z $rb || $rb == usen ]] || rej=0; rb=usen brand=usen

  # 認証画面の step2 の「インターネットに接続する」と同じ要求を送る。誕生年・性別は空（任意の入力で、画面の初期値も空）。
  # stamac は hex で確かめた値（16進数と区切りだけ）なので JSON を壊さない。
  t0=$EPOCHSECONDS
  res=$("${curl[@]}" -m 5 --proto '=http' -w '\n%{http_code}' -H 'Content-Type: application/json' -H "Origin: http://$dev" \
    -e "http://$dev/captive/step2" -H 'authorization;' \
    --data "{\"gender\":\"\",\"birth\":\"\",\"macaddr\":\"$sm\",\"lang\":\"$(jp && print ja || print en)\"}" "http://$dev/capi/welcome"); lrc=$?
  http=${res##*$'\n'} res=${res%$'\n'*}
  # 応答の意味は分からない（画面も中身を使わない）ので、通信成功・HTTP 2xx なら ok とする（ログ用）
  (( lrc == 0 )) && [[ $http == 2?? ]] && api=ok || api=ng
else
  (( watched )) && unwatch   # USEN でも Wi2 でもない
  (( wi2net || kmac )) && fail "portal unknown" "http=$code to=$(path $loc)" 0
  exit 0
fi

# 疎通の回復を1秒ごとに、確かめ始めてから約10秒まで確かめる（1回の確認は最大5秒なので、最悪でも約16秒）
probe=ng t1=$EPOCHSECONDS
for i in {1..10}; do sleep 1; state && { probe=ok; break }; (( EPOCHSECONDS - t1 < 10 )) || break; done

# 途中で別の回線に切り替わっていたら、その疎通や失敗を元の接続先の結果として扱わない（次の回に確かめ直す）。
same || { log "network changed net=$net $brand api=$api probe=$probe"; exit 0 }
# API の結果と疎通回復を分けて記録する（OS の認証画面などによる復旧と区別できる）。t は同意を送り始めてから疎通が戻るまで。
if [[ $api == ok && $probe == ok ]]; then
  rm -f "$ST"
  log "re-authenticated api=ok probe=ok net=$net $brand t=$(( EPOCHSECONDS - t0 ))s"
  exit 0
fi
# 疎通も戻っていなければ知らせる。
[[ $probe == ng ]] && notify=1 || notify=0
# サーバーが応答したのに同意を受け付けず、疎通も戻らない = 拒否（利用上限・利用停止・条件の変更などを含む。
# 一時的な障害と見分けられないので、回数で判断する）。続いたらこの接続先の自動の再同意をやめ、
# 利用者が認証画面を確かめて自分で同意し直すのを待つ（同意し直せば、最初の同意と同じく記録して再開する）。
# USEN は応答の意味が分からないので、機器が応答したのに疎通が戻らなければ api に関係なく拒否と数える。
if (( lrc == 0 )) && [[ ( $api == ng || $brand == usen ) && $probe == ng && $http == [1-4]?? ]] && (( ++rej >= REJECT )); then
  rec "$KN" "$net $brand" ''   # USEN はハッシュ付きの行も消す
  # USEN は停止の時刻を基準時刻にし、それより後の認証画面での同意だけで再開する
  [[ $brand == usen ]] && print -r -- "$net usen $EPOCHSECONDS notified" > "$PD" || print -r -- "$net $brand notified" > "$PD"
  rm -f "$ST" "$SN"   # 利用者が同意し直したら、入店時の確認済みの記録に関係なく確かめて記録できるように
  log "auto stopped net=$net $brand rejected x$rej http=$http curl=$lrc res=$(mask "$res")"
  notify "認証が続けて拒否されたため、この Wi-Fi での自動再接続を止めました。${HOWJA}確認してください。" \
    "Stopped reconnecting to this Wi-Fi automatically because the login was refused repeatedly. Check $HOWEN."
  exit 1
fi
fail "login failed" "api=$api probe=$probe http=$http curl=$lrc res=$(mask "$res")" $notify
