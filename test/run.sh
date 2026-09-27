#!/bin/zsh
# 模擬の curl・route・arp・osascript・launchctl で分岐を確かめる。実際の網には一切つながない。
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
#       引数なしの redirect（認証済みでのブランド確認）は $BARE（ok/other/timeout）。
#       login は本文 $LOGIN と HTTP コード $LHTTP（既定 200。000 ならタイムアウト）を返す。$RECOVER があれば認証済みにする
#       （数なら、その回数の確認のあとで認証済みにする）。-H・-e の値は $M/headers に残す。
cat > $T/bin/curl <<'EOS'
#!/bin/zsh
url=${@[-1]} jar=
for ((i = 1; i <= $#; i++)); do
  [[ ${@[i]} == -c ]] && jar=${@[i+1]}
  [[ ${@[i]} == -[He] ]] && print -r -- "${@[i+1]}" >> $M/headers
done
print -r -- "$url" >> $M/calls
W=https://service.wi2.ne.jp
land() { printf '.service.wi2.ne.jp\tFALSE\t/\tTRUE\t0\tsession_id\tabc\n' > $jar
         printf '302 %s/freewifi/%s/landing.html%s' $W "${BRAND-doutor}" "${1-}" }
case $url in
  *hotspot-detect*)
    [[ ${PROBE-} == down ]] && exit 7
    if [[ -s $M/late ]]; then   # 認証後、疎通が戻るまでに $M/late 回の確認がかかる
      n=$(<$M/late); (( n > 1 )) && print $((n - 1)) > $M/late || { rm $M/late; touch $M/authed }
    fi
    [[ -e $M/authed ]] && printf '<HTML><TITLE>Success</TITLE></HTML>\n200 ' ||
      printf 'x\n302 %s' "${LOC-$W/wi2auth/redirect?cmd=login&mac=${LMAC-aa:bb:cc:dd:ee:0f}&ip=${LIP-10.0.0.5}&essid=%20&apname=<AP>&apgroup=&url=http%3A%2F%2Fcaptive.apple.com%2F}" ;;
  */wi2auth/redirect\?*) case ${REDIR-ok} in
    ok) land ;;
    query) land '?lang=ja' ;;
    chain) printf '302 %s/wi2auth/next' $W ;;
    nocookie) printf '302 %s/freewifi/doutor/landing.html' $W ;;
    503) printf '503 ' ;;
    other) printf '302 https://example.com/' ;;
    error) printf '302 %s/wi2auth/error/ctrlapi_timeout.html?mac=%s&ip=%s' $W ${LMAC-aa:bb:cc:dd:ee:0f} ${LIP-10.0.0.5} ;;
    timeout) printf '000 '; exit 28 ;;
  esac ;;
  */wi2auth/next) land ;;
  */wi2auth/redirect) case ${BARE-ok} in
    ok) land ;;
    other) printf '302 %s/wi2auth/error/ctrlapi_timeout.html' $W ;;
    timeout) printf '000 '; exit 28 ;;
  esac ;;
  */xhr/login) [[ ${LHTTP-} == 000 ]] && { printf '\n000'; exit 28 }
    printf '%s\n%s' "${LOGIN-}" "${LHTTP-200}"; if [[ ${RECOVER-} == <-> ]]; then print $RECOVER > $M/late; elif [[ -n ${RECOVER-} ]]; then touch $M/authed; fi; exit 0 ;;
