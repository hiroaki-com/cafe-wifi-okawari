# セキュリティ / Security

## 脆弱性の報告 / Reporting a vulnerability

安全上の問題は公開の Issue に書かず、[非公開の報告](https://github.com/hiroaki-com/cafe-wifi-okawari/security/advisories/new)（GitHub の Private vulnerability reporting）から送ってください。報告は作者と報告者だけが読めます。日本語・英語のどちらでも構いません。
Do not report security problems in public issues. Use [private reporting](https://github.com/hiroaki-com/cafe-wifi-okawari/security/advisories/new) (GitHub's private vulnerability reporting) instead; only you and the author can read it. Japanese or English is welcome.

対象の例 / For example:

- root（管理者）の権限で動く、または本人のホームの外にファイルを置く / The tool runs as root or writes outside your home folder
- 利用者が同意していない網に同意を送る / It sends an acceptance to a network you have not accepted yourself
- 作者のサーバーや、Apple の接続確認・Wi‑Fi の認証以外へ通信する / It talks to anything other than Apple's connectivity check and the Wi‑Fi login service
- 接続先の応答などから、ほかのコードを実行させられる / A captive portal response or another input can make it run other code
- この Mac やゲートウェイの MAC・IP をメニューに出す / The menu shows the MAC or IP address of this Mac or the gateway

再現に必要な範囲で書いてください。MAC・IP・SSID・店舗名・来店日時などは、例の値に置き換えて構いません。
Include only what is needed to reproduce the problem. You may replace MAC/IP addresses, SSIDs, shop names and visit times with made-up values.

対象は最新の Release だけです。個人で保守しているので、返信や修正の期日は約束できません。
Only the latest release is supported. The tool is maintained by one person, so there is no promised response or fix time.

## 配布物の確かめ方 / Checking the download

`.pkg` は Developer ID Installer（HKDOCS）で署名し、Apple の公証を受けています。ターミナルで確かめられます。
The `.pkg` is signed with Developer ID Installer (HKDOCS) and notarized by Apple. You can check it in Terminal:

```
pkgutil --check-signature ~/Downloads/cafe-wifi-okawari.pkg   # 1. Developer ID Installer: HKDOCS (3CL9HYSJZ8)
spctl -a -vv -t install ~/Downloads/cafe-wifi-okawari.pkg     # source=Notarized Developer ID
```

SHA-256 は Release のノートに載せています。 / The SHA-256 is listed in the release notes.
