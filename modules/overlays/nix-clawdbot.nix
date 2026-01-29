# Overlay for nix-clawdbot
# Input defined in flake.nix: inputs.nix-clawdbot
{ inputs, ... }:
{
  flake.overlays.nix-clawdbot = inputs.nix-clawdbot.overlays.default;
}