esac
EOS
# route: $NOROUTE があれば既定経路なし
print '#!/bin/sh\n[ -n "$NOROUTE" ] && exit 1\necho "   route to: default"\necho "    gateway: 10.0.0.1"\necho "  interface: en0"' > $T/bin/route
print '#!/bin/sh\necho "? ($2) at $MAC on en0 ifscope [ethernet]"' > $T/bin/arp
# ipconfig: DHCP のドメイン名は $DOM（既定は空）、自分の IP は $MYIP（既定 10.0.0.5）
print '#!/bin/sh\ncase $1 in getoption) printf "%s\\n" "$DOM" ;; getifaddr) echo "${MYIP-10.0.0.5}" ;; esac' > $T/bin/ipconfig
print '#!/bin/sh\nprintf "en0: flags=8863<UP>\\n\\tether %s\\n" "${MYMAC-aa:bb:cc:dd:ee:0f}"' > $T/bin/ifconfig
print '#!/bin/sh\nprintf "%s\\n" "$2" >> $M/notify' > $T/bin/osascript
# defaults: macOS の優先言語を $LANGS（既定は ja-JP）として返す。
print '#!/bin/sh\nprintf "(\\n    \\"%s\\",\\n    \\"en-JP\\"\\n)\\n" "${LANGS-ja-JP}"' > $T/bin/defaults
# launchctl: $M/bootstrap_fail に書いた回数だけ bootstrap を失敗させる（bootout 直後の error 5 の再現）。
cat > $T/bin/launchctl <<'EOF'
#!/bin/zsh
print -r -- "$*" >> $M/launchctl
if [[ $1 == bootstrap && -s $M/bootstrap_fail ]]; then
  n=$(<$M/bootstrap_fail); (( n > 0 )) && { print $((n - 1)) > $M/bootstrap_fail; exit 5 }
