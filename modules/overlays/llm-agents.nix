# Overlay for llm-agents
# Input defined in flake.nix: inputs.llm-agents
{ inputs, ... }:
{
  # numtide dropped overlays.default in 8abc3933 (leaving only
  # overlays.shared-nixpkgs). shared-nixpkgs rebuilds the packages against the
  # consumer's nixpkgs, which misses cache.numtide.com and forces a multi-GB
  # source build of opencode's npm deps. Replicate the old overlays.default
  # instead: surface numtide's pre-built packages so the binary cache hits.
  flake.overlays.llm-agents = final: _prev: {
    llm-agents = inputs.llm-agents.packages.${final.stdenv.hostPlatform.system} or { };
  };
}
