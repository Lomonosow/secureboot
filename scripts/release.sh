#!/bin/bash

set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 <version>"
fi

VERSION="$1"
WORKDIR="$(git rev-parse --show-toplevel)"

cd "$WORKDIR"

#if [[ $(git ls-files -m | wc -l) -gt 0 ]]; then
	#echo "You have unstaged changes"
	#exit 1
#fi

if ( git tag | grep $VERSION >/dev/null ); then
    echo "Tag $VERSION already exists. You may delete it manually."
    exit 1
fi

sed -i "s/^declare -r myver=.*$/declare -r myver=\"$VERSION\"/g" "$WORKDIR/secureboot.sh" 

git diff

echo -n "Do you want proceed with it[Y/n]? "
read ans
echo $ans
if [[ "$ans" != 'Y' ]] && [[ "$ans" != 'y' ]] && [[ "$ans" != 'yes' ]] && [[ "$ans" != 'Yes' ]]; then
    exit 2
fi

git commit -a -m "Release version $VERSION"
git push origin master
git tag "$VERSION"
git push --tags

if [[ ! -d "$WORKDIR/aur" ]]; then
    git clone ssh://aur@aur.archlinux.org/secureboot.git "$WORKDIR/aur"
fi

cd "$WORKDIR/aur"

sed -i "s@pkgver=.*@pkgver=$VERSION@g" $WORKDIR/aur/PKGBUILD
sed -i "s@pkgrel=.*@pkgrel=1@g" $WORKDIR/aur/PKGBUILD

SHA="$(makepkg -g 2>/dev/null)"
sed -i "s@sha512sums=.*@$SHA@g" $WORKDIR/aur/PKGBUILD

makepkg --printsrcinfo > "$WORKDIR/aur/.SRCINFO"

git diff
echo -n "Do you want proceed with it? [Y/n] "
echo $ans
read ans
if [[ "$ans" != 'Y' ]] && [[ "$ans" != 'y' ]] && [[ "$ans" != 'yes' ]] && [[ "$ans" != 'Yes' ]]; then
    exit 2
fi

git commit -a -m "Release version $VERSION"
git tag "$VERSION"
git push origin master
