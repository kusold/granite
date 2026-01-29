# Mike's dev configuration (with moltbot)
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
				# Currently the nix module is broken
        # localModules.moltbot
      ];
    };
}
