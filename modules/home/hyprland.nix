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

      # The Quickshell desktop shell. `quickshell` picks up
      # ~/.config/quickshell/shell.qml by default.
      xdg.configFile."quickshell" = {
        source = ../../config/quickshell;
        recursive = true;
      };

      # One shell instance per graphical session, like Omarchy's
      # omarchy-launch-shell (which supervises theirs from Hyprland
      # autostart; a systemd unit does the same job here).
      systemd.user.services.quickshell = {
        Unit = {
          Description = "Quickshell desktop shell";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.quickshell}/bin/quickshell";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      # Interim polkit agent until the quickshell shell grows its own plugin
      # (Omarchy Quattro runs its polkit agent inside Quickshell). Modeled on
      # the unit the nixpkgs package ships (libexec binary, session-scoped).
      systemd.user.services.hyprpolkitagent = {
        Unit = {
          Description = "Hyprland Polkit Authentication Agent";
          ConditionEnvironment = "WAYLAND_DISPLAY";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

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
