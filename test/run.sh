#!/bin/zsh
# 模擬の curl・route・arp・ipconfig・ifconfig・defaults・osascript・launchctl・networksetup・scutil で分岐を確かめる。
# ネットワークの診断（netcheck.sh）は、模擬の netstat・ndp・socketfilterfw・security・ps も使う。
# 実際の網には一切つながない。
# 使い方: zsh test/run.sh
set -u
zmodload zsh/datetime   # EPOCHSECONDS
root=${0:A:h:h}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export M=$T HOME="$T/home"
mkdir -p "$HOME" $T/bin

# --- 模擬コマンド --------------------------------------------------------------
# curl: captive.apple.com は $M/authed があれば Success、なければ 302 で $LOC へ
#       （既定は Wi2 の redirect?…。クエリの mac・ip は $LMAC・$LIP）。
#       redirect?… は $REDIR（ok/nocookie/503/other/timeout/error/chain/query）、ブランドは $BRAND（既定 doutor）。
#       着くページは $PAGE（既定 index.html。捕捉中の実測は同意ページ index.html、認証済みはランディング landing.html）。
#       引数なしの redirect（認証済みでのブランド確認）は $BARE（ok/other/timeout）、着くページは $BAREPAGE（既定 landing.html）。
#       login は本文 $LOGIN と HTTP コード $LHTTP（既定 200。000 ならタイムアウト）を返す。$RECOVER があれば認証済みにする
#       （数なら、その回数の確認のあとで認証済みにする）。-H・-e の値は $M/headers に残す。
#       login は、redirect で受け取った session_id を同じ jar から送り（-b）、本文が同意の JSON のときだけ受け付ける。
#       違えば $M/badlogin に残し、拒否（HTTP 403・result:false）を返す。
#       プローブは $PROBE=down なら通信失敗、$PROBEHTTP があればその HTTP コードを返す。
#       $SWITCH があれば既定経路の接続先を別の MAC に切り替える（login なら送信後、pre なら redirect の時点）。
#       USEN の機器 $UD（10.9.8.7:8080）: 画面 /captive/ は $UPAGE、/captive/dist/page.js は $UJS
#       （ok/notitle・nomark・noterm/big（上限超え）/404/timeout。changed は規約の文面 $TJ2）。同意の POST /capi/welcome は
#       本文を $M/ubody に残し、本文 $ULOGIN と HTTP コード $UHTTP（既定 200。000 ならタイムアウト）を返す。$RECOVER は login と同じ。
#       $USWITCH（page/js/post）なら、その要求の時点で既定経路をなくす（$M/noroute）。機器への要求の --max-filesize は $M/mfs に、
#       --proto '=http' がなければ $M/badproto に残す。どの要求でも --noproxy '*' がなければ $M/proxied に残す。
cat > $T/bin/curl <<'EOS'
#!/bin/zsh
url=${@[-1]} jar= bjar= data= proto= mfs= np=0
for ((i = 1; i <= $#; i++)); do
  [[ ${@[i]} == -c ]] && jar=${@[i+1]}
  [[ ${@[i]} == -b ]] && bjar=${@[i+1]}
  [[ ${@[i]} == --data ]] && data=${@[i+1]}
  [[ ${@[i]} == --proto ]] && proto=${@[i+1]}
  [[ ${@[i]} == --max-filesize ]] && mfs=${@[i+1]}
  [[ ${@[i]} == --noproxy && ${@[i+1]} == '*' ]] && np=1
  [[ ${@[i]} == -[He] ]] && print -r -- "${@[i+1]}" >> $M/headers
done
print -r -- "$url" >> $M/calls
(( np )) || print -r -- "$url" >> $M/proxied
W=https://service.wi2.ne.jp
land() { printf '.service.wi2.ne.jp\tFALSE\t/\tTRUE\t0\tsession_id\tabc\n' > $jar
         [[ ${SWITCH-} == pre ]] && touch $M/switched
         printf '302 %s/freewifi/%s/%s%s' $W "${BRAND-doutor}" "${2-landing.html}" "${1-}" }
recover() { if [[ ${RECOVER-} == <-> ]]; then print $RECOVER > $M/late; elif [[ -n ${RECOVER-} ]]; then touch $M/authed; fi }
# USEN の機器の GET。$1=模擬の状態 $2=本文
uget() {
  [[ -n $mfs ]] && print -r -- $mfs >> $M/mfs
  case $1 in
    big) printf '%s\n200' "${2[1,10]}"; exit 63 ;;
    404) printf 'Not Found\n404' ;;
    timeout) printf '\n000'; exit 28 ;;
    *) printf '%s\n200' "$2" ;;
  esac
}
case $url in
  http://10.9.8.7:8080/*)
    [[ $proto == '=http' ]] || print -r -- "$url" >> $M/badproto
    case $url in
      */captive/) [[ ${USWITCH-} == page ]] && touch $M/noroute
        [[ ${UPAGE-ok} == notitle ]] && t=Portal || t=USPOT-02
        uget "${UPAGE-ok}" "<!DOCTYPE html><html><head><title>$t</title></head><body><div id=\"app\"></div></body></html>" ;;
      */captive/dist/page.js) [[ ${USWITCH-} == js ]] && touch $M/noroute
        j=$TJ; [[ ${UJS-} == changed ]] && j=$TJ2
        k=DAVOLINK_; [[ ${UJS-} == nomark ]] && k=OTHER_
        s="term:{title:\"利用規約\"$j]}},E={}"; [[ ${UJS-} == noterm ]] && s='E={}'
        uget "${UJS-ok}" "(function(){var k=\"${k}lang\",t={$s,u={term:{title:\"Terms of Use\",content:[\"x\"]}}})()" ;;
      */capi/welcome) print -r -- "$data" > $M/ubody
        [[ ${UHTTP-} == 000 ]] && { printf '\n000'; exit 28 }
        [[ ${USWITCH-} == post ]] && touch $M/noroute
        printf '%s\n%s' "${ULOGIN-}" "${UHTTP-200}"; recover ;;
    esac ;;
  *hotspot-detect*)
    [[ ${PROBE-} == down ]] && { printf '\n000 '; exit 7 }
    [[ -n ${PROBEHTTP-} ]] && { printf 'x\n%s ' $PROBEHTTP; exit 0 }
    if [[ -s $M/late ]]; then   # 認証後、疎通が戻るまでに $M/late 回の確認がかかる
      n=$(<$M/late); (( n > 1 )) && print $((n - 1)) > $M/late || { rm $M/late; touch $M/authed }
    fi
    [[ -e $M/authed ]] && printf '<HTML><TITLE>Success</TITLE></HTML>\n200 ' ||
      printf 'x\n302 %s' "${LOC-$W/wi2auth/redirect?cmd=login&mac=${LMAC-aa:bb:cc:dd:ee:0f}&ip=${LIP-10.0.0.5}&essid=%20&apname=tunnel%201&apgroup=&url=http%3A%2F%2Fcaptive.apple.com%2F}" ;;
  */wi2auth/redirect\?*) case ${REDIR-ok} in
    ok) land '' "${PAGE-index.html}" ;;
    query) land '?lang=ja' "${PAGE-index.html}" ;;
    chain) printf '302 %s/wi2auth/next' $W ;;
    nocookie) printf '302 %s/freewifi/doutor/index.html' $W ;;
    503) printf '503 ' ;;
    other) printf '302 https://example.com/' ;;
    error) printf '302 %s/wi2auth/error/ctrlapi_timeout.html?mac=%s&ip=%s' $W ${LMAC-aa:bb:cc:dd:ee:0f} ${LIP-10.0.0.5} ;;
    timeout) printf '000 '; exit 28 ;;
  esac ;;
  */wi2auth/next) land '' index.html ;;
  */wi2auth/redirect) case ${BARE-ok} in
    ok) land '' "${BAREPAGE-landing.html}" ;;
    other) printf '302 %s/wi2auth/error/ctrlapi_timeout.html' $W ;;
    timeout) printf '000 '; exit 28 ;;
  esac ;;
  $W/wi2auth/xhr/login) [[ ${LHTTP-} == 000 ]] && { printf '\n000'; exit 28 }
    if [[ -z $bjar || $bjar != $jar ]] || ! grep -q $'\tsession_id\tabc$' $bjar ||
       [[ $data != '{"login_method":"onetap","login_params":{"agree":"1"}}' ]]; then
      print -r -- "cookie=$bjar data=$data" >> $M/badlogin; printf '{"result":false}\n403'; exit 0
    fi
    [[ ${SWITCH-} == 1 ]] && touch $M/switched
    printf '%s\n%s' "${LOGIN-}" "${LHTTP-200}"; recover; exit 0 ;;
esac
EOS
# route: 既定経路は、$NOROUTE か $M/noroute があればなし。ゲートウェイは $DEFGW（既定 10.0.0.1。none ならゲートウェイの行なし）、
# インターフェースは $DEFIF（既定 en0）。en0 に限った既定経路（-ifscope en0）のゲートウェイは $LANGW（既定 10.0.0.1）。
# 機器（default 以外）への経路は $DEVRT
# （既定は既定経路と同じ。ifc=別のインターフェース、gw=別のゲートウェイ、direct=同じインターフェースの直結）
cat > $T/bin/route <<'EOS'
#!/bin/sh
if [ "$3" = -ifscope ]; then
  { [ -n "$NOROUTE" ] || [ -e $M/noroute ] || [ "$4" != en0 ]; } && exit 1
  printf '   route to: default\n    gateway: %s\n  interface: en0\n' "${LANGW:-10.0.0.1}"; exit 0
fi
if [ "$3" = default ]; then
  { [ -n "$NOROUTE" ] || [ -e $M/noroute ]; } && exit 1
  [ "$DEFGW" = none ] && { printf '   route to: default\n  interface: %s\n' "${DEFIF:-en0}"; exit 0; }
  printf '   route to: default\n    gateway: %s\n  interface: %s\n' "${DEFGW:-10.0.0.1}" "${DEFIF:-en0}"; exit 0
fi
echo "   route to: $3"
case $DEVRT in
  ifc) printf '    gateway: 10.8.0.1\n  interface: utun4\n' ;;
  gw) printf '    gateway: 10.0.0.9\n  interface: en0\n' ;;
  direct) printf '  interface: en0\n' ;;
  *) printf '    gateway: 10.0.0.1\n  interface: en0\n' ;;
esac
EOS
# arp: 既定ゲートウェイの MAC は $MAC（ゲートウェイがなければ失敗。$M/switched があれば別の回線 cc:cc:cc:cc:cc:03）
print '#!/bin/sh\n[ -z "$2" ] && exit 1\n[ -e $M/switched ] && MAC=cc:cc:cc:cc:cc:03\necho "? ($2) at $MAC on en0 ifscope [ethernet]"' > $T/bin/arp
# ipconfig: DHCP のドメイン名は $DOM（既定は空）、自分の IP は $MYIP（既定 10.0.0.5。en0 だけ）。
# getsummary のリース開始は $M/lease か $LEASE（エポック秒。既定は resolv.conf の更新時刻、none なら行なし）。実機と同じ順に、$CID があれば
# 最上位の ConnectionID、$DHCPDOM があれば DHCP のパケットのドメイン名（網が決める文字列）、$WSEC があれば最後に Security の行。
# getpacket は en0 だけで、$DHCPDOM（前に出す）・サブネットマスク $MASK（既定 255.255.255.0）・DNS サーバー $DNS（既定 10.0.0.1。none なら行なし）・
# $OPT121 があれば経路のオプション（option 121。実機の表記は実行ファイルの文字列「classless_static_route」「classless_route」から）
cat > $T/bin/ipconfig <<'EOS'
#!/bin/sh
case $1 in
  getoption) printf "%s\n" "$DOM" ;;
  getpacket) [ "$2" = en0 ] || exit 1
    [ -n "$DHCPDOM" ] && printf 'domain_name (string): %s\n' "$DHCPDOM"
    printf 'subnet_mask (ip): %s\n' "${MASK-255.255.255.0}"
    [ "$DNS" = none ] || printf 'domain_name_server (ip_mult): {%s}\n' "${DNS-10.0.0.1}"
    [ -n "$OPT121" ] && printf 'classless_static_route (classless_route): {%s}\n' "$OPT121"; exit 0 ;;
  getifaddr) [ "$2" = en0 ] && echo "${MYIP-10.0.0.5}" ;;
  getsummary) [ -n "$CID" ] && printf '  ConnectionID : %s\n' "$CID"
    [ -e $M/lease ] && LEASE=$(cat $M/lease)
    [ "$LEASE" = none ] ||
    printf '        LeaseStartTime : %s\n' "$(date -r "${LEASE:-$(stat -f %m $M/resolv)}" '+%m/%d/%Y %H:%M:%S')"
    [ -n "$DHCPDOM" ] && printf 'domain_name (string): %s\n' "$DHCPDOM"
    [ -n "$WSEC" ] && printf '  Security : %s\n' "$WSEC"; exit 0 ;;
esac
EOS
# log show: 呼び出しを $M/logcalls に残す。--start 以後の $WEBSHEET（エポック秒、空白区切り）に websheet: success の行を出す。
# $LOGFAIL なら失敗、$LOGSWITCH なら読む間に接続先を切り替える、$LOGLEASE なら読む間にリース開始をその値に変える。SSID を探す呼び出しには、--start 以後の
# $SSIDLOG（「エポック秒:インターフェース:伏せ字の SSID」、空白区切り）の行を出す。
cat > $T/bin/log <<'EOS'
#!/bin/zsh
zmodload zsh/datetime
print -r -- "$*" >> $M/logcalls
[[ -n ${LOGSWITCH-} ]] && touch $M/switched
[[ -n ${LOGLEASE-} ]] && print -r -- $LOGLEASE > $M/lease
[[ -n ${LOGFAIL-} ]] && exit 1
s=$(strftime -r '%Y-%m-%d %H:%M:%S' "${@[${@[(i)--start]}+1]}") || exit 64
print 'Timestamp               Ty Process[PID:TID]'
if [[ $* == *'"SSID"'* ]]; then
  for w in ${=SSIDLOG-}; do
    (( ${w%%:*} >= s )) && print -r -- "$(strftime '%F %T' ${w%%:*}).000 Df configd[357:10a2] [com.apple.captive:Controller] ${${w#*:}%%:*}: SSID '${w#*:*:}' setting interface rank Never (no cache entry)"
  done
  exit 0
fi
for w in ${=WEBSHEET-}; do
  (( w >= s )) && print -r -- "$(strftime '%F %T' $w).000 Df configd[370:12ee] [com.apple.captive:Controller] Online (websheet: success)"
done
exit 0
EOS
print '#!/bin/sh\nprintf "en0: flags=8863<UP>\\n\\tether %s\\n" "${MYMAC-aa:bb:cc:dd:ee:0f}"' > $T/bin/ifconfig
print '#!/bin/sh\nprintf "%s\\n" "$2" >> $M/notify' > $T/bin/osascript
# defaults: macOS の優先言語を $LANGS（既定は ja-JP）として返す。
# AirPlay 受信のキーは $AIRPLAY（既定 0、none ならキーなし）。ソフトウェア・アップデートは、最後の確認が $SUAGO 秒前（既定 86400）、
# 推奨の更新が $SUAVAIL 件（既定 0）、ConfigDataInstall・CriticalUpdateInstall が $SUCFG・$SUCRIT（既定 1）。$SUDATE があれば日時の文字列
cat > $T/bin/defaults <<'EOS'
#!/bin/sh
case "$*" in
  *AirplayReceiverEnabled*) [ "${AIRPLAY-0}" = none ] && { echo 'does not exist' >&2; exit 1; }; echo "${AIRPLAY-0}" ;;
  *SoftwareUpdate*) d=${SUDATE-$(date -u -r $(( $(date +%s) - ${SUAGO-86400} )) '+%Y-%m-%d %H:%M:%S +0000')}
    printf '{\n    ConfigDataInstall = %s;\n    CriticalUpdateInstall = %s;\n    LastRecommendedUpdatesAvailable = %s;\n    LastSuccessfulDate = "%s";\n}\n' \
      "${SUCFG-1}" "${SUCRIT-1}" "${SUAVAIL-0}" "$d" ;;
  *) printf "(\n    \"%s\",\n    \"en-JP\"\n)\n" "${LANGS-ja-JP}" ;;
esac
EOS
# launchctl: $M/bootstrap_fail に書いた回数だけ bootstrap を失敗させる（bootout 直後の error 5 の再現）。$M/notloaded があれば print は未登録で失敗する。
# $M/mbstopped があれば、メニューバー（*.menubar）は登録済みで止まっている。$M/ncstopped があれば、診断（*.netcheck）は未登録。
# $M/ncfail があれば、診断は登録済みで最後の終了コードが 1
cat > $T/bin/launchctl <<'EOF'
#!/bin/zsh
print -r -- "$*" >> $M/launchctl
[[ $1 == print && -e $M/notloaded ]] && exit 113
[[ $1 == print && $2 == *.menubar && -e $M/mbstopped ]] && { print '\tstate = not running'; exit 0 }
[[ $1 == print && $2 == *.netcheck && -e $M/ncstopped ]] && exit 113
[[ $1 == print && $2 == *.netcheck && -e $M/ncfail ]] && { print '\tstate = not running\n\truns = 7\n\tlast exit code = 1'; exit 0 }
[[ $1 == print ]] && print '\tstate = running\n\truns = 7\n\tlast exit code = 0'
if [[ $1 == bootstrap && -s $M/bootstrap_fail ]]; then
  n=$(<$M/bootstrap_fail); (( n > 0 )) && { print $((n - 1)) > $M/bootstrap_fail; exit 5 }
fi
exit 0
EOF
# networksetup: Wi‑Fi のデバイスは en0（有線の en5 が先に並ぶ）。-getmacaddress はハードウェアの MAC $HWMAC（既定は ifconfig と同じ）
cat > $T/bin/networksetup <<'EOS'
#!/bin/sh
[ "$1" = -getmacaddress ] && { printf "Ethernet Address: %s (Device: %s)\n" "${HWMAC-aa:bb:cc:dd:ee:0f}" "$2"; exit 0; }
printf "Hardware Port: Ethernet\nDevice: en5\nEthernet Address: 0:0:0:0:0:5\n\nHardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa:bb:cc:dd:ee:f\n"
EOS
# scutil: en0 の CaptiveNetwork の WaitingOnUI は $WAITUI（既定 FALSE）。ほかのキーはなし。
# --proxy は $PROXY（既定はプロキシなし）の行、--nc list は $NCLIST の行
cat > $T/bin/scutil <<'EOS'
#!/bin/sh
case $1 in
  --proxy) printf '<dictionary> {\n%b}\n' "${PROXY-  FTPPassive : 1\n}"; exit 0 ;;
  --nc) printf 'Available network connection services in the current set (*=enabled):\n%b' "${NCLIST-}"; exit 0 ;;
esac
read -r c
[ "$c" = 'show State:/Network/Interface/en0/CaptiveNetwork' ] || { echo '  No such key'; exit 0; }
printf '<dictionary> {\n  Stage : Online\n  WaitingOnUI : %s\n}\n' "${WAITUI-FALSE}"
EOS
# netstat: -rn は既定・サブネット・ホスト（VPN のサーバーへの UGHS を含む）・マルチキャストの経路と、$XROUTE（「宛先,ゲートウェイ,フラグ,
# インターフェース」の空白区切り）。-anv は接続中の1行と、$LISTEN（「アドレス.ポート,名前,PID」の空白区切り。名前の + は空白。
# 既定は rapportd の *.49152 と launchd のループバック）の LISTEN の行
cat > $T/bin/netstat <<'EOS'
#!/bin/zsh
if [[ $1 == -rn ]]; then
  print 'Routing tables\n\nInternet:\nDestination        Gateway            Flags               Netif Expire'
  for r in default,10.0.0.1,UGScg,en0 10.0.0/24,link#11,UCS,en0 10.0.0.1,0:0:0:0:0:1,UHLWIir,en0 203.0.113.9,10.0.0.1,UGHS,en0 \
           224.0.0/4,link#11,UmCS,en0 ${=XROUTE-}; do
    w=(${(s:,:)r}); print -r -- "$w[1] $w[2] $w[3] $w[4]"
  done
  exit 0
fi
print 'Active Internet connections (including servers)\nProto Recv-Q Send-Q  Local Address          Foreign Address        (state)  process:pid'
print 'tcp4 0 0 10.0.0.5.51218 17.253.144.10.443 ESTABLISHED 0 0 131072 131072 Safari:300 00102 00000008 0 00000080 04000900 2 0 000000'
for r in ${=${LISTEN-'*.49152,rapportd,728 127.0.0.1.8021,launchd,1'}}; do   # 既定の語は引用する（* で始まる語がファイル名に展開されて止まらないように）
  w=(${(s:,:)r})
  print -r -- "tcp4 0 0 $w[1] *.* LISTEN 0 0 131072 131072 ${w[2]//+/ }:$w[3] 00100 00000006 0000000000001140 00000001 00000800 1 0 000000"
