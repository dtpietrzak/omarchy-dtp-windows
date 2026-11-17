#!/usr/bin/env python3
"""Fix the blur in a checkout of omarchy-hyprland-titlebars.

    fix.py <checkout>

The plugin works out that a glass bar should blur, then draws the bar's rect
without asking for it, so the bar is tinted and never frosted. This passes
.blur and .blurA to that rect (omacom/omarchy-hyprland-titlebars#8). It also
opens the stencil mask before the bar clears the stencil: Hyprland's own
blurred layers leave it shut, and the clear then clears nothing (from #12).

It also gives add_button an optional alt_icon and alt_tag: a window with that
tag shows alt_icon on the button instead. The maximize button uses it to show
when a window fills the screen.

Matched by pattern rather than as a diff, so it fits the 0.56 and 0.57 builds
alike. Exits 0 when it changed the source, 3 when the source already has every
fix (nothing to build), and 1 when the source is not what it expects.
"""

import re
import sys
from pathlib import Path

ALREADY_FIXED = 3


def replace_once(text: str, old: str, new: str, where: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"fix: expected one {old.strip()[:60]!r} in {where}, found {text.count(old)}")
    return text.replace(old, new)


# A button's second icon, shown on windows with its tag.
def alt_icon(root: Path) -> bool:
    globals_h = root / "globals.hpp"
    main_cpp = root / "main.cpp"
    bar_cpp = root / "barDeco.cpp"
    g, m, b = globals_h.read_text(), main_cpp.read_text(), bar_cpp.read_text()
    if "altIcon" in g:
        return False

    g = replace_once(g, "  SP<Render::ITexture> iconTex;\n",
                     "  SP<Render::ITexture> iconTex;\n  std::string altIcon = \"\";\n  std::string altTag = \"\";\n  SP<Render::ITexture> altIconTex;\n",
                     globals_h)

    m = replace_once(m, "  g_pOmarchyFloatingGlobalState->buttons.push_back(std::move(button));\n", """  for (const auto &[field, target] : {std::pair{"alt_icon", &button.altIcon}, std::pair{"alt_tag", &button.altTag}}) {
    lua_getfield(L, 1, field);
    if (lua_isstring(L, -1))
      *target = lua_tostring(L, -1);
    lua_pop(L, 1);
  }

  g_pOmarchyFloatingGlobalState->buttons.push_back(std::move(button));
""", main_cpp)

    # Size and focus changes drop the cached icons; the second one goes too.
    b = replace_once(b, "        button.iconTex = nullptr;\n",
                     "        button.iconTex = nullptr;\n      if (INVALIDATEICONS && button.userfg && button.altIconTex)\n        button.altIconTex = nullptr;\n",
                     bar_cpp)

    # Drawing picks the icon this window shows.
    start = b.index("void COmarchyFloatingHyprBar::renderBarButtonsText(")
    end = b.index("\nvoid ", start + 1)
    body = b[start:end]
    body = body.replace("button.iconTex", "iconTex").replace("!button.icon.empty()", "!iconText.empty()").replace("renderText(button.icon,", "renderText(iconText,")
    body = replace_once(body, "    if ((!iconTex", """    const auto PALTWINDOW = m_pWindow.lock();
    const bool USEALT = !button.altIcon.empty() && !button.altTag.empty() && PALTWINDOW && PALTWINDOW->m_ruleApplicator->m_tagKeeper.isTagged(button.altTag);
    auto &iconTex = USEALT ? button.altIconTex : button.iconTex;
    const auto &iconText = USEALT ? button.altIcon : button.icon;

    if ((!iconTex""", bar_cpp)
    b = b[:start] + body + b[end:]

    # A tag change comes in as a rules update; redraw so the icon follows.
    b = replace_once(b, """void COmarchyFloatingHyprBar::updateRules() {
  const auto PWINDOW = m_pWindow.lock();
  if (!PWINDOW)
    return;
""", """void COmarchyFloatingHyprBar::updateRules() {
  const auto PWINDOW = m_pWindow.lock();
  if (!PWINDOW)
    return;
  damageEntire();
""", bar_cpp)

    globals_h.write_text(g)
    main_cpp.write_text(m)
    bar_cpp.write_text(b)
    return True


def main() -> int:
    root = Path(sys.argv[1])
    path = root / "barDeco.cpp"
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

    changed = False
    if not blur_fixed:
        text = bar.sub(lambda m: m.group(1) + m.group(2).rstrip() + ", .blur = SHOULDBLUR, .blurA = a" + m.group(3), text)
        if not stencil_fixed:
            text = clear.sub(lambda m: "\n" + m.group(1) + "glStencilMask(0xFF);" + m.group(0), text, count=1)
        path.write_text(text)
        changed = True

    try:
        changed = alt_icon(root) or changed
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    # Nothing left to fix: Omarchy's own build is the one to use.
    return 0 if changed else ALREADY_FIXED


if __name__ == "__main__":
    sys.exit(main())
