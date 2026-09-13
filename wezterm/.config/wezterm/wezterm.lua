-- On Windows, place this file at %USERPROFILE%\.wezterm.lua.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.enable_wayland = true

-- Enable if starship prompt won't start
-- config.default_prog = { "/usr/bin/env zsh" }

-- General appearance and visuals
config.hide_tab_bar_if_only_one_tab = true

-- Set primary font with fallbacks
config.font = wezterm.font_with_fallback({
	{ family = "Fira Code", weight = 400, stretch = "Normal", style = "Normal" }, -- Thin variant
	"Fira Code",
	"JetBrains Mono",
	"Hack",
})

config.colors = {
	tab_bar = {

		active_tab = {
			bg_color = "#80bfff", -- col_gray2 (selected tab in bright blue)
			fg_color = "#00141d", -- contrast text on active tab
		},

		inactive_tab = {
			bg_color = "#1a1a1a", -- col_gray4 (dark background for inactive tabs)
			fg_color = "#FFFFFF", -- col_gray3 (white text on inactive tabs)
		},

		new_tab = {
			bg_color = "#1a1a1a", -- same as inactive
			fg_color = "#4fc3f7", -- col_barbie (for the "+" button)
		},
	},
}

if wezterm.target_triple:find("windows") then
	-- Mica is available on Windows 11 build 22621 and later.
	-- WezTerm recommends zero opacity for the best Mica effect.
	config.window_background_opacity = 0
	config.win32_system_backdrop = "Mica"
else
	config.window_background_opacity = 0.3
	config.wayland_window_background_blur = true
end

-- config.color_scheme = "nightfox"
-- config.color_scheme = 'AdventureTime'
-- config.color_scheme = 'Advark Blue'
-- config.color_scheme = 'Dracula'
config.color_scheme = "Catppuccin Mocha"
config.font_size = 12

config.window_padding = {
	left = 10,
	right = 10,
	top = 10,
	bottom = 10,
}

config.use_fancy_tab_bar = true
config.window_frame = {
	font = wezterm.font({ family = "JetBrainsMono Nerd Font Mono", weight = "Regular" }),
}

-- Cursor and performance settings
config.default_cursor_style = "BlinkingBlock" -- SteadyBlock
config.cursor_blink_rate = 500
config.max_fps = 240
config.animation_fps = 60

config.term = "xterm-256color"
config.bold_brightens_ansi_colors = false

-- Keybindings using ALT for tabs & splits
config.keys = {
	-- Tab management
	{ key = "t", mods = "ALT", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "ALT", action = wezterm.action.CloseCurrentTab({ confirm = false }) },
	{ key = "n", mods = "ALT", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "p", mods = "ALT", action = wezterm.action.ActivateTabRelative(-1) },

	-- Pane management
	{ key = "v", mods = "ALT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "h", mods = "ALT", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "q", mods = "ALT", action = wezterm.action.CloseCurrentPane({ confirm = false }) },

	-- Pane navigation (move between panes with ALT + Arrows)
	{ key = "LeftArrow", mods = "ALT", action = wezterm.action.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "ALT", action = wezterm.action.ActivatePaneDirection("Right") },
	{ key = "UpArrow", mods = "ALT", action = wezterm.action.ActivatePaneDirection("Up") },
	{ key = "DownArrow", mods = "ALT", action = wezterm.action.ActivatePaneDirection("Down") },
}

-- Disable missing glyph warnings, since we have fallback fonts now
config.warn_about_missing_glyphs = false

-- function for nvidia_gpu
local function is_nvidia_gpu()
	local handle = io.popen("lspci | grep -i nvidia")
	local result = handle:read("*a")
	handle:close()
	return result ~= ""
end

-- NVIDIA optimization settings
-- config.enable_wayland = not is_nvidia_gpu() -- Disable Wayland if NVIDIA GPU is detected
-- config.front_end = "OpenGL"  -- More stable than WebGPU with NVIDIA
-- config.webgpu_power_preference = "HighPerformance"
-- config.prefer_egl = true
-- config.freetype_load_target = "Light"
-- config.freetype_render_target = "HorizontalLcd"

return config