done
EOS
# ps: -o comm= -p <PID> は $PSMAP（「PID=プログラム」の空白区切り。+ は空白）か既定（728 は rapportd、1 は launchd）。なければ失敗
cat > $T/bin/ps <<'EOS'
#!/bin/zsh
c=
for m in 728=/usr/libexec/rapportd 1=/sbin/launchd ${=PSMAP-}; do [[ ${m%%=*} == $4 ]] && c=${${m#*=}//+/ }; done
[[ -n $c ]] && print -r -- $c
EOS
# ndp: システムの utun の7行と、$RA（「アドレス%インターフェース」の空白区切り）の IPv6 のルーター
cat > $T/bin/ndp <<'EOS'
#!/bin/zsh
for i in {0..6}; do print "fe80::%utun$i if=utun$i, flags=IST, pref=medium, expire=Never"; done
for a in ${=RA-}; do print -r -- "$a if=${a#*%}, flags=, pref=medium, expire=29m"; done
EOS
# socketfilterfw: ファイアウォールは $FW（既定 enabled）・$FWS（既定 1）、ステルスモードは $STEALTH（既定 on）、$BLOCKALL ならすべて遮断
cat > $T/bin/socketfilterfw <<'EOS'
#!/bin/zsh
print -r -- "Firewall is ${FW-enabled}. (State = ${FWS-1})"
print -r -- "Firewall stealth mode is ${STEALTH-on}"
[[ -n ${BLOCKALL-} ]] && print 'Firewall is set to block all non-essential incoming connections' || print 'Firewall has block all state set to disabled.'
EOS
# security dump-trust-settings: 利用者（-d なし）は $CERTS 枚、管理者（-d）は $CERTSD 枚（空ならなし、fail なら失敗）。証明書の名前は $CERTNAME。
# なしは実機と同じく、標準エラーに1文を出して 1 で終わる
cat > $T/bin/security <<'EOS'
#!/bin/zsh
c=${CERTS-}; [[ ${2-} == -d ]] && c=${CERTSD-}
if [[ -z $c ]]; then print -u2 'SecTrustSettingsCopyCertificates: No Trust Settings were found.'; exit 1
elif [[ $c == fail ]]; then print -u2 'SecTrustSettingsCopyCertificates: An internal error occurred.'; exit 1
else print "Number of trusted certs = $c"; print -r -- "Cert 0: ${CERTNAME-Example Root CA}"; fi
EOS
chmod +x $T/bin/*

sed -e "s#/usr/bin/curl#$T/bin/curl#" -e "s#/sbin/route#$T/bin/route#" -e "s#/usr/sbin/arp#$T/bin/arp#" \
    -e "s#/usr/bin/osascript#$T/bin/osascript#" -e "s#/usr/bin/defaults#$T/bin/defaults#" -e 's/sleep 1;/:;/' \
    -e "s#/usr/sbin/ipconfig#$T/bin/ipconfig#" -e "s#/sbin/ifconfig#$T/bin/ifconfig#" \
    -e "s#/var/run/resolv.conf#$M/resolv#" -e "s#/usr/bin/log #$T/bin/log #" \
    $root/cafe-wifi-okawari.sh > $T/s.sh
# メニューバーの判定と install.sh status も、resolv.conf だけ模擬のファイルにする
sed -e "s#/var/run/resolv.conf#$M/resolv#" -e "s#/usr/bin/log #$T/bin/log #" $root/menubar.sh > $T/mb.sh
sed "s#/var/run/resolv.conf#$M/resolv#" $root/install.sh > $T/is.sh
# ネットワークの診断は、使うコマンドをすべて模擬に替える
sed -e "s#/sbin/route#$T/bin/route#" -e "s#/usr/sbin/arp#$T/bin/arp#" -e "s#/usr/sbin/networksetup#$T/bin/networksetup#" \
    -e "s#/usr/sbin/ipconfig#$T/bin/ipconfig#" -e "s#/usr/sbin/netstat#$T/bin/netstat#" -e "s#/usr/sbin/ndp#$T/bin/ndp#" \
    -e "s#/usr/sbin/scutil#$T/bin/scutil#" -e "s#/usr/libexec/ApplicationFirewall/socketfilterfw#$T/bin/socketfilterfw#" \
    -e "s#/usr/bin/defaults#$T/bin/defaults#" -e "s#/usr/bin/security#$T/bin/security#" -e "s#/bin/ps #$T/bin/ps #" \
    -e "s#/sbin/ifconfig#$T/bin/ifconfig#" -e "s#/var/run/resolv.conf#$M/resolv#" $root/netcheck.sh > $T/nc.sh

ST=$HOME/Library/Caches/cafe-wifi-okawari
PD=$ST.pending
SN=$ST.seen
DG=$ST.probe
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
WT="$HOME/Library/Application Support/cafe-wifi-okawari/watched"
mkdir -p ${ST:h}
W=https://service.wi2.ne.jp
# USEN の規約の文面（模擬の page.js の term:{title:"利用規約" から ]} の前まで）と、変更後の文面
export TJ=',desc:"USEN Free Wi-Fiは株式会社USENが提供する模擬のサービスです。",content:["① 模擬の禁止事項","② 模擬の禁止事項"'
export TJ2=${TJ/②/③}

# --- 補助 ----------------------------------------------------------------------
pass=0 failed=0
# run VAR=val...: 1回実行し、rc・out・通信回数を残す（posts は Wi2 と USEN の同意の送信、uposts はそのうち USEN、reads はシステムログの読み取り）
run() {
  rm -f $M/calls $M/notify $M/headers $M/badlogin $M/logcalls $M/ubody $M/proxied $M/badproto $M/mfs
  env "$@" zsh $T/s.sh > $M/out 2>&1; rc=$?
  out=$(<$M/out)
  posts=$(grep -cE 'xhr/login|capi/welcome' $M/calls 2>/dev/null); redirs=$(grep -c wi2auth/redirect $M/calls 2>/dev/null)
  uposts=$(grep -c capi/welcome $M/calls 2>/dev/null)
  notes=$( [[ -e $M/notify ]] && wc -l < $M/notify | tr -d ' ' || print 0)
  reads=$( [[ -e $M/logcalls ]] && wc -l < $M/logcalls | tr -d ' ' || print 0)
}
ok() {  # ok <名前> <条件式...>
  local name=$1; shift
  if eval "$*"; then (( pass++ )); else (( failed++ )); print -r -- "NG: $name  [$*]  rc=$rc posts=$posts uposts=$uposts redirs=$redirs notes=$notes reads=$reads out=$out"; fi
}
# 既定は「接続してから時間が経っている」状態。joined で「今つないだ」状態にする。
reset() { rm -rf $ST $PD $SN $DG $ST.chain $ST.chain.*(N) ${KN:h} $M/lease $M/authed $M/late $M/switched $M/noroute; touch -t 202001010000 $M/resolv }
joined() { touch $M/resolv }
A=aa:aa:aa:aa:aa:01 B=bb:bb:bb:bb:bb:02
consent() { print -r -- "$1 ${2-doutor}" >> $KN }   # 同意済みの接続先を用意する
mkknown() { mkdir -p ${KN:h}; consent "$@" }
OKL='LOGIN={"result":true}'
ago() { touch -t $(strftime '%Y%m%d%H%M.%S' $(( EPOCHSECONDS - $1 ))) $2 }   # ago <秒> <ファイル>: 更新時刻を過去にする

# --- 基本の状態判定 ------------------------------------------------------------
reset; mkknown $A; touch $M/authed
run MAC=$A;               ok '認証済みなら何もしない'  '(( rc == 0 && redirs == 0 && posts == 0 )) && [[ -z $out ]]'
reset; mkknown $A
run MAC=$A PROBE=down;    ok '無接続なら何もしない'    '(( rc == 0 && redirs == 0 && posts == 0 ))'
reset
run MAC=$A;               ok '関係のない網（接続から時間が経過）では通信しない' '(( rc == 0 )) && [[ ! -s $M/calls ]]'
reset; joined; touch $M/authed
run MAC=$A;               ok '接続した直後は確かめる'  '(( $(grep -c hotspot-detect $M/calls) == 1 ))'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok 'Wi2 の網（DHCP のドメイン名）は時間が経っても確かめる' '(( $(grep -c hotspot-detect $M/calls) == 1 ))'
reset; run MAC=$A DOM=example.jp
                          ok '別のドメイン名の網では通信しない' '[[ ! -s $M/calls ]]'
reset; run MAC=$A NOROUTE=1; ok '既定経路がない（OS が認証画面の同意を待っている）なら何もしない' '(( rc == 0 )) && [[ ! -s $M/calls ]]'
reset; mkknown $A; logs=()
for i in {1..4}; do run MAC=$A PROBE=down; [[ -n $out ]] && logs+=("${out#* * }"); done
ok '同意済みの網で確かめられないことが続けば 1・2・4 回目だけ記録' '[[ "${(j:|:)logs}" == "probe failed x1 net=$A if=en0 curl=7 http=000|probe failed x2 net=$A if=en0 curl=7 http=000|probe failed x4 net=$A if=en0 curl=7 http=000" ]]'
touch $M/authed; run MAC=$A
ok '確かめられたら数え直す' '[[ ! -e $DG && -z $out ]]'
reset; run MAC=$A DOM=wi2.ne.jp PROBEHTTP=511
ok 'Wi2 の網で想定外の HTTP 応答なら記録（Wi2 には送らない）' '[[ $out == *"probe failed x1 net=$A if=en0 curl=0 http=511" ]] && (( redirs == 0 && posts == 0 ))'
reset; joined; run MAC=$A PROBE=down
ok '関係のない網では確かめられなくても記録しない' '[[ -z $out && ! -e $DG ]]'

# --- 認証画面での同意（macOS が同意まで網を使わせないので、同意後の状態から記録する） ---
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok '通信できる Wi2 の網: ブランドを確かめて記録' '[[ $(<"$KN") == "$A doutor" ]] && [[ $out == *"consent recorded net=$A doutor (online)" ]] && (( redirs == 1 && posts == 0 ))'
                          ok '確かめるのは引数なしの redirect' 'grep -qx "$W/wi2auth/redirect" $M/calls'
run MAC=$A DOM=wi2.ne.jp; ok '同じ接続先では確かめ直さない' '(( redirs == 0 )) && [[ -z $out ]]'
run MAC=$B DOM=wi2.ne.jp BRAND=starbucks
                          ok '別の接続先に移れば確かめる' 'grep -qxF "$B starbucks" "$KN"'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp SWITCH=pre
                          ok 'ブランドを確かめる間に別の回線へ切り替わったら、元の接続先を同意済みにしない' '[[ ! -e $KN && ! -e $SN && $out == *"network changed net=$A before recording" && $out != *consent* ]] && (( redirs == 1 ))'
rm -f $M/switched $M/authed
run MAC=$A $OKL RECOVER=1 DOM=wi2.ne.jp
                          ok '元の接続先に戻っても同意は送らない（同意待ちにする）' '(( posts == 0 )) && [[ $(<"$PD") == "$A doutor" && $out == *"consent pending net=$A doutor" ]]'
reset; print -r -- "$A doutor" > $PD; touch $M/authed
run MAC=$A SWITCH=pre;    ok '同意待ちの確認中に切り替わっても記録しない' '[[ ! -e $KN && $out == *"network changed net=$A before recording" ]]'
reset; mkknown $A; touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok '同意済みなら記録を重ねない' '[[ $(<"$KN") == "$A doutor" && -z $out ]]'
reset; joined; touch $M/authed
run MAC=$A;               ok 'Wi2 のドメイン名でなければ記録しない' '[[ ! -e "$KN" ]] && (( redirs == 0 ))'
reset; touch $M/authed
for i in {1..4}; do (( i > 1 )) && ago 1800 $SN; run MAC=$A DOM=wi2.ne.jp BARE=other; (( i == 1 )) && o1=$out; done
                          ok '無料 Wi-Fi のランディングでなければ記録しない' '[[ ! -e "$KN" && $o1 == *"not free wi-fi x1 net=$A http=302 to=$W/wi2auth/error/ctrlapi_timeout.html" ]]'
                          ok '確かめるのは3回まで' '(( redirs == 0 ))'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BARE=timeout
                          ok '確かめられなければ記録しない' '[[ ! -e "$KN" && $out == *"redirect failed x1 net=$A curl=28 http=000" ]]'
run MAC=$A DOM=wi2.ne.jp; ok '失敗の直後には確かめ直さない（起動の間隔に依らず30秒空ける）' '(( redirs == 0 )) && [[ ! -e "$KN" ]]'
ago 30 $SN
run MAC=$A DOM=wi2.ne.jp; ok '30秒たてばやり直す' '[[ $(<"$KN") == "$A doutor" ]]'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BARE=timeout; ago 30 $SN; run MAC=$A DOM=wi2.ne.jp BARE=timeout; ago 55 $SN
run MAC=$A DOM=wi2.ne.jp; ok '2回目の失敗のあとは60秒空ける' '(( redirs == 0 ))'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BRAND='x y'
                          ok 'ブランド名が不正なら記録しない' '[[ ! -e "$KN" ]]'
# 確かめるのは接続ごと（resolv.conf が確認の記録より新しければ、つなぎ直した）。同意済みの MAC では resolv.conf の更新から
# 15秒待ってから確かめるので、つなぎ直して20秒たった状態にする
reconnect() { touch -t 202001010001 $SN; ago 20 $M/resolv }
reset; touch $M/authed
for i in {1..3}; do ago 1800 $SN 2>/dev/null; run MAC=$A DOM=wi2.ne.jp BARE=timeout; done
ago 1800 $SN
run MAC=$A DOM=wi2.ne.jp; ok '3回失敗した接続では確かめ直さない' '(( redirs == 0 ))'
reconnect
run MAC=$A DOM=wi2.ne.jp; ok 'つなぎ直せば確かめ直して記録' '[[ $(<"$KN") == "$A doutor" ]]'
reconnect
run MAC=$A DOM=wi2.ne.jp BRAND=starbucks
                          ok '同じ MAC の別ブランドにつなぎ直しても確かめる' 'grep -qxF "$A starbucks" "$KN"'

# 疎通できても Wi2 が同意ページへ転送するなら、まだ認証されていない（時間切れの境目など）
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BAREPAGE=index.html
                          ok '疎通できても同意ページなら同意済みにしない' '(( posts == 0 )) && [[ ! -e "$KN" && $out == *"not free wi-fi x1 net=$A http=302 to=$W/freewifi/doutor/index.html" ]]'
rm $M/authed
run MAC=$A DOM=wi2.ne.jp $OKL RECOVER=1
                          ok '続いて捕捉されても同意を送らない' '(( posts == 0 )) && [[ ! -e "$KN" && $(<$PD) == "$A doutor" ]]'
reset; print -r -- "$A doutor" > $PD; touch $M/authed
run MAC=$A BAREPAGE=index.html
                          ok '同意待ちで疎通できても、同意ページなら記録せず待ち続ける' '[[ ! -e "$KN" && $(<$PD) == "$A doutor" ]]'

# --- 時間切れで初めて捕捉を見た網（同意を待つ） --------------------------------
reset; joined
run MAC=$A;               ok '初回の Wi2: 同意を送らない'     '(( posts == 0 && redirs == 1 ))'
                          ok '初回の Wi2: 転送先の URL をたどる' 'grep -q "$W/wi2auth/redirect?cmd=login" $M/calls'
                          ok '初回の Wi2: すぐには通知しない' '(( notes == 0 ))'
                          ok '初回の Wi2: MAC とブランドを保留' '[[ $(<$PD) == "$A doutor" && $out == *"consent pending net=$A doutor" ]]'
reset; print -r -- "$A doutor" > $PD
run MAC=$A;               ok '保留は時間が経っても確かめ続ける' '(( $(grep -c hotspot-detect $M/calls) == 1 && redirs == 0 ))'
reset; joined
run MAC=$A
run MAC=$A;               ok '保留を書いてから30秒たつまでは知らせない（起動の間隔に依らない）' '(( notes == 0 && redirs == 0 ))'
ago 30 $PD
run MAC=$A;               ok '捕捉が続いたら1回だけ知らせる'  '(( notes == 1 && redirs == 0 && posts == 0 )) && grep -q 最初の1回 $M/notify'
                          ok '知らせるのはダイアログ'         'grep -q "^display alert .*giving up after 120" $M/notify && grep -q captive.apple.com $M/notify'
touch -t 202001010000 $M/resolv
run MAC=$A;               ok '知らせた後は何もしない'         '(( notes == 0 && redirs == 0 && posts == 0 )) && [[ -s $M/calls ]]'
touch $M/authed
run MAC=$A;               ok '自分で同意したら記録'           '[[ $(<"$KN") == "$A doutor" && ! -e $PD ]] && [[ $out == *"consent recorded net=$A doutor" ]]'
rm $M/authed
run MAC=$A $OKL RECOVER=1
                          ok '同意済みの接続先は自動で再認証' '(( posts == 1 )) && [[ $out == *"re-authenticated api=ok probe=ok net=$A doutor t="<->s ]]'
reset; joined
run MAC=$A LANGS=en-US; ago 30 $PD; run MAC=$A LANGS=en-US
                          ok '英語環境では英語で知らせる'     'grep -q "accept the terms yourself once" $M/notify'
reset; joined
run MAC=$A "LOC=https://portal.example.com/login?mac=x"
                          ok 'Wi2 以外のポータル: Wi2 に何も送らない' '(( redirs == 0 && posts == 0 && notes == 0 )) && [[ ! -e $PD && -z $out ]]'
reset; joined
run MAC=$A "LOC=http://service.wi2.ne.jp/wi2auth/redirect?mac=x"
                          ok 'HTTPS でない転送先はたどらない' '(( redirs == 0 && posts == 0 ))'
reset; print -r -- "$A doutor" > $PD; touch $M/authed
run MAC=$B;               ok '別の網で認証済みなら記録しない' '[[ ! -e "$KN" && ! -e $PD ]]'
reset; mkknown $A starbucks
run MAC=$A;               ok '同じ MAC でもブランドが違えば送らない' '(( posts == 0 && redirs == 1 )) && [[ $(<$PD) == "$A doutor" ]]'
reset; mkknown $A
run MAC=$A BRAND='x y';   ok 'ブランド名が不正なら送らない'   '(( posts == 0 )) && [[ ! -e $PD && $out == *"redirect failed x1 http=302"* ]]'
# ルーターの冗長化用の共通 MAC で、別ブランドの古い同意待ちが残っている
reset; mkknown $A; print -r -- "$A starbucks notified" > $PD; ago 3600 $PD
run MAC=$A $OKL RECOVER=1; ok '別ブランドの同意待ちがあっても、同意済みのブランドは再認証' '(( posts == 1 )) && [[ $out == *re-authenticated* ]]'
run MAC=$A;               ok '再認証のあと、別ブランドを同意済みにしない' '[[ $(<"$KN") == "$A doutor" && ! -e $PD ]]'
reset; print -r -- "$A starbucks" > $PD; touch $M/authed
run MAC=$A;               ok '同意待ちと違うブランドで通信できたら、確かめたブランドで記録' '[[ $(<"$KN") == "$A doutor" && ! -e $PD && $out == *"consent recorded net=$A doutor (online)" ]]'
reset; mkknown $A starbucks; joined
run MAC=$A
run MAC=$A;               ok '同じ MAC の別ブランドが同意済みでも、同意待ちの転送先は30秒たつまでたどり直さない' '(( redirs == 0 && posts == 0 && notes == 0 ))'
ago 30 $PD
run MAC=$A;               ok '同じ MAC の別ブランドが同意済みでも、同意待ちなら送らず1回だけ知らせる' '(( posts == 0 && notes == 1 && redirs == 1 ))'
run MAC=$A;               ok '知らせたあとも、たどり直すのは30秒に1回まで' '(( redirs == 0 && notes == 0 ))'
ago 30 $PD
run MAC=$A;               ok '知らせるのは1回だけ' '(( redirs == 1 && posts == 0 && notes == 0 ))'
run MAC=$A;               ok 'たどったら30秒は空ける' '(( redirs == 0 ))'
reset; touch $M/authed
for i in {1..3}; do ago 1800 $SN 2>/dev/null; run MAC=$A DOM=wi2.ne.jp BARE=timeout; done
rm $M/authed; run MAC=$A DOM=wi2.ne.jp
touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok 'ブランドの確認に3回失敗した接続でも、捕捉のあと自分で同意すれば記録' 'grep -qxF "$A doutor" "$KN"'
# 同意待ちで通信できたが、ブランドの確認に失敗し続けた: 保留を消さず、間隔を空けて確かめ続ける
reset; joined; run MAC=$A; touch -t 202001010000 $M/resolv; touch $M/authed
run MAC=$A BARE=timeout
run MAC=$A;               ok '同意待ちでブランドの確認に失敗したら、すぐには確かめ直さない' '(( redirs == 0 )) && [[ -e $PD ]]'
for i in 2 3 4 5; do ago 1800 $SN; run MAC=$A BARE=timeout; done
                          ok '確認に5回失敗しても保留を消さない（5回目は記録しない）' '(( redirs == 1 )) && [[ -e $PD && $(<$SN) == "$A 5" && -z $out ]]'
ago 1800 $SN; run MAC=$A; ok '間隔を空けて確かめ直し、通れば記録' '[[ $(<"$KN") == "$A doutor" && ! -e $PD && $out == *"consent recorded net=$A doutor" ]]'

# --- 転送先の確かめ ------------------------------------------------------------
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 LMAC=11:22:33:44:55:66
                          ok '転送先の MAC が自分と違えば送らない' '(( posts == 0 && redirs == 0 )) && [[ $out == *"portal mismatch x1 mac=ng ip=ok" ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 LIP=10.0.0.99
                          ok '転送先の IP が自分と違えば送らない' '(( posts == 0 )) && [[ $out == *"portal mismatch x1 mac=ok ip=ng" ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 LOC="$W/wi2auth/redirect?cmd=login"
                          ok '転送先に MAC・IP がなければ送らない' '(( posts == 0 )) && [[ $out == *"portal mismatch"* ]]'
for lmac in aabb:cc:dd:ee:0f aa:bb:cc:dd:ee:0f0 aa:bb:cc:dd:ee:0g aa:bb:cc:dd:ee:0f:00; do
  reset; mkknown $A
  run MAC=$A $OKL RECOVER=1 LMAC=$lmac
  ok "転送先の MAC が不正な形式（$lmac）なら送らない" '(( posts == 0 )) && [[ $out == *"portal mismatch x1 mac=ng ip=ok" ]]'
done
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 MYMAC= LMAC=zz
                          ok '自分の MAC が取れなければ送らない' '(( posts == 0 )) && [[ $out == *"portal mismatch x1 mac=ng"* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 SWITCH=1
                          ok '送信後に別の回線へ切り替わったら、成功として記録しない' '(( posts == 1 )) && [[ $out == *"network changed net=$A doutor api=ok probe=ok" && $out != *re-authenticated* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 SWITCH=pre
                          ok '送信前に別の回線へ切り替わったら送らない' '(( posts == 0 )) && [[ $out == *"network changed net=$A doutor before login" ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 LMAC=AA-BB-CC-DD-EE-F
                          ok 'MAC の表記の違いは吸収する' '(( posts == 1 )) && [[ $out == *re-authenticated* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 LMAC=aa%3Abb%3Acc%3Add%3Aee%3A0f
                          ok 'URL エンコードされた MAC も読める' '(( posts == 1 ))'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 REDIR=chain
                          ok 'Wi2 の中の転送はたどる' '(( posts == 1 )) && grep -q /wi2auth/next $M/calls'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 REDIR=query
                          ok '同意ページにクエリがあってもよい' '(( posts == 1 )) && grep -qx "$W/freewifi/doutor/index.html" $M/headers'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 PAGE=landing.html
                          ok '転送先がランディングでも再認証し、Referer はランディング' '(( posts == 1 )) && grep -qx "$W/freewifi/doutor/landing.html" $M/headers && [[ $out == *re-authenticated* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 PAGE=agreement.html
                          ok '同意ページ・ランディング以外のページには送らない' '(( posts == 0 && notes == 1 )) && [[ $out == *"redirect failed x1 http=302 to=$W/freewifi/doutor/agreement.html" ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 REDIR=error
                          ok 'エラーページなら送らずに記録して知らせる' '(( posts == 0 && notes == 1 )) && [[ $out == *"redirect failed x1 http=302 to=$W/wi2auth/error/ctrlapi_timeout.html" ]]'
                          ok 'ログに端末の MAC・IP を残さない' '[[ $out != *aa:bb:cc* && $out != *10.0.0.5* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1
                          ok '認証要求は同意ページからの XHR と同じ' 'grep -qx "Origin: $W" $M/headers && grep -qx "$W/freewifi/doutor/index.html" $M/headers'
                          ok '認証要求は redirect で受け取った Cookie と同意の本文を送る' '[[ ! -e $M/badlogin ]] && [[ $out == *re-authenticated* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=3; ok '疎通が数秒遅れて戻っても成功' '[[ $out == *"re-authenticated api=ok probe=ok net=$A doutor t="<->s ]] && (( $(grep -c hotspot-detect $M/calls) == 4 ))'
reset; mkknown $A
run MAC=$A $OKL RECOVER=10; ok '疎通の確認は1秒ごとに10回まで' '[[ $out == *"re-authenticated api=ok probe=ok"* ]] && (( $(grep -c hotspot-detect $M/calls) == 11 ))'
reset; mkknown $A
run MAC=$A $OKL RECOVER=11; ok '10回で戻らなければ失敗' '[[ $out == *"login failed x1 api=ok probe=ng"* ]] && (( notes == 1 ))'

# --- API 応答の判定 ------------------------------------------------------------
for body verdict in \
  '{"result": true, "message":"AUTHENTICATED"}' 're-authenticated api=ok' \
  '{"result":"true"}' 'api=ng' \
  '<html>"result":true</html>' 'api=ng'; do
  reset; mkknown $A
  [[ $verdict == re-* ]] && run MAC=$A LOGIN=$body RECOVER=1 || run MAC=$A LOGIN=$body
  ok "応答 $body" '[[ $out == *"$verdict"* ]]'
done
reset; mkknown $A
run MAC=$A 'LOGIN={"result":false}' RECOVER=1
                          ok 'API 失敗・疎通回復: 通知しない' '[[ $out == *"login failed x1 api=ng probe=ok"* ]] && (( notes == 0 ))'
reset; mkknown $A
run MAC=$A $OKL LHTTP=503 RECOVER=1
                          ok 'HTTP 5xx なら result:true でも api=ng' '[[ $out == *"login failed x1 api=ng probe=ok http=503"* ]]'
reset; mkknown $A
run MAC=$A LHTTP=000;     ok 'login の通信失敗は curl の終了値を記録' '[[ $out == *"login failed x1 api=ng probe=ng http=000 curl=28 res=" ]]'
reset; mkknown $A
run MAC=$A 'LOGIN={"result":false,"message":"LOGIN_LIMIT","url":"https://service.wi2.ne.jp/wi2auth/redirect?cmd=login&mac=aa:bb:cc:dd:ee:0f&ip=10.0.0.5","ip":"10.0.0.5","mac":"AA-BB-CC-DD-EE-0F"}'
                          ok '応答の本文は MAC・IP・クエリを伏せて記録' '[[ $out == *LOGIN_LIMIT* && $out == *"/wi2auth/redirect?\","* && $out == *"\"ip\":\"<ip>\""* && $out == *"\"mac\":\"<mac>\""* && $out != *10.0.0.5* && $out != *(#i)aa?bb?cc* && $out != *cmd=login* ]]'

# --- 失敗の継続と待機 ----------------------------------------------------------
reset; mkknown $A
total=0 logs=()
for i in {1..9}; do
  [[ -e $ST ]] && sed -i '' 's/^\([0-9]*\) [0-9]*/\1 0/' $ST   # 待機時間を経過させる
  run MAC=$A 'LOGIN={"result":false}' LHTTP=503
  (( total += notes )); [[ -n $out ]] && logs+=(${${out#* * }%% api*})
  (( i == 1 )) && { w1=$(( ${$(<$ST)[(w)2]} - EPOCHSECONDS )) }
done
w9=$(( ${$(<$ST)[(w)2]} - EPOCHSECONDS ))
ok '9回失敗しても通知は1回'        '(( total == 1 ))'
ok '失敗は毎回記録する'            '[[ "$logs" == "login failed x1 login failed x2 login failed x3 login failed x4 login failed x5 login failed x6 login failed x7 login failed x8 login failed x9" ]]'
ok '待機は 30秒から最大30分'       '(( w1 >= 29 && w1 <= 30 && w9 >= 1799 && w9 <= 1800 ))'
ok 'サーバー障害（5xx）では自動を止めない' '[[ $(<"$KN") == "$A doutor" ]]'
run MAC=$A 'LOGIN={"result":false}'
ok '待機中は通信しない'            '(( redirs == 0 && posts == 0 ))'
consent $B
run MAC=$B 'LOGIN={"result":true}' RECOVER=1
ok '別の接続先へ移れば待機を持ち越さない' '(( posts == 1 )) && [[ $out == *re-authenticated* ]]'
reset; mkknown $A; print "3 $(( EPOCHSECONDS + 900 ))" > $ST
run MAC=$A 'LOGIN={"result":true}' RECOVER=1
ok '旧形式の状態ファイルでも動く'  '(( posts == 1 ))'
reset; mkknown $A; print "3 $(( EPOCHSECONDS + 900 )) $A" > $ST; touch -t 202001010000 $ST; joined
run MAC=$A 'LOGIN={"result":true}' RECOVER=1
ok 'つなぎ直したら待機を持ち越さない' '(( posts == 1 ))'
reset; joined
run MAC=$A REDIR=timeout
ok '未同意の網でも Wi2 の通信失敗は記録する（通知なし）' '(( notes == 0 )) && [[ $out == *"redirect failed x1 curl=28 http=000" && -e $ST ]]'

# --- 拒否が続いたときの停止 ----------------------------------------------------
skip() { [[ -e $ST ]] && sed -i '' 's/^\([0-9]*\) [0-9]*/\1 0/' $ST }   # 待機時間を経過させる
reject() { skip; run MAC=$A 'LOGIN={"result":false}' "$@" }
reset; mkknown $A; consent $B
reject; reject;           ok '拒否2回ではまだ止めない'   '(( posts == 1 )) && grep -qxF "$A doutor" "$KN"'
reject;                   ok '拒否3回で自動を止める'     '[[ $(<"$KN") == "$B doutor" && $(<$PD) == "$A doutor notified" && ! -e $ST ]] && [[ $out == *"auto stopped net=$A doutor rejected x3 http=200"* ]]'
                          ok '止めたときに通知する'       '(( notes == 1 )) && grep -q 自動再接続を止めました $M/notify'
run MAC=$A;               ok '止めた後は送らない'         '(( posts == 0 && redirs == 0 && notes == 0 ))'
touch $M/authed
run MAC=$A;               ok '自分で同意し直せば再開'     'grep -qxF "$A doutor" "$KN" && [[ ! -e $PD ]]'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp; rm $M/authed   # 入店時にブランドを確かめた接続
reject DOM=wi2.ne.jp; reject DOM=wi2.ne.jp; reject DOM=wi2.ne.jp; o3=$out
touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok '入店時に確かめた接続で自動を止めても、つなぎ直さずに同意し直せば再開' '[[ $o3 == *"auto stopped"* ]] && grep -qxF "$A doutor" "$KN" && [[ ! -e $PD ]]'
reset; mkknown $A
reject; reject; skip; run MAC=$A 'LOGIN={"result":true}' RECOVER=1; rm $M/authed
reject; reject;           ok '成功を挟めば拒否を数え直す' 'grep -qxF "$A doutor" "$KN"'
reset; mkknown $A
reject; reject; skip; touch -t 202001010000 $ST; joined
run MAC=$A 'LOGIN={"result":false}'
                          ok 'つなぎ直しても拒否の回数は持ち越す' '[[ $out == *"auto stopped"* ]]'
reset; mkknown $A; consent $B
reject; reject; skip
run MAC=$B 'LOGIN={"result":false}'
                          ok '別の接続先では拒否を数え直す' 'grep -qxF "$B doutor" "$KN"'
reset; mkknown $A; consent $A starbucks
reject; reject; skip
run MAC=$A BRAND=starbucks 'LOGIN={"result":false}'
                          ok '同じ MAC の別ブランドでは拒否を数え直す' 'grep -qxF "$A starbucks" "$KN" && [[ $out != *"auto stopped"* ]]'
reset; mkknown $A
reject; reject; skip; run MAC=$A REDIR=timeout
reject;                   ok 'ブランドが分かる前の失敗を挟んでも、同じブランドの拒否は持ち越す' '[[ $out == *"auto stopped"* ]]'
reset; mkknown $A
for i in 1 2 3; do skip; run MAC=$A 'LOGIN={"result":false}' SWITCH=1; rm -f $M/switched; done
                          ok '別の回線に切り替わった失敗は拒否に数えない' 'grep -qxF "$A doutor" "$KN" && [[ ! -e $ST ]]'
reset; mkknown $A
for i in {1..4}; do reject LHTTP=000; done
                          ok 'タイムアウトは拒否に数えない' 'grep -qxF "$A doutor" "$KN"'
reset; mkknown $A
for i in {1..4}; do skip; run MAC=$A 'LOGIN={"result":false}' RECOVER=1; rm -f $M/authed; done
                          ok '疎通が戻った失敗は拒否に数えない' 'grep -qxF "$A doutor" "$KN"'

# --- 認証前段の障害 ------------------------------------------------------------
for mode detail in timeout 'curl=28 http=000' 503 'curl=0 http=503'; do
  reset; mkknown $A
  run MAC=$A REDIR=$mode
  ok "redirect $mode: 失敗として記録・通知なし" '(( posts == 0 && notes == 0 )) && [[ $out == *"redirect failed x1 $detail" && -e $ST ]]'
  run MAC=$A REDIR=$mode
  ok "redirect $mode: 待機する"                 '(( redirs == 0 ))'
done
reset; mkknown $A
run MAC=$A REDIR=timeout; skip; run MAC=$A REDIR=error
                           ok '通知しない失敗のあとでも、知らせる失敗なら1回知らせる' '(( notes == 1 ))'
skip; run MAC=$A REDIR=error; ok '失敗が続く間は2回目を知らせない' '(( notes == 0 ))'
reset; mkknown $A
run MAC=$A REDIR=nocookie; skip; run MAC=$A REDIR=nocookie; skip; run MAC=$A 'LOGIN={"result":false}'
                          ok '失敗の種類が変われば、その回も記録する' '[[ $out == *"login failed x3 api=ng"* ]]'
reset; mkknown $A
run MAC=$A REDIR=nocookie; ok 'session_id なし: 通知する' '(( posts == 0 && notes == 1 )) && [[ $out == *"no session_id"* ]]'
reset; mkknown $A
run MAC=$A REDIR=other;    ok '同意済みで Wi2 の外への転送なら送らずに記録して知らせる' '(( posts == 0 && notes == 1 )) && [[ $out == *"redirect failed x1 http=302 to=https://example.com/" && -e $ST ]]'
reset; mkknown $A
run MAC=$A 'LOC=https://portal.example.com/?mac=aa:bb:cc:dd:ee:0f'
                           ok '同意済みの網で Wi2 以外のポータル: 送らずに記録' '(( redirs == 0 && posts == 0 && notes == 0 )) && [[ $out == *"portal unknown x1 http=302 to=https://portal.example.com/" ]]'

# --- USEN（USPOT-02） ----------------------------------------------------------
UD=http://10.9.8.7:8080
UL="LOC=$UD/captive/?url=captive.apple.com/hotspot-detect.html&stamac=aa:bb:cc:dd:ee:0f"
HASH=$(/sbin/sha256 -q -s "$TJ") HASH2=$(/sbin/sha256 -q -s "$TJ2")
now() { print $(( EPOCHSECONDS - ${1-0} )) }
watch() { mkdir -p ${WT:h}; print -r -- "$1 $(now ${2-60})" >> $WT }   # 見張り中の網を用意する（$2 秒前に記録）
mkpend() { print -r -- "$A usen $(now ${1-100})${2:+ $2}" > $PD }        # USEN の同意待ち（基準時刻は $1 秒前）
rewind() { local p=(${=$(<$PD)}); p[3]=$(( p[3] - 100 )); print -r -- "$p" > $PD }   # 同意待ちの基準時刻を100秒前にする
snap() { cat $KN $WT $PD 2>/dev/null }
PRED='--predicate subsystem == "com.apple.captive" AND eventMessage CONTAINS "websheet: success"'

# 入店時: 通信できていて、今の接続のリース開始より後に認証画面での同意があれば見張る
reset; ago 20 $M/resolv; touch $M/authed
run MAC=$A WEBSHEET=$(now 10)
ok 'USEN 入店時: リース開始より後に認証画面での同意があれば見張る' '[[ $(<$WT) == "$A "<-> && $out == *"captive login seen net=$A" ]] && (( reads == 1 && posts == 0 )) && [[ ! -e $KN ]]'
ok 'USEN 入店時: 読むのは captive の websheet: success の行だけで、リース開始から' 'grep -qF -- "$PRED" $M/logcalls && grep -qF -- "--start $(strftime "%F %T" $(stat -f %m $M/resolv))" $M/logcalls'
ok 'USEN 入店時: ログにシステムログの行を残さない' '[[ $out != *websheet* ]]'
run MAC=$A WEBSHEET=$(now 10)
ok 'USEN 入店時: 見張ったら読み直さない' '(( reads == 0 )) && [[ -z $out ]]'
for w verdict in '' 'ない' $(now 30) 'リース開始より前にしかない'; do
  reset; ago 20 $M/resolv; touch $M/authed
  run MAC=$A WEBSHEET=$w
  ok "USEN 入店時: 認証画面での同意が${verdict}なら見張らない" '[[ ! -e $WT && -z $out ]] && (( reads == 1 ))'
  run MAC=$A WEBSHEET=$(now 10)
  ok "USEN 入店時: 同意が${verdict}接続でも読み直さない" '(( reads == 0 )) && [[ ! -e $WT ]]'
done
reset; ago 20 $M/resolv; touch $M/authed
run MAC=$A WEBSHEET=$(now 10) LEASE=none
ok 'USEN 入店時: リース開始が読めなければシステムログを読まない' '(( reads == 0 )) && [[ ! -e $WT ]]'
reset; ago 20 $M/resolv; touch $M/authed
run MAC=$A WEBSHEET=$(now 10) LEASE=$(now 400)
ok 'USEN 入店時: リース開始が resolv.conf の更新より5分以上前なら読まない' '(( reads == 0 )) && [[ ! -e $WT ]]'
reset; ago 5 $M/resolv; touch $M/authed
run MAC=$A WEBSHEET=$(now 1)
ok 'USEN 入店時: resolv.conf の更新から15秒たっていなければまだ読まない' '(( reads == 0 )) && [[ ! -e $WT && ! -e $SN ]]'
ago 15 $M/resolv
run MAC=$A WEBSHEET=$(now 1)
ok 'USEN 入店時: 15秒たてば読む' '(( reads == 1 )) && [[ -s $WT ]]'
reset; ago 20 $M/resolv; touch $M/authed
run MAC=$A WEBSHEET=$(now 10) LOGSWITCH=1
ok 'USEN 入店時: ログを読む間に接続先が変わったら見張らない' '[[ ! -e $WT && $out == *"network changed net=$A before watching" ]]'
reset; ago 20 $M/resolv; touch $M/authed
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10)
ok 'USEN 入店時: Wi2 の網ではシステムログを読まない' '(( reads == 0 )) && [[ ! -e $WT && $out == *"consent recorded net=$A doutor (online)" ]]'
reset; ago 20 $M/resolv; touch $M/authed; mkknown $A
run MAC=$A WEBSHEET=$(now 10);   ok 'USEN 入店時: 同意済みの網では、60秒以内の同意をログに書くだけで見張らない（USEN でなければブランドなし）' \
  '[[ $out == *" captive login seen net=$A" && ! -e $WT && $(<$KN) == "$A doutor" ]] && (( reads == 1 && posts == 0 ))'
reset; ago 20 $M/resolv; touch $M/authed; watch $A
run MAC=$A WEBSHEET=$(now 10);   ok 'USEN 入店時: 見張り中の網ではシステムログを読まない' '(( reads == 0 )) && [[ -z $out ]]'
reset; ago 20 $M/resolv; touch $M/authed; print -r -- "$A doutor" > $PD
run MAC=$A WEBSHEET=$(now 10);   ok 'USEN 入店時: 同意待ちの網ではシステムログを読まない' '(( reads == 0 )) && [[ ! -e $WT ]]'
reset; ago 400 $M/resolv; touch $M/authed
run MAC=$A WEBSHEET=$(now 10);   ok 'USEN 入店時: 接続から5分以上たっていれば読まない（通信もしない）' '(( reads == 0 )) && [[ ! -s $M/calls ]]'

# 同意済みの網に新しくつないだ: 60秒以内の認証画面での同意だけを、ログに書く（次の時間切れの目安の起点）。記録ファイルは変えない
lstart() { local x=$(<$M/logcalls); x=${x#*--start }; strftime -r '%Y-%m-%d %H:%M:%S' "${x[1,19]}" }   # 読んだ範囲の始まり
CS=" captive login seen net=$A"
reset; ago 20 $M/resolv; touch $M/authed; mkknown $A "usen $HASH"; k0=$(snap)
run MAC=$A WEBSHEET=$(now 10)
ok '同意済みの USEN 入店時: 60秒以内の同意を usen 付きでログに書く（見張らない・送らない）' '[[ $out == *"$CS usen" && $(snap) == "$k0" ]] && (( reads == 1 && posts == 0 ))'
run MAC=$A WEBSHEET=$(now 10)
ok '同意済みの USEN 入店時: 同じ接続では読み直さない' '(( reads == 0 )) && [[ -z $out ]]'
reset; ago 240 $M/resolv; touch $M/authed; mkknown $A "usen $HASH"
run MAC=$A WEBSHEET=$(now 230)
ok '同意済みの USEN 入店時: 60秒より前の同意は書かない（接続から240秒後に初めて動いた）' '[[ -z $out && $(<$SN) == "$A 3" ]] && (( reads == 1 ))'
ok '同意済みの USEN 入店時: 読むのは今の60秒前から（リース開始より遅いとき）' '(( $(lstart) >= EPOCHSECONDS - 62 && $(lstart) <= EPOCHSECONDS - 59 ))'
run MAC=$A WEBSHEET=$(now 10)
ok '同意済みの USEN 入店時: 書かなかった接続でも読み直さない' '(( reads == 0 )) && [[ -z $out ]]'
for v verdict in WEBSHEET= 'システムログに同意がなければ' LOGFAIL=1 'システムログが読めなければ'; do
  reset; ago 20 $M/resolv; touch $M/authed; mkknown $A "usen $HASH"
  run MAC=$A $v
  ok "同意済みの USEN 入店時: ${verdict}書かず、この接続では読み直さない" '[[ -z $out && $(<$SN) == "$A 3" ]] && (( reads == 1 ))'
done
reset; ago 5 $M/resolv; touch $M/authed; mkknown $A "usen $HASH"
run MAC=$A WEBSHEET=$(now 1)
ok '同意済みの USEN 入店時: resolv.conf の更新から15秒たっていなければまだ読まない' '(( reads == 0 )) && [[ -z $out && ! -e $SN ]]'
ago 15 $M/resolv
run MAC=$A WEBSHEET=$(now 1)
ok '同意済みの USEN 入店時: 15秒たてば読んで書く' '(( reads == 1 )) && [[ $out == *"$CS usen" ]]'
reset; ago 20 $M/resolv; touch $M/authed; mkknown $A "usen $HASH"
run MAC=$A WEBSHEET=$(now 10) LOGSWITCH=1
ok '同意済みの USEN 入店時: 読む間に接続先が変わったら書かない' '[[ $out == *"network changed net=$A before watching" && $out != *captive* ]]'
reset; ago 400 $M/resolv; touch $M/authed; mkknown $A "usen $HASH"
run MAC=$A WEBSHEET=$(now 10)
ok '同意済みの USEN: 接続から5分以上たっていれば読まない' '(( reads == 0 )) && [[ -z $out ]]'
# Wi2: この接続の最初のブランドの確認のときだけ読み、同意済みのブランドと分かったときだけ書く
reset; ago 20 $M/resolv; touch $M/authed; mkknown $A
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10)
ok '同意済みの Wi2 入店時: 60秒以内の同意をブランド付きでログに書く' '[[ $out == *"$CS doutor" && $(<$KN) == "$A doutor" ]] && (( redirs == 1 && reads == 1 && posts == 0 ))'
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10)
ok '同意済みの Wi2 入店時: 同じ接続では読まず、確かめ直さない' '(( reads == 0 && redirs == 0 )) && [[ -z $out ]]'
for v verdict in WEBSHEET= 'システムログに同意がなければ（再起動・スリープ復帰のつなぎ直し）' LOGFAIL=1 'システムログが読めなければ'; do
  reset; ago 20 $M/resolv; touch $M/authed; mkknown $A
  run MAC=$A DOM=wi2.ne.jp $v
  ok "同意済みの Wi2 入店時: ${verdict}ブランドを確かめるだけで書かない" '[[ -z $out ]] && (( redirs == 1 && reads == 1 ))'
done
reset; ago 240 $M/resolv; touch $M/authed; mkknown $A
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 230)
ok '同意済みの Wi2 入店時: 60秒より前の同意は書かない' '[[ -z $out ]] && (( redirs == 1 && reads == 1 ))'
reset; ago 5 $M/resolv; touch $M/authed; mkknown $A
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 1)
ok '同意済みの Wi2 入店時: resolv.conf の更新から15秒たっていなければ、読まずにブランドの確認も待つ' '(( reads == 0 && redirs == 0 )) && [[ -z $out && ! -e $SN ]]'
ago 15 $M/resolv
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 1)
ok '同意済みの Wi2 入店時: 15秒たてば確かめて書く' '(( reads == 1 && redirs == 1 )) && [[ $out == *"$CS doutor" ]]'
# 再試行では読まない（.seen を resolv.conf より新しいまま古くする）
reset; ago 20 $M/resolv; touch $M/authed; mkknown $A
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10) BARE=timeout
ok '同意済みの Wi2 入店時: ブランドの確認に失敗したら書かない' '[[ $out == *"redirect failed x1 net=$A"* && $out != *captive* ]] && (( reads == 1 ))'
ago 60 $M/resolv; ago 30 $SN
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10) BARE=timeout
ok '同意済みの Wi2: 再試行ではシステムログを読まない' '[[ $out == *"redirect failed x2 net=$A"* ]] && (( reads == 0 && redirs == 1 ))'
ago 200 $M/resolv; ago 90 $SN
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10)
ok '同意済みの Wi2: 再試行で確かめられても書かない' '[[ -z $out && $(<$SN) == "$A 3" ]] && (( reads == 0 && redirs == 1 ))'
reset; ago 20 $M/resolv; touch $M/authed; mkknown $A starbucks
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 10)
ok '同じ MAC で別ブランドが同意済みの Wi2: 同意の記録だけを書く（1回の同意で2行にしない）' '[[ $out == *" consent recorded net=$A doutor (online)" && $out != *captive* ]] && (( reads == 1 ))'

