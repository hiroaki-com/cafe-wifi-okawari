#!/bin/zsh
# 模擬の curl・route・arp・ipconfig・ifconfig・defaults・osascript・launchctl で分岐を確かめる。実際の網には一切つながない。
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
cat > $T/bin/curl <<'EOS'
#!/bin/zsh
url=${@[-1]} jar= bjar= data=
for ((i = 1; i <= $#; i++)); do
  [[ ${@[i]} == -c ]] && jar=${@[i+1]}
  [[ ${@[i]} == -b ]] && bjar=${@[i+1]}
  [[ ${@[i]} == --data ]] && data=${@[i+1]}
  [[ ${@[i]} == -[He] ]] && print -r -- "${@[i+1]}" >> $M/headers
done
print -r -- "$url" >> $M/calls
W=https://service.wi2.ne.jp
land() { printf '.service.wi2.ne.jp\tFALSE\t/\tTRUE\t0\tsession_id\tabc\n' > $jar
         [[ ${SWITCH-} == pre ]] && touch $M/switched
         printf '302 %s/freewifi/%s/%s%s' $W "${BRAND-doutor}" "${2-landing.html}" "${1-}" }
case $url in
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
    printf '%s\n%s' "${LOGIN-}" "${LHTTP-200}"; if [[ ${RECOVER-} == <-> ]]; then print $RECOVER > $M/late; elif [[ -n ${RECOVER-} ]]; then touch $M/authed; fi; exit 0 ;;
esac
EOS
# route: $NOROUTE があれば既定経路なし
print '#!/bin/sh\n[ -n "$NOROUTE" ] && exit 1\necho "   route to: default"\necho "    gateway: 10.0.0.1"\necho "  interface: en0"' > $T/bin/route
# arp: 既定ゲートウェイの MAC は $MAC（$M/switched があれば別の回線 cc:cc:cc:cc:cc:03）
print '#!/bin/sh\n[ -e $M/switched ] && MAC=cc:cc:cc:cc:cc:03\necho "? ($2) at $MAC on en0 ifscope [ethernet]"' > $T/bin/arp
# ipconfig: DHCP のドメイン名は $DOM（既定は空）、自分の IP は $MYIP（既定 10.0.0.5）
print '#!/bin/sh\ncase $1 in getoption) printf "%s\\n" "$DOM" ;; getifaddr) echo "${MYIP-10.0.0.5}" ;; esac' > $T/bin/ipconfig
print '#!/bin/sh\nprintf "en0: flags=8863<UP>\\n\\tether %s\\n" "${MYMAC-aa:bb:cc:dd:ee:0f}"' > $T/bin/ifconfig
print '#!/bin/sh\nprintf "%s\\n" "$2" >> $M/notify' > $T/bin/osascript
# defaults: macOS の優先言語を $LANGS（既定は ja-JP）として返す。
print '#!/bin/sh\nprintf "(\\n    \\"%s\\",\\n    \\"en-JP\\"\\n)\\n" "${LANGS-ja-JP}"' > $T/bin/defaults
# launchctl: $M/bootstrap_fail に書いた回数だけ bootstrap を失敗させる（bootout 直後の error 5 の再現）。$M/notloaded があれば print は未登録で失敗する。
cat > $T/bin/launchctl <<'EOF'
#!/bin/zsh
print -r -- "$*" >> $M/launchctl
[[ $1 == print && -e $M/notloaded ]] && exit 113
if [[ $1 == bootstrap && -s $M/bootstrap_fail ]]; then
  n=$(<$M/bootstrap_fail); (( n > 0 )) && { print $((n - 1)) > $M/bootstrap_fail; exit 5 }
fi
exit 0
EOF
chmod +x $T/bin/*

sed -e "s#/usr/bin/curl#$T/bin/curl#" -e "s#/sbin/route#$T/bin/route#" -e "s#/usr/sbin/arp#$T/bin/arp#" \
    -e "s#/usr/bin/osascript#$T/bin/osascript#" -e "s#/usr/bin/defaults#$T/bin/defaults#" -e 's/sleep 1;/:;/' \
    -e "s#/usr/sbin/ipconfig#$T/bin/ipconfig#" -e "s#/sbin/ifconfig#$T/bin/ifconfig#" \
    -e "s#/var/run/resolv.conf#$M/resolv#" \
    $root/cafe-wifi-okawari.sh > $T/s.sh

ST=$HOME/Library/Caches/cafe-wifi-okawari
PD=$ST.pending
SN=$ST.seen
DG=$ST.probe
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
mkdir -p ${ST:h}
W=https://service.wi2.ne.jp

# --- 補助 ----------------------------------------------------------------------
pass=0 failed=0
# run VAR=val...: 1回実行し、rc・out・通信回数を残す
run() {
  rm -f $M/calls $M/notify $M/headers $M/badlogin
  env "$@" zsh $T/s.sh > $M/out 2>&1; rc=$?
  out=$(<$M/out)
  posts=$(grep -c xhr/login $M/calls 2>/dev/null); redirs=$(grep -c wi2auth/redirect $M/calls 2>/dev/null)
  notes=$( [[ -e $M/notify ]] && wc -l < $M/notify | tr -d ' ' || print 0)
}
ok() {  # ok <名前> <条件式...>
  local name=$1; shift
  if eval "$*"; then (( pass++ )); else (( failed++ )); print -r -- "NG: $name  [$*]  rc=$rc posts=$posts redirs=$redirs notes=$notes out=$out"; fi
}
# 既定は「接続してから時間が経っている」状態。joined で「今つないだ」状態にする。
reset() { rm -rf $ST $PD $SN $DG ${KN:h} $M/authed $M/late $M/switched; touch -t 202001010000 $M/resolv }
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
reset; run MAC=$A NOROUTE=1; ok '既定経路がない（OS が接続画面の同意を待っている）なら何もしない' '(( rc == 0 )) && [[ ! -s $M/calls ]]'
reset; mkknown $A; logs=()
for i in {1..4}; do run MAC=$A PROBE=down; [[ -n $out ]] && logs+=("${out#* * }"); done
ok '同意済みの網で確かめられないことが続けば 1・2・4 回目だけ記録' '[[ "${(j:|:)logs}" == "probe failed x1 net=$A if=en0 curl=7 http=000|probe failed x2 net=$A if=en0 curl=7 http=000|probe failed x4 net=$A if=en0 curl=7 http=000" ]]'
touch $M/authed; run MAC=$A
ok '確かめられたら数え直す' '[[ ! -e $DG && -z $out ]]'
reset; run MAC=$A DOM=wi2.ne.jp PROBEHTTP=511
ok 'Wi2 の網で想定外の HTTP 応答なら記録（Wi2 には送らない）' '[[ $out == *"probe failed x1 net=$A if=en0 curl=0 http=511" ]] && (( redirs == 0 && posts == 0 ))'
reset; joined; run MAC=$A PROBE=down
ok '関係のない網では確かめられなくても記録しない' '[[ -z $out && ! -e $DG ]]'

# --- 接続画面での同意（macOS が同意まで網を使わせないので、同意後の状態から記録する） ---
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
run MAC=$A DOM=wi2.ne.jp BARE=timeout; ago 30 $SN; run MAC=$A DOM=wi2.ne.jp BARE=timeout; ago 59 $SN
run MAC=$A DOM=wi2.ne.jp; ok '2回目の失敗のあとは60秒空ける' '(( redirs == 0 ))'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BRAND='x y'
                          ok 'ブランド名が不正なら記録しない' '[[ ! -e "$KN" ]]'
# 確かめるのは接続ごと（resolv.conf が確認の記録より新しければ、つなぎ直した）
reconnect() { touch -t 202001010001 $SN; joined }
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

# --- install.sh ----------------------------------------------------------------
H="$T/ho&me<x>"; mkdir -p "$H"
plist="$H/Library/LaunchAgents/local.cafe-wifi-okawari.plist"
print 2 > $M/bootstrap_fail
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: HOME に & < > があっても成功' '(( rc == 0 )) && plutil -lint -s "$plist"'
ok '導入: 日本語環境では日本語で表示'  '[[ $out == 導入しました:* ]]'
ok '導入: plist のパスが正しい'        '[[ $(plutil -extract ProgramArguments.0 raw "$plist") == "$H/.local/bin/cafe-wifi-okawari" ]]'
ok '導入: 接続したときにも起動する'   '[[ $(plutil -extract WatchPaths.0 raw "$plist") == /var/run/resolv.conf ]]'
ok '導入: 10秒ごとに起動する'           '[[ $(plutil -extract StartInterval raw "$plist") == 10 ]]'
ok '導入: bootstrap の一時失敗をやり直す' '(( $(grep -c ^bootstrap $M/launchctl) == 3 ))'
LANGS=en-US HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '再導入も成功'                      '(( rc == 0 ))'
ok '導入: 英語環境では英語で表示'      '[[ $out == Installed:* ]]'
print 99 > $M/bootstrap_fail
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$?
ok '登録できなければ失敗で終わる'      '(( rc != 0 ))'
rm -f $M/bootstrap_fail
mkdir -p "$H/Library/Logs" "$H/Library/Application Support/cafe-wifi-okawari" "$H/Library/Caches"
touch "$H/Library/Logs/cafe-wifi-okawari.log" "$H/Library/Application Support/cafe-wifi-okawari/consented" \
      "$H/Library/Caches/cafe-wifi-okawari" "$H/Library/Caches/cafe-wifi-okawari.pending" \
      "$H/Library/Caches/cafe-wifi-okawari.seen" "$H/Library/Caches/cafe-wifi-okawari.probe"
print -r -- "$A doutor"$'\n'"$B starbucks"$'\n'"$B doutor" > "$H/Library/Application Support/cafe-wifi-okawari/consented"
print -rl -- L{1..6} > "$H/Library/Logs/cafe-wifi-okawari.log"
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 登録済みなら 0 で終わり、動作中と表示' '(( rc == 0 )) && [[ $out == 動作中（10秒ごと）:* ]]'
ok '状態: 同意済みの件数とブランドを表示' '[[ $out == *$'"'"'\n'"'"'"同意済みの接続先: 3 件（doutor starbucks）"$'"'"'\n'"'"'* ]]'
ok '状態: ログの最新5行を表示'          '[[ $out == *$'"'"'\nL2\n'"'"'*L6 && $out != *L1* ]]'
ok '状態: 認証の記録がなければ時刻を出さない' '[[ $out != *最後の認証* && $out != *目安* ]]'
t1=$(date -v-70M '+%F %T') t2=$(date -v-10M '+%F %T') t3=$(date -v-5M '+%F %T')
print -rl -- "$t1 consent recorded net=$A doutor (online)" "$t2 re-authenticated api=ok probe=ok net=$A doutor t=3s" \
  "$t3 login failed x1 api=ng probe=ng" > "$H/Library/Logs/cafe-wifi-okawari.log"
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 最後の認証の時刻と、60分後の目安を出す（失敗の行は数えない）' \
  '(( rc == 0 )) && [[ $out == *$'"'"'\n'"'"'"最後の認証: $t2"$'"'"'\n'"'"'"次の時間切れの目安: $(date -j -v+60M -f "%F %T" "$t2" +%H:%M) 頃"* ]]'
LANGS=en-US HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh status > $M/out 2>&1; out=$(<$M/out)
ok '状態: 目安（英語）'                 '[[ $out == *"Last authenticated: $t2"$'"'"'\n'"'"'"Next time-out: around $(date -j -v+60M -f "%F %T" "$t2" +%H:%M) "* ]]'
print -rl -- "$t1 consent recorded net=$A doutor (online)" > "$H/Library/Logs/cafe-wifi-okawari.log"
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 60分を過ぎていれば時刻だけ出し、目安は出さない' '(( rc == 0 )) && [[ $out == *"最後の認証: $t1"* && $out != *目安* ]]'
touch $M/notloaded
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 未登録なら 1 で終わる'        '(( rc == 1 )) && [[ $out == 登録されていません* ]]'
rm -f $M/notloaded
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh uninstall > $M/out 2>&1; rc=$?
ok '削除: ログ以外は残らない'          '(( rc == 0 )) && [[ $(cd "$H" && find . -type f) == ./Library/Logs/cafe-wifi-okawari.log ]]'
LANGS=en-US HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh status > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '状態: 記録がなければ 0 件（英語）'  '[[ $out == *$'"'"'\nAccepted networks: 0\n'"'"'* ]]'
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh bogus > $M/out 2>&1; rc=$?
ok '引数誤りは 2 で終わる'             '(( rc == 2 ))'

print "pass=$pass fail=$failed"
(( failed == 0 ))
