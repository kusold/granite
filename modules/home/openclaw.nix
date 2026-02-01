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

      # Systemd user service for signal-cli in HTTP JSON-RPC mode
      # Starts automatically with openclaw-gateway
      # See: https://github.com/AsamK/signal-cli/blob/master/man/signal-cli-jsonrpc.5.adoc
      systemd.user.services.signal-cli-jsonrpc = {
        Unit = {
          Description = "Signal CLI JSON-RPC HTTP daemon";
          After = [ "openclaw-gateway.service" "network-online.target" ];
          Wants = [ "openclaw-gateway.service" "network-online.target" ];
        };

        Service = {
          ExecStart = "${pkgs.signal-cli}/bin/signal-cli daemon --http=:8080";
          Restart = "always";
          RestartSec = 5;
          WorkingDirectory = config.home.homeDirectory;
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    };
}
