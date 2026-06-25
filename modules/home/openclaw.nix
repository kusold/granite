# openclaw AI agent configuration
# Exports: flake.modules.homeManager.openclaw
# Note: This module imports openclaw-external which defines the programs.openclaw options
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.openclaw =
    { config, pkgs, ... }:
    {

      # Systemd user service for openclaw gateway
      # See: https://docs.molt.bot/gateway#supervision-systemd-user-unit
      systemd.user.services.openclaw-gateway = {
        Unit = {
          Description = "OpenClaw Gateway (profile: default)";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          ExecStart = "${pkgs.llm-agents.openclaw}/bin/openclaw gateway --port 18789";
          Restart = "always";
          RestartSec = 5;
          # Environment variables can be set here if needed
          # Environment = "OPENCLAW_GATEWAY_TOKEN=your_token_here";
          WorkingDirectory = config.home.homeDirectory;
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      # signal-cli is provided by the host (rockymtn's
      # modules/services/signal-cli.nix) as a system service on 127.0.0.1:8080,
      # shared with Hermes — both gateways use the same Signal account, so
      # openclaw just points at the loopback endpoint.
    };
}
