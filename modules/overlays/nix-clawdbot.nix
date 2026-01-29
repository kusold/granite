# Overlay for nix-moltbot
# Input defined in flake.nix: inputs.nix-moltbot
{ inputs, ... }:
{
  flake.overlays.nix-moltbot = inputs.nix-moltbot.overlays.default;
}
