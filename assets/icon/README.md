# 採用アイコン

2026-09-30 採用：「現行アイコン寄り」のカップ ＋ 「① やや太め」の湯気。
Wi-Fi に見立てた2本の湯気と、外側の線の先端の矢印で「おかわり」を表現する。
カップ本体・飲み口・小さな持ち手・受け皿の形は確定。

| ファイル | 用途 |
| --- | --- |
| `source.png` | 採用した生成画像の原本（1254 × 1254 px）。加工せず保管 |
| `icon.png` | 余白調整済みマスター（1024 × 1024 px、黒一色・透過） |
| `menuBarTemplate.png` | メニューバー用 1x（18 × 18 px、72 dpi） |
| `menuBarTemplate@2x.png` | メニューバー用 2x（36 × 36 px、144 dpi） |
| `prepare.swift` | 原本から配布用PNGを再作成するmacOS標準フレームワークのスクリプト |

## 最適化

元画像のアルファ値を保持してRGBを黒に統一し、透明な外周余白を除去。
カップ・湯気・矢印の形状や相対位置は変更せず、縦横比を保って中央配置する。
18 pt の正方形に上下各1 ptの余白を設け、同じ配置で各解像度へ直接縮小する。
再生成や輪郭の描き直しは行わない。白背景は焼き込まない。

リポジトリのルートで再作成：

```sh
swift assets/icon/prepare.swift
```

## 組み込み

メニューバーのアイコンとして使う（DESIGN.md §3.2）。`menuBarTemplate.png`・`menuBarTemplate@2x.png` を
`install.sh` が `~/.local/bin/cafe-wifi-okawari-menubar.png`・`cafe-wifi-okawari-menubar@2x.png` へコピーし、
`menubar.js` が1x・2xを同じ18 × 18 ptのNSImageの表現として読み込み、`template = true` を指定する。
ファイル名だけでのテンプレート判定には依存しない。状態で画像は替えず、停止中は薄く表示し、印（! … ✓）は右に付く。
5状態とRetina表示はダークのメニューバーで確認済み。ライトのメニューバーでは未確認。

## 原本の記録

- 生成：組み込みimagegen。採用案「① やや太め」
- 旧保存場所：`output/icon-concepts/steam-weight/01-steam-medium.png`（整理済み）
- 原本SHA-256：`3144c21e9f2351c737f8bcafdaf2d253fb1ef821e46d169240fda9389c2ad01f`
- 編集指示：カップと受け皿を保持し、Wi-Fi状の2本の湯気の線を約15%太くする。
  外側の先端のみ矢印、内側の先端は丸いまま。15%は生成指示の目安であり実測値ではない。

不採用案、旧比較画像・HTML、過去のプロンプト集、SF Symbols参照画像とその作成スクリプトは削除済み。