fi
exit 0
EOF
chmod +x $T/bin/*

sed -e "s#/usr/bin/curl#$T/bin/curl#" -e "s#/sbin/route#$T/bin/route#" -e "s#/usr/sbin/arp#$T/bin/arp#" \
    -e "s#/usr/bin/osascript#$T/bin/osascript#" -e "s#/usr/bin/defaults#$T/bin/defaults#" -e 's/sleep 2;/:;/' \
    -e "s#/usr/sbin/ipconfig#$T/bin/ipconfig#" -e "s#/sbin/ifconfig#$T/bin/ifconfig#" \
    -e "s#/var/run/resolv.conf#$M/resolv#" \
    $root/cafe-wifi-okawari.sh > $T/s.sh

ST=$HOME/Library/Caches/cafe-wifi-okawari
PD=$ST.pending
SN=$ST.seen
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
mkdir -p ${ST:h}
W=https://service.wi2.ne.jp

# --- 補助 ----------------------------------------------------------------------
pass=0 failed=0
# run VAR=val...: 1回実行し、rc・out・通信回数を残す
run() {
  rm -f $M/calls $M/notify $M/headers
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
reset() { rm -rf $ST $PD $SN ${KN:h} $M/authed $M/late; touch -t 202001010000 $M/resolv }
joined() { touch $M/resolv }
A=aa:aa:aa:aa:aa:01 B=bb:bb:bb:bb:bb:02
consent() { print -r -- "$1 ${2-doutor}" >> $KN }   # 同意済みの接続先を用意する
mkknown() { mkdir -p ${KN:h}; consent "$@" }
OKL='LOGIN={"result":true}'

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

# --- 接続画面での同意（macOS が同意まで網を使わせないので、同意後の状態から記録する） ---
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok '通信できる Wi2 の網: ブランドを確かめて記録' '[[ $(<"$KN") == "$A doutor" ]] && [[ $out == *"consent recorded net=$A doutor (online)" ]] && (( redirs == 1 && posts == 0 ))'
                          ok '確かめるのは引数なしの redirect' 'grep -qx "$W/wi2auth/redirect" $M/calls'
run MAC=$A DOM=wi2.ne.jp; ok '同じ接続先では確かめ直さない' '(( redirs == 0 )) && [[ -z $out ]]'
run MAC=$B DOM=wi2.ne.jp BRAND=starbucks
                          ok '別の接続先に移れば確かめる' 'grep -qxF "$B starbucks" "$KN"'
reset; mkknown $A; touch $M/authed
run MAC=$A DOM=wi2.ne.jp; ok '同意済みなら記録を重ねない' '[[ $(<"$KN") == "$A doutor" && -z $out ]]'
reset; joined; touch $M/authed
run MAC=$A;               ok 'Wi2 のドメイン名でなければ記録しない' '[[ ! -e "$KN" ]] && (( redirs == 0 ))'
reset; touch $M/authed
for i in {1..4}; do run MAC=$A DOM=wi2.ne.jp BARE=other; (( i == 1 )) && o1=$out; done
                          ok '無料 Wi-Fi のランディングでなければ記録しない' '[[ ! -e "$KN" && $o1 == *"not free wi-fi x1 net=$A http=302 to=$W/wi2auth/error/ctrlapi_timeout.html" ]]'
                          ok '確かめるのは3回まで' '(( redirs == 0 ))'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BARE=timeout
                          ok '確かめられなければ記録しない' '[[ ! -e "$KN" && $out == *"redirect failed x1 net=$A curl=28 http=000" ]]'
run MAC=$A DOM=wi2.ne.jp; ok '次の回にやり直す' '[[ $(<"$KN") == "$A doutor" ]]'
reset; touch $M/authed
run MAC=$A DOM=wi2.ne.jp BRAND='x y'
                          ok 'ブランド名が不正なら記録しない' '[[ ! -e "$KN" ]]'

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
run MAC=$A;               ok '捕捉が続いたら1回だけ知らせる'  '(( notes == 1 && redirs == 0 && posts == 0 )) && grep -q 最初の1回 $M/notify'
                          ok '知らせるのはダイアログ'         'grep -q "^display alert .*giving up after 120" $M/notify && grep -q captive.apple.com $M/notify'
touch -t 202001010000 $M/resolv
run MAC=$A;               ok '知らせた後は何もしない'         '(( notes == 0 && redirs == 0 && posts == 0 )) && [[ -s $M/calls ]]'
touch $M/authed
run MAC=$A;               ok '自分で同意したら記録'           '[[ $(<"$KN") == "$A doutor" && ! -e $PD ]] && [[ $out == *"consent recorded net=$A doutor" ]]'
rm $M/authed
run MAC=$A $OKL RECOVER=1
                          ok '同意済みの接続先は自動で再認証' '(( posts == 1 )) && [[ $out == *"re-authenticated api=ok probe=ok net=$A doutor t=2s" ]]'
reset; joined
run MAC=$A LANGS=en-US; run MAC=$A LANGS=en-US
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
                          ok 'ランディングにクエリがあってもよい' '(( posts == 1 ))'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1 REDIR=error
                          ok 'エラーページなら送らずに記録して知らせる' '(( posts == 0 && notes == 1 )) && [[ $out == *"redirect failed x1 http=302 to=$W/wi2auth/error/ctrlapi_timeout.html" ]]'
                          ok 'ログに端末の MAC・IP を残さない' '[[ $out != *aa:bb:cc* && $out != *10.0.0.5* ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=1
                          ok '認証要求はランディングからの XHR と同じ' 'grep -qx "Origin: $W" $M/headers && grep -qx "$W/freewifi/doutor/landing.html" $M/headers'
reset; mkknown $A
run MAC=$A $OKL RECOVER=3; ok '疎通が数秒遅れて戻っても成功' '[[ $out == *"re-authenticated api=ok probe=ok net=$A doutor t=6s" ]]'
reset; mkknown $A
run MAC=$A $OKL RECOVER=9; ok '10秒で戻らなければ失敗' '[[ $out == *"login failed x1 api=ok probe=ng"* ]] && (( notes == 1 ))'

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
ok 'ログは x1・x2・x4・x8 だけ'     '[[ "$logs" == "login failed x1 login failed x2 login failed x4 login failed x8" ]]'
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
      "$H/Library/Caches/cafe-wifi-okawari.seen"
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh uninstall > $M/out 2>&1; rc=$?
ok '削除: ログ以外は残らない'          '(( rc == 0 )) && [[ $(cd "$H" && find . -type f) == ./Library/Logs/cafe-wifi-okawari.log ]]'
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh bogus > $M/out 2>&1; rc=$?
ok '引数誤りは 2 で終わる'             '(( rc == 2 ))'

print "pass=$pass fail=$failed"
(( failed == 0 ))
