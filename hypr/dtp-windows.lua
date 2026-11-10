-- omarchy-dtp-windows: how windows look.
--   * the focused window's border at 75% opacity
--   * floating windows' title bars as tall as the OS bar, with smaller text
-- Loaded last from hyprland.lua, so it runs after the theme and after Omarchy
-- sets up the title bars.

local ACTIVE_BORDER_OPACITY = 0.75

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

-- The focused window's border, in the theme's color at 75%.
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

hl._dtp_windows = { bar_height = height, bar_text_size = math.floor(font + 0.5) }
-- So omarchy-dtp-floating-titlebar-limits keeps the right amount on screen.
o.titlebar_height = height

-- Omarchy sets the title bar options when a workspace starts floating, which can
-- be after this file has run, and its numbers would win. So the options pass
-- through here on their way in.
if not hl._dtp_windows_wrapped then
  hl._dtp_windows_wrapped = true
  local config = hl.config
  hl.config = function(options, ...)
    local bars = type(options) == "table" and type(options.plugin) == "table" and options.plugin.hyprbars
    if type(bars) == "table" then
      bars.bar_height = hl._dtp_windows.bar_height
      bars.bar_text_size = hl._dtp_windows.bar_text_size
    end
    return config(options, ...)
  end
end

-- The title bars may already be set up by now.
if hl.plugin and hl.plugin.hyprbars then
  hl.config({ plugin = { hyprbars = {} } })
end
