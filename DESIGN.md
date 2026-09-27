# cafe-wifi-okawari 設計

公衆 Wi‑Fi のキャプティブポータルで時間切れ（30分・60分など）により認証画面へ戻されたとき、自動で再認証する macOS 常駐ツール。

## 1. 要件と対象

| 項目 | 内容 |
|---|---|
| 対象 PC | macOS 27.0 / Apple Silicon (arm64)。追加依存なし（`/bin/zsh`・`/usr/bin/curl`・`/usr/bin/jq`・launchd など OS 標準のみ） |
| 対象 Wi‑Fi | ドトール「DOUTOR FREE Wi-Fi」= Wi2（Wire and Wireless, AS131160）。暗号化なし、1回60分。回数について、店頭の案内は日本語が「60分経過後は再認証で接続可能」、英語が「60min three times per day」で食い違う（[案内 PDF](https://www.doutor.co.jp/dcs/service/images/doutor_free_wi-fi.pdf)、<date omitted> 確認）。本ツールは回数を数えない |
| 時間制限 | 固定タイマーを持たず「ポータルに戻されたこと」を検知して再認証する。そのため30分・60分など任意の制限時間にそのまま対応する |
| 同一方式 | スタバ・タリーズ・すかいらーく・ルノアールも同じ Wi2 ワンタップ認証（§1.1）。同じコードで動く見込み |
| 前提 | 規約に同意するだけで使える網に限る。ID・パスワード・メールアドレスは扱わない。OSS として公開する |

### 現地調査の結果（<date omitted>、ドトール店内で実測）

- `https://service.wi2.ne.jp/wi2auth/redirect` → 302 で `/freewifi/doutor/landing.html` へ。`session_id` Cookie（Max-Age=3600）を発行。**このときの認証状態は記録していない**（<date omitted> の試験で、認証済みのときだけの応答だと分かった。下記）
- ポータルの `login-min.js` で使われている認証 API:
  `POST /wi2auth/xhr/login`、`Content-Type: application/json`、
  本文 `{"login_method":"onetap","login_params":{"agree":"1"}}`
- curl から実行した結果 `{"result":true,"licensed":null,"message":"AUTHENTICATED"}`。ブラウザがなくても認証できる

### 現地試験の結果（<date omitted>、ドトール店内。導入済みの版は 47f2d01）

| 時刻 | 出来事 |
|---|---|
| <time omitted> | Wi‑Fi に接続し、利用者が接続画面で同意。本ツールは捕捉を見られず、`consent recorded` は出なかった（下記の「接続直後は見えない」） |
| <time omitted> | 1回目の時間切れで捕捉（同意から約63分）。本ツールは同意待ちとして保留に記録 |
| <time omitted> | 利用者がコントロールセンターから Wi‑Fi を切断（システムログに `user-requested disconnect`）。当初「時間切れの約80秒後に Wi2 が切った」と誤認していた |
| <time omitted>〜26 | 利用者が接続し直して接続画面で同意 → `consent recorded`（捕捉を見たあとの同意なので記録できた） |
| <time omitted> | 2回目の時間切れで捕捉。**自動の再認証は動かず、ログにも何も残らなかった**（下記の「原因」） |
| <time omitted> | 利用者が iPhone のテザリングに切り替えた |
| <time omitted> | 捕捉中の応答を実測（下記） |
| <time omitted>〜57 | Doutor に接続し直す → macOS が `interface rank Never (cached captive network)` → 接続画面で同意 → `Online (websheet: success)`。`resolv.conf` の更新時刻も <time omitted> |
| <time omitted>〜28 | 認証済みのまま応答を実測し、修正版を一時フォルダで実行して `consent recorded … doutor (online)` を確認 |

**原因（自動の再認証が動かなかった）**: 捕捉中に引数なしの `/wi2auth/redirect` を呼ぶと、`302 /wi2auth/error/ctrlapi_timeout.html` が返る。47f2d01 はこれを「対象外の網」と判定し、何も記録せずに終了していた。初期調査時の実測は認証済みのときのもので、模擬試験もその応答を前提にしていたため、試験がすべて通っても実網での保証になっていなかった。想定外の応答を黙って捨てる作りだったため、失敗の跡も残らなかった。

実測した応答（`mac`・`ip` は Wi2 が見ているこの Mac の値。ログには残さない）:

| 状態 | 要求 | 応答 |
|---|---|---|
| 捕捉中 | `http://captive.apple.com/hotspot-detect.html` | `302 https://service.wi2.ne.jp/wi2auth/redirect?cmd=login&mac=<MAC>&ip=<IP>&essid=%20&apname=<AP>&apgroup=&url=…` |
| 捕捉中 | 引数なしの `/wi2auth/redirect` | `302 /wi2auth/error/ctrlapi_timeout.html` |
| 認証済み | 引数なしの `/wi2auth/redirect` | `302 /freewifi/doutor/landing.html` ＋ `session_id` |
| 認証済み | 上の `redirect?cmd=login&mac=…&ip=…`（自分の MAC・IP） | `302 /freewifi/doutor/landing.html` ＋ `session_id` |
| 認証済み | DHCP（`ipconfig getpacket en0`） | `domain_name: wi2.ne.jp`、DNS `103.5.140.1/2`、リース300秒 |

- **接続直後は見えない**: macOS は一度つないだことのある認証画面つきの網に接続すると、接続画面（Captive Network Assistant。ブラウザではなく単体のウィンドウ）で同意が済むまで、その網を他のアプリに使わせない（`interface rank Never`）。既定経路も DNS もないので、本ツールからは「無接続」に見え、接続直後の捕捉は観測できない。そのため「捕捉 → 回復」を見て同意を記録する方式では、入店時の同意を記録できない。同意後に `resolv.conf` が書き換わる
- **時間切れのあと**: macOS は網を使わせたまま（rank を戻さない）なので、捕捉は本ツールから見える。接続画面は自動では開かない
- **Wi2 は時間切れで Wi‑Fi を切らない**: <time omitted> と <time omitted> の切断は、どちらも利用者の操作だった

**修正（<date omitted>）**: 捕捉中は captive.apple.com の転送先（`redirect?cmd=login&mac=…&ip=…`）をたどる（§3 の 4）。入店時の同意は、Wi2 の網（DHCP のドメイン名）で本ツールが何も送っていないのに通信できていることから記録する（§3 の 1）。想定外の応答はログに残す。捕捉中に転送先をたどって認証できるかは、次の現地試験で確かめる（§7）。

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

**判断**: 汎用ツールはどれも Wi2 の XHR 認証に合わないか、依存や権限が過剰。そこで既存の知見（Wi2 の API 手順）を流用し、常駐の仕組みは OS 標準の launchd に任せる。新しく書くのは約200行のシェルスクリプトと導入スクリプトだけにとどめ、車輪の再発明はしない。

## 3. 構成

```
launchd (LaunchAgent, ユーザー権限, 30秒ごと ＋ resolv.conf が書き換わったとき)
  └─ cafe-wifi-okawari.sh
       0. 接続先（既定ゲートウェイの MAC。取れなければ IP）とインターフェースを手元で求める（通信しない）
            既定経路がない（macOS が接続画面での同意を待っている）→ 何もせず終了
            DHCP のドメイン名が wi2.ne.jp（Wi2 の網）でも、同意済みの MAC でも、同意待ちでもなく、
            接続から5分以上経っている → 何も通信せず終了（自宅など関係のない網では、確認の通信をしない）
       1. HTTP  captive.apple.com  … 3状態に分ける
            200+Success → 認証済み。失敗記録を消す。
                 a. 直前に捕捉されていた接続先（保留）と同じなら、「利用者が自分で同意した接続先」として記録（consent recorded）
                 b. Wi2 の網で、この接続先のブランドをまだ確かめていなければ、引数なしの /wi2auth/redirect で
                    ランディング（/freewifi/<ブランド>/landing.html）を確かめ、「MAC ブランド」を記録する
                    （consent recorded … (online)）。本ツールは記録していない接続先に同意を送らないので、
                    通信できている = 利用者が接続画面で同意した。確かめるのは接続先ごとに1回（失敗したら3回まで）
            200(Success なし) / 301・302・303・307 → ポータルに捕捉 → 2へ（転送先 Location を控える）
            通信失敗・それ以外のステータス（4xx/5xx 等）→ 判定不能として何もしない
       2. 同意待ちの接続先なら通信せずに終了。捕捉が2回続いたときだけ「最初の1回は自分で同意して」とダイアログで1回知らせる
       3. 同じ接続先で連続失敗中なら、待機時間（30秒→60秒→…→最大30分）が過ぎるまで終了。
            接続先が変わった、または接続し直した（resolv.conf が失敗記録より新しい）ときは待機状態を捨てる
       4. 転送先が https://service.wi2.ne.jp/wi2auth/redirect? で始まるときだけ Wi2 に問い合わせる
            それ以外（ホテルなど別のポータル）→ Wi2 の網か同意済みの MAC なら portal unknown を記録。何も送らない
            転送先の mac・ip がこの Mac のもの（ifconfig の ether と ipconfig の IP）と違う → portal mismatch。送らない
            転送先を HTTPS でたどる（/wi2auth/ 内の 302 は3回まで。error ページは除く）。
            302 かつ Location が https://service.wi2.ne.jp/freewifi/<ブランド>/landing.html（クエリ可）なら、
            「MAC ブランド」が同意済みか照合する。
              同意済みでない → 同意は送らずに保留として記録し（consent pending）、終了
            同意済みで、かつ session_id を受け取ったときだけ 5へ
            通信失敗（タイムアウト等）・5xx → 障害として失敗扱い（redirect failed。通知なし）
            それ以外の応答（エラーページ・Wi2 の外への転送など）→ 失敗扱い（redirect failed … to=<パス>。同意済みの MAC なら通知）
            session_id がない → 失敗扱い（redirect failed。通知あり）
       5. HTTPS service.wi2.ne.jp/wi2auth/xhr/login (onetap agree)。ランディングの XHR と同じく Origin と Referer を付ける
       6. 2秒ごとに最大10秒、1 を再判定。API 結果（JSON の result が真偽値 true なら api=ok）と
            疎通回復（probe=ok/ng）を分けて記録
            両方 ok のときだけ成功（re-authenticated … t=<秒>）。それ以外は失敗回数を増やし、次の試行を遅らせる
            疎通も戻っていない（probe=ng）ときは、失敗が続く間に1回だけダイアログで知らせる
            サーバーが応答した（通信成功・HTTP 1xx〜4xx）のに api=ng かつ probe=ng を「拒否」と数え、
            同じ接続先で3回続いたら、その接続先を同意済みから外して自動の再同意をやめる（auto stopped。通知あり）。
            保留（notified）に戻すので、利用者が接続画面で自分で同意し直せば、初回と同じく記録して再開する。
            拒否の回数は成功と接続先の変更で数え直す（つなぎ直しでは数え直さない）
```

ログの URL は、クエリ（端末の MAC・IP が入る）を除いたホストとパスだけを書く。失敗は種類ごとに 1・2・4・8… 回目だけ書く。

| ファイル | 役割 |
|---|---|
| `cafe-wifi-okawari.sh` | 検知と再認証（唯一のロジック）。導入先は `~/.local/bin/cafe-wifi-okawari`。API 応答の判定に macOS 標準の `/usr/bin/jq` を使う |
| `install.sh` | 導入・更新・削除。`StartInterval=30` に加え、`WatchPaths=/var/run/resolv.conf` で DNS の設定が変わったときにも起動する（接続画面で同意して通信できるようになった時刻に書き換わるので、同意の直後に記録できる）。LaunchAgent の plist を `$HOME` に合わせて `plutil` で生成する（リポジトリに絶対パスを持たない。パスに `&` などがあっても壊れない）。`bootout` 直後の `bootstrap` の一時失敗は最大10回やり直す |
| `test/run.sh` | 模擬の curl・route・arp・ipconfig・ifconfig・osascript・launchctl による分岐試験。GitHub Actions（macOS）で push ごとに実行 |
| `~/Library/LaunchAgents/local.cafe-wifi-okawari.plist` | LaunchAgent 定義（`install.sh` が生成） |
| `~/Library/Logs/cafe-wifi-okawari.log` | 同意の記録・保留と、再認証の成功・失敗・想定外の応答だけを記録（通常時は何も書かない） |
| `~/Library/Caches/cafe-wifi-okawari` | 連続失敗回数・次回試行時刻・接続先・連続した拒否の回数（1行）。成功時・認証済み時・自動を止めたときに削除 |
| `~/Library/Caches/cafe-wifi-okawari.pending` | 捕捉されているが、まだ自分で同意していない接続先「MAC ブランド [notified]」（1行）。認証済みを確認したら削除 |
| `~/Library/Caches/cafe-wifi-okawari.seen` | 認証済みの状態でブランドを確かめた最後の接続先「MAC 回数」（1行）。同じ接続先で確かめ直さないため |
| `~/Library/Application Support/cafe-wifi-okawari/consented` | 利用者が自分で同意した接続先「MAC ブランド」（1行1つ）。ここにある接続先だけ自動で再認証する。削除時に消す |

## 4. 安全性

- **秘密情報を扱わない**: Wi2 のワンタップ認証は「規約に同意」するだけなので、ID やパスワードを保存しない。Keychain も設定ファイルも不要。保存するのは、自分で同意した店のルーターの MAC アドレスとブランド名だけ（外部には送らない）
- **最小権限**: root ではなくユーザーの LaunchAgent として動く。sudo は不要
- **通信先を固定**: 認証リクエストはコードに書いた `service.wi2.ne.jp` にだけ送る。`--proto '=https'` で HTTPS 以外を拒否し、証明書検証は有効（`-k` は使わない）。curl にリダイレクトを追従させず、本ツールが Location を調べて `https://service.wi2.ne.jp/wi2auth/` 内の転送だけを3回までたどる
- **curl の実行条件を固定**: `/usr/bin/curl -q` で呼ぶ。`-q`（先頭引数必須）で `~/.curlrc` を読まないため、そこに `insecure` や `location` があっても上記の前提は崩れない。PATH 上の別の curl も使わない
- **対象網の判定**: captive.apple.com が `https://service.wi2.ne.jp/wi2auth/redirect?` へ転送し、かつ TLS 検証済みの Wi2 サーバーが無料 Wi‑Fi のランディングへ 302 を返したときだけ同意を送る。それ以外のポータルには、Wi2 にも何も送らない。認証済みの状態で Wi2 に問い合わせる（ブランドの確認）のは、DHCP のドメイン名が `wi2.ne.jp` の網だけ。ドメイン名は網が配る値なので偽れるが、偽っても本ツールが Wi2 に1回問い合わせるだけ
- **転送先の URL は平文 HTTP の応答**: captive.apple.com への問い合わせは平文なので、同じ網の第三者が偽の転送先を返せる。転送先はホスト・パスを固定の文字列と照合し、HTTPS（証明書検証あり）でしかたどらないので、Wi2 以外へは送らない。ただしクエリの `mac`・`ip` は第三者が自由に書けるので、他人の端末の値を入れられると、本ツールがその端末の同意を送ってしまう。これを防ぐため、`mac`・`ip` がこの Mac のもの（`ifconfig` の ether と `ipconfig getifaddr`）と一致するときだけたどる（portal mismatch）。MAC は大文字小文字・区切り・先頭の 0 の違いを吸収して比べる
- **偽アクセスポイント（evil twin）について**: TLS が保証するのは「通信相手が正規の `service.wi2.ne.jp` であること」で、AP が正規であることではない。偽 AP が正規サーバーへの通信をそのまま中継すれば、本ツールは普通に認証を行う。この場合も同意フラグは TLS で正規サーバーにだけ届き、秘密情報は持っていないため、本ツールから漏れるものはない。偽 AP による盗聴や改ざんから自分の通信を守ることは、本ツールの範囲外（下記の VPN など）
- **平文 HTTP のプローブ**: 「認証済みかどうか」の判定と、上の転送先の取得に使う。応答本文の内容で動作を変えることはない
- **知らせ方**: `display alert … giving up after 120`（2分で自動的に閉じるダイアログ）。LaunchAgent からの `display notification` は表示されないため（§7）。ダイアログが開いている間（最大2分）は処理が止まるが、知らせるのは失敗や同意待ちのときだけなので支障はない。文言は固定（日本語と英語。macOS の優先言語で選ぶ）。ポータルの応答などの外部入力は含めない（AppleScript への文字列注入を防ぐ）。osascript の出力（`button returned:…`）はログに書かない
- **一時ファイル**: Cookie は `mktemp`（ユーザー専用 0600）に保存し、終了時に `trap` で削除する
- **利用規約**: サーバー側の利用時間・回数の制限を解除する機能はない。MAC アドレス偽装、多重セッションもしない。回数や合計時間に上限がある網（ルノアールの1日3時間など）で上限に達したときや、利用停止されたときは、API が拒否すると考えられる。拒否が3回続いたら、その接続先の自動の再同意をやめる（§3 の 6）。一時的な障害とは区別できないので、回数で判断する。規約との関係は下記
- **接続先の見分け方**: ルーターの MAC だけでは足りない。ドトールで実測したゲートウェイの MAC は `<gateway-mac>`（VRRP の仮想 MAC）で、店やブランドをまたいで同じ値になりうる。規約本体は Wi2 共通だが、画面や利用条件（時間・回数）はブランドごとに違うので、Wi2 のランディング URL `/freewifi/<ブランド>/landing.html` のブランド名と組にして記録する。ブランド名が英数字・`_`・`-` 以外を含むときは対象外とする
- **初回の同意は利用者自身が行う**: 本ツールが同意を送るのは、利用者がその店で一度自分で同意したと推定できた接続先だけ（§3 の 1・2・4）。推定の根拠は2つ。(a) 本ツールが捕捉を見た接続先で、その後に通信が戻った。(b) Wi2 の網で、本ツールが何も送っていないのに通信できている（macOS は接続画面で同意するまで網を使わせず、本ツールは記録していない接続先に同意を送らない。Wi2 の認証は端末の MAC ごと）。入店時の同意は (b)、時間切れで初めて捕捉を見た網は (a) で記録する。初めての店で規約を読まずに同意してしまうことはない。(b) は DHCP のドメイン名で Wi2 の網を見分けるので、ドメイン名が違う Wi2 の網では記録されず、最初の時間切れでもう1回だけ自分で同意することになる
- 公衆 Wi‑Fi は暗号化されていない。通信内容の保護は本ツールの範囲外で、HTTPS や VPN で守る

### 規約・法令との関係（<date omitted> 確認。弁護士による確認ではない）

[Wi2 フリーWi-Fiサービス利用規約](https://wi2.co.jp/rules/free-wifi.html)（最新改定 2025-12-17）と本ツールの動作を突き合わせた結果。

| 条項 | 内容 | 本ツールとの関係 |
|---|---|---|
| 第2条・第17条 | 同意した時点で利用契約が成立する。接続を終えて設定時間が過ぎると契約は終わり、再び使うには第2条の申込みがもう一度必要 | 時間切れのたびの再同意は、新しい申込み。本ツールは、この申込み（同意の意思表示）を利用者に代わって送る |
| 第9条17号 | 利用開始に必要な手続きを、当社の許可なく回避して利用し、または利用させる行為の禁止 | **主な論点**。同意の送信は省かず、接続画面の JS と同じ要求を送る。ただし規約画面とお知らせ（第16条）を表示しない。「画面を経ること」が手続きに含まれるかは規約から読めず、該当しないとは断定できない。自動の再同意について Wi2 の許諾は得ていない |
| 第16条 | ログインの過程の画面などに、イベント情報等を表示できる | 本ツールによる再同意では表示されない |
| 第8条・第9条（15号・19号） | 支障を来たす行為・当社が不適切と判断する行為の禁止。利用の停止・制限がありうる | 通信は小さい（§5）が、19号は Wi2 の判断による。停止されたときに試し続けないよう、拒否が続いたら自動をやめる |
| 第1条2項 | 民法548条の4に基づき規約を変更できる | 本ツールは規約の変更を検知しない（README で利用者に確認を求める） |

- **不正アクセス禁止法**: アクセス制御機能は識別符号（ID・パスワードなど）で利用を制限する機能（第2条3項）。ワンタップ認証は識別符号を使わず、本ツールも識別符号や制限を免れる情報を入力しないため、該当は想定しにくい
- **電子計算機損壊等業務妨害（刑法234条の2）**: 通常の要求を、利用者が手で行うのと同じ頻度（時間切れごとに1回、失敗時は最大30分間隔）で送るだけで、想定しにくい
- **免責の書き方**: README に「すべて自己責任」「一切責任を負わない」のような全面免責は書かない。README だけでは合意の成立も免責の有効性も保証できず、消費者契約に当たる場合は[消費者契約法](https://laws.e-gov.go.jp/law/412AC0000000061)8条・10条の制限もある。無保証は LICENSE（MIT）の範囲に留める
- **README の方針**: 使える条件、自動化の内容（規約画面を表示せずに同意を再送すること）、止めるべき状況、実装の限界を具体的に書く。自動操作の扱いが不明なら、提供者に確認できるまで通常の接続方法を使うよう求める
- **README では防げないこと**: 同意の誤推定（接続の状態から推定する）、規約変更の見落とし、同じブランドの別の店での初回同意の省略（VRRP の MAC が重なる場合）。拒否後に試し続けることは、上記の自動停止で防ぐ。Wi2 への方式の確認と規約変更の検知は未対応

## 5. パフォーマンス

- 関係のない網（Wi2 のドメイン名でも、同意済みの MAC でも同意待ちでもなく、接続から5分以上経過）では、route・arp・ipconfig で手元の情報を見るだけで通信しない（実測 約0.01秒）。自宅などで Apple のサーバーに30秒ごとに問い合わせることはない
- Wi2 の店にいるときの処理はプローブ1回だけ（実測 約0.07〜0.1秒、応答69B、CPU 約10ms、RSS 約5.6MB）。30秒ごとでも1時間あたり約60KB。ブランドの確認（Wi2 への問い合わせ、実測 約0.46秒）は接続先ごとに1回
- 間隔の30秒は、切断から復旧までの最大時間そのもの。10秒にすると起動が3倍になるのに対し、短縮は20秒だけ。60秒以上だと作業中に切れていることが体感でわかる。1回の処理は CPU をほとんど使わないので、間隔を延ばしても省電力の効果は小さい
- `WatchPaths` で `resolv.conf` が書き換わったときにも起動する。接続画面で同意して通信できるようになった時刻（システムログの `Online (websheet: success)`）に書き換わることを実測で確認したので、入店時の同意をすぐに記録できる
- `ProcessType=Background` で低優先度・省電力のスケジューリングにする。スリープ中は動かず、復帰後の最初の周期で自動的に判定する
- 切断に気づくまで最大30秒（+ 再認証に数秒。疎通の回復は2秒ごとに最大10秒待つ）。間隔を短くするより、この程度で十分と判断した
- **継続障害時**: 失敗（認証 API の失敗に加え、`/wi2auth/redirect` の通信失敗・5xx も含む）のたびに次の試行を 30秒→60秒→…→最大30分 と遅らせる（状態は1行のファイルだけ）。待機状態は接続先ごとで、別の店に移ればすぐに試す。認証 API の呼び出しは最大でも1日約48回。ログは同じ失敗の 1・2・4・8… 回目だけ書き、1日あたり数行に収まる。ダイアログは失敗が続く間に1回だけ（拒否が3回続いて自動をやめるときは、もう1回出す）。認証済みを確認したら状態を消し、次の時間切れからは再び即座に反応する

## 6. 導入・停止

```sh
./install.sh             # 導入・更新（スクリプトを複製し、plist を生成して登録）
./install.sh uninstall   # 停止・削除（同意の記録も消す。ログは残す）
```

スクリプトは `~/.local/bin` へ複製して登録するので、導入後にリポジトリを移動・削除しても動き続ける。利用者向けの説明は README.md（英語）と README.ja.md（日本語）。ダイアログと `install.sh` のメッセージは macOS の優先言語（`defaults read -g AppleLanguages` の先頭）が日本語なら日本語、それ以外は英語。

## 7. 検証

| 確認項目 | 結果 |
|---|---|
| 構文（`zsh -n`・`plutil -lint`・ダイアログの `osacompile`） | OK |
| 模擬試験 `zsh test/run.sh`（下記、86項目） | OK。GitHub Actions でも実行 |
| 試験が不具合を検出できるか（知らせる回数・同意の確認・JSON 判定・再登録のやり直し・通信の抑止・ブランド照合・接続し直しの判定、<date omitted> の修正分として転送先の利用・MAC と IP の照合・DHCP のドメイン名・確認の回数・Origin・疎通の待機・ランディングのクエリ・転送のたどり・ログの URL・ダイアログを、わざと壊して実行） | すべて NG として検出 |
| LaunchAgent から知らせが表示されるか | `display notification` は **NG**（<date omitted>、macOS 27）。終了コード 0 を返すが表示されず、許可も求められない（通知設定にスクリプトエディタが登録されておらず、黙って捨てられる）。LaunchAgent から実行した `display alert … giving up after 120` は表示され、利用者が OK を押せた（`button returned:OK`）→ `display alert` に切り替えた |
| Wi2 API に curl から認証できるか | OK（`AUTHENTICATED`、<date omitted>）。ただし当時の認証状態は不明 |
| 捕捉を見たあとに自分で同意したとき `consent recorded` が出るか | OK（<date omitted> <time omitted>、ドトール。§1 の現地試験） |
| 入店時に接続画面で同意したとき記録されるか | 47f2d01 では **NG**（macOS が同意まで網を使わせないため、捕捉が見えない。§1）。修正版を認証済みのドトールで一時フォルダから実行し、`consent recorded net=<gateway-mac> doutor (online)` を確認（<date omitted> <time omitted>）。導入した状態で入店から試すのは次の現地試験 |
| **実際の時間切れ時**に自動で再認証されるか | 47f2d01 では **NG**（引数なしの redirect が捕捉中は `ctrlapi_timeout` を返す。§1）。修正版は未確認。次の現地試験で `re-authenticated api=ok probe=ok` が出るかを見る。`api=ng probe=ok` なら OS の接続画面など別の経路で復旧したことを、`redirect failed … to=…`・`login failed … res=…` なら Wi2 の応答が想定と違うことを意味する |
| 捕捉中に転送先の URL（`redirect?cmd=login&mac=…&ip=…`）がランディングと `session_id` を返すか | 未確認（捕捉中は未実測）。認証済みでは返ることを確認（<date omitted> <time omitted>） |
| 転送先の `mac`・`ip` がこの Mac の値と一致するか | OK（捕捉中の転送先と `ifconfig en0` の ether・`ipconfig getifaddr en0` が一致。<date omitted>） |
| Wi2 の網の DHCP のドメイン名 | `wi2.ne.jp`（ドトール、<date omitted>）。他の Wi2 ブランドは未確認 |
| 時間切れまでの時間 | 約63分（同意 <time omitted> → 捕捉 <time omitted>）。同意した時刻から60分と見られる |
| 時間切れ時に Wi2 が接続を切るか | 切らない。<time omitted> と <time omitted> の切断は、どちらも利用者の操作（システムログで確認）。当初「約80秒で切る」と誤認していた |
| 実際の店でゲートウェイの MAC が取れるか | OK（ドトール、<date omitted>）。ただし VRRP の仮想 MAC `<gateway-mac>` だったため、ブランド名と組にして記録する作りに変えた |
| 実際の `launchctl` で再導入が成功するか（bootout 直後の bootstrap） | OK（3回続けて成功） |
| launchd が30秒ごとに起動するか | OK（6分で12回） |
| `/var/run/resolv.conf` が書き換わる時刻 | 接続画面で同意して通信できるようになった時刻（`Online (websheet: success)`）と一致（<date omitted> <time omitted>） |
| ドトール以外の Wi2 店舗（スタバ等）で動くか | 未確認（JS 上は同じ API、§1.1）。現地でログを確認する |

次の現地試験（ドトール）で見ること:

1. 入店して接続画面で同意した直後に `consent recorded net=… doutor (online)` が出る
2. 約60分後の時間切れで、30秒以内に `re-authenticated api=ok probe=ok … t=…s` が出て、通信が戻る
3. 失敗したときは、ログの `redirect failed`・`portal …`・`login failed … res=…` の内容で原因を切り分ける（黙って終わる経路は、Wi2 以外のポータルと判定不能のときだけ）

`test/run.sh` で確認している分岐:

| 状況 | 結果 |
|---|---|
| プローブ 200+Success / 通信失敗 | 何もしない（POST なし） |
| 関係のない網（接続から5分以上・同意待ちなし・Wi2 のドメイン名でない） | 一切通信しない |
| 既定経路がない（macOS が接続画面での同意を待っている） | 一切通信しない |
| 接続した直後 / Wi2 のドメイン名の網 | プローブで確かめる |
| Wi2 の網で通信できている（記録なし） | 引数なしの redirect でブランドを確かめ、`consent recorded … (online)`。同じ接続先では確かめ直さない。別の接続先へ移れば確かめる |
| 同上で、ランディング以外の応答 / 通信失敗 | 記録しない。`not free wi-fi` / `redirect failed` を記録し、3回まで確かめ直す |
| Wi2 のドメイン名でない網で通信できている | 記録しない |
| 初めての接続先で Wi2 に捕捉 | 転送先の URL をたどる。POST なし・通知なし。「MAC ブランド」を保留に記録（`consent pending`） |
| 保留中の網は接続から時間が経っても | 確かめ続ける |
| 保留中の再実行で捕捉が続いている | 通信なし（プローブのみ）。「最初の1回は自分で同意」を1回だけダイアログで知らせる（`captive.apple.com` の開き方を含む） |
| 保留中の接続先で認証済みになる（利用者が同意） | 同意済みとして記録（`consent recorded`） |
| 同意済みの接続先で時間切れ | `re-authenticated api=ok probe=ok net=… t=2s` |
| Wi2 以外のポータル（初めての網） | Wi2 に何も送らない。記録もしない |
| Wi2 以外のポータル（同意済みの網） | Wi2 に何も送らない。`portal unknown`（URL はクエリを除く） |
| 転送先が HTTP | たどらない |
| 転送先の MAC / IP が自分と違う・入っていない | 送らない。`portal mismatch mac=… ip=…` |
| 転送先の MAC が大文字・`-` 区切り・先頭の 0 なし / URL エンコード | 同じ MAC として扱い、再認証する |
| 転送先が Wi2 の中でもう1回転送する / ランディングにクエリ | たどって再認証する |
| 転送先がエラーページ（`ctrlapi_timeout`）/ Wi2 の外への 302 | POST なし。`redirect failed … to=<パス>`、同意済みなら通知。ログに端末の MAC・IP を残さない |
| 捕捉を見ていない別の網で認証済み | 同意済みとして記録しない |
| 同じ MAC で別ブランドだけ同意済み | POST なし。保留に記録 |
| ブランド名に不正な文字 | 送らない・記録しない |
| 認証要求のヘッダ | `Origin` とランディングの `Referer` を付ける |
| 疎通が数秒遅れて戻る / 10秒で戻らない | 成功（`t=6s`）/ `login failed api=ok probe=ng`、通知 |
| API が `{"result": true}`（空白あり）・プローブ回復 | `re-authenticated api=ok probe=ok` |
| API が `{"result":"true"}`（文字列）や HTML | `api=ng` |
| API `result:false`・その後プローブ回復 | `login failed x1 api=ng probe=ok`、通知なし |
| 9回連続失敗（API が 503） | 待機時間は 30→…→1800秒で頭打ち。ログは x1・x2・x4・x8、通知は1回だけ。自動は止めない |
| API が同意を拒否（`result:false`・HTTP 200・疎通なし）×3 | 2回目までは続け、3回目で同意済みから外して保留（notified）に戻す。`auto stopped` を記録し通知。以後は送らず、自分で同意し直せば再開 |
| 拒否2回 → 成功 → 拒否2回 | 止めない（成功で数え直す） |
| 拒否2回 → つなぎ直し → 拒否1回 | 止める（つなぎ直しでは数え直さない） |
| 拒否2回 → 別の同意済みの接続先で拒否1回 | 止めない（接続先ごとに数える） |
| API がタイムアウト×4 / 拒否だが疎通は回復×4 | 止めない（拒否に数えない） |
| 失敗直後の再実行 | 待機中のため通信なし |
| 失敗して待機中に、同意済みの別の接続先へ移動 | 待機を持ち越さず、すぐに POST して成功 |
| 旧形式（2項目）の状態ファイル | 待機を持ち越さず動く |
| 待機中に接続し直した（resolv.conf が新しい） | 待機を持ち越さず、すぐに POST |
| 同意していない網で redirect がタイムアウト | `redirect failed` を記録して待機。通知なし |
| 同意済みの接続先で redirect がタイムアウト / 503 | POST なし。`redirect failed x1 …` を記録し待機。通知なし |
| redirect は正しい 302 だが session_id なし | POST なし。通知1回 |
| 知らせ方 | `display alert … giving up after 120`。優先言語が英語なら英語 |
| `install.sh`: HOME に `&`・`<`・`>` | 正しい plist を生成し、パスも正しい。`WatchPaths` に `/var/run/resolv.conf` |
| `install.sh`: bootstrap が2回失敗 | やり直して成功。失敗が続けば 0 以外で終わる |
| `install.sh`: 再導入・引数誤り・削除 | 成功 / 2 で終了 / ログ以外は残らない（`.seen` も消す） |
| 優先言語が日本語 / 英語 | ダイアログと `install.sh` のメッセージがそれぞれの言語になる |

## 8. やらないこと（YAGNI）

- Wi2 以外のポータルへの対応、汎用のフォーム解析、プラグイン機構
  → 別のカフェ（次の候補はコメダ）で必要になり、現地で通信を確かめた時点で、`state` の直後に `case` の分岐を1つ足す
- アンケート・会員登録・メール登録が必要なポータル（§1.1 の対象外）
- 時間切れ前の先回り再認証（検知方式で十分）
- 設定ファイル、メニューバー UI、成功時の通知、ログのローテーション（正常時は1時間に1行、継続障害時も1日数行）
- macOS 標準のポータル画面（Captive Network Assistant）の無効化。これは全ネットワークに影響するので触らない
