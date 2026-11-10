#!/usr/bin/env bash
# Build Omarchy's title bar plugin with blur.patch, for glass title bars.
#
# omarchy-hyprland-titlebars draws its bar without the blur it asks for, so a
# glass title bar is tinted but not frosted. This builds the installed version
# with the fix against the installed Hyprland headers into
# ~/.local/lib/omarchy-dtp-windows/, and stamps it with the Hyprland commit it
# was built for. dtp-windows.lua loads it only while that stamp matches, so a
# Hyprland update falls back to Omarchy's own copy instead of crashing.
# Once the fix is in an Omarchy release this is no longer needed.
#
#   titlebars/build.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/.local/lib/omarchy-dtp-windows"
VERSION_H=/usr/include/hyprland/src/version.h
REPO=https://github.com/omacom/omarchy-hyprland-titlebars.git

fail() {
  echo "titlebars: $*" >&2
  exit 1
}

command -v g++ >/dev/null || fail "needs g++"
command -v git >/dev/null || fail "needs git"
[[ -f $VERSION_H ]] || fail "missing Hyprland headers ($VERSION_H)"
version="$(pacman -Q omarchy-hyprland-titlebars 2>/dev/null | awk '{print $2}' | cut -d- -f1)"
[[ -n $version ]] || fail "omarchy-hyprland-titlebars is not installed"
commit="$(sed -n 's/^#define GIT_COMMIT_HASH *"\(.*\)"/\1/p' "$VERSION_H")"
[[ -n $commit ]] || fail "no commit hash in $VERSION_H"

if [[ -f $OUT/titlebars.so && "$(cat "$OUT/hyprland-commit" 2>/dev/null)" == "$commit" && "$(cat "$OUT/titlebars-version" 2>/dev/null)" == "$version" ]] &&
  cmp -s "$ROOT/blur.patch" "$OUT/blur.patch"; then
  echo "Title bar plugin already built for this Hyprland"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$version" "$REPO" "$work/src"
patch -s -d "$work/src" -p0 <"$ROOT/blur.patch" || fail "blur.patch does not apply to v$version"

# shellcheck disable=SC2046
g++ -std=c++23 -O2 -w -fPIC -shared -fno-gnu-unique \
  "$work"/src/{main,barDeco,BarPassElement,appName}.cpp \
  $(pkg-config --cflags --libs hyprland libdrm libinput libudev pixman-1 wayland-server xkbcommon) -lrt \
  -o "$work/titlebars.so"

mkdir -p "$OUT"
# A new file, not one written over: Hyprland may have the old one mapped.
install -m755 "$work/titlebars.so" "$OUT/titlebars.so.new"
mv "$OUT/titlebars.so.new" "$OUT/titlebars.so"
cp "$ROOT/blur.patch" "$OUT/blur.patch"
printf '%s\n' "$version" >"$OUT/titlebars-version"
printf '%s\n' "$commit" >"$OUT/hyprland-commit"
echo "Built the title bar plugin v$version with blur for Hyprland ${commit:0:7}"
