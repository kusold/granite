# Composes all overlay modules into a single default overlay
{ lib, config, ... }:
{
  # Combined overlay with all granite overlays
  flake.overlays.default = lib.composeManyExtensions (
    lib.attrValues (lib.removeAttrs config.flake.overlays [ "default" ])
  );
}
