# cafe-wifi-okawari

[![test](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml/badge.svg)](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-lightgrey)

[English](README.md) | 日本語

カフェの無料 Wi‑Fi で「60分経ったので認証画面に戻された」ときに、自動で規約に同意し直して接続を戻す macOS 用の常駐スクリプトです。名前の okawari は、コーヒーの「おかわり」のように、時間切れのたびに Wi‑Fi をおかわりすることに由来します。

- 30秒ごとに接続状態を確認し、認証画面に戻されていれば再認証します（切れてから戻るまで最大30秒ほど）
- 60分・30分など、制限時間の長さに関係なく動きます
- ID・パスワード・メールアドレスは使いません。保存もしません
- 追加のインストールは不要です（macOS 標準の zsh・curl・launchd だけで動きます）

## 対応している Wi‑Fi

ワイヤ・アンド・ワイヤレス（Wi2）の「規約に同意するだけ」の無料 Wi‑Fi に対応しています。

| お店 | SSID | 状況 |
|---|---|---|
| ドトール・エクセルシオール | `DOUTOR_FREE_Wi-Fi` | 動作確認済み |
| スターバックス | `at_STARBUCKS_Wi2` | 同じ仕組みのため動く見込み |
| タリーズ | `tullys_Wi-Fi` | 同上 |
| ガストなど すかいらーくグループ | `.Wi2_Free_at_【SK.GROUP】` | 同上 |
| ルノアール・ミヤマ珈琲 | `Renoir_Miyama_Wi-Fi` | 同上（1日3時間の上限は延長できません） |

会員登録やメール登録、アンケートが必要な Wi‑Fi（マクドナルド、サイゼリヤなど）には対応しません。調査結果は [DESIGN.md](DESIGN.md) にあります。

## 動作環境

macOS 15 以降（標準の `/usr/bin/jq` を使います）。Apple Silicon と Intel のどちらでも動きます。動作確認は macOS 27 で行いました。

## 導入

```sh
git clone https://github.com/hiroaki-com/cafe-wifi-okawari.git
cd cafe-wifi-okawari
./install.sh
```

管理者権限（`sudo`）は使いません。スクリプトを `~/.local/bin/cafe-wifi-okawari` にコピーし、ログインユーザーの LaunchAgent として登録します。更新するときも `./install.sh` を再実行してください。

## 使い方

**お店ごとに、最初の1回は自分で同意してください。** 初めてつないだ Wi‑Fi では、このツールは何も送りません。認証画面で利用規約を読み、自分で「同意する」を押してください。ツールはそれを見て、この Wi‑Fi を覚えます。次に時間切れになったときからは、自動で再認証します。

- ツールが Wi‑Fi を覚える前に認証画面に戻された場合は、「最初の1回だけ、ブラウザで規約を読んで同意してください」と1回だけ通知が出ます
- お店は、店内の Wi‑Fi ルーターの MAC アドレスで見分けます。同じチェーンでも、店が変われば最初の1回はもう一度自分で同意します

通知と `install.sh` のメッセージは、macOS の言語設定に合わせて日本語か英語で表示します。

## 削除

```sh
./install.sh uninstall
```

同意したお店の記録も消えます。ログ（`~/Library/Logs/cafe-wifi-okawari.log`）だけは残ります。不要なら手で削除してください。

## 困ったとき

動いているか（`state = running` か、`last exit code` が出ていれば登録されています）:

```sh
launchctl print gui/$UID/local.cafe-wifi-okawari | grep -E 'state|last exit code'
```

ログは、何かが起きたときだけ書きます:

```sh
tail ~/Library/Logs/cafe-wifi-okawari.log
```

| ログ | 意味 |
|---|---|
| `consent recorded net=…` | 自分で同意したお店を覚えた。次からは自動で再認証する |
| `re-authenticated api=ok probe=ok` | 自動で再認証できた |
| `login failed xN api=ng probe=ok` | このツールの認証は失敗したが、別の経路（macOS の認証画面など）で接続は戻った |
| `login failed xN api=ng probe=ng` | 再認証できず、接続も戻っていない。通知が出る。ルノアールなどで1日の利用時間の上限に達した場合もこうなる（延長はできない） |
| `redirect failed xN curl=… http=…` | 認証サーバーに届かない（タイムアウト・障害）。ホテルなど Wi2 以外の Wi‑Fi でも出ることがあるが、害はない。通知はしない |
| `redirect failed xN no session_id` | 認証サーバーの応答が想定と違う（仕様変更の可能性）。通知が出る |

失敗が続いたときは、試す間隔を 30秒 → 60秒 → … → 最大30分 と広げ、ログは 1・2・4・8… 回目だけ書きます。通知は失敗が続く間に1回だけです。別のお店の Wi‑Fi に移ったときは、前のお店での待ち時間を引き継がずにすぐ試します。

## 注意

- **VPN・iCloud プライベートリレー**: 使っていると、認証画面に戻されたことを正しく判定できないことがあります
- **通信の暗号化**: 無料 Wi‑Fi の通信は暗号化されていません。このツールはつなぎ直すだけで、通信内容は守りません。大事な通信は HTTPS や VPN で守ってください
- **利用規約**: 利用者が手で押す「同意する」を、2回目以降に代わりに押すだけです。時間制限の回避、MAC アドレスの偽装、多重接続はしません。お店の利用規約に従って使ってください
- 非公式のツールで、上記の各社とは関係ありません。各社の仕様が変わると動かなくなることがあります

## 開発

```sh
zsh test/run.sh   # 模擬の curl などで分岐を確かめる（実際の網にはつながない）
```

設計・安全性・検証状況は [DESIGN.md](DESIGN.md) にあります。

## ライセンス

[MIT](LICENSE)
