# moltbot AI agent configuration
# Exports: flake.modules.homeManager.moltbot
# Note: This module imports moltbot-external which defines the programs.moltbot options
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.moltbot =
    { ... }:
    {
      imports = [
        # Import the module that defines programs.moltbot options
        localModules.moltbot-external
      ];

      programs.moltbot = {
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
    };
}
