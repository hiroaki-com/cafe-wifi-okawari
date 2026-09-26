# cafe-wifi-okawari 設計

公衆 Wi‑Fi のキャプティブポータルで時間切れ（30分・60分など）により認証画面へ戻されたとき、自動で再認証する macOS 常駐ツール。

## 1. 要件と対象

| 項目 | 内容 |
|---|---|
| 対象 PC | macOS 27.0 / Apple Silicon (arm64)。追加依存なし（`/bin/zsh`・`/usr/bin/curl`・`/usr/bin/jq`・launchd など OS 標準のみ） |
| 対象 Wi‑Fi | ドトール「DOUTOR FREE Wi-Fi」= Wi2（Wire and Wireless, AS131160）。暗号化なし、1回60分、再接続は無制限 |
| 時間制限 | 固定タイマーを持たず「ポータルに戻されたこと」を検知して再認証する。そのため30分・60分など任意の制限時間にそのまま対応する |
| 同一方式 | スタバ・タリーズ・すかいらーく・ルノアールも同じ Wi2 ワンタップ認証（§1.1）。同じコードで動く見込み |
| 前提 | 規約に同意するだけで使える網に限る。ID・パスワード・メールアドレスは扱わない。OSS として公開する |

### 現地調査の結果（<date omitted>、ドトール店内で実測）

- `https://service.wi2.ne.jp/wi2auth/redirect` → 302 で `/freewifi/doutor/landing.html` へ。`session_id` Cookie（Max-Age=3600）を発行
- ポータルの `login-min.js` で使われている認証 API:
  `POST /wi2auth/xhr/login`、`Content-Type: application/json`、
  本文 `{"login_method":"onetap","login_params":{"agree":"1"}}`
- curl から実行した結果 `{"result":true,"licensed":null,"message":"AUTHENTICATED"}`。ブラウザがなくても認証できる

### 1.1 主要チェーンの認証方式（<date omitted> 調査）

公式ページとプレスリリースで確認した。Wi2 の各店舗については、公開されているポータルの JS も取得し、同意ページが呼ぶ API を調べた（取得のみで、認証は送っていない）。

| チェーン | SSID | 運営 | 認証 | 時間制限 | 本ツール |
|---|---|---|---|---|---|
| ドトール・エクセルシオール | DOUTOR_FREE_Wi-Fi | Wi2 | 同意のみ | 60分・回数無制限 | 対応（実測済み） |
| スターバックス | at_STARBUCKS_Wi2 | Wi2 | 同意のみ | 60分 | 対応見込み（JS 一致） |
| タリーズ | tullys_Wi-Fi | Wi2 | 同意のみ | 公式に記載なし（二次情報では無制限） | 対応見込み（JS 一致）。制限がなければ出番はない |
| ガスト等すかいらーく | .Wi2_Free_at_【SK.GROUP】 | Wi2 | 同意のみ | 60分・回数無制限 | 対応見込み（JS 一致） |
| ルノアール・ミヤマ珈琲 | Renoir_Miyama_Wi-Fi | Wi2 | 同意のみ | 1日3時間 | 対応見込み（JS 一致）。上限後は再認証しても延長されない想定 |
| コメダ珈琲 | Komeda_Wi-Fi | USEN | 同意（誕生年・性別は任意） | 60分・回数無制限 | 未対応。API は現地で要調査 |
| サンマルクカフェ | 309cafe_Wi-Fi | 不明 | 同意のみ（二次情報） | 不明 | 未対応。一部店舗のみ |
| サイゼリヤ | Saizeriya_Free | 不明 | 毎回アンケート回答 | 60分×1日3回 | 対象外（回答の自動化は虚偽回答になる） |
| マクドナルド | 00_MCD-FREE-WIFI | — | 会員登録・ログイン | 60分 | 対象外（認証情報が必要） |
| ケンタッキー | KFC_FREE_Wi-Fi | — | メール登録 | 30分×1日3回 | 対象外（認証情報が必要） |
| モスバーガー | 0001docomo ほか | ドコモ等 | d アカウント等 | — | 対象外（認証情報が必要） |
| デニーズ | Dennys_Free_Wifi | — | パスワード（WPA） | — | 対象外（ポータルがない） |

