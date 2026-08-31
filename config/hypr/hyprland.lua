-- Hyprland configuration, aligned with Omarchy Quattro's defaults.
-- https://wiki.hypr.land/Configuring/Start/
--
-- Omarchy Quattro configures Hyprland in Lua (requires Hyprland >= 0.55).
-- Structure and defaults adapted from Omarchy's default config:
-- https://github.com/basecamp/omarchy (MIT)

-- Helpers -------------------------------------------------------------------

-- Bind a key to a plain shell command.
local function bind_cmd(keys, description, command, opts)
  opts = opts or {}
  opts.description = description
  hl.bind(keys, hl.dsp.exec_cmd(command), opts)
end

-- Bind a key to a GUI app, launched through uwsm so it lands in its own
-- systemd scope (Omarchy's o.launch()).
local function bind_app(keys, description, app, opts)
  bind_cmd(keys, description, "uwsm-app -- " .. app, opts)
end

-- Bind a key to a dispatcher object (hl.dsp.*).
local function bind(keys, description, dispatcher, opts)
  opts = opts or {}
  opts.description = description
  hl.bind(keys, dispatcher, opts)
end

-- Launch a GUI app on compositor start, through uwsm.
local function launch_on_start(app)
  hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm-app -- " .. app)
  end)
end

-- Window rule helper (Omarchy's o.window()).
local function window(match, rules)
  rules.match = rules.match or {}
  if type(match) == "string" then
    rules.match.class = match
  else
    for key, value in pairs(match) do
      rules.match[key] = value
    end
  end
  hl.window_rule(rules)
end

-- Environment ---------------------------------------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Better support for screen sharing (Google Meet, Discord, etc).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})

-- Input ---------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    -- CapsLock is the compose key; Caps Lock itself lives on both shifts
    -- together (releases on the next lone shift).
    kb_options = "compose:caps,shift:both_capslock_cancel",
    kb_rules = "",

    follow_mouse = 1,
    sensitivity = 0,

    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Look and feel -------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Basics/Variables/

local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactive_border_color = "rgba(595959aa)"

hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 2,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },

    resize_on_border = false,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,

    shadow = {
      enabled = false,
    },

    blur = {
      enabled = false,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },

    groupbar = {
      font_size = 12,
      font_family = "monospace",
      font_weight_active = "ultraheavy",
      font_weight_inactive = "normal",
      indicator_height = 1,
      indicator_gap = 5,
      height = 22,
      gaps_in = 5,
      gaps_out = 0,
      text_color = "rgb(ffffff)",
      text_color_inactive = "rgba(ffffff90)",
      col = {
        active = "rgba(00000040)",
        inactive = "rgba(00000020)",
      },
      gradients = true,
      gradient_rounding = 0,
      gradient_round_only_edges = false,
    },
  },

  animations = {
    enabled = true,
  },

  dwindle = {
    preserve_split = true,
    force_split = 2,
  },

  master = {
    new_status = "master",
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    disable_scale_notification = true,
    focus_on_activate = true,
    anr_missed_pings = 3,
    on_focus_under_fullscreen = 1,
    initial_workspace_tracking = 0,
    allow_session_lock_restore = true,
  },

  cursor = {
    hide_on_key_press = true,
    warp_on_change_workspace = 1,
  },

  binds = {
    hide_special_on_workspace_change = true,
  },
})

-- Default animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 3.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "fadeSwitch", enabled = false })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = false })

-- Layer rules --------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/#layerrule

-- Shell overlays open instantly — their own QML handles any transitions.
-- (Omarchy applies the same treatment to their menu/launcher namespaces.)
hl.layer_rule({ match = { namespace = "mike-launcher" }, no_anim = true, animation = "none" })

-- Window rules --------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/

window(".*", { suppress_event = "maximize" })

-- Tag all windows for default opacity.
window(".*", { tag = "+default-opacity" })

-- Fix some dragging issues with XWayland.
window({
  class = "^$",
  title = "^$",
  xwayland = true,
  float = true,
  fullscreen = false,
  pin = false,
}, { no_focus = true })

-- Floating dialogs (Omarchy's floating-window treatment).
window({ tag = "floating-window" }, { float = true })
window({ tag = "floating-window" }, { center = true })
window({ tag = "floating-window" }, { size = { 875, 600 } })
window("(org.gnome.NautilusPreviewer|org.gnome.Evince|imv|mpv)", { tag = "+floating-window" })

-- The portal only ever shows dialogs — file pickers, screen shares,
-- permission prompts.
window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

-- No transparency on media windows.
window(
  "^(zoom|vlc|mpv|org.gnome.NautilusPreviewer)$",
  { tag = "-default-opacity" }
)
window(
  "^(zoom|vlc|mpv|org.gnome.NautilusPreviewer)$",
  { opacity = "1 1" }
)

-- Picture-in-picture overlays.
window({ title = "(Picture.?in.?[Pp]icture)" }, { tag = "+pip" })
window({ tag = "pip" }, {
  tag = "-default-opacity",
  float = true,
  pin = true,
  size = { 600, 338 },
  keep_aspect_ratio = true,
  border_size = 0,
  opacity = "1 1",
  move = { "(monitor_w-window_w-40)", "(monitor_h*0.04)" },
})

-- Google Meet PiP uses the meeting title instead of "Picture-in-Picture".
window({ title = "^Meet - .+" }, {
  tag = "-default-opacity",
  float = true,
  pin = true,
  size = { 600, 338 },
  keep_aspect_ratio = true,
  border_size = 0,
  opacity = "1 1",
  move = { "(monitor_w-window_w-40)", "(monitor_h-window_h-40)" },
})

-- Apply default opacity after apps have had a chance to opt out.
window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })

-- Autostart -----------------------------------------------------------------

hl.on("hyprland.start", function()
  -- Slow app launch fix -- set systemd vars before starting session services.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")
end)

launch_on_start("udiskie --automount --no-notify --no-tray")

-- The polkit agent (hyprpolkitagent) runs as a systemd user service bound
-- to graphical-session.target — see modules/home/hyprland.nix.

-- Applications --------------------------------------------------------------

-- The launcher (M3) lives in the quickshell shell; qs ipc toggles it, the
-- same mechanism as the notifications DND keybind below. SUPER+SPACE is
-- Omarchy Quattro's launcher binding.
bind_cmd("SUPER + SPACE", "Launcher", "qs ipc call launcher toggle")

bind_app("SUPER + RETURN", "Terminal", "ghostty")
bind_app("SUPER + SHIFT + RETURN", "Browser", "firefox")
bind_app("SUPER + SHIFT + F", "File manager", "nautilus")

-- Tiling --------------------------------------------------------------------

bind("SUPER + W", "Close window", hl.dsp.window.close())
bind("SUPER + Q", "Close window", hl.dsp.window.close())

bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
bind("SUPER + P", "Pseudo window", hl.dsp.window.pseudo())
bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind("SUPER + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))

bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))
bind("SUPER + UP", "Focus on above window", hl.dsp.focus({ direction = "u" }))
bind("SUPER + DOWN", "Focus on below window", hl.dsp.focus({ direction = "d" }))

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  bind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
bind("SUPER + grave", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
bind("SUPER + SHIFT + grave", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
bind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))

bind("SUPER + SHIFT + LEFT", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
bind("SUPER + SHIFT + RIGHT", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

bind("ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
bind("ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
bind("ALT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
bind("ALT + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())

bind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "e+1" }))
bind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "e-1" }))

bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
bind("SUPER + ALT + G", "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))

-- Media keys ----------------------------------------------------------------
-- pamixer/brightnessctl stand in for Omarchy's omarchy-audio-* and
-- omarchy-brightness-* wrappers; playerctl for their shell MPRIS panel.

bind_cmd("XF86AudioRaiseVolume", "Volume up", "pamixer -i 5", { locked = true, repeating = true })
bind_cmd("XF86AudioLowerVolume", "Volume down", "pamixer -d 5", { locked = true, repeating = true })
bind_cmd("XF86AudioMute", "Mute", "pamixer -t", { locked = true })
bind_cmd("XF86AudioMicMute", "Mute microphone", "pamixer --default-source -t", { locked = true })

bind_cmd("XF86MonBrightnessUp", "Brightness up", "brightnessctl set +5%", { locked = true, repeating = true })
bind_cmd("XF86MonBrightnessDown", "Brightness down", "brightnessctl set 5%-", { locked = true, repeating = true })

bind_cmd("XF86AudioPlay", "Play", "playerctl play-pause", { locked = true })
bind_cmd("XF86AudioPause", "Pause", "playerctl play-pause", { locked = true })
bind_cmd("XF86AudioNext", "Next track", "playerctl next", { locked = true })
bind_cmd("XF86AudioPrev", "Previous track", "playerctl previous", { locked = true })

-- Utilities -----------------------------------------------------------------

-- Screenshots: save to ~/Pictures and copy to the clipboard.
-- TODO(shell): grow into Omarchy's capture flow (region picker with window
-- selection, preview, screen recording) inside the quickshell shell.
bind_cmd("PRINT", "Screenshot", [[sh -c 'grim - | tee "$HOME/Pictures/Screenshot $(date "+%Y-%m-%d at %H.%M.%S").png" | wl-copy']])
bind_cmd("CTRL + PRINT", "Screenshot region", [[sh -c 'grim -g "$(slurp)" - | tee "$HOME/Pictures/Screenshot $(date "+%Y-%m-%d at %H.%M.%S").png" | wl-copy']])
bind_cmd("SUPER + PRINT", "Color picker", "sh -c 'pkill hyprpicker || hyprpicker -a'")

bind_cmd("SUPER + CTRL + N", "Toggle nightlight", "sh -c 'pkill hyprsunset || hyprsunset -t 4000'")

-- The quickshell shell is the notifications daemon (M2); qs ipc talks to it.
bind_cmd("SUPER + N", "Toggle do-not-disturb", "qs ipc call notifications toggleDnd")

-- Session -------------------------------------------------------------------
-- TODO(shell M4): lock screen (Omarchy locks from the quickshell shell) and
-- a system/power menu live here once the shell grows those plugins.

bind_cmd("SUPER + SHIFT + E", "Exit session", "uwsm stop", { locked = true })
