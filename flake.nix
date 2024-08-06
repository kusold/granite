{
  description = "Granite Flakes that make up the RockyMTN";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-unstable
    , home-manager
    , ...
    } @ inputs:
    let
      inherit (self) outputs;
      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

      homeConfigurations = {
        "mike" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          #        extraSpecialArgs = {inherit inputs outputs;};
          modules = [
            ./home-manager/mike/home.nix
          ];
        };
        #      "mkusold" = home-manager.lib.homeManagerConfiguration {
        #        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        #        modules = [
        #          ./home-manager/mkusold/home.nix
        #        ];
        #      };
      };
      # Attempt to let the user config to be imported by nixos homemanager
      homeConfigurationsModules = {
        "mike" = ./home-manager/mike/home.nix;
        #      "mkusold" = ./home-manager/mkusold/home.nix;
      };
    };
}

