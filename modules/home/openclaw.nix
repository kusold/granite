# openclaw AI agent configuration
# Exports: flake.modules.homeManager.openclaw
# Note: This module imports openclaw-external which defines the programs.openclaw options
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.openclaw =
    { pkgs, ... }:
    {
      imports = [
        # Import the module that defines programs.openclaw options
        localModules.openclaw-external
      ];

      programs.openclaw = {
        enable = true;
        # Set documents to null to skip the file existence checks
        # You can configure AGENTS.md, SOUL.md, and TOOLS.md manually later
        documents = null;
        instances.default.enable = true;

        # Causes trouble on linux as of Jan 28, 2026
        firstParty = {
          peekaboo.enable = false;
          summarize.enable = false;
        };
      };

      # Systemd user service for openclaw gateway
      # See: https://docs.molt.bot/gateway#supervision-systemd-user-unit
      systemd.user.services.openclaw-gateway = {
        enable = true;
        Unit = {
          Description = "OpenClaw Gateway (profile: default)";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          ExecStart = "${config.programs.openclaw.package}/bin/openclaw gateway --port 18789";
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
        enable = true;
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
          WantedBy = [ "openclaw-gateway.service" ];
        };
      };
    };
}
