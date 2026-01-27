{ lib, config, ... }:
{
  imports = [
    ./overlays/claude-code.nix
    ./overlays/beads.nix
    ./overlays/nix-clawdbot.nix
    # Add more overlay modules here
  ];

  # Combined overlay with all granite overlays
  flake.overlays.default = lib.composeManyExtensions (
    lib.attrValues (lib.removeAttrs config.flake.overlays [ "default" ])
  );
}
