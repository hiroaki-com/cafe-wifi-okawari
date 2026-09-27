#!/bin/zsh
# 使い方: ./install.sh（導入・更新） / ./install.sh uninstall（削除。ログは残す）
# ユーザー権限の LaunchAgent として登録する。sudo は不要。
set -eu

label=local.cafe-wifi-okawari
bin=$HOME/.local/bin/cafe-wifi-okawari
plist=$HOME/Library/LaunchAgents/$label.plist
log=$HOME/Library/Logs/cafe-wifi-okawari.log

# メッセージは macOS の優先言語が日本語なら日本語、それ以外は英語。$1=日本語 $2=英語
[[ $(defaults read -g AppleLanguages 2>/dev/null | awk -F'"' 'NF > 1 { print $2; exit }') == ja* ]] && ja=1 || ja=0
msg() { (( ja )) && print -r -- "$1" || print -r -- "$2" }

case ${1-} in
  '') ;;
  uninstall)
    launchctl bootout gui/$UID/$label 2>/dev/null || true
    rm -f $plist $bin $HOME/Library/Caches/cafe-wifi-okawari{,.pending,.seen}
    rm -rf "$HOME/Library/Application Support/cafe-wifi-okawari"   # 同意した接続先の記録
    msg "削除しました（ログは残しています: $log）" "Uninstalled (the log is kept: $log)"
    exit 0 ;;
  *) print -u2 -r -- "usage: $0 [uninstall]"; exit 2 ;;
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
plutil -insert StartInterval -integer 30 $plist
plutil -insert RunAtLoad -bool true $plist
# DNS の設定が変わるたびに書き換わるファイルを見て、そのときにも実行する。認証画面つきの網では、
# 接続画面で同意して通信できるようになった時刻に書き換わる（<date omitted> 実測）ので、同意の直後に記録できる。
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
msg "導入しました: $bin（30秒ごとに実行。ログ: $log）" "Installed: $bin (runs every 30 seconds; log: $log)"
