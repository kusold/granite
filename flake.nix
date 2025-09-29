{
  description = "Granite Flakes that make up the RockyMTN";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ...
    }@inputs:
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
      formatter = forAllSystems (system: nixpkgs-unstable.legacyPackages.${system}.nixfmt-tree);

      homeConfigurations = {
        "mike" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          extraSpecialArgs = {
            pkgs-unstable = nixpkgs-unstable.legacyPackages.aarch64-darwin;
          };
          modules = [
            self.homeConfigurationModules.mike
            {
              home.username = "mike";
              home.homeDirectory = "/Users/mike";
            }
          ];
        };
        "mkusold" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          extraSpecialArgs = {
            pkgs-unstable = nixpkgs-unstable.legacyPackages.aarch64-darwin;
          };
          modules = [
            self.homeConfigurationModules.mkusold
            {
              home.username = "mkusold";
              home.homeDirectory = "/Users/mkusold";
            }
          ];
        };
      };
      # Attempt to let the user config to be imported by nixos homemanager
      homeConfigurationModules = {
        "mike" = ./home-manager/mike/home.nix;
        "mkusold" = ./home-manager/mkusold/home.nix;
      };
    };
}
