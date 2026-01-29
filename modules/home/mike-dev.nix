# Mike's dev configuration (with moltbot)
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
      ];

      home.packages = with pkgs; [
        llm-agents.moltbot
        bun
      ];
    };
}
