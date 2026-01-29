# External home-manager module re-exports and backward compatibility
# Individual modules are exported by their own flake-parts files (common.nix, git.nix, etc.)
# This file handles external modules and the homeModules backward-compat alias
{ inputs, config, ... }:
{
  # Backward compatible exports via homeModules
  flake.homeModules = config.flake.modules.homeManager;
}