# 見張り中の網で時間切れ
reset; watch $A
run MAC=$A "$UL" RECOVER=1
ok 'USEN 見張り中の網で捕捉: 画面と page.js を確かめる' 'grep -qx "$UD/captive/" $M/calls && grep -qx "$UD/captive/dist/page.js" $M/calls'
ok 'USEN 見張り中の網で捕捉: 規約のハッシュ付きで記録し、見張りから外し、送って再認証' '[[ $(<"$KN") == "$A usen $HASH" && ! -s $WT ]] && [[ $out == *"consent recorded net=$A usen (captive login)"$'"'"'\n'"'"'*"re-authenticated api=ok probe=ok net=$A usen t="<->s ]] && (( posts == 1 && uposts == 1 && redirs == 0 ))'
ok 'USEN 同意の要求: 誕生年・性別は空、自分の MAC、言語' '[[ $(<$M/ubody) == "{\"gender\":\"\",\"birth\":\"\",\"macaddr\":\"aa:bb:cc:dd:ee:0f\",\"lang\":\"ja\"}" ]]'
ok 'USEN 同意の要求: Content-Type・Origin・Referer・空の authorization' 'grep -qx "Content-Type: application/json" $M/headers && grep -qx "Origin: $UD" $M/headers && grep -qx "$UD/captive/step2" $M/headers && grep -qx "authorization;" $M/headers'
ok 'USEN 機器へは平文 HTTP だけ、応答の大きさに上限、プロキシなし' '[[ ! -e $M/badproto && ! -e $M/proxied && $(<$M/mfs) == 65536$'"'"'\n'"'"'1048576 ]]'
ok 'USEN ログに誘導先のクエリ・端末の MAC を残さない' '[[ $out != *aa:bb:cc* && $out != *stamac* && $out != *hotspot* ]]'
reset; mkknown $A "usen $HASH"
run MAC=$A "$UL" RECOVER=1 LANGS=en-US
ok 'USEN 同意の要求: 英語環境では lang=en' '[[ $(<$M/ubody) == *",\"lang\":\"en\"}" ]] && (( uposts == 1 ))'
reset; mkknown $A "usen $HASH"
run MAC=$A "$UL" RECOVER=1 http_proxy=http://127.0.0.1:9 ALL_PROXY=socks5://127.0.0.1:9
ok '環境変数のプロキシがあっても使わない（USEN）' '[[ ! -e $M/proxied ]] && (( uposts == 1 ))'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 http_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9
ok '環境変数のプロキシがあっても使わない（Wi2）' '[[ ! -e $M/proxied ]] && (( posts == 1 ))'
reset; mkknown $A "usen $HASH"; consent $A
run MAC=$A "$UL" RECOVER=1
ok 'USEN 同意済みの照合: ハッシュ付きの行も「MAC usen」で見つかる（同じ MAC の Wi2 の行とは別）' '(( uposts == 1 )) && [[ $out == *"re-authenticated api=ok probe=ok net=$A usen"* && $(<"$KN") == "$A usen $HASH"$'"'"'\n'"'"'"$A doutor" ]]'
reset; watch $A 86401; joined
run MAC=$A "$UL" RECOVER=1
ok 'USEN 見張りの記録から24時間を過ぎた網: 送らずに同意待ち' '(( posts == 0 )) && [[ $(<$PD) == "$A usen "<-> && $out == *"consent pending net=$A usen" && ! -e $KN ]]'

