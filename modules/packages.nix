# Expose packages from overlays
{ ... }:
{
  perSystem = { pkgs, ... }: {
    packages = {
      inherit (pkgs) hapi;
    };
  };
}
