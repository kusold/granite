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
        localModules.hapi
        localModules.openclaw
      ];

      services.ssh-agent.enable = true;

      home.packages = with pkgs; [
        bun
        llm-agents.beads
        llm-agents.amp
        llm-agents.ccusage-codex
        llm-agents.claude-code
        llm-agents.codex
        llm-agents.gemini-cli
        llm-agents.openclaw
        signal-cli
      ];
    };
}