# 見張りも同意もない網で捕捉 → 同意待ち → 認証画面での同意で記録
reset; joined
run MAC=$A "$UL" RECOVER=1
ok 'USEN 見張りも同意もない網で捕捉: 送らず、同意待ちに「MAC usen 時刻」' '(( posts == 0 && notes == 0 )) && [[ $(<$PD) == "$A usen "<-> && $out == *"consent pending net=$A usen" && ! -e $KN ]]'
p0=$(<$PD); touch -t 202001010000 $M/resolv
run MAC=$A "$UL";         ok 'USEN 同意待ち: 30秒たつまでは知らせない' '(( notes == 0 && posts == 0 )) && ! grep -q "$UD" $M/calls'
ago 30 $PD
run MAC=$A "$UL";         ok 'USEN 同意待ち: 捕捉が続けば1回だけ知らせる（基準時刻は変えない）' '(( notes == 1 && posts == 0 )) && [[ $(<$PD) == "$p0 notified" ]] && grep -q 最初の1回 $M/notify'
run MAC=$A "$UL";         ok 'USEN 同意待ち: 知らせるのは1回だけ' '(( notes == 0 && posts == 0 ))'
touch $M/authed
run MAC=$A;               ok 'USEN 同意待ち: 平文の Success だけでは記録しない' '[[ ! -e $KN && -e $PD ]] && (( reads == 1 ))'
rewind; ago 30 $SN
run MAC=$A WEBSHEET=$(now 5)
ok 'USEN 同意待ち: 基準時刻とリース開始より後に認証画面での同意があれば記録' '[[ $(<"$KN") == "$A usen" && ! -e $PD && $out == *"consent recorded net=$A usen" ]]'
rm $M/authed
run MAC=$A "$UL" RECOVER=1
ok 'USEN 記録したあとの最初の送信で、規約のハッシュを記録する' '[[ $(<"$KN") == "$A usen $HASH" && $out == *"re-authenticated api=ok probe=ok net=$A usen"* ]] && (( uposts == 1 ))'

reset; mkpend; touch $M/authed
run MAC=$A;               ok 'USEN 同意待ち: 同意の行がなければ記録せず、同意待ちを残す' '[[ ! -e $KN && -e $PD ]] && (( reads == 1 && posts == 0 ))'
run MAC=$A;               ok 'USEN 同意待ち: すぐには読み直さない' '(( reads == 0 ))'
ago 25 $SN; run MAC=$A;   ok 'USEN 同意待ち: 30秒たつまでは読み直さない' '(( reads == 0 ))'
ago 30 $SN; run MAC=$A;   ok 'USEN 同意待ち: 30秒たてば読み直す' '(( reads == 1 ))'
ago 55 $SN; run MAC=$A;   ok 'USEN 同意待ち: 次は60秒空ける' '(( reads == 0 ))'
ago 60 $SN; run MAC=$A LOGFAIL=1
                          ok 'USEN 同意待ち: ログが読めなくても同意待ちを残す' '[[ ! -e $KN && -e $PD ]] && (( reads == 1 ))'
for i in {1..6}; do ago 1800 $SN; run MAC=$A LEASE=none; done
ago 1790 $SN; run MAC=$A; ok 'USEN 同意待ち: 読み直す間隔は最大30分' '(( reads == 0 )) && [[ -e $PD ]]'
ago 1800 $SN; run MAC=$A WEBSHEET=$(now 5)
                          ok 'USEN 同意待ち: 読み直して同意の行があれば記録' '[[ $(<"$KN") == "$A usen" && ! -e $PD ]]'
reset; mkpend; touch $M/authed
run MAC=$A DOM=wi2.ne.jp WEBSHEET=$(now 5)
ok 'USEN 同意待ちの網が Wi2 の網なら、同意待ちを消して Wi2 として確かめる' '[[ ! -e $PD && $(<"$KN") == "$A doutor" && $out == *"consent recorded net=$A doutor (online)" ]] && (( reads == 0 ))'

# 同意待ちの基準時刻
reset; mkpend; touch $M/authed
run MAC=$A WEBSHEET=$(now 2); ok 'USEN 基準時刻（対照）: そのまま戻れば同じ行で記録できる' 'grep -qx "$A usen" "$KN"'
reset; mkpend; touch $M/authed; p0=$(<$PD); ago 50 $PD
run MAC=$B;               ok 'USEN 同意待ちがあっても、別の網では確かめない（自宅などで通信しない）' '[[ ! -s $M/calls ]] && (( reads == 0 ))'
ok 'USEN 別の網で resolv.conf が基準時刻より前のままなら、同意待ちを書き直さない' '[[ $(<$PD) == "$p0" ]] && (( EPOCHSECONDS - $(stat -f %m $PD) >= 50 ))'
# 別の網で認証画面で同意すると、その網が既定経路になって resolv.conf が書き換わる（同意の行はその前）
w1=$(now 25); ago 20 $M/resolv
run MAC=$B;               ok 'USEN 別の網にいる間に resolv.conf が書き換われば、同意待ちの基準時刻を今に進める' '(( ${$(<$PD)[(w)3]} >= w1 + 25 ))'
p1=$(<$PD); ago 50 $PD
run MAC=$B
                          ok 'USEN 進めたあとは、resolv.conf が変わらない限り書き直さない' '[[ $(<$PD) == "$p1" ]] && (( EPOCHSECONDS - $(stat -f %m $PD) >= 50 ))'
run MAC=$A WEBSHEET=$w1 LEASE=$(now 300)
                          ok 'USEN 別の網で同意してから戻っても、その行では記録しない（同意待ちは残る）' '[[ ! -e $KN && -e $PD ]] && (( reads == 1 ))'
reset; mkpend; touch $M/authed
run MAC=$A WEBSHEET=${$(<$PD)[(w)3]}
                          ok 'USEN 基準時刻と同じ秒の行は数えない（別の網での同意と区別できない）' '[[ ! -e $KN && -e $PD ]] && (( reads == 1 ))'
reset; mkpend; touch $M/authed
run MAC=$B DOM=wi2.ne.jp BRAND=starbucks
                          ok 'USEN の同意待ちは、別の Wi2 の網で入店時の同意を記録しても残る' '[[ $(<"$KN") == "$B starbucks" && $(<$PD) == "$A usen "<-> ]]'
reset; mkpend; p0=$(<$PD)
run MAC=$A NOROUTE=1;     ok 'USEN 同意待ちの網で既定経路がなくなっても、基準時刻は進めない' '[[ $(<$PD) == "$p0" && ! -s $M/calls ]]'
touch $M/authed
run MAC=$A WEBSHEET=$(now 5)
                          ok 'USEN 既定経路がなくなったあとに利用者が同意すれば記録' 'grep -qx "$A usen" "$KN"'

# 拒否が続いたときの停止と再開
ureject() { skip; run MAC=$A "$UL" "$@" }
reset; mkknown $A "usen $HASH"
ureject UHTTP=403; ureject UHTTP=403; o2=$out; ureject UHTTP=403
ok 'USEN が HTTP 403 を返し疎通なし×3: 自動を止める' '[[ $o2 == *"login failed x2 api=ng probe=ng http=403"* && $out == *"auto stopped net=$A usen rejected x3 http=403"* ]] && (( notes == 1 )) && [[ $(<$PD) == "$A usen "<->" notified" && ! -e $ST ]]'
ok 'USEN 自動の停止: ハッシュ付きの行が消え、「MAC usen」の行も残らない' '! grep -q "^$A usen" "$KN"'
posts_total=0
touch $M/authed; run MAC=$A LOGFAIL=1; (( posts_total += posts ))
ago 1800 $SN; rm $M/authed
run MAC=$A "$UL"; (( posts_total += posts ))
ok 'USEN 停止のあと、ログが読めず30分たっても同意待ちが残り、送らない' '[[ -e $PD ]] && ! grep -q "^$A usen" "$KN" && (( posts_total == 0 ))'
touch $M/authed; rewind; run MAC=$A WEBSHEET=$(now 1)
ok 'USEN 停止のあと、接続から5分を過ぎてから利用者が同意すれば記録し直す' 'grep -qx "$A usen" "$KN" && [[ ! -e $PD ]] && (( posts == 0 ))'
rm $M/authed; run MAC=$A "$UL" RECOVER=1
ok 'USEN 記録し直したあとは再開する' '(( uposts == 1 )) && [[ $out == *re-authenticated* && $(<"$KN") == "$A usen $HASH" ]]'
reset; mkknown $A "usen $HASH"
ureject; o1=$out; ureject; ureject
ok 'USEN が HTTP 200 を返しても疎通なし×3 なら止める' '[[ $o1 == *"login failed x1 api=ok probe=ng http=200"* && $out == *"auto stopped net=$A usen rejected x3 http=200"* && ! -s $KN ]]'
touch $M/authed; run MAC=$A
ok 'USEN 停止のあと、平文の Success だけでは再開しない' '[[ ! -s $KN && -e $PD ]] && (( posts == 0 ))'
rewind; ago 1800 $SN; run MAC=$A WEBSHEET=$(now 5)
ok 'USEN 停止のあと、認証画面での同意があれば再開する' 'grep -qx "$A usen" "$KN" && [[ ! -e $PD ]]'
reset; mkknown $A "usen $HASH"
for i in {1..4}; do ureject UHTTP=000; done
ok 'USEN の送信がタイムアウト×4 なら止めない' 'grep -qx "$A usen $HASH" "$KN" && [[ $out == *"login failed x4 api=ng probe=ng http=000 curl=28"* ]]'
reset; mkknown $A "usen $HASH"
for i in {1..4}; do ureject UHTTP=500; done
ok 'USEN が 5xx を返し続けても止めない' 'grep -qx "$A usen $HASH" "$KN"'

# 規約の変更
reset; mkknown $A "usen 0000"
run MAC=$A "$UL" RECOVER=1
ok 'USEN 規約の文面が変わったら送らず、止めて知らせる' '(( posts == 0 && notes == 1 )) && [[ $out == *"terms changed net=$A usen" && ! -s $KN && $(<$PD) == "$A usen "<->" notified" ]] && grep -q 利用規約が変わった $M/notify'
touch $M/authed; run MAC=$A
ok 'USEN 規約の変更のあと、平文の Success だけでは記録し直さない' '[[ ! -s $KN && -e $PD ]]'
rewind; ago 1800 $SN; run MAC=$A WEBSHEET=$(now 5)
ok 'USEN 規約の変更のあと、認証画面での同意で記録し直す' '[[ $(<"$KN") == "$A usen" ]]'
rm $M/authed; run MAC=$A "$UL" RECOVER=1 UJS=changed
ok 'USEN 規約の変更のあと、次の送信で今の文面のハッシュを記録する' '[[ $(<"$KN") == "$A usen $HASH2" ]] && (( uposts == 1 ))'

# 誘導先の形と経路
for l in "http://8.8.8.8:8080/captive/?stamac=aa:bb:cc:dd:ee:0f" "http://portal.example.com/captive/?stamac=aa:bb:cc:dd:ee:0f" \
         "https://10.9.8.7:8080/captive/?stamac=aa:bb:cc:dd:ee:0f" "http://10.9.8.7:8080/login/?stamac=aa:bb:cc:dd:ee:0f" \
         "http://172.32.0.1/captive/?stamac=aa:bb:cc:dd:ee:0f" "http://10.09.8.7/captive/?stamac=aa:bb:cc:dd:ee:0f" \
         "http://10.9.8.7:8080@example.com/captive/?stamac=aa:bb:cc:dd:ee:0f"; do
  reset; mkknown $A "usen $HASH"
  run MAC=$A "LOC=$l" RECOVER=1
  ok "USEN として扱わない誘導先（$l）: 何も送らない" '(( posts == 0 )) && [[ $(grep -vc hotspot-detect $M/calls) == 0 && $out == *"portal unknown x1 http=302 to="* ]]'
done
for r in ifc gw; do
  reset; mkknown $A "usen $HASH"
  run MAC=$A "$UL" RECOVER=1 DEVRT=$r
  ok "USEN 機器への経路が既定経路と別（$r）なら何も送らない" '(( posts == 0 )) && ! grep -q "$UD" $M/calls'
done
reset; mkknown $A "usen $HASH"
run MAC=$A "$UL" RECOVER=1 DEVRT=direct
ok 'USEN 機器が同じインターフェースの直結なら送る' '(( uposts == 1 ))'
for q in 'stamac=11:22:33:44:55:66' 'stamac=' 'x=1' 'stamac=aa:bb:cc:dd:ee:0f%22'; do
  reset; mkknown $A "usen $HASH"
  run MAC=$A "LOC=$UD/captive/?url=captive.apple.com/hotspot-detect.html&$q" RECOVER=1
  ok "USEN の stamac が自分と違う・ない・不正（$q）なら送らない" '(( posts == 0 )) && [[ $out == *"portal mismatch x1 mac=ng" ]] && ! grep -q "$UD" $M/calls'
done
reset; mkknown $A "usen $HASH"
run MAC=$A "LOC=$UD/captive/?url=captive.apple.com/hotspot-detect.html&stamac=AA-BB-CC-DD-EE-F" RECOVER=1
ok 'USEN の stamac の表記の違いは吸収する' '(( uposts == 1 ))'

# 画面と page.js の中身
for up uj in notitle ok  big ok  ok nomark  ok noterm  ok big; do
  reset; watch $A
  run MAC=$A "$UL" RECOVER=1 UPAGE=$up UJS=$uj
  ok "USEN の目印がない・上限を超える（画面 $up・page.js $uj）: 送らず、見張りから外す" '(( posts == 0 )) && [[ $out == *"portal unknown x1 http=200 to=$UD/captive/"* && ! -s $WT && ! -e $KN ]]'
done
for up uj in timeout ok  404 ok  ok timeout  ok 404; do
  reset; watch $A; w0=$(<$WT)
  run MAC=$A "$UL" RECOVER=1 UPAGE=$up UJS=$uj
  ok "USEN の画面・page.js が取れない（画面 $up・page.js $uj）: 送らず、見張りは残して待機（有効期限は延ばさない）" '(( posts == 0 && notes == 0 )) && [[ $out == *"portal check failed x1 curl="*" to=$UD/captive/"* && $(<$WT) == "$w0" && -e $ST && ! -e $KN ]]'
done
run MAC=$A "$UL" RECOVER=1; ok 'USEN 確かめられなかったあとの待機中は通信しない' '! grep -q "$UD" $M/calls'
skip; run MAC=$A "$UL" RECOVER=1
ok 'USEN 確かめられなかったあとの捕捉で取得できれば、記録して送る' '[[ $out == *"consent recorded net=$A usen (captive login)"* ]] && (( uposts == 1 ))'
reset; watch $A; joined
run MAC=$A;               ok 'USEN 見張り中の網が Wi2 へ転送したら見張りから外す（Wi2 の分岐はこれまでどおり）' '[[ ! -s $WT && $(<$PD) == "$A doutor" && $out == *"consent pending net=$A doutor" ]] && (( posts == 0 && redirs == 1 ))'
reset; watch $A
run MAC=$A "LOC=https://portal.example.com/login?mac=aa:bb:cc:dd:ee:0f"
ok 'USEN 見張り中の網が USEN でも Wi2 でもないポータルなら、何も送らず見張りから外す' '[[ ! -s $WT && -z $out ]] && [[ $(grep -vc hotspot-detect $M/calls) == 0 ]]'

# 途中で既定経路がなくなる
for st in watched known hashed changed none; do
  for sw in page js; do
    reset
    case $st in
      watched) watch $A ;; known) mkknown $A usen ;; hashed) mkknown $A "usen $HASH" ;; changed) mkknown $A "usen 0000" ;; none) joined ;;
    esac
    s0=$(snap)
    run MAC=$A "$UL" RECOVER=1 USWITCH=$sw
    ok "USEN（$st）で画面の GET の最中・送る直前（$sw）に既定経路がなくなったら、送らず何も書かない" '(( posts == 0 && notes == 0 )) && [[ $out == *"network changed net=$A usen before recording" && $(snap) == "$s0" ]]'
  done
done
reset; mkknown $A "usen $HASH"; s0=$(snap)
for i in 1 2 3; do skip; run MAC=$A "$UL" USWITCH=post; rm -f $M/noroute; done
ok 'USEN 送ったあとに既定経路がなくなったら、成功とも拒否とも数えない' '(( uposts == 1 )) && [[ $out == *"network changed net=$A usen api=ok probe=ng" && $(snap) == "$s0" && ! -e $ST ]]'

