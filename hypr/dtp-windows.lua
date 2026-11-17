-- omarchy-dtp-windows: how windows look.
--   * the focused window's border at 50% opacity
--   * floating windows' title bars as tall as the OS bar, with smaller text
--   * glass title bars, see-through and blurred while the OS bar is glassy
-- Loaded from hyprland.lua before Omarchy sets up the title bars, so it is in
-- place whenever they are set up, at load or later.

local ACTIVE_BORDER_OPACITY = 0.5

local home = os.getenv("HOME")
local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

-- One number from a shell.toml, from the lines of a section.
local function toml_number(text, section, key)
  if not text then
    return nil
  end
  local pattern = "^%s*" .. key:gsub("%-", "%%-") .. "%s*=%s*(%-?[%d.]+)"
  local current
  for line in text:gmatch("[^\r\n]+") do
    local name = line:match("^%s*%[([%w_-]+)%]")
    if name then
      current = name
    elseif current == section then
      local value = line:match(pattern)
      if value then
        return tonumber(value)
      end
    end
  end
  return nil
end

-- One quoted value from a shell.toml section.
local function toml_string(text, section, key)
  if not text then
    return nil
  end
  local pattern = "^%s*" .. key:gsub("%-", "%%-") .. '%s*=%s*"([^"]*)"'
  local current
  for line in text:gmatch("[^\r\n]+") do
    local name = line:match("^%s*%[([%w_-]+)%]")
    if name then
      current = name
    elseif current == section then
      local value = line:match(pattern)
      if value then
        return value
      end
    end
  end
  return nil
end

-- The focused window's border, in the theme's color at half strength.
local theme_hyprland = read(state_home .. "/omarchy/current/theme/hyprland.lua") or ""
local hex = theme_hyprland:match('active_border_color%s*=%s*"#(%x%x%x%x%x%x)"')
if hex then
  local color = string.format("rgba(%s%02x)", hex, math.floor(ACTIVE_BORDER_OPACITY * 255 + 0.5))
  hl.config({
    general = { col = { active_border = color } },
    group = { col = { border_active = color } },
  })
end

-- The OS bar's height and text size, worked out as the shell does: the theme
-- gives the height at font size 12 and it grows and shrinks with the font size,
-- which the user's own shell.toml can set.
local theme_shell = read(state_home .. "/omarchy/current/theme/shell.toml")
local user_shell = read(home .. "/.config/omarchy/shell.toml")
local font = toml_number(user_shell, "font", "base-size") or toml_number(theme_shell, "font", "base-size") or 12
local bar = toml_number(user_shell, "bar", "size-horizontal") or toml_number(theme_shell, "bar", "size-horizontal") or 26
local height = math.floor(bar * font / 12 + 0.5)

-- The title bars' glass: while the OS bar is glassy they take its look, the
-- theme's glass opacity ([dtp] glass-alpha, 0.35 without it) and the blur behind.
local glassy_flag = io.open(state_home .. "/omarchy/toggles/hypr/bar-glassy.lua", "r")
local glassy = glassy_flag ~= nil
if glassy_flag then
  glassy_flag:close()
end
local alpha = toml_number(theme_shell, "dtp", "glass-alpha") or 0.35
-- The glass is the OS bar's color, not the raised color the title bar has when solid.
local bar_color = (toml_string(user_shell, "bar", "background") or toml_string(theme_shell, "bar", "background") or ""):match("^#(%x%x%x%x%x%x)$")

hl._dtp_windows = {
  bar_height = height,
  bar_text_size = math.floor(font + 0.5),
  glassy = glassy,
  alpha = alpha,
  color = bar_color,
}
-- So omarchy-dtp-floating-titlebar-limits keeps the right amount on screen.
o.titlebar_height = height

-- A title bar color as glass: the OS bar's color at the glass opacity, or at
-- the opacity given. Takes rgb(rrggbb) and rgba(rrggbbaa), and leaves anything
-- else alone.
local function glass(color, alpha)
  local state = hl._dtp_windows
  if not state.glassy or type(color) ~= "string" then
    return color
  end
  local hex = color:match("^rgb%((%x%x%x%x%x%x)%)$") or color:match("^rgba%((%x%x%x%x%x%x)%x%x%)$")
  if not hex then
    return color
  end
  return string.format("rgba(%s%02x)", state.color or hex, math.floor((alpha or state.alpha) * 255 + 0.5))
end

-- The buttons sit on the bar, so a tint of their own would stack on the bar's
-- and show as darker squares. On glass they are clear: only the symbol and the
-- hover highlight are drawn.
local function clear(color)
  return glass(color, 0)
end

-- Double-clicking a title bar (or its □ button) fills the screen by plain move
-- and resize: the window stays an ordinary floating window, with its title bar,
-- border and rounding, inside the gaps and clear of the OS bar. Doing it again
-- puts the window back where it was. Omarchy's own action instead puts the
-- window in Hyprland's maximized state, a kind of fullscreen.
hl._dtp_windows_filled = hl._dtp_windows_filled or {}

local function close_to(a, b)
  return math.abs(a - b) <= 2
end

