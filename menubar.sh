#!/bin/zsh
# メニューバーに出す状態を決める（DESIGN.md §3.2）。判定はすべてここで行い、menubar.js は表示するだけ。
# 出力: 1行目はアイコンの種類（off・warn・wait・check・on）。2行目以降はメニューの行で、タブで区切った
# 「表示 [右の列] [ツールチップ]」。空行は区切り線。通信しない。本体の記録ファイルとログは読むだけ。表示は英語のみ。
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
now=$EPOCHSECONDS
# ログの行の時刻（先頭19文字）をエポック秒にして t に入れる
at() { strftime -r -s t '%Y-%m-%d %H:%M:%S' "${1[1,19]}" 2>/dev/null }
# ブランド名の表記を nm に入れる（先頭だけ大文字。usen は USEN）。英字・数字・-・_ 以外を含めば空（MAC・IP などを出さない）
bn() { nm=; [[ $1 == [A-Za-z0-9_-]## ]] || return; [[ $1 == usen ]] && nm=USEN || nm=${(U)1[1]}${1[2,-1]} }

# ログの末尾 16KB のうち、直近の出来事として出す種類の行（ローテーションしないので全体は読まない）。
# 通信できている間のブランドの確認の失敗（redirect failed … net=…）は再接続の失敗ではないので除く。
hits=(${(M)${(f)"$(tail -c 16384 "$log" 2>/dev/null)"}:#[0-9](#c4)-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] (re-authenticated|consent recorded|login failed|redirect failed|auto stopped) *~*redirect failed * net=*})

if launchctl print gui/$UID/$label >/dev/null 2>&1; then
  kind=on rows=('cafe-wifi-okawari — Running')
  # 再認証から10分は ✓
  a=(${(M)hits:#??????????????????? re-authenticated *})
  (( $#a )) && at $a[-1] && (( now - t < 600 )) && kind=check

  # 今の接続先（install.sh status・本体の netid と同じく、既定ゲートウェイの MAC。取れなければ IP）
  r=$(route -n get default 2>/dev/null) || r=
  gw=${${(M)${(f)r}:#*gateway:*}##* } net=
  if [[ -n $gw ]]; then
    net=$(arp -n "$gw" 2>/dev/null | awk '{ print $4 }')
    [[ $net == *:*:* ]] || net=$gw
  fi

  if [[ -z $net ]]; then
    # 既定経路がない。Wi‑Fi に IPv4 があるか、macOS が接続画面を待っていれば接続画面待ち（どの網かは分からない）
    wifi=$(networksetup -listallhardwareports 2>/dev/null | awk '$0 == "Hardware Port: Wi-Fi" { getline; print $2; exit }')
    if [[ -n $wifi ]] && { [[ -n $(ipconfig getifaddr "$wifi" 2>/dev/null) ]] ||
         [[ $(scutil <<< "show State:/Network/Interface/$wifi/CaptiveNetwork" 2>/dev/null) == *'WaitingOnUI : TRUE'* ]] }; then
      kind=wait
      rows+=('This Wi‑Fi: Waiting for Login Page' "If the login page doesn't appear, open http://captive.apple.com.")
    else
      rows+='This Wi‑Fi: Offline'
    fi
  else
    if kb=$(awk -v n="$net" '$1 == n { f = 1; print $2 } END { exit !f }' "$KN" 2>/dev/null); then
      # 同じ MAC で同意済みのブランドが複数あれば並べる（install.sh status と同じ）
      kb=(${(f)kb}) b=()
      for x in $kb; do bn "$x"; [[ -n $nm ]] && b+=$nm; done
      b=${(j:, :)b}
      rows+="This Wi‑Fi: ${b:+$b · }Auto Reconnect On"
    elif awk -v n="$net" -v t=$(( now - 86400 )) '$1 == n && $2 > t { f = 1 } END { exit !f }' "$WT" 2>/dev/null; then
      rows+='This Wi‑Fi: Auto Reconnect from Next Time-out'   # 見張り中（§3.1）
    else
      rows+='This Wi‑Fi: Auto Reconnect Off'
    fi
    # 注意（今の接続先のときだけ。店を出たあとも本体の記録ファイルは残ることがある）
    # 状態ファイル「連続失敗回数 次回試行時刻 接続先 拒否の回数 知らせたか 拒否したブランド」で、知らせたあと
    n= next= prev= rej= told= rb=
    [[ -r $ST ]] && read -r n next prev rej told rb < "$ST"
    [[ $prev == "$net" && $told == 1 ]] && kind=warn rows+="Couldn't reconnect automatically. Check the login page."
    # 同意待ち「MAC ブランド notified」「MAC usen 基準時刻 notified」（初めての網で知らせたあと・自動の停止のあと）
    pd=(); [[ -r $PD ]] && pd=(${=$(<"$PD")})
    (( $#pd >= 3 )) && [[ $pd[1] == "$net" && $pd[-1] == notified ]] &&
      kind=warn rows+='Accept the terms once on the login page. After that, it reconnects automatically.'

    # 次の時間切れの目安: 今の接続先での最後の認証から60分。接続画面での同意の記録（captive login。送る前に書く）は除く。
    # その行の30秒より後に resolv.conf が書き換わっていれば（つなぎ直した・自分で同意し直した）、今の接続の認証ではないので出さない。
    a=(${(M)hits:#??????????????????? (re-authenticated|consent recorded)* net=$net *~*'(captive login)'})
    zstat -A m +mtime $RC 2>/dev/null || m=(0)
    (( $#a )) && at $a[-1] && (( now - t < 3600 && m[1] <= t + 30 )) &&
      rows+="Next Time-out: ~$(strftime '%H:%M' $(( t + 3600 )))"$'\t\t'"Estimated from the last authentication, if the shop's limit is 60 minutes."
  fi
else
  kind=off rows=('cafe-wifi-okawari — Stopped' 'Run ./install.sh to Restart')
fi

# 直近の出来事（新しい順に3件）。時刻・種類・ブランド・秒数だけ（MAC・IP は出さない）
strftime -s today %F $now; strftime -r -s md %F $today; strftime -s yday %F $(( md - 1 ))
(( $#hits )) && rows+=''
for l in ${${(Oa)hits}[1,3]}; do
  w=(${=l[21,-1]}) d=${l[1,10]}
  bn "${w[${w[(i)net=*]}+1]-}"; b=${nm:+ · $nm}
  case $w[1] in
    re-authenticated) s=${${${(M)w:#t=<->s}[1]-}#t=}; e="Reconnected$b${s:+ · ${s%s} s}" ;;
    consent) e="Terms Accepted$b" ;;
    auto) e="Auto Reconnect Stopped$b" ;;
    *) e="Couldn't Reconnect" ;;   # login failed・redirect failed（本体はブランドを書かない）
  esac
  [[ $d == $today ]] && d=Today || { [[ $d == $yday ]] && d=Yesterday || d=${d[6,10]} }
  rows+="$d ${l[12,16]}"$'\t'"$e"
done

print -r -- $kind
print -rl -- "${rows[@]}"