# --- メニューバーの表示（menubar.sh） ------------------------------------------
LG=$HOME/Library/Logs/cafe-wifi-okawari.log
NL=$'\n' TB=$'\t'
R="head${TB}cafe-wifi-okawari"   # 見出し
TIP="${TB}Estimated from the last authentication, if the shop's limit is 60 minutes."
NT="${NL}-${TB}Next Time-out${TB}~"   # 次の時間切れの行（時刻の前まで）
RE="${NL}${NL}head${TB}Recent${NL}-${TB}" EV="${NL}-${TB}"   # 直近の出来事の見出しと1件目の始まり / 2件目以降の始まり
ON='Auto Reconnect On' NX='Auto Reconnect from Next Time-out'
OFF="gray${TB}This Wi‑Fi${NL}-${TB}Auto Reconnect Off"   # 未同意（印は灰）
# mb VAR=val...: menubar.sh を1回実行し、1行目を icon に、2行目以降を rows に残す
mb() { env "$@" PATH=$T/bin:$PATH zsh $T/mb.sh > $M/out 2>&1; rc=$? out=$(<$M/out); icon=${out%%$'\n'*} rows=${out#*$'\n'} }
mbreset() { reset; rm -f $LG $M/notloaded; mkdir -p ${LG:h}; T0=$EPOCHSECONDS }
# 基準の時刻 T0（mbreset の時刻）から数える。行の時刻と期待する表示を同じ基準で作り、分の境目で揺れないようにする
lt() { strftime '%F %T' $(( T0 - $1 )) }   # lt <秒>: その秒数前のログの時刻
hm() { strftime '%H:%M' $(( T0 - $1 )) }   # hm <秒>: その秒数前の時:分
mbreset
mb MAC=$A;                ok 'メニューバー: 記録がなければ動作中・未同意だけ（区切り線も出来事も出さない）' '(( rc == 0 )) && [[ $icon == on && $rows == "$R${NL}$OFF" ]]'
touch $LG; mb MAC=$A;     ok 'メニューバー: ログが空でも同じ' '[[ $icon == on && $rows == "$R${NL}$OFF" ]]'
mkknown $A skylark
mb MAC=$A;                ok 'メニューバー: 同意済みならブランド（先頭だけ大文字）と自動再接続 On' '[[ $rows == "$R${NL}green${TB}Skylark${NL}-${TB}$ON" ]]'
consent $A "usen $HASH"; consent $B doutor
mb MAC=$A;                ok 'メニューバー: 同じ MAC の同意済みのブランドを並べる（usen は USEN）' '[[ $rows == "$R${NL}green${TB}Skylark, USEN${NL}-${TB}$ON" ]]'
mbreset; mkdir -p ${WT:h}; print -r -- "$A $(now 3600)" > $WT
mb MAC=$A;                ok 'メニューバー: 見張り中（24時間以内）なら次の時間切れから' '[[ $rows == "$R${NL}yellow${TB}This Wi‑Fi${NL}-${TB}$NX" ]]'
print -r -- "$A $(now 86401)" > $WT
mb MAC=$A;                ok 'メニューバー: 見張りから24時間を過ぎていれば未同意' '[[ $rows == "$R${NL}$OFF" ]]'
# 注意の2条件（今の接続先のときだけ）
W1="-${TB}Couldn't reconnect automatically. Check the login page."
W2="-${TB}Accept the terms once on the login page. After that, it reconnects automatically."
mbreset; mkknown $A; print -r -- "2 $(now -60) $A 0 1 doutor" > $ST
mb MAC=$A;                ok 'メニューバー: 再接続に失敗して知らせたあとは注意（案内は This Wi‑Fi の直後）' '[[ $icon == warn && $rows == "$R${NL}red${TB}Doutor${NL}-${TB}$ON${NL}$W1" ]]'
mb MAC=$B;                ok 'メニューバー: 失敗の状態ファイルが別の接続先なら注意にしない' '[[ $icon == on && $rows != *reconnect\ automatically* ]]'
print -r -- "2 $(now -60) $A 0 0 doutor" > $ST
mb MAC=$A;                ok 'メニューバー: 失敗しても、まだ知らせていなければ注意にしない' '[[ $icon == on && $rows != *reconnect\ automatically* ]]'
print -r -- "3 $(now -60)" > $ST
mb MAC=$A;                ok 'メニューバー: 旧形式の状態ファイルでも動く（注意にしない）' '(( rc == 0 )) && [[ $icon == on && $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON" ]]'
mbreset; print -r -- "$A doutor notified" > $PD
mb MAC=$A;                ok 'メニューバー: 同意待ちで知らせたあとは注意（同意の案内）' '[[ $icon == warn && $rows == "$R${NL}yellow${TB}This Wi‑Fi${NL}-${TB}Auto Reconnect Off${NL}$W2" ]]'
mb MAC=$B;                ok 'メニューバー: 同意待ちが別の接続先なら注意にしない（店を出たあとの自宅など）' '[[ $icon == on && $rows == "$R${NL}$OFF" ]]'
print -r -- "$A doutor" > $PD
mb MAC=$A;                ok 'メニューバー: 同意待ちでも、まだ知らせていなければ注意にしない' '[[ $icon == on ]]'
print -r -- "$A usen $(now 60) notified" > $PD
mb MAC=$A;                ok 'メニューバー: USEN の同意待ち（自動の停止のあと）も注意' '[[ $icon == warn && $rows == *"${NL}$W2" ]]'
print -r -- "$A usen $(now 60)" > $PD
mb MAC=$A;                ok 'メニューバー: USEN の同意待ちで知らせる前は注意にしない' '[[ $icon == on ]]'
mkknown $A; print -r -- "2 $(now -60) $A 0 1 doutor" > $ST; print -r -- "$A doutor notified" > $PD
mb MAC=$A;                ok 'メニューバー: 失敗と同意待ちが重なれば、印は赤のまま案内を両方出す' '[[ $icon == warn && $rows == "$R${NL}red${TB}Doutor${NL}-${TB}$ON${NL}$W1${NL}$W2" ]]'
rm -f $ST
# 認証画面待ち・未接続（既定経路がない）
WL="yellow${TB}Waiting for Login Page${NL}-${TB}If the login page doesn't appear, open http://captive.apple.com."
print -r -- "$A doutor notified" > $PD
mb MAC=$A NOROUTE=1;      ok 'メニューバー: 注意の最中に既定経路がなくなり、Wi‑Fi に IPv4 があれば認証画面待ち' '[[ $icon == wait && $rows == "$R${NL}$WL" ]]'
mb MAC=$A NOROUTE=1 MYIP= WAITUI=TRUE
                          ok 'メニューバー: Wi‑Fi に IPv4 がなくても、macOS が認証画面を待っていれば認証画面待ち' '[[ $icon == wait && $rows == "$R${NL}$WL" ]]'
mb MAC=$A NOROUTE=1 MYIP=; ok 'メニューバー: どちらもなければ未接続（アイコンは動作中）' '[[ $icon == on && $rows == "$R${NL}gray${TB}Offline" ]]'
# 再認証直後（✓）と優先順位
mbreset; mkknown $A
print -r -- "$(lt 590) re-authenticated api=ok probe=ok net=$A doutor t=2s" > $LG
mb MAC=$A;                ok 'メニューバー: 再認証から10分以内は ✓' '[[ $icon == check ]]'
mb MAC=$B;                ok 'メニューバー: ✓ は今の接続先に依らない' '[[ $icon == check ]]'
mb MAC=$A NOROUTE=1;      ok 'メニューバー: 認証画面待ちは ✓ より優先' '[[ $icon == wait ]]'
print -r -- "2 $(now -60) $A 0 1 doutor" > $ST
mb MAC=$A;                ok 'メニューバー: 注意は ✓ より優先' '[[ $icon == warn ]]'
touch $M/notloaded
mb MAC=$A;                ok 'メニューバー: 停止中は注意より優先し、今の接続先・案内・目安を出さない' \
  '(( rc == 0 )) && [[ $icon == off && $rows == "$R${NL}gray${TB}Stopped${NL}-${TB}Run install.sh to Restart${RE}Today $(hm 590)${TB}Reconnected · Doutor · 2 s" ]]'
rm -f $M/notloaded $ST
print -r -- "$(lt 610) re-authenticated api=ok probe=ok net=$A doutor t=2s" > $LG
mb MAC=$A;                ok 'メニューバー: 再認証から10分を過ぎれば ✓ を外す' '[[ $icon == on ]]'
# 次の時間切れの目安
mbreset; mkknown $A
print -r -- "$(lt 600) re-authenticated api=ok probe=ok net=$A doutor t=2s" > $LG
mb MAC=$A;                ok 'メニューバー: 今の接続先で再認証していれば、その60分後を目安に（ツールチップ付き）' '[[ $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON${NT}$(hm -3000)$TIP${RE}"* ]]'
mb MAC=$B;                ok 'メニューバー: 店 A で再認証したあと店 B へ移れば目安を出さない' '[[ $rows != *Next\ Time-out* ]]'
print -r -- "$(lt 3700) consent recorded net=$A doutor (online)" > $LG
mb MAC=$A;                ok 'メニューバー: 最後の認証から60分を過ぎていれば目安を出さない' '[[ $rows != *Next\ Time-out* ]]'
print -r -- "$(lt 3500) consent recorded net=$A doutor (online)" > $LG
mb MAC=$A;                ok 'メニューバー: 入店時の同意の記録からも目安を出す' '[[ $rows == *"${NT}$(hm -100)$TIP${NL}"* ]]'
# 削除して入れ直すと、認証済みの網で同意を記録し直す（(online)）。同じ接続の前の認証を起点にする
print -rl -- "$(lt 1800) re-authenticated api=ok probe=ok net=$A doutor t=2s" "$(lt 700) consent recorded net=$A doutor (online)" > $LG
mb MAC=$A;                ok 'メニューバー: 入れ直したあとの同意の記録し直しより、同じ接続の前の認証を目安の起点にする' '[[ $rows == *"${NT}$(hm -1800)$TIP${NL}"* ]]'
ago 1000 $M/resolv
mb MAC=$A;                ok 'メニューバー: 前の認証のあとにつなぎ直していれば、同意の記録を起点にする' '[[ $rows == *"${NT}$(hm -2900)$TIP${NL}"* ]]'
touch -t 202001010000 $M/resolv
mbreset; mkknown $A "usen $HASH"
print -rl -- "$(lt 3700) re-authenticated api=ok probe=ok net=$A usen t=1s" "$(lt 120) consent recorded net=$A usen (captive login)" \
  "$(lt 110) login failed x1 api=ng probe=ng http=200 curl=0 res=" > $LG
mb MAC=$A;                ok 'メニューバー: 認証画面での同意の記録（captive login）のあと送信に失敗したら目安を出さない' '[[ $rows != *Next\ Time-out* ]]'
print -r -- "$(lt 60) re-authenticated api=ok probe=ok net=$A usen t=1s" >> $LG
mb MAC=$A;                ok 'メニューバー: そのあと再認証すれば、その時刻から60分' '[[ $rows == *"${NT}$(hm -3540)$TIP${NL}"* ]]'
ago 40 $M/resolv
mb MAC=$A;                ok 'メニューバー: 行から30秒以内に resolv.conf が書き換わっても目安を出す' '[[ $rows == *Next\ Time-out* ]]'
ago 20 $M/resolv
mb MAC=$A;                ok 'メニューバー: 行の30秒より後に resolv.conf が書き換わっていれば（つなぎ直し）目安を出さない' '[[ $rows != *Next\ Time-out* ]]'
# 認証画面での同意を確かめた行（captive login seen）。ブランド付きの行だけを目安の起点にする
mbreset; mkknown $A
print -r -- "$(lt 600) captive login seen net=$A doutor" > $LG
mb MAC=$A;                ok 'メニューバー: 認証画面での同意を確かめた行から60分後を目安に（✓ は付けない）' \
  '[[ $icon == on && $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON${NT}$(hm -3000)$TIP${RE}Today $(hm 600)${TB}Accepted on Login Page · Doutor" ]]'
mb MAC=$B;                ok 'メニューバー: 認証画面での同意を確かめた行も、別の接続先では目安にしない' '[[ $rows != *Next\ Time-out* && $rows == *"Accepted on Login Page · Doutor" ]]'
ago 500 $M/resolv
mb MAC=$A;                ok 'メニューバー: 認証画面での同意を確かめた行の30秒より後に resolv.conf が書き換わっていれば目安を出さない' '[[ $rows != *Next\ Time-out* ]]'
mbreset; mkknown $A "usen $HASH"
print -r -- "$(lt 600) captive login seen net=$A usen" > $LG
mb MAC=$A;                ok 'メニューバー: USEN の網で認証画面での同意を確かめた行からも目安を出す' \
  '[[ $icon == on && $rows == *"${NT}$(hm -3000)$TIP${RE}Today $(hm 600)${TB}Accepted on Login Page · USEN" ]]'
print -r -- "$A tullys 1" > $ST.chain
mb MAC=$A;                ok 'メニューバー: 認証画面での同意を確かめた USEN の行も、チェーンが分かればチェーン' '[[ $rows == *"${TB}Accepted on Login Page · Tully'"'"'s" ]]'
mbreset; watch $A
print -r -- "$(lt 600) captive login seen net=$A" > $LG
mb MAC=$A;                ok 'メニューバー: ブランドのない行（見張りを始めた網）は、チェーンが分からなければ目安にせず、直近の出来事にだけ出す' \
  '[[ $rows == "$R${NL}yellow${TB}This Wi‑Fi${NL}-${TB}$NX${RE}Today $(hm 600)${TB}Accepted on Login Page" ]]'
# チェーンの分かった見張り中の網（来店時に認証画面で同意した USEN の網）: 緑の On と、見張りを始めた行からの目安
WTIP="${TB}Estimated from when you accepted on the login page, if the shop's limit is 60 minutes. It may be a few minutes off."
print -r -- "$A tullys 1" > $ST.chain
mb MAC=$A;                ok 'メニューバー: 見張り中でチェーンが分かれば、緑の On と、見張りを始めた行から60分後の目安（専用のツールチップ）' \
  '[[ $icon == on && $rows == "$R${NL}green${TB}Tully'"'"'s (USEN)${NL}-${TB}$ON${NT}$(hm -3000)$WTIP${RE}Today $(hm 600)${TB}Accepted on Login Page" ]]'
ago 650 $M/resolv
mb MAC=$A;                ok 'メニューバー: 見張りを始めた行の前5分以内に resolv.conf が書き換わっていれば、その時刻（早いほう）を起点に' '[[ $rows == *"${NT}$(hm -2950)$WTIP${NL}"* ]]'
ago 905 $M/resolv
mb MAC=$A;                ok 'メニューバー: resolv.conf の書き換えが行の5分より前なら（この接続のものではない）、行の時刻を起点に' '[[ $rows == *"${NT}$(hm -3000)$WTIP${NL}"* ]]'
ago 580 $M/resolv
mb MAC=$A;                ok 'メニューバー: 行から30秒以内の resolv.conf の書き換えなら、行の時刻を起点に' '[[ $rows == *"${NT}$(hm -3000)$WTIP${NL}"* ]]'
ago 560 $M/resolv
mb MAC=$A;                ok 'メニューバー: 見張りを始めた行の30秒より後に resolv.conf が書き換わっていれば目安を出さない（緑の On は出す）' '[[ $rows == "$R${NL}green${TB}Tully'"'"'s (USEN)${NL}-${TB}$ON${RE}"* ]]'
mb MAC=$B;                ok 'メニューバー: 見張りを始めた行も、別の接続先では目安にしない' '[[ $rows != *Next\ Time-out* ]]'
print -r -- "$(lt 3500) captive login seen net=$A" > $LG; ago 3620 $M/resolv
mb MAC=$A;                ok 'メニューバー: 起点（resolv.conf の書き換え）から60分を過ぎていれば目安を出さない' '[[ $rows == "$R${NL}green${TB}Tully'"'"'s (USEN)${NL}-${TB}$ON${RE}"* ]]'
print -r -- "$(lt 3610) captive login seen net=$A" > $LG; ago 3590 $M/resolv
mb MAC=$A;                ok 'メニューバー: 行のあと30秒以内の resolv.conf の書き換えは起点にしない（遅いほうにしない）' '[[ $rows != *Next\ Time-out* ]]'
print -rl -- "$(lt 600) captive login seen net=$A usen" "$(lt 500) re-authenticated api=ok probe=ok net=$A usen t=1s" > $LG; touch -t 202001010000 $M/resolv
mb MAC=$A;                ok 'メニューバー: 見張り中の網では、ブランド付きの行は目安にしない（見張りを始めた行だけ）' '[[ $rows != *Next\ Time-out* ]]'
print -r -- "$(lt 600) captive login seen net=$A" > $LG; print -r -- "2 $(now -60) $A 0 1 usen" > $ST
mb MAC=$A;                ok 'メニューバー: 見張り中でチェーンが分かっても、再接続に失敗して知らせたあとは赤（目安は出す）' \
  '[[ $icon == warn && $rows == "$R${NL}red${TB}Tully'"'"'s (USEN)${NL}-${TB}$ON${NL}$W1${NT}$(hm -3000)$WTIP${RE}"* ]]'
rm -f $ST
# USEN の網のチェーン（システムログの伏せ字の SSID）
CH=$ST.chain TU='tu********Fi' KO='Ko********Fi'
mbreset; mkknown $A "usen $HASH"; rm -f $M/logcalls
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: USEN の網で、リース開始のあとの伏せ字の SSID がタリーズならチェーンと運営を出す' '[[ $rows == "$R${NL}green${TB}Tully'"'"'s (USEN)${NL}-${TB}$ON" ]]'
ok 'メニューバー: チェーンはキーと接続先だけ残す（伏せ字の SSID は残さない）' '[[ $(<$CH) == "$A tullys $(( T0 - 60 ))" ]]'
n1=$(wc -l < $M/logcalls)
mb MAC=$A LEASE=$(( T0 - 30 )) SSIDLOG="$(( T0 - 27 )):en0:$KO"
                          ok 'メニューバー: 分かったチェーンは接続先ごとに覚え、システムログを読み直さない' '[[ $rows == *"${TB}Tully'"'"'s (USEN)${NL}"* && $(wc -l < $M/logcalls) == $n1 ]]'
rm -f $CH; mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$KO"
                          ok 'メニューバー: コメダの形ならコメダ' '[[ $rows == "$R${NL}green${TB}Komeda (USEN)${NL}-${TB}$ON" ]]'
rm -f $CH; mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU $(( T0 - 55 )):en0:ho****me"
                          ok 'メニューバー: 表にない SSID なら USEN のまま（最後の行で判定）' '[[ $rows == "$R${NL}green${TB}USEN${NL}-${TB}$ON" ]]'
ok 'メニューバー: 見つからなかった接続はリース開始だけ残す（伏せ字の SSID は残さない）' '[[ $(<$CH) == "$A - $(( T0 - 60 ))" ]]'
n1=$(wc -l < $M/logcalls)
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: 同じ接続では、見つからなくても読み直さない' '[[ $rows == *"${TB}USEN${NL}"* && $(wc -l < $M/logcalls) == $n1 ]]'
mb MAC=$A LEASE=$(( T0 - 20 )) SSIDLOG="$(( T0 - 17 )):en0:$TU"
                          ok 'メニューバー: リース開始が変われば（つなぎ直し・DHCP の更新）読み直す' '[[ $rows == *"${TB}Tully'"'"'s (USEN)${NL}"* ]] && (( $(wc -l < $M/logcalls) == n1 + 1 ))'
rm -f $CH; mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 3600 )):en0:$KO $(( T0 - 1800 )):en0:$TU"
                          ok 'メニューバー: リース開始より前の SSID の行も使う（DHCP の更新でリース開始が進んだあと。最後の行で判定）' '[[ $rows == *"${TB}Tully'"'"'s (USEN)${NL}"* ]]'
rm -f $CH; mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 7300 )):en0:$TU"
                          ok 'メニューバー: 2時間より前の SSID の行は使わない' '[[ $rows == *"${TB}USEN${NL}"* && $(<$CH) == "$A - $(( T0 - 60 ))" ]]'
rm -f $CH; mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU $(( T0 - 55 )):en1:$KO"
                          ok 'メニューバー: 今のインターフェースでない SSID の行は使わない（あとに出ても）' '[[ $rows == *"${TB}Tully'"'"'s (USEN)${NL}"* ]]'
rm -f $CH $M/logcalls; mb MAC=$A LEASE=$(( T0 - 10 )) SSIDLOG="$(( T0 - 7 )):en0:$TU"
                          ok 'メニューバー: リース開始から15秒はシステムログを読まず、何も残さない' '[[ $rows == *"${TB}USEN${NL}"* && ! -e $M/logcalls && ! -e $CH ]]'
mb MAC=$A LEASE=none SSIDLOG="$(( T0 - 7 )):en0:$TU"
                          ok 'メニューバー: リース開始が読めなければシステムログを読まない' '[[ $rows == *"${TB}USEN${NL}"* && ! -e $M/logcalls ]]'
mb MAC=$A LEASE=$(( T0 - 60 )) LOGFAIL=1
                          ok 'メニューバー: システムログが読めなければ USEN のまま' '(( rc == 0 )) && [[ $rows == *"${TB}USEN${NL}"* ]]'
rm -f $CH; mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU" LOGSWITCH=1; rm -f $M/switched
                          ok 'メニューバー: 読む間に別の接続先へ切り替われば、チェーンを出さず何も残さない（別の網の SSID を結び付けない）' '[[ $rows == *"${TB}USEN${NL}"* && ! -e $CH ]]'
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU" LOGLEASE=$(( T0 - 20 )); rm -f $M/lease
                          ok 'メニューバー: 読む間につなぎ直せば（リース開始が変われば）、チェーンを出さず何も残さない' '[[ $rows == *"${TB}USEN${NL}"* && ! -e $CH ]]'
