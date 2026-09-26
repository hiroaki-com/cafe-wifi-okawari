#!/bin/zsh
# 使い方: ./install.sh（導入・更新） / ./install.sh uninstall（削除。ログは残す）
# ユーザー権限の LaunchAgent として登録する。sudo は不要。
set -eu

label=local.cafe-wifi-okawari
bin=$HOME/.local/bin/cafe-wifi-okawari
plist=$HOME/Library/LaunchAgents/$label.plist
log=$HOME/Library/Logs/cafe-wifi-okawari.log

case ${1-} in
  '') ;;
  uninstall)
    launchctl bootout gui/$UID/$label 2>/dev/null || true
    rm -f $plist $bin $HOME/Library/Caches/cafe-wifi-okawari
    print "削除しました（ログは残しています: $log）"
    exit 0 ;;
  *) print -u2 "usage: $0 [uninstall]"; exit 2 ;;
esac

# スクリプトを固定の場所へ複製する（リポジトリを移動・削除しても動き続ける）。
mkdir -p ${bin:h} ${plist:h} ${log:h}
install -m 755 ${0:A:h}/cafe-wifi-okawari.sh $bin

cat > $plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin</string>
  </array>
  <key>StartInterval</key>
  <integer>30</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$log</string>
  <key>StandardErrorPath</key>
  <string>$log</string>
</dict>
</plist>
EOF
plutil -lint -s $plist

launchctl bootout gui/$UID/$label 2>/dev/null || true
launchctl bootstrap gui/$UID $plist
print "導入しました: $bin（30秒ごとに実行。ログ: $log）"
