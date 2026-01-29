# Overlay for beads (bd) - AI-supervised issue tracker
# Input defined in flake.nix: inputs.beads
{ inputs, ... }:
{
  flake.overlays.beads = final: prev: {
    # Individual packages
    beads-unwrapped = inputs.beads.packages.${prev.system}.default;
    beads-zsh-completions = inputs.beads.packages.${prev.system}.zsh-completions;

    # Combined package with completions included
    beads = prev.symlinkJoin {
      name = "beads-with-completions";
      paths = [
        inputs.beads.packages.${prev.system}.default
        inputs.beads.packages.${prev.system}.zsh-completions
      ];
    };
  };
}