rm -f $CH; print -r -- other > $CH.tmp
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: キャッシュは自分だけの一時ファイルから置き換える（ほかのプロセスの一時ファイルに触らず、残さない）' '[[ $(<$CH) == "$A tullys $(( T0 - 60 ))" && $(<$CH.tmp) == other && -z $(print -l $CH.*(N:t) | grep -v "^${CH:t}.tmp$") ]]'
rm -f $CH $CH.tmp
mbreset; mkknown $A skylark; consent $A "usen $HASH"; rm -f $M/logcalls
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: 同じ MAC の Wi2 のブランドと並べる' '[[ $rows == "$R${NL}green${TB}Skylark, Tully'"'"'s (USEN)${NL}-${TB}$ON" ]]'
mbreset; mkknown $A doutor; rm -f $M/logcalls
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: Wi2 の網ではシステムログを読まない' '[[ $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON" && ! -e $M/logcalls && ! -e $CH ]]'
mb MAC=$B LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: 未同意の網ではシステムログを読まない' '[[ $rows == "$R${NL}$OFF" && ! -e $M/logcalls && ! -e $CH ]]'
mbreset; mkdir -p ${WT:h}; print -r -- "$A $(now 3600)" > $WT
mb MAC=$A LEASE=$(( T0 - 60 )) SSIDLOG="$(( T0 - 57 )):en0:$TU"
                          ok 'メニューバー: 見張り中の網でチェーンが分かれば、緑の On' '[[ $rows == "$R${NL}green${TB}Tully'"'"'s (USEN)${NL}-${TB}$ON" ]]'
print -rl -- "$(lt 120) re-authenticated api=ok probe=ok net=$A usen t=1s" "$(lt 100) re-authenticated api=ok probe=ok net=$B usen t=2s" > $LG
mb MAC=$B;                ok 'メニューバー: 直近の出来事の USEN は、チェーンが分かっている接続先ならチェーン' \
  '[[ $rows == *"${RE}Today $(hm 100)${TB}Reconnected · USEN · 2 s${EV}Today $(hm 120)${TB}Reconnected · Tully'"'"'s · 1 s" ]]'
touch $M/notloaded
mb MAC=$B;                ok 'メニューバー: 停止中も直近の出来事はチェーン' '[[ $icon == off && $rows == *"Reconnected · Tully'"'"'s · 1 s" ]]'
rm -f $M/notloaded
print -r -- "$B - 1" >> $CH
mb MAC=$B;                ok 'メニューバー: 見つからなかった接続先の出来事は USEN のまま' '[[ $rows == *"Reconnected · USEN · 2 s"* && $out != *aa:aa* && $out != *bb:bb* ]]'
# 直近の出来事の読み替え
mbreset; mkknown $A
strftime -s d0 %F $EPOCHSECONDS; strftime -r -s md %F $d0; strftime -s d1 %F $(( md - 1 )); strftime -s d2 %F $(( md - 86401 ))
print -rl -- "$d2 10:00:00 re-authenticated api=ok probe=ok net=$A skylark t=9s" \
  "$d2 10:05:00 auto stopped net=$A doutor rejected x3 http=200 curl=0 res={\"result\":false}" \
  "$d1 23:59:30 re-authenticated api=ok probe=ok net=$A skylark t=2s" \
  "$d0 00:00:05 consent recorded net=$A doutor (online)" \
  "$d0 00:00:20 consent recorded net=$A usen (captive login)" \
  "$d0 00:00:30 redirect failed x2 http=302 to=https://service.wi2.ne.jp/wi2auth/error/ctrlapi_timeout.html" \
  "$d0 00:00:31 consent pending net=$B doutor" "$d0 00:00:32 captive login seen net=$B" "$d0 00:00:33 probe failed x1 net=$A if=en0 curl=7 http=000" \
  "$d0 00:00:34 redirect failed x1 net=$A curl=28 http=000" "$d0 00:00:35 network changed net=$A doutor api=ok probe=ng" \
  "$d0 00:00:40 login failed x3 api=ng probe=ng http=200 curl=0 res={\"result\":false}" > $LG
mb MAC=$B;                ok 'メニューバー: 直近の出来事は新しい順に3件（失敗はブランドなし。認証画面での同意を確かめた行も出す。確認の失敗・同意待ちなどは出さない）' \
  '[[ $rows == "$R${NL}$OFF${RE}Today 00:00${TB}Couldn'"'"'t Reconnect${EV}Today 00:00${TB}Accepted on Login Page${EV}Today 00:00${TB}Couldn'"'"'t Reconnect" ]]'
sed -i '' '/ 00:00:[1-4]/d' $LG
mb MAC=$B;                ok 'メニューバー: 今日・昨日の境目と、それより前は月-日' \
  '[[ $rows == *"${RE}Today 00:00${TB}Terms Accepted · Doutor${EV}Yesterday 23:59${TB}Reconnected · Skylark · 2 s${EV}${d2[6,10]} 10:05${TB}Auto Reconnect Stopped · Doutor" ]]'
print -r -- "$d0 00:00:50 consent recorded net=$A aa:bb:cc (online)" >> $LG
mb MAC=$B;                ok 'メニューバー: ブランド名に英数字・-・_ 以外があれば出さない' '[[ $rows == *"${RE}Today 00:00${TB}Terms Accepted${EV}Today 00:00${TB}Terms Accepted · Doutor${NL}"* && $out != *aa:bb* ]]'
sed -i '' '$d' $LG; mb MAC=$B
                          ok 'メニューバー: MAC・IP・URL・応答を出さない' '[[ $out != *aa:aa* && $out != *net=* && $out != *10.0.0* && $out != *http* && $out != *result* ]]'
o1=$out; mb MAC=$B LANGS=en-US
                          ok 'メニューバー: 優先言語が日本語でも英語でも同じ英語の表示' '[[ $out == "$o1" ]]'
# ログは末尾の 16KB だけ読む（途中で切れた行は使わない）
{ print -r -- "$(lt 60) re-authenticated api=ok probe=ok net=$A doutor t=2s"; for i in {1..300}; do print -r -- "$(lt 30) probe failed x1 net=$A if=en0 curl=7 http=000"; done } > $LG
mb MAC=$A;                ok 'メニューバー: 16KB より前の行は読まない' '[[ $icon == on && $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON" ]]'

# --- ネットワークの診断（netcheck.sh） ------------------------------------------
NCF=$ST.netcheck NCB=$ST.netcheck.base NCP="$HOME/Library/LaunchAgents/local.cafe-wifi-okawari.netcheck.plist"
# ncr VAR=val...: netcheck.sh を1回実行し、結果ファイルを res に残す（This Mac の控えは毎回捨てて読み直させる。ncrc は控えを残す）。nr <ID>: その行（ID を除く）
ncr() { rm -f $NCF.mac; ncrc "$@" }
ncrc() { env "$@" zsh $T/nc.sh > $M/out 2>&1; rc=$? out=$(<$M/out); res=; [[ -e $NCF ]] && res=$(<$NCF) }
nr() { print -r -- ${${(M)${(f)res}:#$1 *}#$1 } }
ncreset() { mbreset; rm -f $NCF $NCF.*(N) $NCP $M/pwned }
nlog() { [[ -e $LG ]] && print -r -- "${(F)${(@)${(f)"$(<$LG)"}#????????????????????}}" }   # ログの時刻を除いた行
# 確かめ中の危険を CONFIRM 秒より前に見たことにする（2回目の診断が数秒あとに来た状態）。forgot は最後に見たのも KEEP 秒より前にする
aged() { sed -i '' -E 's/^([a-z]+ [a-z-]+) [0-9]+ ([0-9]+)$/\1 1 \2/' $NCB }
forgot() { sed -i '' -E 's/^([a-z]+ [a-z-]+) [0-9]+ [0-9]+$/\1 1 1/' $NCB }
# 基準を取ってから GRACE 秒より後にする
settled() { sed -i '' -E '1s/ [0-9]+ ([^ ]+)$/ 1 \1/' $NCB }
NCB0="10.0.0.0/255.255.255.0 10.0.0.1 "   # 基準のサブネットと DNS サーバー（模擬の既定）
NCOK="gateway ok ok${NL}dns ok ok${NL}routes ok ok${NL}proxy ok off${NL}ipv6 ok none${NL}firewall ok stealth${NL}airplay ok off${NL}sharing ok off${NL}open ok none${NL}updates ok uptodate${NL}rootcerts ok none${NL}vpn unknown off${NL}privaddr info off"
ncreset
ncr MAC=$A;               ok '診断: 異常がなければ、接続先・時刻と全項目を固定の語で書き、ログには何も書かない' \
  '(( rc == 0 )) && [[ -z $out && $res == "v1 $A "<->" 0 -${NL}wifi unknown unknown${NL}$NCOK" && ! -e $LG ]]'
ok '診断: 結果と基準のファイルは 0600' '[[ $(stat -f %Lp $NCF) == 600 && $(stat -f %Lp $NCB) == 600 ]]'
i1=$(stat -f %i $NCF); ago 30 $NCF; ncr MAC=$A
ok '診断: 中身が変わらなければ書き直さず、更新時刻だけ進める' '[[ $(stat -f %i $NCF) == $i1 ]] && (( EPOCHSECONDS - $(stat -f %m $NCF) < 5 ))'
# W（Wi‑Fi の暗号化）と V（VPN）
ncr MAC=$A WSEC=NONE;     ok '診断: 暗号化なし（NONE）は注意、VPN なしも注意。ログに1行ずつ（net= 付き）' \
  '[[ $(nr wifi) == "notice none" && $(nr vpn) == "notice off" && $(nlog) == "netcheck wifi notice none net=$A${NL}netcheck vpn notice off net=$A" ]]'
ncr MAC=$A WSEC=NONE;     ok '診断: 変わらなければログに書き足さない' '(( $(wc -l < $LG) == 2 ))'
i1=$(stat -f %i $NCF); ncr MAC=$A WSEC=NONE LISTEN='*.8000,Python,901 *.49152,rapportd,728' PSMAP='901=/usr/bin/python3'
ncr MAC=$A WSEC=NONE LISTEN='*.8000,Python,901 *.49152,rapportd,728' PSMAP='901=/usr/bin/python3'
ok '診断: ループバック以外の待ち受けがあっても、変わらなければログにも結果にも書き足さない（前の結果を読む変数をポートの変数で上書きしない）' \
  '(( $(wc -l < $LG) == 3 )) && [[ $(nr open) == "notice apps n=1 p=8000" && $(stat -f %i $NCF) != $i1 ]] && i1=$(stat -f %i $NCF) && ncr MAC=$A WSEC=NONE LISTEN="*.8000,Python,901" PSMAP=901=/usr/bin/python3 && [[ $(stat -f %i $NCF) == $i1 ]] && (( $(wc -l < $LG) == 3 ))'
ncr MAC=$A WSEC=NONE   # 待ち受けをやめた状態に戻す（ログに open ok none）
ncr MAC=$A WSEC=WPA2_PSK; ok '診断: 実機で確かめていない値（WPA2_PSK など）は Unknown。注意から戻ったことをログに' \
  '[[ $(nr wifi) == "unknown unknown" && $(nr vpn) == "unknown off" && $(nlog) == *"${NL}netcheck wifi unknown unknown net=$A${NL}netcheck vpn unknown off net=$A" ]]'
ncr MAC=$A DEFIF=en5 WSEC=NONE; ok '診断: 既定経路が Wi‑Fi でなければ Not Wi‑Fi' '[[ $(nr wifi) == "unknown not-wifi" && $(nr privaddr) == "info unknown" ]]'
ncr MAC=$A DEFIF=utun4 DEVRT=ifc WSEC=NONE
ok '診断: VPN（既定経路が utun）なら On。下の Wi‑Fi の暗号化は見る' '[[ $(nr vpn) == "ok on" && $(nr wifi) == "notice none" && $(nr routes) == "ok ok" ]]'
ncreset; ncr MAC=$A DEFIF=utun4 DEFGW=10.8.0.1 LANGW=10.0.0.1 DEVRT=ifc
ok '診断: VPN の既定経路にゲートウェイがあっても、網のゲートウェイは Wi‑Fi に限った既定経路から読む。1行目の接続先は既定経路のまま' \
  '[[ $(nr gateway) == "ok ok" && $(<$NCB) == "10.0.0.1 "* && $res == "v1 $A "* ]]'
ncr MAC=$A DEFIF=utun4 DEFGW=none DEVRT=ifc WSEC=NONE
ok '診断: VPN の既定経路にゲートウェイの行がなくても（WireGuard など）診断し、1行目の接続先は -' \
  '[[ $res == "v1 - "* && $(nr vpn) == "ok on" && $(nr gateway) == "ok ok" && $(nr wifi) == "notice none" && $(nr routes) == "ok ok" ]]'
ncr MAC=$A NCLIST='* (Connected)      0A1B2C3D-0000 VPN (com.example) "Work"    [VPN/com.example]\n' WSEC=NONE
ok '診断: VPN がつながっていても既定経路が Wi‑Fi なら Partial（灰）' '[[ $(nr vpn) == "unknown partial" ]]'
ncr MAC=$A NCLIST='* (Disconnected)   0A1B2C3D-0000 VPN (com.example) "(Connected)"    [VPN/com.example]\n' WSEC=NONE
ok '診断: VPN の名前に (Connected) があっても、状態の欄が切断なら Partial にしない' '[[ $(nr vpn) == "notice off" ]]'
ncr MAC=$A DEVRT=ifc WSEC=NONE
ok '診断: 既定経路は Wi‑Fi のまま 0/1・128/1 で全部を通す VPN も、公開の宛先への経路で On。ゲートウェイは Wi‑Fi 側を見る' \
  '[[ $(nr vpn) == "ok on" && $(nr wifi) == "notice none" && $(nr gateway) == "ok ok" && $(nr routes) == "ok ok" && $res == "v1 $A "* ]]'
ncreset; ncr MAC=$A DEVRT=ifc XROUTE=1.0.0/8,10.0.0.1,UGSc,en0 OPT121=1.0.0.0/8,10.0.0.1; aged; ncr MAC=$A DEVRT=ifc XROUTE=1.0.0/8,10.0.0.1,UGSc,en0 OPT121=1.0.0.0/8,10.0.0.1
ok '診断: その型の VPN でも、網が経路を配った Wi‑Fi 側の余分な経路は Bypasses VPN' '[[ $(nr routes) == "risk bypass" ]]'
# 網が決める文字列（DHCP のドメイン名など）は getsummary で Security より前に出る。同じ形の文字列を入れても結果を変えられない
ncreset; ncr MAC=$A WSEC=NONE DHCPDOM='shop.example Security : WPA3_SAE'
ok '診断: DHCP のドメイン名に「Security : WPA3_SAE」を入れても、暗号化なしを隠せない' '[[ $(nr wifi) == "notice none" && $(nr vpn) == "notice off" ]]'
ncr MAC=$A WSEC=NONE DHCPDOM=$'x\n  Security : WPA2_PSK'
ok '診断: 改行で最上位の Security の行を装っても、最後の行（本物）を使う' '[[ $(nr wifi) == "notice none" ]]'
# G（ゲートウェイ）: 危険の確かめ直しと接続の基準
ncreset; ncr MAC=$A
ok '診断: 接続の基準にゲートウェイの IP・resolv.conf の更新時刻・MAC・IPv6 のルーター・サブネット・DNS サーバー・取った時刻・Wi‑Fi の暗号化を残す' \
  '[[ $(<$NCB) == "10.0.0.1 $(stat -f %m $M/resolv) $A - $NCB0"<->" -" ]]'
ncr MAC=$B;               ok '診断: 接続の途中でゲートウェイの MAC が変われば、1回目は注意（黄）。ログに基準の MAC と今の MAC。危険の記録はまだ作らない' \
  '[[ $(nr gateway) == "notice changed" && $(nlog) == "netcheck gateway notice changed net=$A to=$B" && $(sed -n 2p $NCB) == "gateway changed "<->" "<-> && ! -e $NCF.alert ]]'
ncr MAC=$B;               ok '診断: 数秒以内の2回目でもまだ危険にしない' '[[ $(nr gateway) == "notice changed" && $(wc -l < $LG) -eq 1 ]]'
aged; ncr MAC=$B;         ok '診断: 続けて変わったままなら危険。ログに基準の MAC と今の MAC を残し、結果の接続先は今の MAC' \
  '[[ $(nr gateway) == "risk changed" && $res == "v1 $B "* && $(nlog) == *"${NL}netcheck gateway risk changed net=$A to=$B" ]]'
ok '診断: 危険になれば危険の記録に時刻・ID・値だけを足す（0600。MAC・IP は書かない）' \
  '[[ $(<$NCF.alert) == <->" gateway changed" && $(stat -f %Lp $NCF.alert) == 600 ]]'
ncr MAC=$A;               ok '診断: 基準の MAC に戻れば OK に戻し、ログに1行。危険の記録と確かめ中の危険は残す' \
  '[[ $(nr gateway) == "ok ok" && $(nlog) == *"${NL}netcheck gateway ok ok net=$A" && $(wc -l < $NCB) -eq 2 && -s $NCF.alert ]]'
ncreset; ncr MAC=$A; ncr MAC=$B; ncr MAC=$A; aged; ncr MAC=$A; ncr MAC=$B
ok '診断: 診断の合間だけ偽装しても（変わる・戻るを繰り返す）、5分のうちに2回見れば危険' '[[ $(nr gateway) == "risk changed" ]]'
ncreset; ncr MAC=$A; ncr MAC=$B; ncr MAC=$A; forgot; ncr MAC=$B
ok '診断: 前に見てから5分を過ぎていれば、1回目から数え直す（注意）' '[[ $(nr gateway) == "notice changed" ]]'
ncreset; ncr MAC=$A; for i in {1..25}; do print -r -- "$i routes bypass"; done > $NCF.alert; ncr MAC=$B; aged; ncr MAC=$B
ok '診断: 危険の記録は新しい20件だけ残す' '(( $(wc -l < $NCF.alert) == 20 )) && [[ $(sed -n 1p $NCF.alert) == "7 routes bypass" && $(sed -n 20p $NCF.alert) == <->" gateway changed" ]]'
ncreset; ncr MAC=$A; ncr MAC=$B; aged; LEASE=$(( EPOCHSECONDS - 5 )) ncr MAC=$B
ok '診断: リースの更新（resolv.conf は変わらない）では基準を捨てない' '[[ $(nr gateway) == "risk changed" ]]'
ncreset; ncr MAC=$A WSEC=NONE; joined; ncr MAC=$B WSEC=NONE
ok '診断: つなぎ直しても（resolv.conf の書き換え）、暗号化なしの同じサブネットへ2分のうちなら前の基準と比べる（切断させてから偽装する攻撃）' \
  '[[ $(nr gateway) == "notice changed" && $(sed -n 1p $NCB) == "10.0.0.1 "<->" $A "*" NONE" ]]'
ncreset; ncr MAC=$A WSEC=NONE; ago 200 $NCB; joined; ncr MAC=$B WSEC=NONE
ok '診断: 2分より後のつなぎ直しは基準を取り直し、危険にしない' '[[ $(nr gateway) == "ok ok" && $(<$NCB) == "10.0.0.1 "<->" $B - "* && $(nlog) != *gateway* ]]'
ncreset; ncr MAC=$A WSEC=NONE; joined; ncr MAC=$B WSEC=NONE DEFGW=192.168.1.1
ok '診断: 別のサブネットへのつなぎ直しは、すぐでも基準を取り直す（別の網）' '[[ $(nr gateway) == "ok ok" && $(<$NCB) == "192.168.1.1 "<->" $B - 192.168.1.0/"* ]]'
ncreset; ncr MAC=$A WSEC=WPA2_PSK; joined; ncr MAC=$B WSEC=WPA2_PSK
ok '診断: 暗号化ありの網へのつなぎ直しは、同じサブネットへすぐでも基準を取り直す（テザリング・中継器の取り違え）' \
  '[[ $(nr gateway) == "ok ok" && $(<$NCB) == "10.0.0.1 "<->" $B - "*" WPA2_PSK" && $(nlog) != *gateway* ]]'
ncreset; ncr MAC=$A WSEC=WPA2_PSK; joined; ncr MAC=$B WSEC=NONE
ok '診断: 暗号化ありから暗号化なしの網へのつなぎ直しも、基準を取り直す' '[[ $(nr gateway) == "ok ok" && $(nlog) != *gateway* ]]'
ncreset; ncr MAC=$A WSEC=NONE; joined; ncr MAC=$B
ok '診断: Wi‑Fi でない網へのつなぎ直しも、基準を取り直す' '[[ $(nr gateway) == "ok ok" && $(nlog) != *gateway* ]]'
ncreset; ncr MAC=$A WSEC=NONE; ago 200 $NCB; ncr MAC=$A WSEC=NONE; joined; ncr MAC=$B WSEC=NONE
ok '診断: 接続している間は、基準が変わらなくても更新時刻（最後に接続していた時刻）を進める' '[[ $(nr gateway) == "notice changed" ]]'
ncreset; ncr MAC=$A WSEC=NONE; ago 200 $NCB; ncr MAC=$A NOROUTE=1; joined; ncr MAC=$B WSEC=NONE
ok '診断: 既定経路のない間は、基準の更新時刻を進めない' '[[ $(nr gateway) == "ok ok" ]]'
# Wi‑Fi では接続の見分けに ConnectionID（つなぐたびに増える）と起動時刻を使い、resolv.conf の書き換えでは基準を取り直さない
ncreset; ncr MAC=$A CID=3
ok '診断: Wi‑Fi の接続の基準は起動時刻と ConnectionID' '[[ $(<$NCB) == "10.0.0.1 c$(sysctl -n kern.boottime | sed -E "s/.*sec = ([0-9]+),.*/\1/").3 $A - $NCB0"<->" -" ]]'
ncr MAC=$B CID=3; aged; joined; ncr MAC=$B CID=3
ok '診断: 同じ接続のまま resolv.conf を書き換えさせても（RA の DNS サーバー・DHCP の更新）、基準を取り直さず危険' \
  '[[ $(nr gateway) == "risk changed" && $(nlog) == *"${NL}netcheck gateway risk changed net=$A to=$B" ]]'
ncreset; ncr MAC=$A CID=3 WSEC=NONE; ago 200 $NCB; ncr MAC=$B CID=4 WSEC=NONE; aged; ncr MAC=$B CID=4 WSEC=NONE
ok '診断: ConnectionID が変われば（つなぎ直し）、2分より後なら基準を取り直し、危険にしない' '[[ $(nr gateway) == "ok ok" && $(<$NCB) == *".4 $B - "* && $(nlog) != *gateway* ]]'
ncreset; ncr MAC=$A CID=3 WSEC=NONE; ncr MAC=$B CID=4 WSEC=NONE; aged; ncr MAC=$B CID=4 WSEC=NONE
ok '診断: 切断させてすぐつなぎ直させても（ConnectionID が増える）、前の基準と比べて危険' '[[ $(nr gateway) == "risk changed" && $(<$NCB) == *".4 $A - "* ]]'
ncreset; ncr MAC=$A CID=3 DHCPDOM=$'x\n  ConnectionID : 99'; ncr MAC=$B CID=3 DHCPDOM=$'x\n  ConnectionID : 98'; aged; ncr MAC=$B CID=3 DHCPDOM=$'x\n  ConnectionID : 97'
ok '診断: DHCP の文字列で ConnectionID を装っても、最初の行（本物）を使い、基準を取り直させられない' '[[ $(nr gateway) == "risk changed" && $(<$NCB) == *".3 $A -"* ]]'
ncreset; ncr MAC=$A CID=3; ago 200 $NCB; ncr MAC=$B CID=3 DEFGW=192.168.1.1; aged; ncr MAC=$B CID=3 DEFGW=192.168.1.1
ok '診断: 同じ接続のままゲートウェイの IP がサブネットごと変わっても（偽の DHCP）、基準を取り直さず危険' '[[ $(nr gateway) == "risk changed" && $(<$NCB) == "192.168.1.1 "*" $A "* ]]'
ncreset; ncr MAC=$A CID=3; ncr MAC=$A CID=3 DEFGW=10.0.0.254
ok '診断: ゲートウェイの IP だけ変わり MAC が同じなら OK' '[[ $(nr gateway) == "ok ok" ]]'
# D（DHCP の DNS サーバー）
ncreset; ncr MAC=$A DNS='10.0.0.1, 10.0.0.2'; ok '診断: DHCP の DNS サーバーを基準に残す（区切りは ,）' '[[ $(nr dns) == "ok ok" && $(<$NCB) == *" 10.0.0.1,10.0.0.2 "<->" -" ]]'
ncr MAC=$A DNS=192.0.2.53; ok '診断: 同じ接続の途中で DNS サーバーが変われば、1回目は注意' '[[ $(nr dns) == "notice changed" && $(nlog) == "netcheck dns notice changed net=$A" ]]'
aged; ncr MAC=$A DNS=192.0.2.53; ok '診断: 続けば危険（危険の記録にも足す）' '[[ $(nr dns) == "risk changed" && $(<$NCF.alert) == <->" dns changed" ]]'
ncreset; ncr MAC=$A DNS=none; ok '診断: DHCP の DNS サーバーがなければ Unknown' '[[ $(nr dns) == "unknown unknown" ]]'
ncr MAC=$A; ok '診断: 基準を取ってすぐ（30秒のうち）に見えた DNS サーバーは基準にする' '[[ $(nr dns) == "ok ok" ]]'
ncreset; ncr MAC=$A DHCPDOM=$'x\ndomain_name_server (ip_mult): {192.0.2.53}'
ok '診断: DHCP のドメイン名で DNS サーバーの行を装えば、2行になるので使わない（Unknown）' '[[ $(nr dns) == "unknown unknown" && $res != *192.0.2* && $(<$NCB) != *192.0.2* ]]'
ncreset; ncr MAC=$A DHCPDOM=$'x\nsubnet_mask (ip): 0.0.0.0'; ok '診断: サブネットマスクの行を装っても使わない' '[[ $(<$NCB) == "10.0.0.1 "<->" $A - - "* ]]'
ncreset; ncr MAC='(incomplete)'
ok '診断: ARP が不完全なら Unknown（接続先はゲートウェイの IP）' '[[ $(nr gateway) == "unknown unknown" && $res == "v1 10.0.0.1 "* ]]'
# R（経路）
ncreset; ncr MAC=$A XROUTE=1.0.0/8,10.0.0.1,UGSc,en0
ok '診断: Wi‑Fi 側に既定・サブネット・ホスト以外の経路があれば Extra Routes（VPN のサーバーへのホスト経路は数えない）' '[[ $(nr routes) == "notice extra n=1" ]]'
ncr MAC=$A XROUTE=1.0.0/8,10.0.0.1,UGSc,en5; ok '診断: 別のインターフェースの経路は数えない' '[[ $(nr routes) == "ok ok" ]]'
ncr MAC=$A MYIP=203.0.113.5; ok '診断: この Mac の IP が私用の範囲の外なら Public Subnet（IP は書かない）' '[[ $(nr routes) == "notice public" && $res != *203.0.113* ]]'
for x in 10.1.2.3 172.16.0.9 172.31.255.1 192.168.0.4 100.64.0.2 100.127.0.1 169.254.3.3; do ncr MAC=$A MYIP=$x; [[ $(nr routes) == "ok ok" ]] || break; done
ok '診断: 私用の範囲（10/8・172.16/12・192.168/16・100.64/10・169.254/16）の境目' '[[ $(nr routes) == "ok ok" ]]'
ncr MAC=$A MYIP=172.32.0.1; ok '診断: 172.32 は私用の範囲の外' '[[ $(nr routes) == "notice public" ]]'
ncreset; ncr MAC=$A DEFIF=utun4 OPT121=1.0.0.0/8,10.0.0.1
ok '診断: VPN の使用中に、網が経路を配り（DHCP の option 121）公開の宛先への経路が Wi‑Fi を通れば、1回目は注意' '[[ $(nr routes) == "notice bypass" && $(nlog) == "netcheck routes notice bypass net=$A" ]]'
aged; ncr MAC=$A DEFIF=utun4 OPT121=1.0.0.0/8,10.0.0.1; ok '診断: 続けば Bypasses VPN（危険）' '[[ $(nr routes) == "risk bypass" && $(nlog) == *"${NL}netcheck routes risk bypass net=$A" ]]'
ncreset; ncr MAC=$A DEFIF=utun4; aged; ncr MAC=$A DEFIF=utun4 XROUTE=10.0.0.0/8,10.0.0.1,UGSc,en0
ok '診断: 網が経路を配っていなければ、Wi‑Fi のゲートウェイを通る経路は VPN の除外の設定とみなし OK' '[[ $(nr routes) == "ok ok" && ! -e $LG ]]'
ncreset; ncr MAC=$A DEFIF=utun4 DEVRT=direct; aged; ncr MAC=$A DEFIF=utun4 DEVRT=direct
ok '診断: 網が経路を配っていなくても、公開の宛先が Wi‑Fi のサブネットに直結なら Bypasses VPN（TunnelCrack の LocalNet）' '[[ $(nr routes) == "risk bypass" ]]'
ncreset; ncr MAC=$A DEFIF=utun4 DEVRT=ifc DHCPDOM=$'x\nclassless_static_route (classless_route): {1.0.0.0/8, 10.0.0.1}' XROUTE=1.0.0/8,10.0.0.1,UGSc,en0
ok '診断: DHCP の文字列で経路のオプションの行を装えば、疑いが増える（注意）だけ' '[[ $(nr routes) == "notice bypass" ]]'
ncreset; ncr MAC=$A DEFIF=utun4 DEVRT=ifc XROUTE=1.0.0/8,10.0.0.1,UGSc,en0 OPT121=1.0.0.0/8,10.0.0.1; aged; ncr MAC=$A DEFIF=utun4 DEVRT=ifc XROUTE=1.0.0/8,10.0.0.1,UGSc,en0 OPT121=1.0.0.0/8,10.0.0.1
ok '診断: VPN の使用中に Wi‑Fi 側の余分な経路（DHCP の option 121 など）があれば Bypasses VPN' '[[ $(nr routes) == "risk bypass" ]]'
ncreset; ncr MAC=$A DEFIF=utun4 DEVRT=ifc MYIP=203.0.113.5; aged; ncr MAC=$A DEFIF=utun4 DEVRT=ifc MYIP=203.0.113.5
ok '診断: VPN の使用中に Wi‑Fi のサブネットが公開の範囲なら Bypasses VPN' '[[ $(nr routes) == "risk bypass" ]]'
# P（プロキシ）・6（IPv6 のルーター）
ncreset; ncr MAC=$A PROXY='  ProxyAutoDiscoveryEnable : 1\n'; ok '診断: プロキシの自動検出が有効なら注意' '[[ $(nr proxy) == "notice autodiscovery" ]]'
ncr MAC=$A PROXY='  HTTPSEnable : 1\n  HTTPSProxy : proxy.example\n'; ok '診断: プロキシが設定されていれば注意（名前は書かない）' '[[ $(nr proxy) == "notice set" && $res != *example* ]]'
ncr MAC=$A PROXY='  ProxyAutoConfigEnable : 1\n'; ok '診断: PAC も Set' '[[ $(nr proxy) == "notice set" ]]'
ncr MAC=$A PROXY='  HTTPEnable : 0\n'; ok '診断: 無効のプロキシは Off' '[[ $(nr proxy) == "ok off" ]]'
ncr MAC=$A PROXY='  HTTPEnable : 0\n  HTTPProxy : x ProxyAutoDiscoveryEnable : 1 HTTPEnable : 1\n'
ok '診断: プロキシの名前に「Enable : 1」の形があっても数えない（行全体で比べる）' '[[ $(nr proxy) == "ok off" ]]'
ncreset; ncr MAC=$A RA='fe80::1%en0'; ok '診断: IPv6 のルーターが1つなら OK（utun の行は数えない）' '[[ $(nr ipv6) == "ok ok" && $(<$NCB) == *" fe80::1%en0 "* ]]'
ncr MAC=$A RA='fe80::2%en0'; ok '診断: 接続の途中でルーターが変われば Changed' '[[ $(nr ipv6) == "notice changed" && $(nlog) == "netcheck ipv6 notice changed net=$A" ]]'
ncr MAC=$A RA='fe80::1%en0 fe80::9%en1'; ok '診断: 別のインターフェースのルーターは数えない' '[[ $(nr ipv6) == "ok ok" ]]'
ncreset; ncr MAC=$A RA='fe80::1%en0 fe80::2%en0'; ok '診断: 2つ以上なら Multiple' '[[ $(nr ipv6) == "notice multiple n=2" ]]'
ncreset; ncr MAC=$A; ncr MAC=$A RA='fe80::1%en0'; ok '診断: 基準を取ったときにルーターがなく、30秒のうちに見えたものは基準にする' '[[ $(nr ipv6) == "ok ok" ]]'
ncreset; ncr MAC=$A; settled; ncr MAC=$A RA='fe80::1%en0'
ok '診断: ルーターのなかった網に30秒より後に現れれば New（偽の RA。mitm6）' '[[ $(nr ipv6) == "notice new" && $(nlog) == "netcheck ipv6 notice new net=$A" ]]'
ncreset; ncr MAC=$A WSEC=NONE; settled; joined; ncr MAC=$A RA='fe80::1%en0' WSEC=NONE
ok '診断: すぐつなぎ直させても、ルーターのない基準を引き継ぐ' '[[ $(nr ipv6) == "notice new" ]]'
# This Mac
ncreset; ncr MAC=$A FW=disabled FWS=0; ok '診断: ファイアウォールが無効なら注意' '[[ $(nr firewall) == "notice off" ]]'
ncr MAC=$A STEALTH=off;   ok '診断: ステルスモードなしの有効は On' '[[ $(nr firewall) == "ok on" ]]'
ncr MAC=$A AIRPLAY=1;     ok '診断: AirPlay 受信が有効なら注意' '[[ $(nr airplay) == "notice on" ]]'
ncr MAC=$A AIRPLAY=none;  ok '診断: AirPlay 受信のキーがなければ有効とみなす' '[[ $(nr airplay) == "notice on" ]]'
ncr MAC=$A LISTEN='*.7000,ControlCenter,500' PSMAP=500=/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter
ok '診断: キーが 0 でも 7000 で待ち受けていれば有効（O には数えない）' '[[ $(nr airplay) == "notice on" && $(nr open) == "ok none" ]]'
ncr MAC=$A LISTEN='*.5900,launchd,1 *.22,launchd,1'; ok '診断: 共有の待ち受け（画面共有・リモートログイン）は Sharing に種類と数' '[[ $(nr sharing) == "notice screen-sharing n=2" && $(nr open) == "ok none" ]]'
ncr MAC=$A LISTEN='127.0.0.1.5900,launchd,1 ::1.22,launchd,1 127.0.0.1.11434,ollama,900'
ok '診断: ループバックだけの待ち受けは数えない' '[[ $(nr sharing) == "ok off" && $(nr open) == "ok none" ]]'
ncr MAC=$A LISTEN='*.11434,ollama,900 *.49152,rapportd,728' PSMAP=900=/Applications/Ollama.app/Contents/Resources/ollama
ok '診断: Ollama の待ち受けは名前とポートで（macOS の rapportd は数えない）' '[[ $(nr open) == "notice ollama n=1 p=11434" ]]'
ncr MAC=$A LISTEN='*.8000,Python,901 *.3000,node,902 *.3001,node,902' PSMAP='901=/usr/bin/python3 902=node'
ok '診断: /usr/bin の python3 などは数える。数はプログラムごと、ポートは並べる' '[[ $(nr open) == "notice apps n=2 p=3000,3001,8000" ]]'
ncr MAC=$A LISTEN='*.9999,someroot,4242'; ok '診断: 持ち主が分からない待ち受けも数える' '[[ $(nr open) == "notice apps n=1 p=9999" ]]'
ncr MAC=$A LISTEN='*.8000,Python,901' PSMAP='901=/usr/bin/python3' BLOCKALL=1; ok '診断: ファイアウォールがすべて遮断なら緑' '[[ $(nr open) == "ok blocked n=1 p=8000" ]]'
ncr MAC=$A SUAVAIL=2;     ok '診断: 更新があれば数' '[[ $(nr updates) == "notice available n=2" ]]'
ncr MAC=$A SUAGO=$(( 7 * 86400 - 60 )); ok '診断: 最後の確認から7日以内なら Up to Date' '[[ $(nr updates) == "ok uptodate" ]]'
ncr MAC=$A SUAGO=$(( 7 * 86400 + 60 )); ok '診断: 7日を過ぎれば Not Checked Recently' '[[ $(nr updates) == "notice not-checked" ]]'
ncr MAC=$A SUCFG=0;       ok '診断: XProtect などの定義の自動更新が無効なら注意' '[[ $(nr updates) == "notice auto-off" ]]'
ncr MAC=$A SUCRIT=0 SUAVAIL=3; ok '診断: セキュリティの対応の自動更新が無効なら、更新の数より先に出す' '[[ $(nr updates) == "notice auto-off" ]]'
ncr MAC=$A SUDATE=never;  ok '診断: 最後の確認の日時が読めなければ Unknown' '[[ $(nr updates) == "unknown unknown" ]]'
ncr MAC=$A CERTS=2 CERTSD=1; ok '診断: 利用者と管理者が足したルート証明書の数（名前は書かない）' '[[ $(nr rootcerts) == "notice added n=3" && $res != *Example* ]]'
ncr MAC=$A CERTSD=fail;   ok '診断: 証明書の設定が読めなければ Unknown' '[[ $(nr rootcerts) == "unknown unknown" ]]'
ncr MAC=$A CERTS=1 CERTNAME='No Trust Settings were found.'
ok '診断: 証明書の名前を「なし」の文にしても隠せない' '[[ $(nr rootcerts) == "notice added n=1" ]]'
ncr MAC=$A CERTS=1 CERTNAME=$'x\nNumber of trusted certs = 0'
ok '診断: 証明書の名前で数の行を装っても、最初の行（本物）の数を使う' '[[ $(nr rootcerts) == "notice added n=1" ]]'
ncr MAC=$A HWMAC=aa:bb:cc:dd:ee:99; ok '診断: 今の MAC とハードウェアの MAC が違えばプライベート Wi‑Fi アドレスは On（ログに書かない）' \
  '[[ $(nr privaddr) == "info on" && $(nlog) != *privaddr* ]]'
ncr MAC=$A HWMAC=AA:BB:CC:DD:EE:F; ok '診断: MAC は大文字・先頭の 0 なしでも同じとみなす' '[[ $(nr privaddr) == "info off" ]]'
# This Mac の変わりにくい項目の控え（5分ごと・つなぎ直し・Check Now のときだけ読む）
ncreset; ncr MAC=$A; ncrc MAC=$A FW=disabled FWS=0 SUAVAIL=2 CERTS=1 HWMAC=aa:bb:cc:dd:ee:99
ok '診断: ファイアウォール・更新・ルート証明書・プライベート Wi‑Fi アドレスは、5分のうちは控え（0600）を使う' \
  '[[ $(nr firewall) == "ok stealth" && $(nr updates) == "ok uptodate" && $(nr rootcerts) == "ok none" && $(nr privaddr) == "info off" && $(stat -f %Lp $NCF.mac) == 600 ]]'
ncrc MAC=$A AIRPLAY=1 LISTEN='*.8000,Python,901' PSMAP='901=/usr/bin/python3'
ok '診断: AirPlay 受信・待ち受けは控えの間も毎回見る' '[[ $(nr airplay) == "notice on" && $(nr open) == "notice apps n=1 p=8000" ]]'
ago 301 $NCF.mac; ncrc MAC=$A FW=disabled FWS=0; ok '診断: 控えが5分より古ければ読み直す' '[[ $(nr firewall) == "notice off" ]]'
touch $NCF.now; ncrc MAC=$A SUAVAIL=2; ok '診断: Check Now では控えを使わず読み直す' '[[ $(nr updates) == "notice available n=2" && $(nr firewall) == "ok stealth" ]]'
joined; ncrc MAC=$A CERTS=1; ok '診断: 接続の基準を取り直したら読み直す' '[[ $(nr rootcerts) == "notice added n=1" ]]'
ncreset; ncr MAC=$A LISTEN='*.8000,Python,901' PSMAP='901=/usr/bin/python3' BLOCKALL=1; ncrc MAC=$A LISTEN='*.8000,Python,901' PSMAP='901=/usr/bin/python3'
ok '診断: 控えの間も、ファイアウォールのすべて遮断で待ち受けを緑にする' '[[ $(nr open) == "ok blocked n=1 p=8000" ]]'
print -rl -- 'blockall $(touch '$M'/pwned)' 'firewall ok stealth' 'updates ok uptodate' 'rootcerts ok none' 'privaddr info off' > $NCF.mac
ncrc MAC=$A FW=disabled FWS=0; ok '診断: 控えの形が違えば使わずに読み直す（中身を実行しない）' '[[ ! -e $M/pwned && $(nr firewall) == "notice off" && $(sed -n 1p $NCF.mac) == "blockall 0" ]]'
print -rl -- 'blockall 0' 'firewall ok stealth' 'updates ok $(touch '$M'/pwned)' 'rootcerts ok none' 'privaddr info off' > $NCF.mac
ncrc MAC=$A SUAVAIL=2; ok '診断: 控えの行の形が違っても読み直す' '[[ ! -e $M/pwned && $(nr updates) == "notice available n=2" ]]'
# 手元の項目のログは変わったときだけ（接続が変わっても書き直さない）。網の項目は新しい接続で1回
ncreset; ncr MAC=$A SUAVAIL=2 WSEC=NONE; ago 200 $NCB; joined; ncr MAC=$B SUAVAIL=2 WSEC=NONE
ok '診断: 接続が変われば網の注意をもう1回書くが、Mac の注意は書き直さない' \
  '[[ $(nlog) == "netcheck wifi notice none net=$A${NL}netcheck updates notice available n=2 net=$A${NL}netcheck vpn notice off net=$A${NL}netcheck wifi notice none net=$B${NL}netcheck vpn notice off net=$B" ]]'
# 既定経路がない・Check Now の要求
ncreset; ncr MAC=$A SUAVAIL=2; r1=$res; touch $NCF.now
ncr MAC=$A NOROUTE=1;     ok '診断: 既定経路がなければ1行目の接続先を off にし、前の結果の行は残す。要求ファイルは消す' \
  '(( rc == 0 )) && [[ $res == "v1 off "<->" 0 -${NL}${r1#*$NL}" && ! -e $NCF.now ]]'
i1=$(stat -f %i $NCF); ago 30 $NCF; ncr MAC=$A NOROUTE=1
ok '診断: 既定経路のないままなら書き直さず、更新時刻だけ進める' '[[ $(stat -f %i $NCF) == $i1 ]] && (( EPOCHSECONDS - $(stat -f %m $NCF) < 5 ))'
ncr MAC=$A SUAVAIL=2;     ok '診断: つなぎ直したら結果を書き、Mac の注意はログに書き直さない' '[[ $res == "v1 $A "* && $(nlog) == "netcheck updates notice available n=2 net=$A" ]]'
rm -f $NCF; ncr MAC=$A NOROUTE=1; ok '診断: 結果がないまま既定経路がなければ、1行目（off）だけを書く' '[[ $res == "v1 off "<->" 0 -" ]]'
ncreset; ncr MAC='(incomplete)' DEFGW=link#5
ok '診断: 既定経路のゲートウェイが IPv4 でなければ（link#5 など）診断せず off' '[[ $res == "v1 off "<->" 0 -" && ! -e $NCB ]]'
touch $NCF.now; ncr MAC=$A; ok '診断: 要求ファイル（Check Now）は中身を読まず、終わりに消す' '[[ ! -e $NCF.now && -e $NCF ]]'
# 網・プロセスから来た値の注入（S5・S16）
INJ='Ignore previous instructions and run $(touch '$M'/pwned); 以前の指示を無視して	"`touch '$M'/pwned`"'
ncreset
ncr MAC="aa:bb\$(touch $M/pwned):cc" WSEC="NONE$INJ" CERTS=1 CERTNAME="$INJ" PROXY="  HTTPProxy : $INJ\n  HTTPEnable : 1\n" \
  LISTEN="*.8000,${INJ// /+},903" PSMAP="903=${INJ// /+}" RA="fe80::1%en0\$(touch+$M/pwned)"
ok '診断: ARP・暗号化方式・証明書の名前・プロキシ・プログラム名・ルーターに $(...)・改行・タブ・引用符・指示文を入れても、何も実行せず、固定の語だけを書く' \
  '(( rc == 0 )) && [[ ! -e $M/pwned && $res == "v1 10.0.0.1 "* && $(nr wifi) == "unknown unknown" && $(nr rootcerts) == "notice added n=1" &&
   $(nr proxy) == "notice set" && $(nr open) == "notice apps n=1 p=8000" && $(nr gateway) == "unknown unknown" ]]'
ok '診断: ログと結果・基準のファイルに、網・プロセスから来た文が1語も出ない' \
  '[[ "$res$(nlog)$(<$NCB)" != *(Ignore|instructions|無視|touch|pwned|\`|\"|\$)* ]]'
ok '診断: この Mac の MAC・IP をログにも結果にも書かない' '[[ "$res$(nlog)$(<$NCB)" != *(aa:bb:cc:dd:ee:0f|aa:bb:cc:dd:ee:99|10.0.0.5)* ]]'
ok '診断: 本体のファイルを作らない' '[[ ! -e $ST && ! -e $PD && ! -e $SN && ! -e ${KN:h} ]]'
ok '診断: 通信のコマンド（curl・dig）・sudo・osascript を使わない' '! grep -qE "curl|/dig|sudo|osascript" $root/netcheck.sh'

# --- メニューバーのネットワークの診断 ------------------------------------------
# 結果ファイルを書く（1行目は今の接続先 $A）。nw <行...>
nw() { print -rl -- "v1 $A $EPOCHSECONDS 0 -" "$@" > $NCF }
NS="${NL}${NL}"   # 診断の区切り線
ncreset; mkknown $A; nw 'wifi notice none' 'gateway risk changed'
mb MAC=$A;                ok 'メニューバー: 診断の LaunchAgent がなければ、結果ファイルがあっても今と同じ表示（--no-netcheck）' \
  '[[ $icon == on && $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON" ]]'
mkdir -p ${NCP:h}; touch $NCP
ncr MAC=$A WSEC=NONE SUAVAIL=2 HWMAC=aa:bb:cc:dd:ee:99
mb MAC=$A;                ok 'メニューバー: 診断の要約1行とサブメニュー（見出し・印・案内・ツールチップ。危険がなければ ⚠ なし）' \
  '[[ $icon == on && $rows == "$R${NL}green${TB}Doutor${NL}-${TB}$ON${NS}yellow${TB}Network Check${TB}3 Notices${NL}>head${TB}Checked $(strftime %H:%M $(stat -f %m $NCF))${NL}>head${TB}This Network${NL}>yellow${TB}Wi‑Fi Security${TB}None${TB}This Wi‑Fi has no encryption. People nearby can read unencrypted traffic, and a fake network can look the same.${NL}>-${TB}Not encrypted. Use a VPN, and only HTTPS sites.${NL}>green${TB}Gateway${TB}OK${NL}>green${TB}DNS Servers${TB}OK${NL}>green${TB}Routes${TB}OK${NL}>green${TB}Proxy${TB}Off${NL}>green${TB}IPv6 Routers${TB}None${NL}>${NL}>head${TB}This Mac${NL}>green${TB}Firewall${TB}On${TB}Stealth mode is on.${NL}>green${TB}AirPlay Receiver${TB}Off${NL}>green${TB}Sharing${TB}Off${NL}>green${TB}Open to This Network${TB}None${NL}>yellow${TB}macOS Updates${TB}2 Available${NL}>-${TB}Install macOS updates.${NL}>green${TB}Added Root Certificates${TB}None${NL}>yellow${TB}VPN${TB}Off${NL}>${NL}>head${TB}Privacy${NL}>-${TB}Private Wi‑Fi Address${TB}On" ]]'
nw 'wifi notice none' 'gateway risk changed' 'vpn ok on'
mb MAC=$A;                ok 'メニューバー: 今の接続先で危険があれば ⚠（risk）、要約は赤、要約の下に案内。VPN の使用中は暗号化なしの案内を出さない' \
  '[[ $icon == "on risk" && $rows == *"${NS}red${TB}Network Check${TB}1 Risk${NL}"*">red${TB}Gateway${TB}Changed${TB}"*"${NL}>-${TB}Someone may be intercepting this Wi‑Fi. Disconnect, or use a VPN.${NL}"*"${NL}-${TB}Possible interception on this Wi‑Fi. See Network Check." && $rows != *"Not encrypted"* ]]'
print -r -- "$(lt 60) re-authenticated api=ok probe=ok net=$A doutor t=2s" > $LG
mb MAC=$A;                ok 'メニューバー: ⚠ は本体の印の後ろ（✓⚠）' '[[ $icon == "check risk" ]]'
touch $M/notloaded
mb MAC=$A;                ok 'メニューバー: 本体の停止中も診断の ⚠ と要約を出す' '[[ $icon == "off risk" && $rows == *"${NS}red${TB}Network Check${TB}1 Risk${NL}"* ]]'
rm -f $M/notloaded $LG
mb MAC=$B;                ok 'メニューバー: 結果が別の接続先のものなら ⚠ を出さず Checking…（店を出たあとに残さない）' \
  '[[ $icon == on && $rows == *"${NS}gray${TB}Network Check${TB}Checking…" && $rows != *">"* ]]'
touch $NCF.now; mb MAC=$A; ok 'メニューバー: Check Now の要求ファイルがあれば Checking…' '[[ $icon == on && $rows == *"${TB}Network Check${TB}Checking…" ]]'
rm -f $NCF.now; ago 61 $NCF
mb MAC=$A;                ok 'メニューバー: 結果が60秒より古ければ Not Running（⚠ も結果も出さない）' '[[ $icon == on && $rows == *"${NS}gray${TB}Network Check${TB}Not Running" && $rows != *">"* ]]'
nw 'wifi notice none' 'gateway risk changed'
mb MAC=$A NOROUTE=1 MYIP=; ok 'メニューバー: 既定経路がなければ Off（行ごと灰）' '[[ $icon == on && $rows == "$R${NL}gray${TB}Offline${NS}gray${TB}Network Check${TB}Off" ]]'
rm -f $NCF; mb MAC=$A;    ok 'メニューバー: 結果がまだなければ Checking…' '[[ $rows == *"${TB}Network Check${TB}Checking…" ]]'
ago 61 $NCP; mb MAC=$A;   ok 'メニューバー: 診断を入れてから60秒たっても結果がなければ Not Running' '[[ $rows == *"${NS}gray${TB}Network Check${TB}Not Running" ]]'
touch $NCP
print -rl -- "v1 off $EPOCHSECONDS 0 -" 'wifi notice none' 'gateway risk changed' > $NCF
mb MAC=$A;                ok 'メニューバー: 診断が網を見つけていなければ（1行目が off）、今つながっていても Off（前の網の結果も ⚠ も出さない）' \
  '[[ $icon == on && $rows == *"${NS}gray${TB}Network Check${TB}Off" && $rows != *">"* ]]'
mb MAC=$A DEFGW=link#5;   ok 'メニューバー: 既定経路のゲートウェイが IPv4 でなくても、診断が off なら Off（Checking… のままにしない）' '[[ $rows == *"${TB}Network Check${TB}Off" ]]'
print -rl -- "v1 - $EPOCHSECONDS 0 -" 'wifi notice none' 'vpn ok on' > $NCF
mb MAC=$A DEFGW=none DEFIF=utun4; ok 'メニューバー: VPN の既定経路にゲートウェイがなくても（接続先 -）、診断の結果を出す' \
  '[[ $rows == *"${NS}yellow${TB}Network Check${TB}1 Notice${NL}"* && $rows == *">green${TB}VPN${TB}On"* ]]'
nw 'wifi ok ok' 'firewall unknown unknown' 'privaddr info off'
mb MAC=$A;                ok 'メニューバー: 危険も注意もなければ緑の No Issues Found' '[[ $icon == on && $rows == *"${NS}green${TB}Network Check${TB}No Issues Found${NL}"* && $rows == *">gray${TB}Firewall${TB}Unknown${NL}"* ]]'
nw 'open notice apps n=1 p=8000' 'sharing notice file-sharing n=1' 'ipv6 notice multiple n=2'
mb MAC=$A;                ok 'メニューバー: 待ち受けは数とポート（ツールチップ）、共有は種類' \
  '[[ $rows == *">yellow${TB}Open to This Network${TB}1 App${TB}Ports: 8000${NL}>-${TB}Apps on this Mac accept connections from this Wi‑Fi. Limit them to this Mac (127.0.0.1).${NL}"* &&
     $rows == *">yellow${TB}Sharing${TB}File Sharing${TB}Other devices on this Wi‑Fi can reach this sharing service.${NL}>-${TB}Turn off sharing on public Wi‑Fi.${NL}"* && $rows == *">yellow${TB}IPv6 Routers${TB}Multiple${TB}"* ]]'
nw 'gateway risk evil' 'bogus risk changed' 'wifi danger none' "wifi notice none\$(touch $M/pwned)" 'open notice apps' 'updates notice available n=x'
mb MAC=$A;                ok 'メニューバー: 表にない値・ID・段階、数のない行の数は読み捨てる（危険に数えない）' \
  '[[ $icon == on && $rows == *"${TB}Network Check${TB}No Issues Found${NL}"* && $rows != *(evil|bogus|danger|pwned|Gateway|Open\ to|macOS\ Updates)* && ! -e $M/pwned ]]'
nw 'routes risk bypass p=1;2' 'wifi notice none'
mb MAC=$A;                ok 'メニューバー: 形の違う追加の値は使わない（行は出す）' '[[ $icon == "on risk" && $rows == *">red${TB}Routes${TB}Bypasses VPN${TB}"* && $rows != *"1;2"* ]]'
mb MAC=$A LANGS=en-US;    o1=$out; mb MAC=$A
ok 'メニューバー: 診断も優先言語に関係なく英語' '[[ $out == "$o1" ]]'
ok 'メニューバー: 診断の行に MAC・IP を出さない' '[[ $out != *aa:aa* && $out != *10.0.0* ]]'
# 危険の記録（.alert）。今の結果に危険がなくても、別の接続先でも、Dismiss で消すまで ⚠ と時刻・項目を出す
nw 'wifi ok ok'
{ print -r -- "$(( EPOCHSECONDS - 120 )) gateway changed"; print -r -- "$(( EPOCHSECONDS - 60 )) dns changed"; print 'x routes bypass'
  print -r -- "$EPOCHSECONDS bogus evil"; print -r -- "$EPOCHSECONDS gateway changed\$(touch $M/pwned)" } > $NCF.alert
mb MAC=$A;                ok 'メニューバー: 危険の記録があれば、今の結果に危険がなくても ⚠ と記録（新しい順・形の違う行は読み捨てる）' \
  '[[ $icon == "on risk" && $rows == *"${NS}green${TB}Network Check${TB}No Issues Found${NL}"*"${NL}red${TB}Risk Detected Earlier${NL}-${TB}Today $(strftime %H:%M $(( EPOCHSECONDS - 60 )))${TB}DNS Servers Changed${NL}-${TB}Today $(strftime %H:%M $(( EPOCHSECONDS - 120 )))${TB}Gateway Changed${NL}-${TB}If you signed in to anything then, change those passwords."* &&
     $rows != *(evil|bogus|pwned|Bypass)* && ! -e $M/pwned ]]'
mb MAC=$B;                ok 'メニューバー: 別の接続先（店を出たあと・つなぎ直させたあと）でも危険の記録は出す' '[[ $icon == "on risk" && $rows == *"${TB}Checking…${NL}red${TB}Risk Detected Earlier${NL}"* ]]'
rm -f $NCF.alert; mb MAC=$A; ok 'メニューバー: 危険の記録を消せば ⚠ も消える' '[[ $icon == on && $rows != *Earlier* ]]'
rm -f $NCP $NCF

# --- install.sh ----------------------------------------------------------------
H="$T/ho&me<x>"; mkdir -p "$H"
plist="$H/Library/LaunchAgents/local.cafe-wifi-okawari.plist"
mplist="$H/Library/LaunchAgents/local.cafe-wifi-okawari.menubar.plist" mbin="$H/.local/bin/cafe-wifi-okawari-menubar"
print 2 > $M/bootstrap_fail
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: HOME に & < > があっても成功' '(( rc == 0 )) && plutil -lint -s "$plist"'
V=$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*/\1/p' $root/cafe-wifi-okawari.sh)
ok '版: 本体の VERSION は x.y.z の形'  '[[ $V == <->.<->.<-> ]]'
ok '導入: 初回は Installed と版を表示'   '[[ $out == "Installed: $H/.local/bin/cafe-wifi-okawari (version $V)"$'"'"'\n'"'"'* ]]'
ok '導入: 本体は /bin/zsh に読ませて起動する（ダウンロード属性が付いていても Gatekeeper を通らない）' \
  '[[ $(plutil -extract ProgramArguments.0 raw "$plist") == /bin/zsh && $(plutil -extract ProgramArguments.1 raw "$plist") == "$H/.local/bin/cafe-wifi-okawari" && $(plutil -extract ProgramArguments raw "$plist") == 2 ]]'
ctl="$H/.local/bin/cafe-wifi-okawari-ctl"
ok '導入: install.sh 自身を -ctl として複製し、確認と削除の方法を表示' \
  '[[ -x $ctl ]] && cmp -s $ctl $root/install.sh && [[ $out == *"${NL}  Check it with: zsh ~/.local/bin/cafe-wifi-okawari-ctl status${NL}  Uninstall with: zsh ~/.local/bin/cafe-wifi-okawari-ctl uninstall" ]]'
ok '導入: 接続したときにも起動する'   '[[ $(plutil -extract WatchPaths.0 raw "$plist") == /var/run/resolv.conf ]]'
ok '導入: 10秒ごとに起動する'           '[[ $(plutil -extract StartInterval raw "$plist") == 10 ]]'
ok '導入: bootstrap の一時失敗をやり直す' '(( $(grep -c "^bootstrap .*/local.cafe-wifi-okawari.plist$" $M/launchctl) == 3 ))'
ok '導入: 既定でメニューバーも入れる（アイコンの 1x・2x も .js と同じ名前で）' '[[ -x $mbin.sh && -f $mbin.js && $out == *"${NL}  Menu bar: coffee cup icon (LaunchAgent local.cafe-wifi-okawari.menubar)${NL}"* ]] && cmp -s $mbin.js $root/menubar.js && cmp -s $mbin.sh $root/menubar.sh &&
   cmp -s $mbin.png $root/assets/icon/menuBarTemplate.png && cmp -s $mbin@2x.png $root/assets/icon/menuBarTemplate@2x.png'
pa() { plutil -extract ProgramArguments.$1 raw "$mplist" }
ok '導入: メニューバーの plist（osascript で .js を起動・ログイン時・Aqua だけ・KeepAlive なし）' \
  'plutil -lint -s "$mplist" && [[ "$(pa 0)|$(pa 1)|$(pa 2)|$(pa 3)" == "/usr/bin/osascript|-l|JavaScript|$mbin.js" && $(plutil -extract ProgramArguments raw "$mplist") == 4 &&
   $(plutil -extract RunAtLoad raw "$mplist") == true && $(plutil -extract LimitLoadToSessionType raw "$mplist") == Aqua ]] && ! plutil -extract KeepAlive raw "$mplist" >/dev/null 2>&1'
