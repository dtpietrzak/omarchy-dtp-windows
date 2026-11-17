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

And it takes over resizing from a floating window's border: a side moves only
that side and a corner moves both (Hyprland grabs a corner wherever you press),
and the edge above the bar and the strips beside it get the resize cursor and
resize too (Hyprland measures its border from the window's content).
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


# Resizing from a floating window's border, one edge or one corner at a time.
#
# Hyprland resizes from the border by grabbing the corner of the quarter the
# press lands in, so a press on the left side moves the top or bottom as well
# when the pointer drifts. And it measures its border from the window's content,
# so on a titled window nothing above the bar or beside it shows the resize
# cursor or resizes. This takes over presses on a floating window's border: a
# side moves only that side and a corner moves both, matching the cursor shape,
# which now also shows above the bar and beside it. The cursor goes in the lowest
# override group; where Hyprland shows its own, the shapes agree.
EDGE_FUNCTIONS = r"""
// The one bar showing the edge cursor; others leave it alone.
static COmarchyFloatingHyprBar *g_pEdgeCursorOwner = nullptr;

// The edge a press at this point resizes: one side, or a corner's two sides.
// CORNER_NONE off the window's resize border. Below the bar it draws the same
// zones as Hyprland's resize cursor; above and beside the bar it adds its own.
Layout::eRectCorner COmarchyFloatingHyprBar::edgeAt(PHLWINDOW window, const Vector2D &mouse) {
  using namespace Layout;
  static const auto RESIZEONBORDER = CConfigValue<Config::INTEGER>("general:resize_on_border");
  static const auto EXTENDGRAB = CConfigValue<Config::INTEGER>("general:extend_border_grab_area");

  if (!*RESIZEONBORDER || !window || !window->m_isFloating || Fullscreen::controller()->isFullscreen(window) || window->hasPopupAt(mouse))
    return CORNER_NONE;

  const double BORDER = window->getRealBorderSize();
  const double GRAB = BORDER + *EXTENDGRAB;
  // Hyprland's corner reach: the rounding and the border, plus 10 pixels.
  const double CORNER = window->rounding() + BORDER + 10;
  const auto BAR = assignedBoxGlobal();
  const auto BOX = window->getWindowMainSurfaceBox();

  // The band above the bar, and the strips beside it, which sit within the
  // corner reach of the window's top corners.
  if (!m_hidden && mouse.x >= BAR.x - GRAB && mouse.x < BAR.x + BAR.w + GRAB && mouse.y >= BAR.y - GRAB && mouse.y < BAR.y + BAR.h) {
    if (mouse.y < BAR.y) {
      if (mouse.x < BAR.x + CORNER)
        return CORNER_TOPLEFT;
      if (mouse.x >= BAR.x + BAR.w - CORNER)
        return CORNER_TOPRIGHT;
      return CORNER_TOP;
    }
    if (mouse.x < BAR.x)
      return CORNER_TOPLEFT;
    if (mouse.x >= BAR.x + BAR.w)
      return CORNER_TOPRIGHT;
    return CORNER_NONE;
  }

  if (!BOX.copy().expand(GRAB).containsPoint(mouse) || (!m_hidden && BAR.containsPoint(mouse)))
    return CORNER_NONE;

  // Inside the window only its rounded-off corners resize.
  if (BOX.containsPoint(mouse)) {
    if (!window->isInCurvedCorner(mouse.x, mouse.y))
      return CORNER_NONE;
    return sc<eRectCorner>((mouse.y < BOX.y + CORNER ? CORNER_TOP : CORNER_BOTTOM) | (mouse.x < BOX.x + CORNER ? CORNER_LEFT : CORNER_RIGHT));
  }

  const bool LEFT = mouse.x < BOX.x + CORNER;
  const bool RIGHT = mouse.x > BOX.x + BOX.w - CORNER;
  if (mouse.y < BOX.y + CORNER)
    return LEFT ? CORNER_TOPLEFT : RIGHT ? CORNER_TOPRIGHT : CORNER_TOP;
  if (mouse.y > BOX.y + BOX.h - CORNER)
    return LEFT ? CORNER_BOTTOMLEFT : RIGHT ? CORNER_BOTTOMRIGHT : CORNER_BOTTOM;
  return LEFT ? CORNER_LEFT : RIGHT ? CORNER_RIGHT : CORNER_NONE;
}

// Hyprland's names for its resize cursors.
static const char *edgeCursorName(Layout::eRectCorner edge) {
  using namespace Layout;
  switch (edge) {
    case CORNER_TOP: return "top_side";
    case CORNER_BOTTOM: return "bottom_side";
    case CORNER_LEFT: return "left_side";
    case CORNER_RIGHT: return "right_side";
    case CORNER_TOPLEFT: return "top_left_corner";
    case CORNER_TOPRIGHT: return "top_right_corner";
    case CORNER_BOTTOMLEFT: return "bottom_left_corner";
    case CORNER_BOTTOMRIGHT: return "bottom_right_corner";
    default: return nullptr;
  }
}

// Whether this window is the one under the pointer, with no panel over it.
bool COmarchyFloatingHyprBar::windowIsUnderPointer(PHLWINDOW window, const Vector2D &mouse) {
  const auto PMONITOR = State::monitorState()->query().vec(mouse).run();
  if (!PMONITOR || (g_pSeatManager->m_seatGrab && !g_pSeatManager->m_seatGrab->accepts(window->wlSurface()->resource())))
    return false;

  Desktop::CViewHitTester hitTester{*Desktop::viewState()};
  if (hitTester.windowAt(mouse, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING) != window)
    return false;

  PHLLS foundSurface = nullptr;
  Vector2D surfaceCoords;
  hitTester.layerSurfaceAt(mouse, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], &surfaceCoords, &foundSurface);
  if (!foundSurface)
    hitTester.layerSurfaceAt(mouse, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_TOP], &surfaceCoords, &foundSurface);
  return !foundSurface;
}

// Shows the resize cursor while the pointer is on this window's border, and
// takes it away when the pointer leaves.
void COmarchyFloatingHyprBar::updateEdgeCursor() {
  static const auto HOVERICON = CConfigValue<Config::INTEGER>("general:hover_icon_on_border");

  const char *shape = nullptr;
  const auto PWINDOW = m_pWindow.lock();
  if (*HOVERICON && PWINDOW && !m_hidden && g_pOmarchyFloatingGlobalState->config.enabled->value() && g_pInputManager->m_currentlyHeldButtons.empty()) {
    const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
    shape = edgeCursorName(edgeAt(PWINDOW, MOUSE));
    if (shape && !windowIsUnderPointer(PWINDOW, MOUSE))
      shape = nullptr;
  }

  if (shape) {
    g_pEdgeCursorOwner = this;
    Pointer::Cursor::overrideController->setOverride(shape, Pointer::Cursor::CURSOR_OVERRIDE_UNKNOWN);
  } else if (g_pEdgeCursorOwner == this) {
    g_pEdgeCursorOwner = nullptr;
    Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_UNKNOWN);
  }
}
"""

# Replaces the plugin's own top-edge press handler, which left the corner to
# Hyprland's quarter rule and covered only the band above the bar.
EDGE_PRESS = r"""bool COmarchyFloatingHyprBar::startTopEdgeResize(Event::SCallbackInfo &info, PHLWINDOW window, const Vector2D &coords) {
  const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
  const auto EDGE = edgeAt(window, MOUSE);
  if (EDGE == Layout::CORNER_NONE || g_layoutManager->dragController()->target() || !windowIsUnderPointer(window, MOUSE))
    return false;

  if (Desktop::focusState()->window() != window)
    Desktop::focusState()->fullWindowFocus(window, Desktop::FOCUS_REASON_CLICK);
  Desktop::windowState()->raise(window);

  // A side moves only that side; a corner moves both of its sides.
  g_layoutManager->beginDragTarget(window->layoutTarget(), MBIND_RESIZE, EDGE);

  // The press never reaches Hyprland, so neither does the release: the up
  // handler ends the resize the way it ends a titlebar drag.
  info.cancelled = true;
  m_bCancelledDown = true;
  m_bDraggingThis = true;
  m_bDragPending = false;
  return true;
}
"""


def edge_cursor(root: Path) -> bool:
    bar_h = root / "barDeco.hpp"
    bar_cpp = root / "barDeco.cpp"
    h, b = bar_h.read_text(), bar_cpp.read_text()
    if "edgeAt" in b:
        return False

    h = replace_once(h, "  void onMouseMove(Vector2D coords);\n",
                     "  void onMouseMove(Vector2D coords);\n"
                     "  Layout::eRectCorner edgeAt(PHLWINDOW window, const Vector2D &mouse);\n"
                     "  bool windowIsUnderPointer(PHLWINDOW window, const Vector2D &mouse);\n"
                     "  void updateEdgeCursor();\n",
                     bar_h)
    # After the plugin's InputManager include, which opens its private parts.
    h = replace_once(h, "#undef private\n", "#undef private\n#include <hyprland/src/layout/LayoutManager.hpp>\n", bar_h)

    b = replace_once(b, '#include "globals.hpp"\n',
                     '#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>\n'
                     '#include <hyprland/src/layout/supplementary/DragController.hpp>\n\n#include "globals.hpp"\n', bar_cpp)

    # The functions go just before the first member definition.
    first = b.index("\nCOmarchyFloatingHyprBar::COmarchyFloatingHyprBar(")
    b = b[:first] + "\n" + EDGE_FUNCTIONS + b[first:]

    # A closing window gives the cursor back.
    destructor = re.compile(r"COmarchyFloatingHyprBar::~COmarchyFloatingHyprBar\(\) \{")
    if len(destructor.findall(b)) != 1:
        raise ValueError(f"fix: expected one destructor in {bar_cpp}")
    b = destructor.sub(lambda m: m.group(0) + """
  if (g_pEdgeCursorOwner == this) {
    g_pEdgeCursorOwner = nullptr;
    Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_UNKNOWN);
  }
""", b)

    b = replace_once(b, "void COmarchyFloatingHyprBar::onMouseMove(Vector2D coords) {\n",
                     "void COmarchyFloatingHyprBar::onMouseMove(Vector2D coords) {\n  updateEdgeCursor();\n\n", bar_cpp)

    press = re.compile(r"bool COmarchyFloatingHyprBar::startTopEdgeResize\(Event::SCallbackInfo &info, PHLWINDOW window, const Vector2D &coords\) \{\n.*?\n\}\n", re.S)
    if len(press.findall(b)) != 1:
        raise ValueError(f"fix: startTopEdgeResize is not what it expects in {bar_cpp}")
    b = press.sub(lambda m: EDGE_PRESS, b)

    bar_h.write_text(h)
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
        changed = edge_cursor(root) or changed
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    # Nothing left to fix: Omarchy's own build is the one to use.
    return 0 if changed else ALREADY_FIXED


if __name__ == "__main__":
    sys.exit(main())
