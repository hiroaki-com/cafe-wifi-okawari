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
# curl: captive.apple.com は $M/authed があれば Success、なければ 302。
#       redirect は $REDIR（ok/nocookie/503/other/timeout）、login は $LOGIN を返す。$RECOVER があれば認証済みにする。
cat > $T/bin/curl <<'EOF'
#!/bin/zsh
url=${@[-1]} jar=
for ((i = 1; i <= $#; i++)); do [[ ${@[i]} == -c ]] && jar=${@[i+1]}; done
print -r -- "$url" >> $M/calls
case $url in
  *hotspot-detect*)
    [[ ${PROBE-} == down ]] && exit 7
    [[ -e $M/authed ]] && printf '<HTML><TITLE>Success</TITLE></HTML>\n200' || printf 'x\n302' ;;
  */wi2auth/redirect) case ${REDIR-ok} in
    ok) printf '.service.wi2.ne.jp\tFALSE\t/\tTRUE\t0\tsession_id\tabc\n' > $jar
        printf '302 https://service.wi2.ne.jp/freewifi/doutor/landing.html' ;;
    nocookie) printf '302 https://service.wi2.ne.jp/freewifi/doutor/landing.html' ;;
    503) printf '503 ' ;;
    other) printf '302 https://example.com/' ;;
    timeout) printf '000 '; exit 28 ;;
  esac ;;
  */xhr/login) print -rn -- "${LOGIN-}"; [[ -n ${RECOVER-} ]] && touch $M/authed ;;
esac
EOF
print '#!/bin/sh\necho "gateway: 10.0.0.1"' > $T/bin/route
print '#!/bin/sh\necho "? ($2) at $MAC on en0 ifscope [ethernet]"' > $T/bin/arp
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
    -e "s#/usr/bin/osascript#$T/bin/osascript#" -e "s#/usr/bin/defaults#$T/bin/defaults#" -e 's/^sleep 2$/:/' \
    $root/cafe-wifi-okawari.sh > $T/s.sh

ST=$HOME/Library/Caches/cafe-wifi-okawari
PD=$ST.pending
KN="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
mkdir -p ${ST:h}

# --- 補助 ----------------------------------------------------------------------
pass=0 failed=0
# run VAR=val...: 1回実行し、rc・out・通信回数を残す
run() {
  rm -f $M/calls $M/notify
  env "$@" zsh $T/s.sh > $M/out 2>&1; rc=$?
  out=$(<$M/out)
  posts=$(grep -c xhr/login $M/calls 2>/dev/null); redirs=$(grep -c wi2auth/redirect $M/calls 2>/dev/null)
  notes=$( [[ -e $M/notify ]] && wc -l < $M/notify | tr -d ' ' || print 0)
}
ok() {  # ok <名前> <条件式...>
  local name=$1; shift
  if eval "$*"; then (( pass++ )); else (( failed++ )); print -r -- "NG: $name  [$*]  rc=$rc posts=$posts redirs=$redirs notes=$notes out=$out"; fi
}
reset() { rm -rf $ST $PD ${KN:h} $M/authed }
A=aa:aa:aa:aa:aa:01 B=bb:bb:bb:bb:bb:02
consent() { print -r -- $1 >> $KN }   # 同意済みの接続先を用意する
mkknown() { mkdir -p ${KN:h}; consent $1 }

# --- 基本の状態判定 ------------------------------------------------------------
reset; touch $M/authed
run MAC=$A;               ok '認証済みなら何もしない'  '(( rc == 0 && redirs == 0 && posts == 0 )) && [[ -z $out ]]'
reset
run MAC=$A PROBE=down;    ok '無接続なら何もしない'    '(( rc == 0 && redirs == 0 && posts == 0 ))'

# --- 初回の同意 ----------------------------------------------------------------
reset
run MAC=$A;               ok '初回の Wi2: 同意を送らない'     '(( posts == 0 && redirs == 1 ))'
                          ok '初回の Wi2: 案内を1回通知'      '(( notes == 1 )) && grep -q 最初の1回 $M/notify'
                          ok '初回の Wi2: 保留に記録'         '[[ $(<$PD) == $A ]]'