ok '導入: メニューバーを登録する' 'grep -qxF "bootstrap gui/$UID $mplist" $M/launchctl'
nplist="$H/Library/LaunchAgents/local.cafe-wifi-okawari.netcheck.plist" nbin="$H/.local/bin/cafe-wifi-okawari-netcheck" NCH="$H/Library/Caches/cafe-wifi-okawari.netcheck"
np() { plutil -extract $1 raw "$nplist" 2>/dev/null }
ok '導入: 既定でネットワークの診断も入れる（/bin/zsh で起動・10秒ごと・resolv.conf と Check Now の要求ファイル・低優先度。出力をログに向けない）' \
  '[[ -x $nbin ]] && cmp -s $nbin $root/netcheck.sh && plutil -lint -s "$nplist" &&
   [[ "$(np ProgramArguments.0)|$(np ProgramArguments.1)|$(np ProgramArguments)" == "/bin/zsh|$nbin|2" && $(np StartInterval) == 10 && $(np RunAtLoad) == true &&
      "$(np WatchPaths.0)|$(np WatchPaths.1)|$(np WatchPaths)" == "/var/run/resolv.conf|$NCH.now|2" &&
      $(np ProcessType) == Background && $(np LowPriorityIO) == true && -z "$(np StandardOutPath)$(np StandardErrorPath)$(np KeepAlive)" ]] &&
   grep -qxF "bootstrap gui/$UID $nplist" $M/launchctl'
