{ inputs, ... }:
{
  imports = [
    ./home-configurations/mike.nix
    ./home-configurations/mkusold.nix
  ];

  # Reusable home-manager modules (no nixpkgs.config or overlays - those are
  # handled by the consumer when using useGlobalPkgs, or by mkHome for standalone)
  #
  # These modules can be used in two ways:
  # 1. Standalone: Referenced by homeConfigurations via mkHome
  # 2. NixOS: Imported directly in home-manager.users.<user>
  flake.homeModules = {
    # Mike's base configuration
    mike = ../../home-manager/users/mike/default.nix;
    # Mike's dev configuration (with clawdbot)
    mike-dev = ../../home-manager/users/mike/dev.nix;
    # Mkusold's configuration
    mkusold = ../../home-manager/users/mkusold/default.nix;
    # Shared modules
    clawdbot = ../../home-manager/_modules/clawdbot.nix;
    clawdbot-external = inputs.nix-clawdbot.homeManagerModules.clawdbot;
    common = ../../home-manager/_modules/common.nix;
    git = ../../home-manager/_modules/git.nix;
    neovim = ../../home-manager/_modules/neovim.nix;
    zsh = ../../home-manager/_modules/zsh.nix;
  };
}