run MAC=$A;               ok '保留中の再実行は通信しない'     '(( posts == 0 && redirs == 0 && notes == 0 ))'
touch $M/authed
run MAC=$A;               ok '自分で同意したら記録'           '[[ $(<"$KN") == $A && ! -e $PD ]] && [[ $out == *"consent recorded net=$A" ]]'
rm $M/authed
run MAC=$A 'LOGIN={"result":true}' RECOVER=1
                          ok '同意済みの接続先は自動で再認証' '(( posts == 1 )) && [[ $out == *"re-authenticated api=ok probe=ok" ]]'
reset
reset
run MAC=$A LANGS=en-US;   ok '英語環境では英語で通知'         'grep -q "accept them in your browser once" $M/notify'
reset
run MAC=$A REDIR=other;   ok '初回の対象外の網: 通知しない'   '(( posts == 0 && notes == 0 )) && [[ -e $PD ]]'
reset; touch $M/authed
run MAC=$A;               ok '捕捉を見ていない網は記録しない' '[[ ! -e "$KN" ]]'
reset; print -r -- $A > $PD; touch $M/authed
run MAC=$B;               ok '別の網で認証済みなら記録しない' '[[ ! -e "$KN" && ! -e $PD ]]'

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
  run MAC=$A 'LOGIN={"result":false}'
  (( total += notes )); [[ -n $out ]] && logs+=(${${out#* * }%% api*})
  (( i == 1 )) && { w1=$(( ${$(<$ST)[(w)2]} - EPOCHSECONDS )) }
done
w9=$(( ${$(<$ST)[(w)2]} - EPOCHSECONDS ))
ok '9回失敗しても通知は1回'        '(( total == 1 ))'
ok 'ログは x1・x2・x4・x8 だけ'     '[[ "$logs" == "login failed x1 login failed x2 login failed x4 login failed x8" ]]'
ok '待機は 30秒から最大30分'       '(( w1 >= 29 && w1 <= 30 && w9 >= 1799 && w9 <= 1800 ))'
run MAC=$A 'LOGIN={"result":false}'
ok '待機中は通信しない'            '(( redirs == 0 && posts == 0 ))'
consent $B
run MAC=$B 'LOGIN={"result":true}' RECOVER=1
ok '別の接続先へ移れば待機を持ち越さない' '(( posts == 1 )) && [[ $out == *re-authenticated* ]]'
reset; mkknown $A; print "3 $(( EPOCHSECONDS + 900 ))" > $ST
run MAC=$A 'LOGIN={"result":true}' RECOVER=1
ok '旧形式の状態ファイルでも動く'  '(( posts == 1 ))'

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
run MAC=$A REDIR=other;    ok '同意済みでも対象外の応答なら何もしない' '(( posts == 0 && notes == 0 )) && [[ -z $out && ! -e $ST ]]'

# --- install.sh ----------------------------------------------------------------
H="$T/ho&me<x>"; mkdir -p "$H"
plist="$H/Library/LaunchAgents/local.cafe-wifi-okawari.plist"
print 2 > $M/bootstrap_fail
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh > $M/out 2>&1; rc=$? out=$(<$M/out)
ok '導入: HOME に & < > があっても成功' '(( rc == 0 )) && plutil -lint -s "$plist"'
ok '導入: 日本語環境では日本語で表示'  '[[ $out == 導入しました:* ]]'
ok '導入: plist のパスが正しい'        '[[ $(plutil -extract ProgramArguments.0 raw "$plist") == "$H/.local/bin/cafe-wifi-okawari" ]]'
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
      "$H/Library/Caches/cafe-wifi-okawari" "$H/Library/Caches/cafe-wifi-okawari.pending"
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh uninstall > $M/out 2>&1; rc=$?
ok '削除: ログ以外は残らない'          '(( rc == 0 )) && [[ $(cd "$H" && find . -type f) == ./Library/Logs/cafe-wifi-okawari.log ]]'
HOME=$H PATH=$T/bin:$PATH zsh $root/install.sh bogus > $M/out 2>&1; rc=$?
ok '引数誤りは 2 で終わる'             '(( rc == 2 ))'

print "pass=$pass fail=$failed"
(( failed == 0 ))
