# Clawdbot AI agent configuration
# Exports: flake.modules.homeManager.clawdbot
# Note: This module imports clawdbot-external which defines the programs.clawdbot options
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.clawdbot =
    { ... }:
    {
      imports = [
        # Import the module that defines programs.clawdbot options
        localModules.clawdbot-external
      ];

      programs.clawdbot = {
        enable = true;
        # Set documents to null to skip the file existence checks
        # You can configure AGENTS.md, SOUL.md, and TOOLS.md manually later
        documents = null;
        instances.default.enable = true;
      };
    };
}
