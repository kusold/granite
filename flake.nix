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
    flake-utils.url = "github:numtide/flake-utils";
    import-tree.url = "github:vic/import-tree";
    # Deliberately NOT following nixpkgs. numtide publishes prebuilt store paths
    # to cache.numtide.com built against its OWN pinned nixpkgs-unstable rev.
    # Following granite's nixpkgs-unstable rebuilds the nixpkgs-sensitive
    # packages (notably opencode's fetchNpmDeps) against a different rev, so
    # those paths miss the cache and build from source — the multi-GB npm build.
    # Let llm-agents use its own nixpkgs so every package hits the cache.
    # (Same reasoning as rockymtn's hermes-agent input.)
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  # Declare the numtide binary cache so standalone granite builds (home-manager
  # switch / nix build / laptops) consult cache.numtide.com. The rockymtn fleet
  # sets this at the system level via its cache module; this covers the rest.
  # Requires the consumer to accept flake config (accept-flake-config = true).
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { config, self, ... }:
      {
        imports = [
          # Dendritic pattern: import all modules from ./modules using import-tree
          (inputs.import-tree ./modules)
        ];

        # Configure perSystem to apply overlays
        perSystem =
          { config, system, ... }:
          {
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
              config.allowUnfree = true;
            };
          };
      }
    );
}
