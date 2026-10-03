#!/bin/zsh
# メニューバーに出す状態を決める（DESIGN.md §3.2）。判定はすべてここで行い、menubar.js は表示するだけ。
# 出力: 1行目はアイコンの種類（off・warn・wait・check・on）。2行目以降はメニューの行で、タブで区切った
# 「種類 表示 [右の列] [ツールチップ]」。種類は head（見出し）・green・yellow・red・gray（左の印の色）・-（印なし）。
# 空行は区切り線。通信しない。本体の記録ファイルとログは読むだけ。表示は英語のみ。
set -u
setopt extended_glob   # [A-Za-z0-9_-]## と ~
zmodload zsh/datetime   # EPOCHSECONDS・strftime
zmodload -F zsh/stat b:zstat

label=local.cafe-wifi-okawari
log=$HOME/Library/Logs/cafe-wifi-okawari.log
ST=$HOME/Library/Caches/cafe-wifi-okawari
PD=$ST.pending
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
WT="${KN:h}/watched"
RC=/var/run/resolv.conf
CH=$ST.chain   # USEN の接続先のチェーン「MAC キー リース開始」。見つからなければキーを「-」にする（伏せ字の SSID は残さない）
now=$EPOCHSECONDS
TB=$'\t'
# USEN の網のチェーン（§3.2）。システムログに出る伏せ字の SSID（先頭2文字と末尾2文字、間は同じ文字数の *）とキー、キーと表記
typeset -A chains=('tu********Fi' tullys 'Ko********Fi' komeda)
typeset -A cname=(tullys "Tully's" komeda Komeda)
# ログの行の時刻（先頭19文字）をエポック秒にして t に入れる
at() { strftime -r -s t '%Y-%m-%d %H:%M:%S' "${1[1,19]}" 2>/dev/null }
# ブランド名の表記を nm に入れる（先頭だけ大文字。usen は USEN）。英字・数字・-・_ 以外を含めば空（MAC・IP などを出さない）
bn() { nm=; [[ $1 == [A-Za-z0-9_-]## ]] || return; [[ $1 == usen ]] && nm=USEN || nm=${(U)1[1]}${1[2,-1]} }
# 今の接続先（install.sh status・本体の netid と同じく、既定ゲートウェイの MAC。取れなければ IP）を net、
# 既定経路のインターフェースを ifc に入れる
netid() {
  local r; r=$(route -n get default 2>/dev/null) || r=
  gw=${${(M)${(f)r}:#*gateway:*}##* } ifc=${${(M)${(f)r}:#*interface:*}##* } net=
  if [[ -n $gw ]]; then
    net=$(arp -n "$gw" 2>/dev/null | awk '{ print $4 }')
    [[ $net == *:*:* ]] || net=$gw
  fi
}
# ifc のリース開始（エポック秒）を出す。読めなければ失敗
lease() {
  local l=(${(M)${(f)"$(ipconfig getsummary "$ifc" 2>/dev/null)"}:#*LeaseStartTime :*})
  strftime -r '%m/%d/%Y %H:%M:%S' "${l[1]##* : }" 2>/dev/null
}
# 今の接続先（USEN の網）のチェーンのキーを ck に入れる。分からなければ空。
# システムログを読むのは、リース開始ごとに1回だけ（リース開始は DHCP の更新でも進むので、見つからない網では更新ごとに
# 読み直す）。直近2時間の、今のインターフェースの最後の SSID の行を表と照らす（行はつなぐたびに1行出るので、最後の行が
# 今の接続。リース開始より前の行も使う）。リース開始から15秒は、つないだ直後の行の書き込みを待って読まない。
chain() {
  local c s m l
  ck= c=$(awk -v n="$net" '$1 == n { print $2, $3; exit }' "$CH" 2>/dev/null)
  [[ -n ${cname[${c%% *}]-} ]] && { ck=${c%% *}; return }
  [[ -n $ifc ]] || return
  s=$(lease) || return
  [[ $c == "- $s" ]] && return
  (( now - s >= 15 )) || return
  l=(${(M)${(f)"$(/usr/bin/log show --style compact --start "$(strftime '%F %T' $(( now - 7200 )))" \
    --predicate 'subsystem == "com.apple.captive" AND eventMessage CONTAINS "SSID"' 2>/dev/null)"}:#* $ifc: SSID \'*})
  (( $#l )) && { m=${${l[-1]#* $ifc: SSID \'}%%\'*}; ck=${chains[$m]-} }
  # 読む間に接続先・インターフェース・リース開始が変わっていれば、出さず残さない（別の網の SSID を今の接続先に結び付けない）
  [[ $(netid; print -r -- "$net $ifc $(lease)") == "$net $ifc $s" ]] || { ck=; return }
  # プロセスごとの一時ファイルから置き換える（同時に動いても互いの書きかけを公開しない）
  { awk -v n="$net" '$1 != n' "$CH" 2>/dev/null; print -r -- "$net ${ck:--} $s" } > "$CH.$$" && mv -f "$CH.$$" "$CH" ||
    rm -f "$CH.$$"
}

# ログの末尾 16KB のうち、直近の出来事として出す種類の行（ローテーションしないので全体は読まない）。
# 認証画面での同意をシステムログで確かめた行（captive login seen）も出す。
# 通信できている間のブランドの確認の失敗（redirect failed … net=…）は再接続の失敗ではないので除く。
hits=(${(M)${(f)"$(tail -c 16384 "$log" 2>/dev/null)"}:#[0-9](#c4)-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] (re-authenticated|consent recorded|captive login seen|login failed|redirect failed|auto stopped) *~*redirect failed * net=*})

if launchctl print gui/$UID/$label >/dev/null 2>&1; then
  kind=on rows=("head${TB}cafe-wifi-okawari")
  # 再認証から10分は ✓
  a=(${(M)hits:#??????????????????? re-authenticated *})
  (( $#a )) && at $a[-1] && (( now - t < 600 )) && kind=check

  netid

  if [[ -z $net ]]; then
    # 既定経路がない。Wi‑Fi に IPv4 があるか、macOS が認証画面を待っていれば認証画面待ち（どの網かは分からない）
    wifi=$(networksetup -listallhardwareports 2>/dev/null | awk '$0 == "Hardware Port: Wi-Fi" { getline; print $2; exit }')
    if [[ -n $wifi ]] && { [[ -n $(ipconfig getifaddr "$wifi" 2>/dev/null) ]] ||
         [[ $(scutil <<< "show State:/Network/Interface/$wifi/CaptiveNetwork" 2>/dev/null) == *'WaitingOnUI : TRUE'* ]] }; then
      kind=wait
      rows+=("yellow${TB}Waiting for Login Page" "-${TB}If the login page doesn't appear, open http://captive.apple.com.")
    else
      rows+="gray${TB}Offline"
    fi
  else
    wl=0   # チェーンの分かった見張り中の網
    if kb=$(awk -v n="$net" '$1 == n { f = 1; print $2 } END { exit !f }' "$KN" 2>/dev/null); then
      # 同じ MAC で同意済みのブランドが複数あれば並べる（install.sh status と同じ）。USEN はチェーンが分かれば「Tully's (USEN)」
      kb=(${(f)kb}) b=()
      for x in $kb; do
        bn "$x"; [[ $x == usen ]] && { chain; [[ -n $ck ]] && nm="$cname[$ck] (USEN)" }
        [[ -n $nm ]] && b+=$nm
      done
      dot=green name=${(j:, :)b} st='Auto Reconnect On'
    elif awk -v n="$net" -v t=$(( now - 86400 )) '$1 == n && $2 > t { f = 1 } END { exit !f }' "$WT" 2>/dev/null; then
      # 見張り中（§3.1）。チェーンが分かれば USEN の網で、利用者は認証画面で同意している。次の時間切れで USPOT-02 と
      # 確かめてから自動で送るので On と同じに出す（送る条件は変えない）。分からなければ黄の「次の時間切れから」
      chain
      if [[ -n $ck ]]; then dot=green name="$cname[$ck] (USEN)" st='Auto Reconnect On' wl=1
      else dot=yellow name= st='Auto Reconnect from Next Time-out'; fi
    else
      dot=gray name= st='Auto Reconnect Off'
    fi
    # 印の行は接続先の名前（分からなければ This Wi‑Fi）、その下に自動再接続の状態と案内。印は案内で赤・黄に変える
    rows+=(x "-$TB$st") i=$(( $#rows - 1 ))
    # 注意（今の接続先のときだけ。店を出たあとも本体の記録ファイルは残ることがある）
    # 状態ファイル「連続失敗回数 次回試行時刻 接続先 拒否の回数 知らせたか 拒否したブランド」で、知らせたあと
    n= next= prev= rej= told= rb=
    [[ -r $ST ]] && read -r n next prev rej told rb < "$ST"
    [[ $prev == "$net" && $told == 1 ]] && kind=warn dot=red rows+="-${TB}Couldn't reconnect automatically. Check the login page."
    # 同意待ち「MAC ブランド notified」「MAC usen 基準時刻 notified」（初めての網で知らせたあと・自動の停止のあと）
    pd=(); [[ -r $PD ]] && pd=(${=$(<"$PD")})
    if (( $#pd >= 3 )) && [[ $pd[1] == "$net" && $pd[-1] == notified ]]; then
      kind=warn rows+="-${TB}Accept the terms once on the login page. After that, it reconnects automatically."
      [[ $dot == red ]] || dot=yellow   # 利用者の操作待ちなので黄。失敗の赤は残す
    fi
    rows[i]="$dot$TB${name:-This Wi‑Fi}"

    # 次の時間切れの目安: 今の接続先での最後の認証から60分。認証画面での同意を確かめた行（ブランド付きの captive login seen。
    # 同意から60秒以内に書く）も起点にする。認証画面での同意の記録（(captive login)。送る前に書く）は除く。
    # その行の30秒より後に resolv.conf が書き換わっていれば（認証画面を通らずにつなぎ直した）、今の接続の認証ではないので出さない。
    # チェーンの分かった見張り中の網では、見張りを始めた行（ブランドのない captive login seen。接続から5分以内に書く）を使い、
    # その前5分以内に resolv.conf が書き換わっていれば（接続・認証画面での同意）その時刻を起点にする（早いほう）。
    if (( wl )); then
      a=(${(M)hits:#??????????????????? captive login seen net=$net})
      tip="Estimated from when you accepted on the login page, if the shop's limit is 60 minutes. It may be a few minutes off."
    else
      a=(${(M)hits:#??????????????????? (re-authenticated|consent recorded|captive login seen)* net=$net *~*'(captive login)'})
      tip="Estimated from the last authentication, if the shop's limit is 60 minutes."
    fi
    zstat -A m +mtime $RC 2>/dev/null || m=(0)
    if (( $#a )) && at $a[-1] && (( m[1] <= t + 30 )); then
      # 最後の行が同意の記録し直し（(online)。削除して入れ直したあと、認証済みの網で書く）なら認証の時刻ではないので、
      # それより前の (online) でない行が同じ接続のもの（その30秒より後に resolv.conf が書き換わっていない）ならそちらを起点にする
      if [[ $a[-1] == *' (online)' ]]; then
        u=$t b=(${a:#*' (online)'})
        (( $#b )) && at $b[-1] && (( m[1] <= t + 30 )) || t=$u
      fi
      (( wl && m[1] < t && m[1] > t - 300 )) && t=$m[1]
      (( now - t < 3600 )) && rows+="-${TB}Next Time-out$TB~$(strftime '%H:%M' $(( t + 3600 )))$TB$tip"
    fi
  fi
else
  kind=off rows=("head${TB}cafe-wifi-okawari" "gray${TB}Stopped" "-${TB}Run install.sh to Restart")
fi

# 直近の出来事（新しい順に3件）。時刻・種類・ブランド・秒数だけ（MAC・IP は出さない）。USEN はチェーンが分かっている接続先ならチェーン
typeset -A nc=(); [[ -r $CH ]] && while read -r x y z; do [[ -n ${cname[$y]-} ]] && nc[$x]=$y; done < "$CH"
strftime -s today %F $now; strftime -r -s md %F $today; strftime -s yday %F $(( md - 1 ))
(( $#hits )) && rows+=('' "head${TB}Recent")
for l in ${${(Oa)hits}[1,3]}; do
  w=(${=l[21,-1]}) d=${l[1,10]}
  i=${w[(i)net=*]}; bn "${w[i+1]-}"
  [[ ${w[i+1]-} == usen && -n ${nc[${w[i]#net=}]-} ]] && nm=$cname[${nc[${w[i]#net=}]}]
  b=${nm:+ · $nm}
  case $w[1] in
    re-authenticated) s=${${${(M)w:#t=<->s}[1]-}#t=}; e="Reconnected$b${s:+ · ${s%s} s}" ;;
    consent) e="Terms Accepted$b" ;;
    captive) e="Accepted on Login Page$b" ;;
    auto) e="Auto Reconnect Stopped$b" ;;
    *) e="Couldn't Reconnect" ;;   # login failed・redirect failed（本体はブランドを書かない）
  esac
  [[ $d == $today ]] && d=Today || { [[ $d == $yday ]] && d=Yesterday || d=${d[6,10]} }
  rows+="-$TB$d ${l[12,16]}$TB$e"
done

print -r -- $kind
print -rl -- "${rows[@]}"