function hl._dtp_windows_fill(address)
  local window
  for _, candidate in ipairs(hl.get_windows()) do
    if candidate.address == address then
      window = candidate
      break
    end
  end
  if not window or not window.monitor then
    return
  end
  if (window.fullscreen or 0) ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
    return
  end
  if not window.floating then
    return
  end

  local monitor = window.monitor
  local scale = (monitor.scale and monitor.scale ~= 0) and monitor.scale or 1
  local width, height = monitor.width / scale, monitor.height / scale
  if (monitor.transform or 0) % 2 == 1 then
    width, height = height, width
  end
  local reserved = type(monitor.reserved) == "table" and monitor.reserved or {}
  local gaps = hl.get_config("general.gaps_out")
  if type(gaps) ~= "table" then
    local gap = tonumber(gaps) or 0
    gaps = { top = gap, right = gap, bottom = gap, left = gap }
  end
  local border = tonumber(hl.get_config("general.border_size")) or 0
  -- The title bar hangs above the client, so the client starts below it.
  local bar = o.titlebar_height or 30

  local left = monitor.x + (reserved.left or 0) + (gaps.left or 0) + border
  local top = monitor.y + (reserved.top or 0) + (gaps.top or 0) + border + bar
  local right = monitor.x + width - (reserved.right or 0) - (gaps.right or 0) - border
  local bottom = monitor.y + height - (reserved.bottom or 0) - (gaps.bottom or 0) - border
  local fill = {
    x = math.floor(left + 0.5),
    y = math.floor(top + 0.5),
    w = math.floor(right - left + 0.5),
    h = math.floor(bottom - top + 0.5),
  }

  local at, size = window.at, window.size
  local filled = close_to(at.x, fill.x) and close_to(at.y, fill.y) and close_to(size.x, fill.w) and close_to(size.y, fill.h)
  local saved = hl._dtp_windows_filled[address]
  local target
  if filled and saved then
    target = saved
    hl._dtp_windows_filled[address] = nil
  elseif filled then
    return
  else
    hl._dtp_windows_filled[address] = { x = at.x, y = at.y, w = size.x, h = size.y }
    target = fill
  end

  hl.dispatch(hl.dsp.window.resize({ x = target.w, y = target.h, relative = false, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = target.x, y = target.y, relative = false, window = window }))
end

local FILL_ACTION = [[hyprctl eval 'hl._dtp_windows_fill("%WINDOW%")']]

-- Omarchy sets the title bar options when a workspace starts floating, which can
-- be after this file has run, and its numbers would win. So the options pass
-- through here on their way in.
if not hl._dtp_windows_wrapped then
  hl._dtp_windows_wrapped = true
  local config = hl.config
  hl.config = function(options, ...)
    local bars = type(options) == "table" and type(options.plugin) == "table" and options.plugin.hyprbars
    if type(bars) == "table" then
      local state = hl._dtp_windows
      bars.bar_height = state.bar_height
      bars.bar_text_size = state.bar_text_size
      bars.bar_blur = state.glassy
      bars.bar_color = glass(bars.bar_color)
      bars.bar_color_inactive = glass(bars.bar_color_inactive)
      bars.inactive_button_color = clear(bars.inactive_button_color)
      bars.on_double_click = FILL_ACTION
    end
    return config(options, ...)
  end

  -- The buttons paint a background of their own, which would show as squares
  -- on a glass bar. They are added after the plugin loads, so they are caught
  -- as it does.
  local function patch_buttons()
    local bars_api = hl.plugin and hl.plugin.hyprbars
    if bars_api and bars_api.add_button and not bars_api._dtp_windows_patched then
      local add_button = bars_api.add_button
      bars_api.add_button = function(button, ...)
        if type(button) == "table" then
          button.bg_color = clear(button.bg_color)
          if type(button.action) == "string" and button.action:find('"maximized"', 1, true) then
            button.action = FILL_ACTION
          end
        end
        return add_button(button, ...)
      end
      bars_api._dtp_windows_patched = true
    end
  end

  -- Omarchy's title bar plugin draws its bar without the blur it asks for.
  -- titlebars/build.sh builds it with the fix into ~/.local/lib, stamped with
  -- the Hyprland it was built for; it stands in for Omarchy's copy only while
  -- that is still the Hyprland installed, since a plugin built for another one
  -- can take Hyprland down.
  local OMARCHY_TITLEBARS = "/usr/lib/omarchy-hyprland-titlebars/titlebars.so"
  local patched_dir = home .. "/.local/lib/omarchy-dtp-windows"
  local function titlebars_path(path)
    if path ~= OMARCHY_TITLEBARS then
      return path
    end
    local built_for = (read(patched_dir .. "/hyprland-commit") or ""):match("%x+")
    local installed = (read("/usr/include/hyprland/src/version.h") or ""):match('GIT_COMMIT_HASH%s+"(%x+)"')
    local plugin = io.open(patched_dir .. "/titlebars.so", "r")
    if plugin then
      plugin:close()
    end
    if plugin and built_for and built_for == installed then
      return patched_dir .. "/titlebars.so"
    end
    return path
  end

  local load = hl.plugin.load
  hl.plugin.load = function(path, ...)
    local results = table.pack(load(titlebars_path(path), ...))
    patch_buttons()
    return table.unpack(results, 1, results.n)
  end
  patch_buttons()
end
