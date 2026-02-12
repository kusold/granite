# Hapi overlay
{ inputs, ... }:
{
  flake.overlays.hapi = final: _prev: {
    hapi = final.callPackage ../pkgs/hapi.nix { };
  };
}
