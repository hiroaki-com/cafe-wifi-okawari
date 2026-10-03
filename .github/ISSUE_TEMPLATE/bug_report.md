---
name: 不具合報告 / Bug report
about: 公開できる情報だけで症状を報告する / Report a problem without private data
title: ''
labels: ''
assignees: ''
---

このIssueは公開されます。日本語・英語のどちらでも記入できます。不明な項目は「不明」で構いません。
This issue is public. Japanese or English is welcome; write “unknown” for anything you cannot tell.

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

### 操作と症状 / Steps and symptoms

店舗・日時を含めず、操作の順番、期待した結果、実際の結果を書いてください。
Describe the steps, expected result, and actual result without shop details or dates/times.

### 発生する場面 / When it happens

導入、初回の同意、時間切れ、スリープ復帰、Wi-Fiのつなぎ直し、更新、削除など。試した回数と再現した回数も分かれば記入してください。
For example: installation, first acceptance, time-out, waking from sleep, rejoining Wi-Fi, update, or uninstall. Include attempts and occurrences if known.

### エラーの種類（任意） / Error category (optional)

READMEのログ一覧にある種類（例: `probe failed`）と数値の `curl`・`http` コードだけを書いてください。行全体や応答本文は貼り付けないでください。
Use only a category from the README log reference (e.g. `probe failed`) and numeric `curl` / `http` codes. Do not paste whole lines or response bodies.

### 投稿前の確認 / Before posting

- [ ] 本文・タイトルに上記の非公開情報を含めず、添付もしていません。 / I have excluded the private information listed above from the body, title, and attachments.
