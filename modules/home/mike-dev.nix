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
        localModules.hyprland
      ];

      services.ssh-agent.enable = true;

      home.packages = with pkgs; [
        bun
        llm-agents.ccusage
        llm-agents.claude-code
        llm-agents.codex
        llm-agents.openclaw
        llm-agents.pi
      ];
    };
}
