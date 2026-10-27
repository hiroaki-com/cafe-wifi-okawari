#!/bin/zsh
# メニューバーに出す状態を決める（DESIGN.md §3.2）。判定はすべてここで行い、menubar.js は表示するだけ。
# 出力: 1行目はアイコンの種類（off・warn・wait・check・on）。ネットワークの診断で危険があるか、危険の記録が残っていれば、空白と risk を足す（⚠）。
# 2行目以降はメニューの行で、タブで区切った「種類 表示 [右の列] [ツールチップ]」。種類は head（見出し）・green・yellow・red・
# gray（左の印の色）・-（印なし）。空行は区切り線。種類の前に > が付いた行は、直前の > のない行のサブメニューの行（> だけなら区切り線）。
# 通信しない。本体の記録ファイルとログ、診断の結果ファイルは読むだけ。表示は英語のみ。
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

# ネットワークの診断（§3.3）。診断の LaunchAgent が入っていなければ何も出さない（--no-netcheck は今のまま）。本体の停止中も出す。
# 読むのは netcheck.sh の結果ファイルと Check Now の要求ファイルだけ。表にない ID・段階・値の行は読み捨てる。
# 「⚠」（1行目の risk）は、結果が今の接続先のもので危険の行があるときと、危険の記録（.alert。利用者が Dismiss で消す）があるとき
risk=
strftime -s today %F $now; strftime -r -s md %F $today; strftime -s yday %F $(( md - 1 ))
if [[ -e $HOME/Library/LaunchAgents/$label.netcheck.plist ]]; then
  [[ $kind == off ]] && netid   # 停止中は今の接続先を求めていない
  NC=$ST.netcheck nr=() sub=() nk=0 nn=0 nd=gray
  [[ -r $NC ]] && { nr=(${(f)"$(<$NC)"}) }
  zstat -A nm +mtime $NC 2>/dev/null || nm=(0)
  if [[ -z $net ]]; then ns=Off
  elif (( ! $#nr )); then ns='Checking…'
  elif (( now - nm[1] > 60 )); then ns='Not Running'
  elif [[ -e $NC.now || $nr[1] != "v1 $net "* ]]; then ns='Checking…'
  else
    typeset -A lb=(wifi 'Wi‑Fi Security' gateway Gateway dns 'DNS Servers' routes Routes proxy Proxy ipv6 'IPv6 Routers' firewall Firewall
      airplay 'AirPlay Receiver' sharing Sharing open 'Open to This Network' updates 'macOS Updates'
      rootcerts 'Added Root Certificates' vpn VPN privaddr 'Private Wi‑Fi Address')
    typeset -A vl=(ok OK none None off Off on On stealth On unknown Unknown not-wifi 'Not Wi‑Fi' changed Changed new New
      extra 'Extra Routes' public 'Public Subnet' bypass 'Bypasses VPN' autodiscovery 'Auto-Discovery On' set Set
      multiple Multiple partial Partial uptodate 'Up to Date' not-checked 'Not Checked Recently'
      auto-off 'Auto Security Updates Off' remote-login 'Remote Login' file-sharing 'File Sharing'
      remote-management 'Remote Management' screen-sharing 'Screen Sharing' ollama Ollama lmstudio 'LM Studio'
      jupyter Jupyter mcp-inspector 'MCP Inspector' blocked 'Blocked by Firewall' apps Apps available Available added Added)
    typeset -A dc=(ok green notice yellow risk red unknown gray info -)
    # 理由（ツールチップ）と、注意・危険の行の下に出す案内。キーは「ID 値」か ID
    typeset -A tp=(
      'wifi none' "This Wi‑Fi has no encryption. People nearby can read unencrypted traffic, and a fake network can look the same."
      'wifi unknown' "Only unencrypted Wi‑Fi has been checked so far. Other kinds of security show as Unknown."
      'gateway changed' "The router's hardware address changed during this connection or right after reconnecting. Another device may be posing as the router."
      'dns changed' "The DNS servers this Wi‑Fi hands out changed during this connection. Another device may be answering in place of the network."
      'routes extra' "This Wi‑Fi added routes for some addresses."
      'routes public' "This Wi‑Fi uses public addresses for its local network."
      'routes bypass' "Routes from this Wi‑Fi send some traffic outside your VPN."
      'proxy autodiscovery' "This Mac looks for a proxy on each network, so a network can choose where your web traffic goes."
      'proxy set' "A proxy is set on this Mac. That's fine if you or your workplace set it."
      'ipv6 multiple' "More than one IPv6 router is announcing itself on this Wi‑Fi."
      'ipv6 changed' "The IPv6 router changed during this connection."
      'ipv6 new' "An IPv6 router appeared on this Wi‑Fi after it had none. A device may be offering itself as the router."
      'firewall stealth' "Stealth mode is on."
      'firewall on' "Stealth mode is off."
      'airplay on' "Other devices on this Wi‑Fi may be able to reach AirPlay Receiver."
      sharing "Other devices on this Wi‑Fi can reach this sharing service."
      'updates not-checked' "Software Update hasn't checked for updates in over 7 days."
      'updates auto-off' "Security Responses or system data files aren't installed automatically."
      'rootcerts added' "Added root certificates can let something read secure connections. That's fine if you or your workplace added them."
      'vpn partial' "A VPN is connected, but most traffic goes through this Wi‑Fi."
      'privaddr off' "Shops can tell this is the same Mac across visits. If you turn it on, the shop sees a new device and you accept the terms once again.")
    typeset -A gd=(
      'wifi none' 'Not encrypted. Use a VPN, and only HTTPS sites.'
      'gateway changed' 'Someone may be intercepting this Wi‑Fi. Disconnect, or use a VPN.'
      'dns changed' 'Someone may be redirecting websites. Disconnect, or use a VPN.'
      'routes bypass' 'Some traffic skips your VPN. Disconnect from this Wi‑Fi.'
      open 'Apps on this Mac accept connections from this Wi‑Fi. Limit them to this Mac (127.0.0.1).'
      'updates auto-off' 'Turn on security updates in System Settings › Software Update.'
      'updates available' 'Install macOS updates.'
      'firewall off' 'Turn on the firewall in System Settings.'
      'airplay on' 'Turn off AirPlay Receiver in System Settings.'
      sharing 'Turn off sharing on public Wi‑Fi.')
    typeset -A nv=()
    for x in ${nr[2,-1]}; do nv[${x%% *}]=${x#* }; done
    sub=(">head${TB}Checked $(strftime '%H:%M' $nm[1])")
    for g in 'This Network:wifi gateway dns routes proxy ipv6' 'This Mac:firewall airplay sharing open updates rootcerts vpn' 'Privacy:privaddr'; do
      sub+=(">head$TB${g%%:*}")
      for id in ${=g#*:}; do
        y=(${=nv[$id]-}) n= p=
        for x in ${y[3,-1]}; do [[ $x == n=<-> ]] && n=${x#n=}; [[ $x == p=[0-9,]## ]] && p=${x#p=}; done
        [[ -n ${dc[${y[1]-}]-} && -n ${vl[${y[2]-}]-} ]] || continue
        s=$vl[$y[2]]
        if [[ $y[2] == (apps|available|added) ]]; then
          [[ -n $n ]] || continue
          s="$n $s"; [[ $s == '1 Apps' ]] && s='1 App'
        fi
        tip=${tp[$id $y[2]]-}; [[ -z $tip && $y[1] == (notice|risk) ]] && tip=${tp[$id]-}
        [[ $id == open && -n $p ]] && tip="Ports: ${p//,/, }"
        sub+=(">$dc[$y[1]]$TB$lb[$id]$TB$s${tip:+$TB$tip}")
        [[ $y[1] == (notice|risk) ]] || continue
        [[ $y[1] == risk ]] && (( ++nk )) || (( ++nn ))
        # 暗号化なしの網でも、VPN を使っていれば案内しない
        [[ $id == wifi && ${nv[vpn]-} == 'ok on' ]] && continue
        x=${gd[$id $y[2]]-${gd[$id]-}}; [[ -n $x ]] && sub+=(">-$TB$x")
      done
      [[ $g == Privacy:* ]] || sub+='>'
    done
    if (( nk )); then nd=red ns="$nk Risk${${nk:#1}:+s}" risk=' risk'
    elif (( nn )); then nd=yellow ns="$nn Notice${${nn:#1}:+s}"
    else nd=green ns='No Issues Found'; fi
  fi
  rows+=('' "$nd${TB}Network Check$TB$ns" $sub)
  [[ -n $risk ]] && rows+="-${TB}Possible interception on this Wi‑Fi. See Network Check."
  # 危険の記録（新しいものから3件）。攻撃者が偽装をやめても、つなぎ直させても、店を出ても、利用者が Dismiss で消すまで出す
  typeset -A an=('gateway changed' 'Gateway Changed' 'dns changed' 'DNS Servers Changed' 'routes bypass' 'Routes Bypassed VPN')
  al=(); [[ -r $NC.alert ]] && { al=(${(M)${(f)"$(<$NC.alert)"}:#<-> (gateway changed|dns changed|routes bypass)}) }
  if (( $#al )); then
    risk=' risk'
    rows+="red${TB}Risk Detected Earlier"
    for x in ${${(Oa)al}[1,3]}; do
      y=(${=x}) d=$(strftime %F $y[1])
      [[ $d == $today ]] && d=Today || { [[ $d == $yday ]] && d=Yesterday || d=${d[6,10]} }
      rows+="-$TB$d $(strftime %H:%M $y[1])$TB$an[$y[2] $y[3]]"
    done
    rows+="-${TB}If you signed in to anything then, change those passwords."
  fi
fi

# 直近の出来事（新しい順に3件）。時刻・種類・ブランド・秒数だけ（MAC・IP は出さない）。USEN はチェーンが分かっている接続先ならチェーン
typeset -A nc=(); [[ -r $CH ]] && while read -r x y z; do [[ -n ${cname[$y]-} ]] && nc[$x]=$y; done < "$CH"
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

print -r -- $kind$risk
print -rl -- "${rows[@]}"
