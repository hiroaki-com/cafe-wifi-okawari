#!/bin/zsh
# 使い方: ./install.sh（導入・更新） / ./install.sh status（動作の確認） / ./install.sh uninstall（削除。ログは残す）
# ユーザー権限の LaunchAgent として登録する。sudo は不要。
set -eu

label=local.cafe-wifi-okawari
bin=$HOME/.local/bin/cafe-wifi-okawari
plist=$HOME/Library/LaunchAgents/$label.plist
log=$HOME/Library/Logs/cafe-wifi-okawari.log
kn="$HOME/Library/Application Support/cafe-wifi-okawari/consented"
every=10   # 起動の間隔（秒）。launchd は既定で10秒より短い間隔ではジョブを起動しない

# メッセージは macOS の優先言語が日本語なら日本語、それ以外は英語。$1=日本語 $2=英語
[[ $(defaults read -g AppleLanguages 2>/dev/null | awk -F'"' 'NF > 1 { print $2; exit }') == ja* ]] && ja=1 || ja=0
msg() { (( ja )) && print -r -- "$1" || print -r -- "$2" }

case ${1-} in
  '') ;;
  status)
    # 登録されているか・同意済みの接続先（ブランド名だけ）・ログの最新5行を表示する。通信はしない。登録がなければ 1 で終わる。
    launchctl print gui/$UID/$label >/dev/null 2>&1 && on=1 || on=0
    (( on )) && msg "動作中（${every}秒ごと）: $bin" "Running (every $every seconds): $bin" \
             || msg "登録されていません（./install.sh で導入）" "Not registered (run ./install.sh to install)"
    n=$(grep -c . "$kn" 2>/dev/null) || n=0
    b=$(awk '{ print $2 }' "$kn" 2>/dev/null | sort -u | paste -sd ' ' -) || b=
    msg "同意済みの接続先: $n 件${b:+（$b）}" "Accepted networks: $n${b:+ ($b)}"
    [[ -s $log ]] && { msg "ログ（最新5行）: $log" "Log (last 5 lines): $log"; tail -n 5 "$log" }
    exit $(( ! on )) ;;
  uninstall)
    launchctl bootout gui/$UID/$label 2>/dev/null || true
    rm -f $plist $bin $HOME/Library/Caches/cafe-wifi-okawari{,.pending,.seen,.probe}
    rm -rf "${kn:h}"   # 同意した接続先の記録
    msg "削除しました（ログは残しています: $log）" "Uninstalled (the log is kept: $log)"
    exit 0 ;;
  *) print -u2 -r -- "usage: $0 [status|uninstall]"; exit 2 ;;
esac

# スクリプトを固定の場所へ複製する（リポジトリを移動・削除しても動き続ける）。
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

launchctl bootout gui/$UID/$label 2>/dev/null || true
# bootout の直後は登録解除が終わっておらず bootstrap が失敗することがある（error 5）ので、少し待ってやり直す。
for i in {1..10}; do
  launchctl bootstrap gui/$UID $plist 2>/dev/null && break
  (( i < 10 )) || { msg "登録に失敗しました: launchctl bootstrap gui/$UID $plist" \
                         "Failed to register: launchctl bootstrap gui/$UID $plist" >&2; exit 1 }
  sleep 0.5
done
msg "導入しました: $bin（${every}秒ごとに実行。ログ: $log。確認: ./install.sh status）" \
    "Installed: $bin (runs every $every seconds; log: $log; check: ./install.sh status)"