Wi2 の5ブランドはどれも、同意ページ（`/freewifi/<店舗>/agreement.html` または `index.html`）の JS に `xhr/login`・`login_method:"onetap"`・`agree:"1"` があり、ランディングは `/freewifi/<店舗>/landing.html` の共通雛形だった。本スクリプトはランディングの店舗名を固定していないので、変更なしで動くはず。実機での確認はドトールだけ。

**判断**: 同意だけで使えて時間制限もある主要チェーンは、ほとんどが Wi2 に集まっている。そのため、対応は Wi2 のみのまま据え置く。次の候補はコメダ（USEN）だが、現地で通信を確かめるまでは実装しない（§8）。

## 2. 既存 OSS の調査と判断

| OSS | 方式 | 不採用の理由 |
|---|---|---|
| [captive-watchdog](https://github.com/CorentinGC/captive-watchdog) | Swift / macOS、HTML フォームを推測して送信 | Wi2 は JS（XHR）で認証するためフォーム推測が効かない。非商用ライセンス、ビルドに Xcode が必要、利用実績がほぼない |
| [portal-autologin](https://github.com/Masudali23/portal-autologin) | bash + curl、launchd 対応 | FortiGate 向けのフォームログイン。LaunchDaemon を3つ root 権限で常駐させるため、権限が過剰 |
| [starbuccaneer](https://github.com/MichaelCharles/starbuccaneer) | Node + Puppeteer | Chromium が必要で重い。リポジトリは 404（消失） |
| [captive-portal-manager](https://github.com/AlpBora/captive-portal-manager) | LaunchAgent + Hammerspoon | Hammerspoon への依存が増える |
| [Qiita: relu](https://qiita.com/relu/items/6356093451d1f4bf742f) | NetworkManager dispatcher + wget | **Wi2 の API はこれと同じ**。ただし Linux 専用 |

**判断**: 汎用ツールはどれも Wi2 の XHR 認証に合わないか、依存や権限が過剰。そこで既存の知見（Wi2 の API 手順）を流用し、常駐の仕組みは OS 標準の launchd に任せる。新しく書くのは約120行のシェルスクリプトと導入スクリプトだけにとどめ、車輪の再発明はしない。

## 3. 構成

```
launchd (LaunchAgent, ユーザー権限, 30秒ごと)
  └─ cafe-wifi-okawari.sh
       1. HTTP  captive.apple.com  … 3状態に分ける
            200+Success → 認証済み（失敗記録を消して終了）。直前に捕捉されていた接続先と同じなら、
                          「利用者が自分で同意した接続先」として記録する（consent recorded）
            200(Success なし) / 301・302・303・307 → ポータルに捕捉 → 2へ
            通信失敗・それ以外のステータス（4xx/5xx 等）→ 判定不能として何もしない
       2. 接続先（既定ゲートウェイの MAC。取れなければ IP）を求める
            自分で同意した記録がない接続先 → 同意は送らずに保留として記録し、終了
              初めて保留にしたときだけ 3 の判定を1回行い、Wi2 なら「最初の1回は自分で同意して」と通知
              同じ接続先で保留中なら、通信もせずに終了
       3. 同じ接続先で連続失敗中なら、待機時間（30秒→60秒→…→最大30分）が過ぎるまで終了。
            接続先が変わっていれば前の待機状態は捨てる
       4. HTTPS service.wi2.ne.jp/wi2auth/redirect
            302 かつ Location が https://service.wi2.ne.jp/freewifi/<店舗>/landing.html、
            かつ session_id を受け取ったときだけ 5へ
            通信失敗（タイムアウト等）・5xx → 障害として失敗扱い（redirect failed。通知なし）
            session_id がない → 失敗扱い（redirect failed。通知あり）
            それ以外の応答 → 対象外の網として何もせず終了
       5. HTTPS service.wi2.ne.jp/wi2auth/xhr/login (onetap agree)
       6. 2秒後に 1 を再判定。API 結果（JSON の result が真偽値 true なら api=ok）と
            疎通回復（probe=ok/ng）を分けて記録
            両方 ok のときだけ成功。それ以外は失敗回数を増やし、次の試行を遅らせる
            疎通も戻っていない（probe=ng）ときは、失敗が続く間に1回だけ macOS の通知を出す
```

| ファイル | 役割 |
|---|---|
| `cafe-wifi-okawari.sh` | 検知と再認証（唯一のロジック）。導入先は `~/.local/bin/cafe-wifi-okawari`。API 応答の判定に macOS 標準の `/usr/bin/jq` を使う |
| `install.sh` | 導入・更新・削除。LaunchAgent の plist を `$HOME` に合わせて `plutil` で生成する（リポジトリに絶対パスを持たない。パスに `&` などがあっても壊れない）。`bootout` 直後の `bootstrap` の一時失敗は最大10回やり直す |
| `test/run.sh` | 模擬の curl・route・arp・osascript・launchctl による分岐試験。GitHub Actions（macOS）で push ごとに実行 |
| `~/Library/LaunchAgents/local.cafe-wifi-okawari.plist` | LaunchAgent 定義（`install.sh` が生成） |
| `~/Library/Logs/cafe-wifi-okawari.log` | 同意の記録と、再認証の成功・失敗だけを記録（通常時は何も書かない） |
| `~/Library/Caches/cafe-wifi-okawari` | 連続失敗回数・次回試行時刻・接続先（1行）。成功時・認証済み時に削除 |
| `~/Library/Caches/cafe-wifi-okawari.pending` | 捕捉されているが、まだ自分で同意していない接続先（1行）。認証済みを確認したら削除 |
| `~/Library/Application Support/cafe-wifi-okawari/consented` | 利用者が自分で同意した接続先（1行1つ）。ここにある接続先だけ自動で再認証する。削除時に消す |

## 4. 安全性

- **秘密情報を扱わない**: Wi2 のワンタップ認証は「規約に同意」するだけなので、ID やパスワードを保存しない。Keychain も設定ファイルも不要。保存するのは、自分で同意した店のルーターの MAC アドレスだけ（外部には送らない）
- **最小権限**: root ではなくユーザーの LaunchAgent として動く。sudo は不要
- **通信先を固定**: 認証リクエストはコードに書いた `service.wi2.ne.jp` にだけ送る。`--proto '=https'` で HTTPS 以外を拒否し、証明書検証は有効（`-k` は使わない）。リダイレクトは追従しない。ポータルが返す URL や内容を信用して動くことはない
- **curl の実行条件を固定**: `/usr/bin/curl -q` で呼ぶ。`-q`（先頭引数必須）で `~/.curlrc` を読まないため、そこに `insecure` や `location` があっても上記の前提は崩れない。PATH 上の別の curl も使わない
- **対象網の判定**: ポータルに捕捉されていて、かつ TLS 検証済みの Wi2 サーバーが無料 Wi‑Fi のランディングへ 302 を返したときだけ同意を送る。HTTP 障害（4xx/5xx）や別の場所への 302 では送らない。ただし、Wi2 以外の網でこのサーバーに届いた場合の応答は未確認（§7）。届いたとしても、送るのは Wi2 への同意フラグだけ
- **偽アクセスポイント（evil twin）について**: TLS が保証するのは「通信相手が正規の `service.wi2.ne.jp` であること」で、AP が正規であることではない。偽 AP が正規サーバーへの通信をそのまま中継すれば、本ツールは普通に認証を行う。この場合も同意フラグは TLS で正規サーバーにだけ届き、秘密情報は持っていないため、本ツールから漏れるものはない。偽 AP による盗聴や改ざんから自分の通信を守ることは、本ツールの範囲外（下記の VPN など）
- **平文 HTTP のプローブ**: 「認証済みかどうか」の判定にだけ使い、その内容で動作を変えることはない
- **通知**: 文言は固定（日本語と英語。macOS の優先言語で選ぶ）。ポータルの応答などの外部入力は通知に含めない（AppleScript への文字列注入を防ぐ）
- **一時ファイル**: Cookie は `mktemp`（ユーザー専用 0600）に保存し、終了時に `trap` で削除する
- **利用規約**: ドトール等は再接続が無制限と明示されている。回数や合計時間に上限がある網（ルノアールの1日3時間など）で上限に達したときは、API が拒否して失敗扱いになり、待機時間の延長で自然に止まる（通知は1回だけ）。時間制限の回避、MAC アドレス偽装、多重セッションはしない
- **初回の同意は利用者自身が行う**: 本ツールが同意を送るのは、利用者がその店で一度自分で同意したことを確認できた接続先だけ（§3 の 1・2）。初めての店で規約を読まずに同意してしまうことはない。利用者の同意後、本ツールが捕捉を見ていなかった場合（30秒以内に同意した等）は記録されず、最初の時間切れで通知が出て、もう1回だけ自分で同意することになる
- 公衆 Wi‑Fi は暗号化されていない。通信内容の保護は本ツールの範囲外で、HTTPS や VPN で守る

## 5. パフォーマンス

- 通常時の処理はプローブ1回だけ（同意待ちの接続先で捕捉中も同じ）（実測 約0.1秒、応答69B、CPU 約10ms、RSS 約5.6MB）。30秒ごとでも1日あたり約1.4MB、CPU 約30秒
- `ProcessType=Background` で低優先度・省電力のスケジューリングにする。スリープ中は動かず、復帰後の最初の周期で自動的に判定する
- 切断に気づくまで最大30秒（+ 再認証に約2〜3秒）。間隔を短くするより、この程度で十分と判断した
- **継続障害時**: 失敗（認証 API の失敗に加え、`/wi2auth/redirect` の通信失敗・5xx も含む）のたびに次の試行を 30秒→60秒→…→最大30分 と遅らせる（状態は1行のファイルだけ）。待機状態は接続先ごとで、別の店に移ればすぐに試す。認証 API の呼び出しは最大でも1日約48回。ログは同じ失敗の 1・2・4・8… 回目だけ書き、1日あたり数行に収まる。通知は失敗が続く間に1回だけ。認証済みを確認したら状態を消し、次の時間切れからは再び即座に反応する

## 6. 導入・停止

```sh
./install.sh             # 導入・更新（スクリプトを複製し、plist を生成して登録）
./install.sh uninstall   # 停止・削除（同意の記録も消す。ログは残す）
```

スクリプトは `~/.local/bin` へ複製して登録するので、導入後にリポジトリを移動・削除しても動き続ける。利用者向けの説明は README.md（英語）と README.ja.md（日本語）。通知と `install.sh` のメッセージは macOS の優先言語（`defaults read -g AppleLanguages` の先頭）が日本語なら日本語、それ以外は英語。

## 7. 検証

| 確認項目 | 結果 |
|---|---|
| 構文（`zsh -n`・`plutil -lint`・通知の `osacompile`） | OK |
| 模擬試験 `zsh test/run.sh`（下記、37項目） | OK。GitHub Actions でも実行 |
| 試験が不具合を検出できるか（通知回数・同意の確認・JSON 判定・再登録のやり直しを、わざと壊して実行） | すべて NG として検出 |
| LaunchAgent から通知が実際に表示されるか | 未確認。初回の通知で「スクリプトエディタ」の通知許可を求められる可能性がある |
| Wi2 API に curl から認証できるか | OK（`AUTHENTICATED`） |
| **実際の時間切れ時**に自動で再認証されるか | 未確認。店で自分で同意したあと `consent recorded` がログに出ることを確かめ、60分以内に `re-authenticated api=ok probe=ok` が出るかを見る。`api=ng probe=ok` なら OS のポータル画面など、別の経路で復旧したことを意味する |
| 時間切れ時に Wi2 が接続を切るか（切る場合、OS のポータル画面が本ツールと同時に動く） | 未確認。上と同時に見る |
| 実際の店でゲートウェイの MAC が取れるか | 未確認。`~/Library/Application Support/cafe-wifi-okawari/consented` に MAC 形式（`xx:xx:…`）で記録されているかを見る |
| 実際の `launchctl` で再導入が成功するか（bootout 直後の bootstrap） | 未確認。再試行で吸収する作り |
| ドトール以外の Wi2 店舗（スタバ等）で動くか | 未確認（JS 上は同じ API、§1.1）。現地でログを確認する |
| Wi2 以外の網で `/wi2auth/redirect` がどう応答するか | 未確認。別の網につないだ際に `curl -q -s -o /dev/null -w '%{http_code} %{redirect_url}' https://service.wi2.ne.jp/wi2auth/redirect` で確かめる |

`test/run.sh` で確認している分岐:

| 状況 | 結果 |
|---|---|
| プローブ 200+Success / 通信失敗 | 何もしない（POST なし） |
| 初めての接続先で Wi2 に捕捉 | POST なし。保留に記録し、「最初の1回は自分で同意」を1回通知 |
| 保留中の再実行 | 通信なし・通知なし |
| 保留中の接続先で認証済みになる（利用者が同意） | 同意済みとして記録（`consent recorded`） |
| 同意済みの接続先で時間切れ | `re-authenticated api=ok probe=ok` |
| 初めての接続先で Wi2 以外の網 | POST なし・通知なし |
| 捕捉を見ていない、または別の接続先で認証済み | 同意済みとして記録しない |
| API が `{"result": true}`（空白あり）・プローブ回復 | `re-authenticated api=ok probe=ok` |
| API が `{"result":"true"}`（文字列）や HTML | `api=ng` |
| API `result:false`・その後プローブ回復 | `login failed x1 api=ng probe=ok`、通知なし |
| 9回連続失敗 | 待機時間は 30→…→1800秒で頭打ち。ログは x1・x2・x4・x8、通知は1回だけ |
| 失敗直後の再実行 | 待機中のため通信なし |
| 失敗して待機中に、同意済みの別の接続先へ移動 | 待機を持ち越さず、すぐに POST して成功 |
| 旧形式（2項目）の状態ファイル | 待機を持ち越さず動く |
| 同意済みの接続先で redirect がタイムアウト / 503 | POST なし。`redirect failed x1 …` を記録し待機。通知なし |
| redirect は正しい 302 だが session_id なし | POST なし。通知1回 |
| 同意済みの接続先で redirect が別ホストへの 302 | 何もしない（記録なし） |
| `install.sh`: HOME に `&`・`<`・`>` | 正しい plist を生成し、パスも正しい |
| `install.sh`: bootstrap が2回失敗 | やり直して成功。失敗が続けば 0 以外で終わる |
| `install.sh`: 再導入・引数誤り・削除 | 成功 / 2 で終了 / ログ以外は残らない |
| 優先言語が日本語 / 英語 | 通知と `install.sh` のメッセージがそれぞれの言語になる |

## 8. やらないこと（YAGNI）

- Wi2 以外のポータルへの対応、汎用のフォーム解析、プラグイン機構
  → 別のカフェ（次の候補はコメダ）で必要になり、現地で通信を確かめた時点で、`state` の直後に `case` の分岐を1つ足す
- アンケート・会員登録・メール登録が必要なポータル（§1.1 の対象外）
- 時間切れ前の先回り再認証（検知方式で十分）
- 設定ファイル、メニューバー UI、成功時の通知、ログのローテーション（正常時は1時間に1行、継続障害時も1日数行）
- macOS 標準のポータル画面（Captive Network Assistant）の無効化。これは全ネットワークに影響するので触らない
