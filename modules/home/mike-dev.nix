# Mike's dev configuration (with openclaw)
# Exports: flake.modules.homeManager.mike-dev
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mike-dev =
    { pkgs, ... }:
    {
      imports = [
        localModules.mike
				localModules.openclaw
      ];

      services.ssh-agent.enable = true;

      home.packages = with pkgs; [
        llm-agents.openclaw
        bun
        signal-cli
      ];
    };
}
