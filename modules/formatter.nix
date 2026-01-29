# Configures the nix formatter for this flake
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      formatter = inputs.nixpkgs-unstable.legacyPackages.${system}.nixfmt-tree;
    };
}
