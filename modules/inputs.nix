# Imports external flake modules
{ inputs, ... }:
{
  imports = [
    # Enables flake.modules.<class>.* with type checking
    inputs.flake-parts.flakeModules.modules
    # Home-manager flake-parts integration
    inputs.home-manager.flakeModules.home-manager
  ];
}
