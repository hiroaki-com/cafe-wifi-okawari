#!/bin/zsh
# つないでいる網とこの Mac の設定を、通信せずに診断する（DESIGN.md §3.3）。launchd から10秒ごとと、DNS の設定が変わったとき・
# メニューバーの Check Now で実行される。結果ファイルを書き、注意・危険の変化だけを本体のログに1行ずつ足す。
# 本体とは別に動き、本体のファイルは読まない。設定を変えず、どこへも送らない。表示は menubar.sh が結果ファイルから作る。
# 網やプロセスから来た文はログにも結果ファイルにも書かない。書くのは固定の語・数・ポート番号と、形を確かめたゲートウェイの MAC・IP だけ。
set -u
setopt extended_glob   # (#c1,2) と <0-255>
zmodload zsh/datetime   # EPOCHSECONDS・strftime
zmodload -F zsh/stat b:zstat
umask 077

log=$HOME/Library/Logs/cafe-wifi-okawari.log
NC=$HOME/Library/Caches/cafe-wifi-okawari.netcheck   # 結果「v1 接続先 時刻 0 -」と「ID 段階 値 [n=数] [p=ポート,…]」の行
BS=$NC.base   # 接続の基準「ゲートウェイの IP 接続の見分け ゲートウェイの MAC IPv6 のルーター」と、確かめ中の危険「ID 値 最初に見た時刻」
RQ=$NC.now    # Check Now の要求（menubar.js が作る）。中身は読まず、終わりに消す
RC=/var/run/resolv.conf   # つなぎ直したときと認証画面で同意したときに書き換わる（DESIGN.md §7）。Wi‑Fi でない接続の見分けに使う
CONFIRM=5     # 危険の条件が2回以上の診断にわたって、この秒数より長く続いたときだけ危険にする（一時的な揺れで赤にしない）
now=$EPOCHSECONDS

