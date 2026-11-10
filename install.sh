#!/usr/bin/env bash
# Install the window look: copies hypr/dtp-windows.lua into ~/.config/hypr and
# loads it from hyprland.lua, before the toggles. Safe to run again.
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
  echo "Sets the focused window border to 50% and makes title bars as tall as the OS bar."
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

status="$(python3 - "$HYPR/hyprland.lua" "$LINE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
line = sys.argv[2]
comment = "-- omarchy-dtp-windows: window border opacity and title bar look. Loaded before the\n-- toggles, which is where Omarchy sets up the title bars.\n"
anchor = 'require("default.hypr.toggles")'
text = path.read_text()
lines = text.splitlines(keepends=True)

# Where it belongs: just before the toggles.
anchor_idx = next((i for i, l in enumerate(lines) if l.strip() == anchor), None)
line_idx = next((i for i, l in enumerate(lines) if l.strip() == line), None)
if anchor_idx is None:
    # No toggles line to go before: the end of the file will do.
    if line_idx is not None:
        print("same")
        raise SystemExit(0)
    new = text + ("" if text.endswith("\n") else "\n") + "\n" + comment + line + "\n"
    path.write_text(new)
    print("added")
    raise SystemExit(0)
if line_idx is not None and line_idx < anchor_idx:
    print("same")
    raise SystemExit(0)
# An earlier install put it at the end. Take that copy out.
if line_idx is not None:
    start = line_idx
    while start > 0 and lines[start - 1].startswith("--"):
        start -= 1
    del lines[start:line_idx + 1]
    anchor_idx = next(i for i, l in enumerate(lines) if l.strip() == anchor)
    while len(lines) > 0 and lines[-1].strip() == "":
        lines.pop()
lines.insert(anchor_idx, comment + line + "\n\n")
path.write_text("".join(lines))
print("added")
PY
)"
if [[ $status == added ]]; then
  echo "Added the dtp-windows line to hyprland.lua"
  changed=1
else
  echo "hyprland.lua already loads dtp-windows"
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
