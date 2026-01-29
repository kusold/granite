# Overlay for llm-agents
# Input defined in flake.nix: inputs.llm-agents
{ inputs, ... }:
{
  flake.overlays.llm-agents = inputs.llm-agents.overlays.default;
}