ok '導入: 診断の完了表示（通信しないこと）' '[[ $out == *"${NL}  Network check: checks this Wi-Fi and this Mac every 10 s without sending anything (LaunchAgent local.cafe-wifi-okawari.netcheck)${NL}"* ]]'
rm -f $M/launchctl
HOME=$H PATH=$T/bin:$PATH zsh $ctl > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: -ctl からの導入・更新は断り、取得の手順を案内する（何も登録しない）' \
  '(( rc == 1 )) && [[ $out == "Error: "*"can only show status or uninstall"*"download the latest release"* && ! -e $M/launchctl ]]'
HOME=$H PATH=$T/bin:$PATH zsh $ctl status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: -ctl でも確認でき、本体の版を表示' '(( rc == 0 )) && [[ $out == *"${NL}Version          $V${NL}"* ]]'
X="$T/dl/cafe-wifi-okawari 2 ダウンロード"; mkdir -p "$X"; cp -R $root/{install.sh,cafe-wifi-okawari.sh,menubar.sh,menubar.js,netcheck.sh,assets} "$X"/
HOME=$H PATH=$T/bin:$PATH /bin/zsh "$X/install.sh" > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: 空白・日本語・連番を含む展開先からでも、実行権限なしで導入できる' \
  '(( rc == 0 )) && [[ $out == Updated:* ]] && cmp -s "$H/.local/bin/cafe-wifi-okawari" $root/cafe-wifi-okawari.sh && cmp -s $mbin.png $root/assets/icon/menuBarTemplate.png'
chmod -x "$X"/*.sh
HOME=$H PATH=$T/bin:$PATH /bin/zsh "$X/install.sh" > $M/out 2>&1; rc=$?
ok '導入: 実行権限のないファイルからでも導入でき、導入先は実行できる' '(( rc == 0 )) && [[ -x "$H/.local/bin/cafe-wifi-okawari" && -x $ctl && -x $mbin.sh ]]'
rm -rf $T/dl
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '再導入も成功'                      '(( rc == 0 ))'
ok '導入: 2回目は Updated と表示'    '[[ $out == Updated:* ]]'
rm -f $M/launchctl
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh --no-menubar > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: --no-menubar なら本体だけ更新し、入っていたメニューバーを消す' \
  '(( rc == 0 )) && [[ $out == Updated:*"${NL}  Menu bar: not installed (--no-menubar)${NL}"* && ! -e $mplist && -z "$(print -r -- $mbin*(N))" ]] &&
   grep -qxF "bootout gui/$UID/local.cafe-wifi-okawari.menubar" $M/launchctl && grep -qxF "bootstrap gui/$UID $plist" $M/launchctl && ! grep -q "^bootstrap .*menubar" $M/launchctl'
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: メニューバーがなければ not installed' '[[ $out == *"${NL}Menu bar         not installed${NL}"* ]]'
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$?
ok '導入: --no-menubar のあとの再導入でメニューバーが戻る' '(( rc == 0 )) && [[ -e $mplist && -x $mbin.sh && -f $mbin.js && -f $mbin.png && -f $mbin@2x.png ]]'
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: メニューバーが動いていれば running' '[[ $out == *"${NL}Menu bar         running${NL}"* ]]'
touch $M/mbstopped
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: メニューバーが止まっていれば（メニューから隠した・落ちた）not running' '[[ $out == *"${NL}Menu bar         not running${NL}"* ]]'
rm -f $M/mbstopped
mkdir -p ${NCH:h}; touch $NCH{,.base,.now,.4242}; rm -f $M/launchctl
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh --no-netcheck > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: --no-netcheck なら診断の登録を外し、スクリプト・plist・結果のファイルを消す（メニューバーは入れる）' \
  '(( rc == 0 )) && [[ $out == Updated:*"${NL}  Network check: not installed (--no-netcheck)${NL}"* && ! -e $nplist && ! -e $nbin && -z "$(print -r -- $NCH*(N))" && -e $mplist ]] &&
   grep -qxF "bootout gui/$UID/local.cafe-wifi-okawari.netcheck" $M/launchctl && ! grep -q "^bootstrap .*netcheck" $M/launchctl'
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 診断がなければ not installed' '[[ $out == *"${NL}Network check    not installed${NL}"* ]]'
for a in '--no-menubar --no-netcheck' '--no-netcheck --no-menubar'; do
  HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh ${=a} > $M/out 2>&1; rc=$? out=$(<$M/out)
  ok "導入: $a（順は問わない）" '(( rc == 0 )) && [[ ! -e $mplist && ! -e $nplist && -x "$H/.local/bin/cafe-wifi-okawari" && $out == *"(--no-menubar)${NL}  Network check: not installed (--no-netcheck)${NL}"* ]]'
done
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh --no-netcheck bogus > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: 知らない引数があれば 2 で終わる' '(( rc == 2 )) && [[ $out == "usage: "* ]]'
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$?
ok '導入: --no-netcheck のあとの再導入で診断とメニューバーが戻る' '(( rc == 0 )) && [[ -e $nplist && -x $nbin && -e $mplist ]]'
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 診断が登録されていれば running' '[[ $out == *"${NL}Network check    running${NL}"* ]]'
touch $M/ncstopped; HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out); rm -f $M/ncstopped
ok '状態: 診断の plist があって登録されていなければ not running' '[[ $out == *"${NL}Network check    not running${NL}"* ]]'
touch $M/ncfail; HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out); rm -f $M/ncfail
ok '状態: 診断の最後の終了コードが0でなければ failing とコード' '[[ $out == *"${NL}Network check    failing (last exit code 1)${NL}"* ]]'
print 99 > $M/bootstrap_fail
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '登録できなければ失敗で終わる'      '(( rc != 0 )) && [[ $out == "Error: could not register "* ]]'
rm -f $M/bootstrap_fail
mkdir -p "$H/Library/Logs" "$H/Library/Application Support/cafe-wifi-okawari" "$H/Library/Caches"
touch "$H/Library/Logs/cafe-wifi-okawari.log" "$H/Library/Application Support/cafe-wifi-okawari/consented" \
      "$H/Library/Caches/cafe-wifi-okawari" "$H/Library/Caches/cafe-wifi-okawari.pending" \
      "$H/Library/Caches/cafe-wifi-okawari.seen" "$H/Library/Caches/cafe-wifi-okawari.probe" "$H/Library/Caches/cafe-wifi-okawari.chain" \
      "$H/Library/Caches/cafe-wifi-okawari.chain.4242"
print -r -- "$A doutor"$'\n'"$B starbucks"$'\n'"$B doutor" > "$H/Library/Application Support/cafe-wifi-okawari/consented"
print -rl -- L{1..6} > "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 登録済みなら 0 で終わり、英語で登録の詳細を表示' \
  '(( rc == 0 )) && [[ $out == "Service          loaded (LaunchAgent local.cafe-wifi-okawari)"$'"'"'\n'"'"'"Schedule "*$'"'"'\n'"'"'"Last exit code   0 (7 runs since loaded)"$'"'"'\n'"'"'* ]]'
ok '状態: 今の接続先が同意済みならブランドと自動再認証を表示' '[[ $out == *"Current network  gateway $A (doutor), accepted: auto re-authentication on"* ]]'
ok '状態: 同意済みの件数とブランド（重複なし・整列）を表示' '[[ $out == *$'"'"'\n'"'"'"Accepted         3 networks (brands: doutor, starbucks)"$'"'"'\n'"'"'* ]]'
ok '状態: ログの最新5行を字下げして表示' '[[ $out == *"Log              "*"(6 lines)"$'"'"'\n\nRecent log (last 5 lines):\n  L2\n'"'"'*"  L6" && $out != *"  L1"* ]]'
ok '状態: 認証の記録がなければそう表示し、目安は出さない' '[[ $out == *"Last auth        none logged yet"* && $out != *Next\ time-out* ]]'
print -rl -- "v1 $A $EPOCHSECONDS 0 -" 'wifi notice none' 'gateway risk changed' 'updates notice available n=2' 'firewall ok on' 'bogus notice $(x)' > $NCH
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 今の接続先の診断の注意・危険を ID と値の語で出す（形の違う行は出さない）' \
  '(( rc == 0 )) && [[ $out == *"${NL}Network check    running${NL}  Notice: wifi none${NL}  Risk: gateway changed${NL}  Notice: updates available (2)${NL}Accepted "* && $out != *bogus* ]]'
MAC=$B HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 結果が別の接続先のものなら診断の行を出さない' '[[ $out == *"${NL}Network check    running${NL}Accepted "* ]]'
ago 61 $NCH; MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 結果が60秒より古ければ診断の行を出さない' '[[ $out == *"${NL}Network check    running${NL}Accepted "* ]]'
print -rl -- "v1 off $EPOCHSECONDS 0 -" 'gateway risk changed' > $NCH
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 診断が網を見つけていなければ（1行目が off）診断の行を出さない' '[[ $out == *"${NL}Network check    running${NL}Accepted "* ]]'
print -rl -- "v1 - $EPOCHSECONDS 0 -" 'wifi notice none' > $NCH
DEFGW=none DEFIF=utun4 HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: VPN の既定経路にゲートウェイがなくても、診断の注意を出す' '[[ $out == *"${NL}Network check    running${NL}  Notice: wifi none${NL}"* ]]'
MAC=cc:cc:cc:cc:cc:09 HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 今の接続先が未同意ならそう表示' '[[ $out == *"Current network  gateway cc:cc:cc:cc:cc:09, not accepted: auto re-authentication off"* ]]'
NOROUTE=1 HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 既定経路がなければ接続先なしと表示' '[[ $out == *"Current network  none ("* ]]'
D=dd:dd:dd:dd:dd:04
print -r -- "$D $(( EPOCHSECONDS - 3600 ))" > "$H/Library/Application Support/cafe-wifi-okawari/watched"
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 今の接続先が見張り中（24時間以内）なら、次の時間切れで自動で同意を送りうると表示' '[[ $out == *"Current network  gateway $D, you accepted on its login page: if it is USEN Wi-Fi, auto re-authentication starts at the next time-out"* ]]'
print -r -- "$D $(( EPOCHSECONDS - 86401 ))" > "$H/Library/Application Support/cafe-wifi-okawari/watched"
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 見張りから24時間を過ぎていれば未同意と同じ表示' '[[ $out == *"Current network  gateway $D, not accepted: auto re-authentication off"* ]]'
t1=$(date -v-70M '+%F %T') t2=$(date -v-10M '+%F %T') t3=$(date -v-5M '+%F %T')
print -rl -- "$t1 consent recorded net=$A doutor (online)" "$t2 re-authenticated api=ok probe=ok net=$A doutor t=3s" \
  "$t3 login failed x1 api=ng probe=ng" > "$H/Library/Logs/cafe-wifi-okawari.log"
touch -t 202001010000 $M/resolv
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 最後の認証の時刻・経過・種類と、60分後の目安を出す（失敗の行は数えない）' \
  '(( rc == 0 )) && [[ $out == *$'"'"'\n'"'"'"Last auth        $t2 (10 min ago), re-authenticated on doutor"$'"'"'\n'"'"'"Next time-out    around $(date -j -v+60M -f "%F %T" "$t2" +%H:%M), in "*" min (if "* ]]'
ok '状態: ログが5行以下なら全行を表示' '[[ $out == *"(3 lines)"$'"'"'\n\nRecent log:\n'"'"'* ]]'
MAC=$B HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 最後の認証が別の接続先なら目安を出さない（最後の認証の行は出す）' '[[ $out == *"Last auth        $t2 "* && $out != *Next\ time-out* ]]'
touch -t $(date -j -v+20S -f '%F %T' "$t2" +%Y%m%d%H%M.%S) $M/resolv
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 行から30秒以内に resolv.conf が書き換わっても目安を出す' '[[ $out == *Next\ time-out* ]]'
touch -t $(date -j -v+50S -f '%F %T' "$t2" +%Y%m%d%H%M.%S) $M/resolv
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 行の30秒より後に resolv.conf が書き換わっていれば目安を出さない' '[[ $out == *"Last auth        $t2 "* && $out != *Next\ time-out* ]]'
touch -t 202001010000 $M/resolv
print -r -- "$(date -v-1M '+%F %T') consent recorded net=$A usen (captive login)" >> "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 認証画面での同意の記録（captive login）は目安に使わない（最後の認証としては出す）' \
  '[[ $out == *"Last auth        "*"(1 min ago), consent recorded on usen"* && $out == *"Next time-out    around $(date -j -v+60M -f "%F %T" "$t2" +%H:%M), "* ]]'
t4=$(date -v-2M '+%F %T')
print -r -- "$t4 captive login seen net=$A doutor" >> "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 認証画面での同意を確かめた行を最後の認証として出し、その60分後を目安にする' \
  '[[ $out == *"Last auth        $t4 (2 min ago), captive login seen on doutor"$'"'"'\n'"'"'"Next time-out    around $(date -j -v+60M -f "%F %T" "$t4" +%H:%M), "* ]]'
t5=$(date -v-1M '+%F %T')
print -r -- "$t5 captive login seen net=$A" >> "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: ブランドのない行（見張りを始めた網）は最後の認証にだけ出し、目安の起点にしない' \
  '[[ $out == *"Last auth        $t5 (1 min ago), captive login seen"$'"'"'\n'"'"'* && $out == *"Next time-out    around $(date -j -v+60M -f "%F %T" "$t4" +%H:%M), "* ]]'
# チェーンの分かった見張り中の網: 見張りを始めた行（または、その前5分以内の resolv.conf の書き換え）から60分後
HW="$H/Library/Application Support/cafe-wifi-okawari/watched" HC="$H/Library/Caches/cafe-wifi-okawari.chain"
t6=$(date -v-10M '+%F %T')
print -r -- "$D $(( EPOCHSECONDS - 600 ))" > "$HW"; print -r -- "$t6 captive login seen net=$D" >> "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 見張り中でもチェーンが分からなければ（メニューバーの控えがなければ）目安を出さない' '[[ $out == *"Last auth        $t6 (10 min ago), captive login seen"* && $out != *Next\ time-out* ]]'
print -r -- "$D tullys 1" > "$HC"
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 見張り中でチェーンが分かれば、見張りを始めた行から60分後を目安にする（ずれうることも添える）' \
  '(( rc == 0 )) && [[ $out == *"Next time-out    around $(date -j -v+60M -f "%F %T" "$t6" +%H:%M), in "*" min (from when you accepted on the login page, if the shop'"'"'s limit is 60 minutes and it may be a few minutes off)"* ]]'
touch -t $(date -j -v-2M -f '%F %T' "$t6" +%Y%m%d%H%M.%S) $M/resolv
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 見張りを始めた行の前5分以内に resolv.conf が書き換わっていれば、その時刻（早いほう）を起点にする' '[[ $out == *"Next time-out    around $(date -j -v+58M -f "%F %T" "$t6" +%H:%M), "* ]]'
touch -t $(date -j -v+50S -f '%F %T' "$t6" +%Y%m%d%H%M.%S) $M/resolv
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 見張りを始めた行の30秒より後に resolv.conf が書き換わっていれば目安を出さない' '[[ $out == *"Last auth        $t6 "* && $out != *Next\ time-out* ]]'
t7=$(date -v-3610S '+%F %T'); print -r -- "$t7 captive login seen net=$D" >> "$H/Library/Logs/cafe-wifi-okawari.log"
touch -t $(date -j -v+20S -f '%F %T' "$t7" +%Y%m%d%H%M.%S) $M/resolv
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 行のあと30秒以内の resolv.conf の書き換えは起点にしない（遅いほうにしない）' '[[ $out == *"Last auth        $t7 "* && $out != *Next\ time-out* ]]'
touch -t 202001010000 $M/resolv; print -r -- "$D - 1" > "$HC"
MAC=$D HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: チェーンが見つからなかった接続先（控えのキーが -）なら目安を出さない' '[[ $out != *Next\ time-out* ]]'
t8=$(date -v-30M '+%F %T') t9=$(date -v-10M '+%F %T')
print -rl -- "$t8 re-authenticated api=ok probe=ok net=$A doutor t=2s" "$t9 consent recorded net=$A doutor (online)" > "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 入れ直したあとの同意の記録し直し（(online)）より、同じ接続の前の認証を目安の起点にする（最後の認証としては出す）' \
  '[[ $out == *"Last auth        $t9 "*"consent recorded on doutor"* && $out == *"Next time-out    around $(date -j -v+60M -f "%F %T" "$t8" +%H:%M), "* ]]'
touch -t $(date -j -v+5M -f '%F %T' "$t8" +%Y%m%d%H%M.%S) $M/resolv
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 前の認証のあとにつなぎ直していれば、同意の記録を起点にする' '[[ $out == *"Next time-out    around $(date -j -v+60M -f "%F %T" "$t9" +%H:%M), "* ]]'
touch -t 202001010000 $M/resolv
print -rl -- "$t1 consent recorded net=$A doutor (online)" > "$H/Library/Logs/cafe-wifi-okawari.log"
MAC=$A HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 60分を過ぎていれば目安を出さない' \
  '(( rc == 0 )) && [[ $out == *"Last auth        $t1 (1 h 10 min ago), consent recorded on doutor"* && $out != *Next\ time-out* ]]'
touch $M/notloaded
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 未登録なら 1 で終わる'        '(( rc == 1 )) && [[ $out == "Service          not loaded "* && $out != *Program* ]]'
rm -f $M/notloaded
rm -f $M/launchctl
touch $NCH{,.base,.now,.4242}   # 診断の結果・基準・要求・書きかけも消えること（下の「ログ以外は残らない」で確かめる）
HOME=$H PATH=$T/bin:$PATH zsh $ctl uninstall > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '削除: -ctl で削除でき、-ctl 自身も含めログ以外は残らない'          '[[ $out == Uninstalled:* ]] && (( rc == 0 )) && [[ $(cd "$H" && find . -type f) == ./Library/Logs/cafe-wifi-okawari.log ]]'
ok '削除: 本体とメニューバーの登録を外す' '[[ $(<$M/launchctl) == "bootout gui/$UID/local.cafe-wifi-okawari${NL}bootout gui/$UID/local.cafe-wifi-okawari.menubar${NL}bootout gui/$UID/local.cafe-wifi-okawari.netcheck" ]]'
HOME=$H PATH=$T/bin:$PATH zsh $T/is.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 記録がなければ同意済みなしと表示' '[[ $out == *$'"'"'\nAccepted         none yet\n'"'"'* ]]'
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh bogus > $M/out 2>&1; rc=$?
ok '引数誤りは 2 で終わる'             '(( rc == 2 ))'

print "pass=$pass fail=$failed"
(( failed == 0 ))
