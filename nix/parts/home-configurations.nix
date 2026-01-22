{
  imports = [
    ./home-configurations/mike.nix
    ./home-configurations/mkusold.nix
  ];

  # Reusable home-manager modules (no nixpkgs.config or overlays - those are
  # handled by the consumer when using useGlobalPkgs, or by mkHome for standalone)
  flake.homeModules = {
    mike = ../../home-manager/mike/home.nix;
    mkusold = ../../home-manager/mkusold/home.nix;
  };
}
