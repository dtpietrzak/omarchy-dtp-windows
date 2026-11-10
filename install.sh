#!/usr/bin/env bash
# Install the window look: copies hypr/dtp-windows.lua into ~/.config/hypr and
# loads it from the end of hyprland.lua. Safe to run again.
#
#   ./install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HYPR="$HOME/.config/hypr"
LINE='require("hypr.dtp-windows")'

fail() {
  echo "install: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: install.sh"
  echo "Sets the focused window border to 75% and makes title bars as tall as the OS bar."
  exit 0
fi
[[ $# -eq 0 ]] || fail "unknown argument: $1"
[[ -f $ROOT/hypr/dtp-windows.lua ]] || fail "missing $ROOT/hypr/dtp-windows.lua"
[[ -f $HYPR/hyprland.lua ]] || fail "$HYPR/hyprland.lua must already exist"

changed=0
if ! cmp -s "$ROOT/hypr/dtp-windows.lua" "$HYPR/dtp-windows.lua"; then
  cp "$ROOT/hypr/dtp-windows.lua" "$HYPR/dtp-windows.lua"
  echo "Updated $HYPR/dtp-windows.lua"
  changed=1
fi

if grep -qxF "$LINE" "$HYPR/hyprland.lua"; then
  echo "hyprland.lua already loads dtp-windows"
else
  [[ -z $(tail -c1 "$HYPR/hyprland.lua") ]] || printf '\n' >>"$HYPR/hyprland.lua"
  printf '\n-- omarchy-dtp-windows: window border opacity and title bar size.\n%s\n' "$LINE" >>"$HYPR/hyprland.lua"
  echo "Added the dtp-windows line to hyprland.lua"
  changed=1
fi

if [[ $changed -eq 1 ]]; then
  hyprctl reload >/dev/null
fi
errors="$(hyprctl configerrors 2>&1 || true)"
if [[ -n ${errors//[[:space:]]/} ]]; then
  printf '%s\n' "$errors" >&2
  fail "Hyprland reported config errors"
fi
echo "Hyprland config has no errors"
