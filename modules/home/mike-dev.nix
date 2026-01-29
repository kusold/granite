# Mike's dev configuration (with clawdbot)
# Exports: flake.modules.homeManager.mike-dev
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mike-dev =
    { ... }:
    {
      imports = [
        localModules.mike
        localModules.clawdbot
      ];
    };
}
