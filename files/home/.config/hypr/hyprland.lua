-- Hyprland 0.56 Lua config. Environment variables live in ~/.config/uwsm/env.

----------------------------------------------------------------------
-- Monitors   (port names: hyprctl monitors all)
----------------------------------------------------------------------
-- >>> monitors: post-install.sh replaces this block from MONITORS in config.sh
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
-- <<< monitors

----------------------------------------------------------------------
-- Programs
----------------------------------------------------------------------
local terminal    = "kitty"
local fileManager = "thunar"
local menu        = "rofi -show drun"

-- Launch apps as systemd units inside the uwsm session
local function app(cmd) return hl.dsp.exec_cmd("uwsm app -- " .. cmd) end

----------------------------------------------------------------------
-- Autostart   (waybar, swaync, hypridle, polkit agent run as user services, see 8.3)
----------------------------------------------------------------------
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("uwsm app -- awww-daemon")
    hl.exec_cmd("uwsm app -- wl-paste --watch cliphist store")
    hl.exec_cmd("uwsm app -- ckb-next --background")   -- CORSAIR_KEYBOARD=yes only
    hl.exec_cmd("sh -c 'sleep 1; if [ -f \"$HOME/Pictures/wallpaper.jpg\" ]; then awww img \"$HOME/Pictures/wallpaper.jpg\"; else awww img /usr/share/hypr/wall0.png; fi'")
end)

----------------------------------------------------------------------
-- Look and feel
----------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 2,   -- per window side: 4px between windows
        gaps_out    = 2,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout        = "dwindle",
        allow_tearing = true,   -- master switch; games opt in with the `immediate` rule below
    },

    decoration = {
        rounding           = 10,
        active_opacity     = 0.95,
        inactive_opacity   = 0.85,
        fullscreen_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 15,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled           = true,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            ignore_opacity    = true,
        },
    },

    animations = { enabled = true },

    render = {
        direct_scanout = 2,     -- auto: fullscreen games bypass composition. Set 0 if fullscreen flickers.
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        vrr                     = 0,    -- per-monitor vrr above takes over
    },

    input = {
        kb_layout          = "us",      -- KB_LAYOUT / KB_VARIANT in config.sh
        kb_variant         = "",
        numlock_by_default = true,
        follow_mouse       = 1,
        sensitivity        = 0,
        accel_profile      = "flat",    -- raw 1:1 mouse input (no acceleration), like games expect
    },

    dwindle = { preserve_split = true },
})

hl.curve("overshot",  { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("smoothOut", { type = "bezier", points = { {0.36, 0},   {0.66, -0.56} } })
hl.curve("smoothIn",  { type = "bezier", points = { {0.25, 1},   {0.5, 1} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4,  bezier = "overshot",  style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4,  bezier = "smoothOut", style = "slide" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 5,  bezier = "smoothIn" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5,  bezier = "overshot",  style = "slidevert" })

----------------------------------------------------------------------
-- Keybinds
----------------------------------------------------------------------
local mod = "SUPER"

hl.bind(mod .. " + Return",      app(terminal))
hl.bind(mod .. " + D",           app(menu))
hl.bind(mod .. " + E",           app(fileManager))
hl.bind(mod .. " + Q",           hl.dsp.window.close())
hl.bind(mod .. " + F",           hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",           hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + P",           hl.dsp.window.pseudo())
hl.bind(mod .. " + L",           hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + SHIFT + E",   hl.dsp.exec_cmd("uwsm stop"))       -- clean logout (don't use hl.dsp.exit with uwsm)
hl.bind(mod .. " + SHIFT + V",   hl.dsp.exec_cmd("cliphist list | rofi -dmenu | cliphist decode | wl-copy"))
hl.bind("Print",                 hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("SHIFT + Print",         hl.dsp.exec_cmd('grim - | wl-copy'))

hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Keyboard media keys / volume wheel
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

----------------------------------------------------------------------
-- Window rules
----------------------------------------------------------------------
-- Example for a game outside Steam (Black Desert via Lutris). Find a game's class with: hyprctl clients
hl.window_rule({
    name      = "black-desert",
    match     = { class = "(?i)^blackdesert64\\.exe$" },
    immediate = true,   -- allow tearing (lowest input latency) when fullscreen
    opaque    = true,
})

-- Steam games run as XWayland windows with class steam_app_<appid>
hl.window_rule({
    name      = "steam-games",
    match     = { class = "^steam_app_[0-9]+$" },
    immediate = true,
    opaque    = true,
})

-- Never lock or blank the screen while something is fullscreen (games, video)
hl.window_rule({
    name         = "idle-inhibit-fullscreen",
    match        = { class = ".*" },
    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Blur behind the waybar pills; ignore_alpha keeps the transparent gaps between them unblurred
hl.layer_rule({
    name         = "waybar-blur",
    match        = { namespace = "^waybar$" },
    blur         = true,
    ignore_alpha = 0.1,
})
