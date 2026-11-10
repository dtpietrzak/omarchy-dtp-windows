#!/usr/bin/env bash
# Build Omarchy's title bar plugin with the blur fixed, for glass title bars.
#
# omarchy-hyprland-titlebars draws its bar without the blur it asks for, so a
# glass title bar is tinted but not frosted. This clones the installed version,
# fixes it with fix.py, and builds it against the installed Hyprland headers
# into ~/.local/lib/omarchy-dtp-windows/, stamped with the Hyprland commit it
# was built for. dtp-windows.lua loads it only while that stamp matches, so a
# Hyprland update falls back to Omarchy's own copy instead of crashing.
#
# Once an Omarchy release has the fix, this removes its copy and Omarchy's own
# loads again.
#
#   titlebars/build.sh
#
# Prints one line saying what it did. "Built ..." and "Removed ..." mean the
# plugin to load changed and Hyprland needs a reload.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/.local/lib/omarchy-dtp-windows"
VERSION_H=/usr/include/hyprland/src/version.h
REPO=https://github.com/omacom/omarchy-hyprland-titlebars.git

fail() {
  echo "titlebars: $*" >&2
  exit 1
}

version="$(pacman -Q omarchy-hyprland-titlebars 2>/dev/null | awk '{print $2}' | cut -d- -f1)"
if [[ -z $version ]]; then
  echo "Omarchy's title bar plugin is not installed; nothing to build"
  exit 0
fi
[[ -f $VERSION_H ]] || fail "missing Hyprland headers ($VERSION_H)"
commit="$(sed -n 's/^#define GIT_COMMIT_HASH *"\(.*\)"/\1/p' "$VERSION_H")"
[[ -n $commit ]] || fail "no commit hash in $VERSION_H"
fixer_sum="$(sha256sum "$ROOT/fix.py" | cut -d' ' -f1)"

stamp() { cat "$OUT/$1" 2>/dev/null || true; }
if [[ -f $OUT/titlebars.so && $(stamp hyprland-commit) == "$commit" && $(stamp titlebars-version) == "$version" && $(stamp fix-sha256) == "$fixer_sum" ]]; then
  echo "Title bar plugin already built for this Hyprland"
  exit 0
fi

# The tools to build with. Omarchy has most of them; a fresh install may not.
missing=()
command -v git >/dev/null || missing+=(git)
command -v g++ >/dev/null || missing+=(gcc)
command -v pkg-config >/dev/null || missing+=(pkgconf)
command -v python3 >/dev/null || missing+=(python)
if ((${#missing[@]})); then
  echo "titlebars: installing ${missing[*]} to build the title bar plugin" >&2
  omarchy-pkg-add "${missing[@]}" >&2 || fail "could not install ${missing[*]}"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$version" "$REPO" "$work/src" ||
  fail "could not fetch omarchy-hyprland-titlebars v$version"

status=0
python3 "$ROOT/fix.py" "$work/src" || status=$?
if [[ $status -eq 3 ]]; then
  # Omarchy's own build blurs. Make way for it.
  if [[ -e $OUT ]]; then
    rm -rf "$OUT"
    echo "Removed the patched title bar plugin: Omarchy's v$version blurs on its own"
  else
    echo "Omarchy's title bar plugin v$version blurs on its own; nothing to build"
  fi
  exit 0
fi
[[ $status -eq 0 ]] || fail "fix.py does not fit omarchy-hyprland-titlebars v$version"

# shellcheck disable=SC2046
g++ -std=c++23 -O2 -w -fPIC -shared -fno-gnu-unique \
  "$work"/src/{main,barDeco,BarPassElement,appName}.cpp \
  $(pkg-config --cflags --libs hyprland libdrm libinput libudev pixman-1 wayland-server xkbcommon) -lrt \
  -o "$work/titlebars.so" >&2 || fail "the title bar plugin v$version did not compile against Hyprland ${commit:0:7}"

mkdir -p "$OUT"
# A new file, not one written over: Hyprland may have the old one mapped.
install -m755 "$work/titlebars.so" "$OUT/titlebars.so.new"
mv "$OUT/titlebars.so.new" "$OUT/titlebars.so"
printf '%s\n' "$version" >"$OUT/titlebars-version"
printf '%s\n' "$commit" >"$OUT/hyprland-commit"
printf '%s\n' "$fixer_sum" >"$OUT/fix-sha256"
rm -f "$OUT/blur.patch"
echo "Built the title bar plugin v$version with blur for Hyprland ${commit:0:7}"
