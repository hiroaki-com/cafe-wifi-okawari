#!/bin/zsh
# 署名・公証した .pkg を作る（DESIGN.md §6.2）。作者の Mac で実行する（Xcode のコマンドと Developer ID Installer の証明書を使う）。
# 使い方: zsh pkg/build.sh <タグ>   例: zsh pkg/build.sh v1.2.0
# 中身はタグの git archive からだけ取る。作業フォルダの変更・追跡しないファイル（.claude/ など）は入らない。
# 公証は、App Store Connect の API 鍵を環境変数で渡したときだけ行う: NOTARY_KEY（.p8 のパス）・NOTARY_KEY_ID・NOTARY_ISSUER。
# 鍵はリポジトリにも CI にも置かない。出力は dist/cafe-wifi-okawari.pkg（名前に版を入れない。§6.1）
set -eu
setopt extended_glob
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

id=com.hkdocs.cafe-wifi-okawari
signer='Developer ID Installer: HKDOCS (3CL9HYSJZ8)'
# .pkg に入れるファイル（install.sh が導入に使うものだけ）。導入スクリプト（pkg/postinstall）は別に足す
files=(install.sh cafe-wifi-okawari.sh menubar.sh menubar.js netcheck.sh assets/icon/menuBarTemplate.png assets/icon/menuBarTemplate@2x.png)
die() { print -u2 -r -- "Error: $*"; exit 1 }

root=${0:A:h:h}
tag=${1-}
[[ $tag == v[0-9]##.[0-9]##.[0-9]## ]] || die "usage: zsh pkg/build.sh v1.2.0"
git -C $root rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null || die "no tag $tag"
ver=${tag#v}
v=$(git -C $root show "${tag}:cafe-wifi-okawari.sh" | sed -n 's/^VERSION=\([0-9][0-9.]*\).*/\1/p')
[[ $v == $ver ]] || die "tag $tag does not match VERSION=$v"

w=$(mktemp -d)
trap 'rm -rf $w' EXIT
mkdir $w/src $w/scripts $w/build
git -C $root archive --format=tar "$tag" | tar -x -C $w/src
for f in $files; do
  [[ -f $w/src/$f ]] || die "$f is not in $tag"
  mkdir -p $w/scripts/${f:h}
  install -m 644 $w/src/$f $w/scripts/$f
done
install -m 755 $w/src/pkg/postinstall $w/scripts/postinstall

# ペイロードのない、導入スクリプトだけの部品。導入先には何も置かず、postinstall が install.sh で導入する
pkgbuild --quiet --nopayload --scripts $w/scripts --identifier $id --version $ver $w/build/component.pkg
sed "s/@VERSION@/$ver/" $w/src/pkg/distribution.xml > $w/distribution.xml
out=$root/dist/cafe-wifi-okawari.pkg
mkdir -p ${out:h}
rm -f $out
# 署名にはキーチェーンの確認が出る（秘密鍵の「アクセスを許可する前に確認」）。タイムスタンプは Apple のサーバーから取る
productbuild --quiet --distribution $w/distribution.xml --resources $w/src/pkg/resources --package-path $w/build \
  --sign "$signer" --timestamp $out

# 中身の照合: .pkg の中のファイルの一覧が決めたとおりで、どれもタグの中身と同じこと。
# 導入スクリプトのフォルダ（cpio）には、macOS が作業中のファイルに付ける com.apple.provenance（消せない）が AppleDouble（._）で入る。
# ditto で展開して元のファイルの拡張属性に戻し、それ以外の属性（ダウンロード属性など）がないことを確かめる
mkdir $w/x
(cd $w/x && xar -xf $out)
ditto -x $w/x/component.pkg/Scripts $w/xs
rm $w/x/component.pkg/Scripts
want=(Distribution component.pkg/PackageInfo ${${(f)"$(cd $w/src/pkg/resources && find . -type f | sed 's#^\./#Resources/#')"}}
  ${files/#/Scripts/} Scripts/postinstall)
got=(${(f)"$(cd $w/x && find . -type f | sed 's#^\./##')"} ${(f)"$(cd $w/xs && find . -type f | sed 's#^\./#Scripts/#')"})
extra=(${got:|want}) missing=(${want:|got})
(( $#extra + $#missing == 0 )) || die "unexpected files in the package: ${extra-} / missing: ${missing-}"
a=$(cd $w/xs && find . -exec xattr {} + | sed 's/^.*: //' | sort -u | grep -vx com.apple.provenance) && die "the scripts have extended attributes: $a"
for f in $files; do cmp -s $w/src/$f $w/xs/$f || die "$f differs from $tag"; done
cmp -s $w/src/pkg/postinstall $w/xs/postinstall || die "postinstall differs from $tag"
[[ -x $w/xs/postinstall ]] || die "postinstall is not executable"
for f in $w/src/pkg/resources/**/*(.); do cmp -s $f $w/x/Resources/${f#$w/src/pkg/resources/} || die "${f:t} differs from $tag"; done
# Distribution は productbuild が整え直すので、要点を確かめる: JavaScript がない・導入先は本人のホームだけ・版がタグと同じ
grep -qE '<script|script=' $w/x/Distribution && die "Distribution has a script"
grep -qF " version=\"$ver\" " $w/x/Distribution || die "Distribution is not version $ver"
grep -q 'enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"' $w/x/Distribution || die "Distribution allows a domain other than the user's home"
pkgutil --check-signature $out | grep -qF "1. $signer" || die "not signed by $signer"

if [[ -n ${NOTARY_KEY-} ]]; then
  r=$(xcrun notarytool submit $out --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait --output-format json)
  s=$(print -r -- "$r" | jq -r .status) sid=$(print -r -- "$r" | jq -r .id)
  if [[ $s != Accepted ]]; then
    xcrun notarytool log "$sid" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" >&2 || true
    die "notarization $sid: $s"
  fi
  xcrun stapler staple -q $out
  xcrun stapler validate -q $out
  spctl -a -vv -t install $out 2>&1 | grep -q 'source=Notarized Developer ID' || die "Gatekeeper does not accept $out"
  print -r -- "Notarized: $sid"
else
  print -r -- "Not notarized (set NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER to notarize)"
fi
print -r -- "Built: $out ($tag)"
shasum -a 256 $out
