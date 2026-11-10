#!/usr/bin/env python3
"""Fix the blur in a checkout of omarchy-hyprland-titlebars.

    fix.py <checkout>

The plugin works out that a glass bar should blur, then draws the bar's rect
without asking for it, so the bar is tinted and never frosted. This passes
.blur and .blurA to that rect (omacom/omarchy-hyprland-titlebars#8). It also
opens the stencil mask before the bar clears the stencil: Hyprland's own
blurred layers leave it shut, and the clear then clears nothing (from #12).

Matched by pattern rather than as a diff, so it fits the 0.56 and 0.57 builds
alike. Exits 0 when it changed the source, 3 when the source already has the
fix (nothing to build), and 1 when the source is not what it expects.
"""

import re
import sys
from pathlib import Path

ALREADY_FIXED = 3


def main() -> int:
    path = Path(sys.argv[1]) / "barDeco.cpp"
    text = path.read_text()

    # The bar's own rect: renderRect([ctx, ]titleBarBox, color, {...}).
    bar = re.compile(r"(g_pHyprOpenGL->renderRect\((?:ctx,\s*)?titleBarBox,\s*color,\s*\{)([^{}]*)(\}\);)")
    found = bar.findall(text)
    if len(found) != 1:
        print(f"fix: expected one titlebar renderRect in {path}, found {len(found)}", file=sys.stderr)
        return 1
    blur_fixed = ".blur" in found[0][1]

    # The stencil clear before the rounded-corner mask.
    clear = re.compile(r"\n([ \t]*)glClearStencil\(0\);\n[ \t]*glClear\(GL_STENCIL_BUFFER_BIT\);\n\s*g_pHyprOpenGL->setCapStatus\(GL_STENCIL_TEST, true\);")
    match = clear.search(text)
    if not match:
        print(f"fix: no stencil clear found in {path}", file=sys.stderr)
        return 1
    stencil_fixed = "glStencilMask(0xFF);" in text[max(0, match.start() - 80) : match.start() + 1]

    if blur_fixed:
        # Omarchy has the blur now. Its own build is the one to use.
        return ALREADY_FIXED

    text = bar.sub(lambda m: m.group(1) + m.group(2).rstrip() + ", .blur = SHOULDBLUR, .blurA = a" + m.group(3), text)
    if not stencil_fixed:
        text = clear.sub(lambda m: "\n" + m.group(1) + "glStencilMask(0xFF);" + m.group(0), text, count=1)
    path.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