# 宛先 $1 への経路のゲートウェイを rg に（直結なら空）、インターフェースを ri に入れる。通信はしない（本体と同じ）
rt() {
  local r=$(/sbin/route -n get "$1" 2>/dev/null)
  rg=${${(M)${(f)r}:#*gateway:*}##* } ri=${${(M)${(f)r}:#*interface:*}##* }
}
# MAC を区切りなしの小文字12桁にする。MAC の形でなければ失敗（本体と同じ）
hex() {
  local o h= a=(${(s.:.)${${1:l}//-/:}})
  (( $#a == 6 )) || return
  for o in $a; do [[ $o == [0-9a-f](|[0-9a-f]) ]] || return; h+=${(l:2::0:)o}; done
  print -r -- $h
}

# 今の接続先（本体の netid と同じく、既定ゲートウェイの MAC。取れなければ IP）
rt default; gw=$rg ifc=$ri mac= net=
[[ $gw == <0-255>.<0-255>.<0-255>.<0-255> ]] || gw=
if [[ -n $gw ]]; then
  mac=$(/usr/sbin/arp -n "$gw" 2>/dev/null | /usr/bin/awk '{ print $4 }')
  hex $mac >/dev/null || mac=
  net=${mac:-$gw}
fi
if [[ -z $net ]]; then
  # 既定経路がない（未接続・認証画面待ち）。メニューバーは自分で Off と出すので、結果は書き換えず、動いていることだけ残す
  [[ -e $NC ]] && /usr/bin/touch $NC
  rm -f $RQ; exit 0
fi

wifi=$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk '$0 == "Hardware Port: Wi-Fi" { getline; print $2; exit }')
# VPN（全経路）は既定経路が VPN のインターフェースを通る。そのときの網は下の Wi‑Fi。
# 既定経路を残したまま 0/1・128/1 の経路で全部を通す VPN（OpenVPN の def1 など）は、公開の宛先への経路で見る
vpn=0 lan=$ifc
if [[ $ifc == (utun|ipsec|ppp)<-> ]]; then vpn=1 lan=$wifi
else rt 1.1.1.1; [[ $ri == (utun|ipsec|ppp)<-> ]] && vpn=1; fi

# Wi‑Fi の状態。最上位のキーは名前順で、ConnectionID は DHCP のパケット（ドメイン名など網が決める文字列を含む）より前、
# Security は最後に出る（実機）。網の文字列に紛れた同じ形の行を拾わないよう、頭の空白2つから行全体で比べ、前のキーは最初の行、最後のキーは最後の行を使う
gs=(); [[ -n $lan && $lan == "$wifi" ]] && gs=(${(f)"$(/usr/sbin/ipconfig getsummary $wifi 2>/dev/null)"})
cid=${${${(M)gs:#  ConnectionID : <->}[1]-}##* }

# 接続の基準（ゲートウェイの IP と接続の見分けの組が同じ間）。Wi‑Fi はつなぐたびに増える ConnectionID（スリープの間は同じ網なら変わらず、
# 再起動で1に戻るので起動時刻と組にする。実機）。resolv.conf の更新時刻は IPv6 の RA の DNS サーバーや DHCP の更新で網の側から変えられ、
# 基準を取り直させられるので、Wi‑Fi では使わない。Wi‑Fi でなければ resolv.conf の更新時刻（リースの更新では変わらない）
bt=${${"$(/usr/sbin/sysctl -n kern.boottime 2>/dev/null)"#*sec = }%%,*}
if [[ -n $cid && $bt == <-> ]]; then m=(c$bt.$cid)
else zstat -A m +mtime $RC 2>/dev/null || m=(0); fi
b=(); [[ -r $BS ]] && { b=(${(f)"$(<$BS)"}) }
bl=(${=b[1]-}) old=1
typeset -A sus=()   # 確かめ中の危険「ID:値」→ 最初に見た時刻
if (( $#bl == 4 )) && [[ $bl[1] == "$gw" && $bl[2] == "$m[1]" ]] && { [[ $bl[3] == - ]] || hex $bl[3] >/dev/null }; then
  for x in ${b[2,-1]}; do y=(${=x}); (( $#y == 3 )) && [[ $y[3] == <-> ]] && sus[$y[1]:$y[2]]=$y[3]; done
else
  bl=($gw $m[1] - -) old=0
fi
[[ $bl[3] == - && -n $mac ]] && bl[3]=$mac
cur=()
# 危険の条件 $1=ID $2=値 を見た。前の診断から続いていて CONFIRM 秒を過ぎていれば成功（危険）
seen() {
  local t=${sus[$1:$2]-$now}
  cur+="$1 $2 $t"
  (( now - t >= CONFIRM ))
}

# 待ち受け（TCP の LISTEN のうちループバック以外）。共有（S）・AirPlay 受信（A）・それ以外（O）に分ける
typeset -A svc=(22 remote-login 445 file-sharing 548 file-sharing 3283 remote-management 5900 screen-sharing)
typeset -A known=(11434 ollama 1234 lmstudio 8888 jupyter 6274 mcp-inspector 6277 mcp-inspector)
sh=() air=0 op=() pids=() kn=
for l in ${(f)"$(/usr/sbin/netstat -anv -p tcp 2>/dev/null)"}; do
  w=(${=l}); [[ ${w[6]-} == LISTEN ]] || continue
  a=${w[4]%.*} p=${w[4]##*.}
  [[ $p == <-> && $a != (127.*|::1|*%lo0) ]] || continue
  if [[ -n ${svc[$p]-} ]]; then sh+=$svc[$p]
  elif (( p == 7000 )); then air=1
  else
    # 持ち主（netstat の「名前:PID」の PID）が macOS のプログラム（/System・/usr/libexec の下。例: rapportd）なら数えない。
    # /usr/bin の python3・nc などは利用者が動かすものなので数える。名前は比べるだけで、どこにも書かない
    pid=(${(M)w:#*:<->}) pid=${${pid[-1]-}##*:}
    [[ $(/bin/ps -o comm= -p "$pid" 2>/dev/null) == (/System/|/usr/libexec/)* ]] && continue
    op+=$p pids+=${pid:-?$p}; [[ -z $kn ]] && kn=${known[$p]-}   # PID が読めなければポートごとに1つと数える
  fi
done
sh=(${(u)sh}) op=(${(onu)op}) pids=(${(u)pids})

# 段階は ok・notice・risk・unknown・info。値は固定の語
rows=()
# This Network
if [[ -n $lan && $lan == "$wifi" ]]; then
  s=${${${(M)gs:#  Security : [A-Z0-9_]##}[-1]-}##* }
  # 実機で確かめたのは暗号化なしの NONE だけ。ほかの値は確かめるまで Unknown（DESIGN.md §3.3）
  [[ $s == NONE ]] && rows+='wifi notice none' || rows+='wifi unknown unknown'
else
  rows+='wifi unknown not-wifi'
fi

if [[ -z $mac ]]; then rows+='gateway unknown unknown'
elif [[ $(hex $mac) == "$(hex $bl[3])" ]]; then rows+='gateway ok ok'
elif seen gateway changed; then rows+='gateway risk changed'
else rows+='gateway ok ok'; fi

# Wi‑Fi 側の、既定・サブネット・ホスト・マルチキャスト以外のゲートウェイ経路（DHCP の option 121 などで足されたもの）
ex=(${(f)"$(/usr/sbin/netstat -rn -f inet 2>/dev/null | /usr/bin/awk -v i="$lan" '$4 == i && $1 != "default" && $3 ~ /G/ && $3 !~ /H/')"})
# この Mac の IPv4 が私用の範囲の外か（比べるだけで、どこにも書かない）
ip=$(/usr/sbin/ipconfig getifaddr "$lan" 2>/dev/null) pub=0
[[ $ip == <0-255>.<0-255>.<0-255>.<0-255> &&
   $ip != (10.*|192.168.*|169.254.*|172.(1[6-9]|2[0-9]|3[01]).*|100.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7]).*) ]] && pub=1
if (( vpn )); then
  # VPN の使用中に、Wi‑Fi 側の経路・サブネットか、決まった公開の宛先への経路が Wi‑Fi を通れば、VPN の外へ出る（TunnelVision・TunnelCrack）
  by=$(( $#ex || pub ))
  for d in 1.1.1.1 17.253.144.10 8.8.8.8; do rt $d; [[ -n $lan && $ri == "$lan" ]] && by=1; done
  (( by )) && seen routes bypass && rows+='routes risk bypass' || rows+='routes ok ok'
elif (( $#ex )); then rows+="routes notice extra n=$#ex"
elif (( pub )); then rows+='routes notice public'
else rows+='routes ok ok'; fi

# 行全体で比べる（プロキシの名前などの値に同じ形の文字列があっても拾わない）
x=(${(f)"$(/usr/sbin/scutil --proxy 2>/dev/null)"})
if (( ! $#x )); then rows+='proxy unknown unknown'
elif [[ -n ${(M)x:#  ProxyAutoDiscoveryEnable : 1} ]]; then rows+='proxy notice autodiscovery'
elif [[ -n ${(M)x:#  (ProxyAutoConfig|HTTP|HTTPS|SOCKS)Enable : 1} ]]; then rows+='proxy notice set'
else rows+='proxy ok off'; fi

# IPv6 のルーター（Wi‑Fi 側の行だけ。utun の行はシステムのもの）。最初に見えたルーターを基準にする
ra=(${${(M)${(f)"$(/usr/sbin/ndp -rn 2>/dev/null)"}:#* if=$lan,*}%% *})
ra=(${(o)${(M)ra:#[[:xdigit:]:]##(%[[:alnum:]]##|)}})
r6=${(j:,:)ra}; [[ -n $r6 ]] || r6=-
[[ $bl[4] == - ]] && bl[4]=$r6
if (( ! $#ra )); then rows+='ipv6 ok none'
elif [[ $r6 != $bl[4] ]]; then rows+='ipv6 notice changed'
elif (( $#ra > 1 )); then rows+="ipv6 notice multiple n=$#ra"
else rows+='ipv6 ok ok'; fi

# This Mac
x=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --getstealthmode --getblockall 2>/dev/null)
blockall=0; [[ $x == *'block all non-essential'* ]] && blockall=1
if [[ $x == *'(State = 0)'* ]]; then rows+='firewall notice off'
elif [[ $x == *'(State = '[12]')'* ]]; then [[ $x == *'stealth mode is on'* ]] && rows+='firewall ok stealth' || rows+='firewall ok on'
else rows+='firewall unknown unknown'; fi

# AirPlay 受信。キーがなければ既定（有効）。待ち受け（7000）があれば有効
[[ $(/usr/bin/defaults -currentHost read com.apple.controlcenter AirplayReceiverEnabled 2>/dev/null) == 0 ]] && (( ! air )) &&
  rows+='airplay ok off' || rows+='airplay notice on'

(( $#sh )) && rows+="sharing notice $sh[1] n=$#sh" || rows+='sharing ok off'

if (( ! $#op )); then rows+='open ok none'
elif (( blockall )); then rows+="open ok blocked n=$#pids p=${(j:,:)op}"
else rows+="open notice ${kn:-apps} n=$#pids p=${(j:,:)op}"; fi

# macOS の更新（ソフトウェア・アップデートの最後の確認の結果。通信しない）
x=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null)
k() { print -r -- ${${${(M)${(f)x}:#[[:space:]]#$1 = *}[1]#*= }%;} }
u=$(k LastRecommendedUpdatesAvailable) d=$(k LastSuccessfulDate)
TZ=UTC strftime -r -s t '%Y-%m-%d %H:%M:%S' "${${d#\"}[1,19]}" 2>/dev/null || t=   # 「"2026-10-26 04:56:33 +0000"」（UTC）
if [[ $(k ConfigDataInstall) == 0 || $(k CriticalUpdateInstall) == 0 ]]; then rows+='updates notice auto-off'
elif [[ $u == <1-> ]]; then rows+="updates notice available n=$u"
elif [[ -z $t || $u != <-> ]]; then rows+='updates unknown unknown'
elif (( now - t > 7 * 86400 )); then rows+='updates notice not-checked'
else rows+='updates ok uptodate'; fi

# 利用者・管理者が足したルート証明書の数（証明書の名前は読まない）
# 足した証明書がなければ、決まった1文だけを標準エラーに出して 1 で終わる（実機）。証明書の名前に同じ文や数の行を入れても
# 数を変えられないよう、数は成功したときの行全体の一致で、「なし」は出力全体の一致で見る
c=0
for o in '' -d; do
  x=$(/usr/bin/security dump-trust-settings $o 2>&1) r=$?
  y=${${(M)${(f)x}:#Number of trusted certs = <->}[1]-}
  if (( ! r )) && [[ -n $y ]]; then (( c += ${y##* } ))
  elif (( r )) && [[ $x == 'SecTrustSettingsCopyCertificates: No Trust Settings were found.' ]]; then :
  else c=-1; break; fi
done
(( c < 0 )) && rows+='rootcerts unknown unknown' || { (( c )) && rows+="rootcerts notice added n=$c" || rows+='rootcerts ok none' }

if (( vpn )); then rows+='vpn ok on'
elif [[ -n ${(M)${(f)"$(/usr/sbin/scutil --nc list 2>/dev/null)"}:#[* ] \(Connected\) *} ]]; then rows+='vpn unknown partial'   # 状態の欄だけ見る（名前は見ない）
elif [[ $rows[1] == 'wifi notice none' ]]; then rows+='vpn notice off'
else rows+='vpn unknown off'; fi

# Privacy（色の印を付けない情報）。プライベート Wi‑Fi アドレスは、今の MAC とハードウェアの MAC を比べるだけ（値は残さない）
if [[ -n $lan && $lan == "$wifi" ]] && e1=$(hex "$(/sbin/ifconfig $wifi ether 2>/dev/null | /usr/bin/awk '$1 == "ether" { print $2; exit }')") &&
   e2=$(hex "$(/usr/sbin/networksetup -getmacaddress $wifi 2>/dev/null | /usr/bin/awk '{ print $3; exit }')"); then
  [[ $e1 == "$e2" ]] && rows+='privaddr info off' || rows+='privaddr info on'
else
  rows+='privaddr info unknown'
fi

# 注意・危険に変わったとき・注意・危険から戻ったときだけログに1行。網の項目は、接続の基準を取り直したら前の結果と比べない（新しい網で1回書く）
p=(); [[ -r $NC ]] && { p=(${(f)"$(<$NC)"}) }
typeset -A prev=()
for x in ${p[2,-1]}; do y=(${=x}); prev[$y[1]]=${x#* }; done
(( old )) || for x in wifi gateway routes proxy ipv6 vpn privaddr; do unset "prev[$x]"; done
for x in $rows; do
  y=(${=x}) q=${prev[$y[1]]-ok}
  [[ ${x#* } == "$q" ]] && continue
  [[ $y[2] == (notice|risk) || ${q%% *} == (notice|risk) ]] || continue
  if [[ $x == 'gateway risk changed' ]]; then
    print -r -- "$(strftime '%F %T' $now) netcheck $x net=$bl[3] to=$mac" >> $log
  else
    print -r -- "$(strftime '%F %T' $now) netcheck $x net=$net" >> $log
  fi
done 2>/dev/null

# 結果と基準は、中身が変わったときだけ一時ファイルから置き換える（変わらなければ更新時刻だけ進める。メニューバーは60秒より古ければ Not Running）
if [[ ${p[1]-} == "v1 $net "* && ${(F)p[2,-1]} == "${(F)rows}" ]]; then
  /usr/bin/touch $NC
else
  print -rl -- "v1 $net $now 0 -" $rows > $NC.$$ && mv -f $NC.$$ $NC || rm -f $NC.$$
fi
x=("$bl" $cur)
[[ ${(F)x} == "${(F)b}" ]] || { print -rl -- $x > $BS.$$ && mv -f $BS.$$ $BS || rm -f $BS.$$ }
rm -f $RQ
exit 0
