# Expose packages from overlays
{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages = {
        inherit (pkgs) hapi;
      };
    };
}
