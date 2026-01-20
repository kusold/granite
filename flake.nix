{
  description = "Granite Flakes that make up the RockyMTN";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.home-manager.flakeModules.home-manager
      ];

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        { system, ... }:
        {
          formatter = nixpkgs-unstable.legacyPackages.${system}.nixfmt-tree;
        };

      flake = {
        # Reusable home-manager modules
        homeModules = {
          mike = ./home-manager/mike/home.nix;
          mkusold = ./home-manager/mkusold/home.nix;
        };

        homeConfigurations =
          let
            mkHome =
              {
                username,
                system,
                homeDirectory ?
                  if builtins.match ".*-darwin" system != null then "/Users/${username}" else "/home/${username}",
              }:
              home-manager.lib.homeManagerConfiguration {
                pkgs = import nixpkgs { inherit system; };
                extraSpecialArgs = {
                  inherit inputs system;
                  pkgs-unstable = import nixpkgs-unstable { inherit system; };
                };
                modules = [
                  self.homeModules.${username}
                  {
                    home.username = username;
                    home.homeDirectory = homeDirectory;
                  }
                ];
              };
          in
          {
            # mike's configurations (hostname-based for automatic detection)
            "mike@Mac.int.rockymtn.org" = mkHome {
              username = "mike";
              system = "aarch64-darwin";
            };

            # Fallback configurations (when hostname doesn't match)
            "mike" = mkHome {
              username = "mike";
              system = "x86_64-linux";
            };
            "mkusold" = mkHome {
              username = "mkusold";
              system = "aarch64-darwin";
            };
          };
      };
    };
}
