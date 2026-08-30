# Mike's Hyprland desktop, aligned with Omarchy Quattro's technology choices:
# Hyprland (Lua config, >= 0.55) + uwsm session + Quickshell shell + Ghostty
# terminal. See https://github.com/basecamp/omarchy (MIT) for the reference.
#
# Roadmap: the quickshell shell grows Omarchy's plugins incrementally:
#   M1 bar (workspaces, clock, tray)      <- done
#   M2 notifications daemon
#   M3 launcher / menu
#   M4 lock + idle
#   M5 clipboard history
#   M6 background switcher / screensaver
# Until then a few stand-ins are used (hyprpolkitagent, playerctl, plain
# grim/slurp captures) — see config/hypr/hyprland.lua TODOs.
#
# Exports: flake.modules.homeManager.hyprland
{ ... }:
{
  flake.modules.homeManager.hyprland =
    { lib, pkgs, ... }:
    {
      # Hyprland >= 0.55 reads ~/.config/hypr/hyprland.lua, like Omarchy
      # Quattro. Not using home-manager's wayland.windowManager.hyprland:
      # it generates the legacy .conf syntax.
      xdg.configFile."hypr/hyprland.lua".source = ../../config/hypr/hyprland.lua;

      # Ghostty (one of Omarchy's supported terminals; their default is foot).
      xdg.configFile."ghostty/config".source = ../../config/ghostty/config;

      home.packages = with pkgs; [
        ghostty
        quickshell

        # Omarchy Quattro core utilities
        wl-clipboard # clipboard (history moves into the shell in M5)
        pamixer
        brightnessctl
        hyprsunset # night light
        hyprpicker # color picker
        playerctl # interim MPRIS control until the shell grows a media panel
      ];
    };
}
