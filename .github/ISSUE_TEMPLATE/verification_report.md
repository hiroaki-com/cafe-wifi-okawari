---
name: 動作報告 / Verification report
about: 確かめた範囲を報告する / Report what you actually verified
title: ''
labels: ''
assignees: ''
---

このIssueは公開されます。日本語・英語のどちらでも記入できます。未確認の項目は「未確認」のままにしてください。
This issue is public. Japanese or English is welcome. Leave untested items as “not tested.”

**ログ全文、`cafe-wifi-okawari-ctl status` の出力、画面画像、通信の記録は添付しないでください。**
MAC・IP（ゲートウェイを含む）、SSID、店舗名・所在地、来店日時・行動時刻、ユーザー名・個人のファイルパス、認証URL・Cookie・トークンを書かないでください。タイトルも同様です。
**Do not attach full logs, `cafe-wifi-okawari-ctl status` output, screenshots, or network captures.**
Do not include MAC/IP addresses (including the gateway), SSIDs, shop names/locations, visit dates or activity times, usernames/personal file paths, authentication URLs, cookies, or tokens, including in the title.

### 環境 / Environment

- macOSのバージョン / macOS version:
- CPU（Apple Silicon / Intel / 不明） / CPU (Apple Silicon / Intel / unknown):
- ツールの版（`status` の `Version` 行。Gitで導入した場合はコミットでも可。分かる場合だけ。取得日時は不要） / Tool version (the `Version` line of `status`; a commit is fine for Git installs; if known; no download date):
- メニューバーあり・なし / With or without menu bar:
- Wi2 / USEN / 不明 / unknown:
- VPN・プライベートリレーの使用有無 / VPN / Private Relay enabled:

### 確認結果 / Results

各項目を「成功 / 失敗 / 未確認」で記入してください。時間切れ後の再接続は、自分で認証画面を操作した場合と区別してください。
Use “passed / failed / not tested” for each item. Distinguish automatic reconnection after a time-out from accepting manually on the login page.

- 導入 / Installation:
- 初回の手動同意の記録 / Recording the first manual acceptance:
- 実際の時間切れ後の自動再接続（試した回数・成功回数） / Automatic reconnection after a real time-out (attempts / successes):
- メニューバーの状態表示 / Menu bar status:
- 更新 / Update:
- 削除 / Uninstall:

### 補足（任意） / Notes (optional)

店舗・日時を含めず、確認した操作や未確認の範囲を書いてください。模擬試験だけの場合は、その旨を明記してください。
Describe the operations tested and remaining gaps without shop details or dates/times. State explicitly if you ran only mock tests.

### 投稿前の確認 / Before posting

- [ ] 本文・タイトルに上記の非公開情報を含めず、添付もしていません。 / I have excluded the private information listed above from the body, title, and attachments.
