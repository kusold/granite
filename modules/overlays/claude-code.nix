# Overlay for claude-code
# Input defined in flake.nix: inputs.claude-code
{ inputs, ... }:
{
  flake.overlays.claude-code = inputs.claude-code.overlays.default;
}
