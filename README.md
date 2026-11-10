# omarchy-dtp-windows

How windows look.

- **Focused window border at 50% opacity.** The color stays the theme's; only its opacity changes. It follows the theme when you switch.
- **Glass title bars.** While the OS bar is glassy the title bars take its look: see-through at the theme's glass opacity (`glass-alpha` from `omarchy-dtp-theme`, 0.35 without it), with the blur behind. The buttons go clear on glass, so only their symbols show and they don't sit on the bar as darker squares. With an opaque bar they stay solid.

  Omarchy's title bar plugin (`omarchy-hyprland-titlebars` 0.2.2) asks for the blur but never draws it. Until [omacom/omarchy-hyprland-titlebars#8](https://github.com/omacom/omarchy-hyprland-titlebars/pull/8) (or #12) is released, `install.sh` runs `titlebars/build.sh`, which builds the installed version with `titlebars/blur.patch` into `~/.local/lib/omarchy-dtp-windows/`, and Omarchy loads that copy in place of its own. It's stamped with the Hyprland it was built for. After a Hyprland update the stamp no longer matches and Omarchy's own copy loads again (tinted, not blurred) until you run `./install.sh` again. Building needs `g++` and `git`.
- **Title bars as tall as the OS bar, with smaller text.** A floating window's title bar is 30 pixels tall with 12 pixel text in stock Omarchy. Here its height is the OS bar's (it follows the bar's size and your text size setting) and its text is the same size as the bar's.

## Install

`omarchy-dtp-install` runs this after `omarchy-dtp-floating-titlebar-limits`. From GitHub:

```bash
git clone https://github.com/dtpietrzak/omarchy-dtp-windows.git
cd omarchy-dtp-windows
./install.sh
```

The script copies `hypr/dtp-windows.lua` to `~/.config/hypr/` and adds `require("hypr.dtp-windows")` to `~/.config/hypr/hyprland.lua`, just before the toggles line (a copy at the end from an earlier version is moved), then reloads Hyprland. Running it again changes nothing.

## How it works

Omarchy sets the title bar's options when the config loads or when a workspace starts floating, so a plain setting would be overwritten. This file is loaded first and passes those options through a small wrapper on the way in, so the height, text size and glass hold either way. It also sets `o.titlebar_height`, which `omarchy-dtp-floating-titlebar-limits` reads to keep the right amount of the bar on screen.

## Change it

The numbers are at the top of `hypr/dtp-windows.lua` (`ACTIVE_BORDER_OPACITY`) and in the "OS bar's height and text size" part.

## Undo

Remove the `require("hypr.dtp-windows")` line from `~/.config/hypr/hyprland.lua`, delete `~/.local/lib/omarchy-dtp-windows/`, and reload Hyprland.
