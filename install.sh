#!/bin/zsh
# 使い方: ./install.sh（導入・更新） / ./install.sh --no-menubar（メニューバーの表示なしで導入・更新）
#         ./install.sh status（動作の確認） / ./install.sh uninstall（削除。ログは残す）
# ユーザー権限の LaunchAgent として登録する。sudo は不要。
set -eu

label=local.cafe-wifi-okawari
bin=$HOME/.local/bin/cafe-wifi-okawari
plist=$HOME/Library/LaunchAgents/$label.plist
log=$HOME/Library/Logs/cafe-wifi-okawari.log
kn="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
# メニューバーの表示（DESIGN.md §3.2）。判定の .sh と表示の .js の組。本体からは呼ばず、本体の動作に関係しない
mlabel=$label.menubar
mbin=$HOME/.local/bin/cafe-wifi-okawari-menubar
mplist=$HOME/Library/LaunchAgents/$mlabel.plist
every=10   # 起動の間隔（秒）。launchd は既定で10秒より短い間隔ではジョブを起動しない
# メッセージは英語のみ。

menubar=1
case ${1-} in
  '') ;;
  --no-menubar) menubar=0 ;;
  status)
    # 登録の状態・メニューバーの表示・今の接続先・同意済みの接続先・最後の認証と次の時間切れの目安・ログの最新5行を表示する（英語のみ）。
    # 通信はしない（今の接続先は経路表と ARP キャッシュから、本体の netid と同じ方法で読む）。登録がなければ 1 で終わる。
    zmodload zsh/datetime   # EPOCHSECONDS
    row() { printf '%-17s%s\n' "$1" "$2" }
    # 経過時間を短く表す（45 s / 52 min / 3 h 12 min / 4 days）
    dur() {
      local s=$(( $1 > 0 ? $1 : 0 ))
      if (( s < 60 )); then print -r -- "$s s"
      elif (( s < 3600 )); then print -r -- "$(( s / 60 )) min"
      elif (( s < 172800 )); then print -r -- "$(( s / 3600 )) h $(( s % 3600 / 60 )) min"
      else print -r -- "$(( s / 86400 )) days"; fi
    }
    now=$EPOCHSECONDS

    if lc=$(launchctl print gui/$UID/$label 2>/dev/null); then
      on=1
      row Service "loaded (LaunchAgent $label)"
      row Schedule "every $every s, and whenever the network settings change"
      row Program "$bin"
      ec=$(print -r -- "$lc" | awk -F' = ' '$1 ~ /^[ \t]*last exit code$/ { print $2; exit }')
      runs=$(print -r -- "$lc" | awk -F' = ' '$1 ~ /^[ \t]*runs$/ { print $2; exit }')
      [[ -n $ec ]] && row 'Last exit code' "$ec${runs:+ ($runs runs since loaded)}"
    else
      on=0
      row Service "not loaded (run ./install.sh to install or re-register)"
    fi
    if [[ ! -e $mplist ]]; then row 'Menu bar' 'not installed'
    elif [[ $(launchctl print gui/$UID/$mlabel 2>/dev/null | awk -F' = ' '$1 ~ /^[ \t]*state$/ { print $2; exit }') == running ]]; then row 'Menu bar' running
    else row 'Menu bar' 'not running'; fi

    r=$(route -n get default 2>/dev/null) || r=
    gw=${${(M)${(f)r}:#*gateway:*}##* } net=
    if [[ -n $gw ]]; then
      net=$(arp -n "$gw" 2>/dev/null | awk '{ print $4 }')
      [[ $net == *:*:* ]] || net=$gw
    fi
    if [[ -z $net ]]; then
      row 'Current network' 'none (offline, or macOS is waiting for you to accept on the login page)'
    elif kb=$(awk -v n="$net" '$1 == n { f = 1; if (NF > 1) b = b (b == "" ? "" : ", ") $2 } END { print b; exit !f }' "$kn" 2>/dev/null); then
      row 'Current network' "gateway $net${kb:+ ($kb)}, accepted: auto re-authentication on"
    elif awk -v n="$net" -v t=$(( now - 86400 )) '$1 == n && $2 > t { f = 1 } END { exit !f }' "${kn:h}/watched" 2>/dev/null; then
      # 接続画面での同意をシステムログで確かめた網（24時間以内）。USEN なら、次の時間切れで同意を記録して自動で送る。
      row 'Current network' "gateway $net, you accepted on its login page: if it is USEN Wi-Fi, auto re-authentication starts at the next time-out"
    else
      row 'Current network' "gateway $net, not accepted: auto re-authentication off"
    fi

    n=$(grep -c . "$kn" 2>/dev/null) || n=0
    b=(${(ou)${(f)"$(awk 'NF > 1 { print $2 }' "$kn" 2>/dev/null || :)"}})
    if (( n == 0 )); then row Accepted 'none yet'
    else row Accepted "$n network$( (( n > 1 )) && print s)${b:+ (brand$( (( $#b > 1 )) && print s): ${(j:, :)b})}"; fi

    # 最後の認証（自動の再認証・同意の記録。どの接続先でも）
    a=$(grep -E '^[0-9-]{10} [0-9:]{8} (re-authenticated|consent recorded) ' "$log" 2>/dev/null | tail -n 1) || a=
    if [[ -n $a ]] && t=$(date -j -f '%F %T' "${a[1,19]}" +%s 2>/dev/null); then
      w=(${=a[21,-1]}) i=${w[(i)net=*]}
      ev=${${w[1]}/consent/consent recorded} br=${w[i+1]-}
      [[ $br == *[=\(]* ]] && br=
      row 'Last auth' "${a[1,19]} ($(dur $(( now - t ))) ago), $ev${br:+ on $br}"
    else
      row 'Last auth' 'none logged yet'
    fi
    # 次の時間切れの目安（メニューバーと同じ条件。DESIGN.md §3.2）: 今の接続先での最後の認証から60分。制限時間は店で違うので
    # 60分の店の場合として示す。接続画面での同意の記録（captive login。送る前に書く）は除く。その行の30秒より後に
    # resolv.conf が書き換わっていれば（つなぎ直した・自分で同意し直した。ログに残らない）今の接続の認証ではないので、出さない。
    a=$(grep -E '^[0-9-]{10} [0-9:]{8} (re-authenticated|consent recorded) ' "$log" 2>/dev/null | grep -F " net=$net " | grep -vF '(captive login)' | tail -n 1) || a=
    if [[ -n $net && -n $a ]] && t=$(date -j -f '%F %T' "${a[1,19]}" +%s 2>/dev/null) &&
       (( t + 3600 > now && $(stat -f %m /var/run/resolv.conf 2>/dev/null || print 0) <= t + 30 )); then
      row 'Next time-out' "around $(date -r $(( t + 3600 )) +%H:%M), in $(dur $(( t + 3600 - now ))) (if the shop's limit is 60 minutes)"
    fi

    if [[ -s $log ]]; then
      nl=$(wc -l < "$log") nl=${nl// }
      row Log "$log ($nl line$( (( nl > 1 )) && print s))"
      print; print -r -- "Recent log$( (( nl > 5 )) && print ' (last 5 lines)'):"
      tail -n 5 "$log" | sed 's/^/  /'
    else
      row Log "$log (empty; lines are written only when something happens)"
    fi
    exit $(( ! on )) ;;
  uninstall)
    launchctl bootout gui/$UID/$label 2>/dev/null || true
    launchctl bootout gui/$UID/$mlabel 2>/dev/null || true
    rm -f $plist $bin $mplist $mbin{.sh,.js,.png,@2x.png} $HOME/Library/Caches/cafe-wifi-okawari{,.pending,.seen,.probe}
    rm -rf "${kn:h}"   # 同意した接続先の記録
    print -r -- "Uninstalled: removed the LaunchAgents ($label, $mlabel), the programs and the list of accepted networks"
    print -r -- "  Log kept: $log (delete it by hand if you no longer need it)"
    exit 0 ;;
  *) print -u2 -r -- "usage: $0 [--no-menubar|status|uninstall]"; exit 2 ;;
esac

# スクリプトを固定の場所へ複製する（リポジトリを移動・削除しても動き続ける）。
[[ -e $bin ]] && verb=Updated || verb=Installed
mkdir -p ${bin:h} ${plist:h} ${log:h}
install -m 755 ${0:A:h}/cafe-wifi-okawari.sh $bin

# plist は plutil で組み立てる（HOME に & や < があっても XML が壊れない）。
rm -f $plist
plutil -create xml1 $plist
plutil -insert Label -string $label $plist
plutil -insert ProgramArguments -array $plist
plutil -insert ProgramArguments -string $bin -append $plist
plutil -insert StartInterval -integer $every $plist
plutil -insert RunAtLoad -bool true $plist
# DNS の設定が変わるたびに書き換わるファイルを見て、そのときにも実行する。認証画面つきの網では、
# 接続画面で同意して通信できるようになった時刻に書き換わる（現地で実測）ので、同意の直後に記録できる。
plutil -insert WatchPaths -array $plist
plutil -insert WatchPaths -string /var/run/resolv.conf -append $plist
plutil -insert ProcessType -string Background $plist
plutil -insert StandardOutPath -string $log $plist
plutil -insert StandardErrorPath -string $log $plist
plutil -lint -s $plist

# LaunchAgent $2 を plist $1 で登録し直す。bootout の直後は登録解除が終わっておらず bootstrap が失敗することがある（error 5）ので、
# 少し待ってやり直す。
load() {
  launchctl bootout gui/$UID/$2 2>/dev/null || true
  for i in {1..10}; do
    launchctl bootstrap gui/$UID $1 2>/dev/null && return
    (( i < 10 )) || { print -u2 -r -- "Error: could not register the LaunchAgent after 10 attempts (launchctl bootstrap gui/$UID $1)"; exit 1 }
    sleep 0.5
  done
}
load $plist $label

# メニューバーの表示。ログインしている画面のセッション（Aqua）でだけ動かす。落ちても立ち上げ直さない（KeepAlive なし。DESIGN.md §3.2）
if (( menubar )); then
  install -m 755 ${0:A:h}/menubar.sh $mbin.sh
  install -m 644 ${0:A:h}/menubar.js $mbin.js
  install -m 644 ${0:A:h}/assets/icon/menuBarTemplate.png $mbin.png
  install -m 644 ${0:A:h}/assets/icon/menuBarTemplate@2x.png $mbin@2x.png
  rm -f $mplist
  plutil -create xml1 $mplist
  plutil -insert Label -string $mlabel $mplist
  plutil -insert ProgramArguments -array $mplist
  for a in /usr/bin/osascript -l JavaScript $mbin.js; do plutil -insert ProgramArguments -string $a -append $mplist; done
  plutil -insert RunAtLoad -bool true $mplist
  plutil -insert LimitLoadToSessionType -string Aqua $mplist
  plutil -lint -s $mplist
  load $mplist $mlabel
else
  launchctl bootout gui/$UID/$mlabel 2>/dev/null || true
  rm -f $mplist $mbin{.sh,.js,.png,@2x.png}
fi
print -r -- "$verb: $bin"
print -r -- "  Runs every $every s, and whenever the network settings change (LaunchAgent $label)"
if (( menubar )); then print -r -- "  Menu bar: coffee cup icon (LaunchAgent $mlabel)"
else print -r -- "  Menu bar: not installed (--no-menubar)"; fi
print -r -- "  Log: $log"
print -r -- "  Check it with: ./install.sh status"
